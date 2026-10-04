--!strict
-- ServerEngine.server.luau
-- Servidor Autoritativo com Tick-Based Physics e Broadcast de Snapshots.
-- O servidor é a verdade absoluta. Nunca faz rollback.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local replicatedModules = ReplicatedStorage:WaitForChild("Modules")
local replicatedGameRemotes = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("GameRemotes")
local serverModules = script.Parent.Modules

local MapData = require(replicatedModules:WaitForChild("MapData"))
local PhysicsEngine = require(replicatedModules:WaitForChild("PhysicsEngine"))
local GameState = require(replicatedModules:WaitForChild("GameState"))
local InputBuffer = require(replicatedModules:WaitForChild("InputBuffer"))
local MatchManager = require(serverModules:WaitForChild("MatchManager"))

local gameInputEvent = replicatedGameRemotes:WaitForChild("GameInput")

-- Criar RemoteEvent para snapshots se não existir
local gameSnapshotEvent = replicatedGameRemotes:FindFirstChild("GameSnapshot")

if not gameSnapshotEvent then
	gameSnapshotEvent = Instance.new("UnreliableRemoteEvent")
	gameSnapshotEvent.Name = "GameSnapshot"
	gameSnapshotEvent.Parent = replicatedGameRemotes
end

local currentMap = MapData.Default

----------------------------------------------------
-- CONVERSOR DE STRINGS DE GRUPOS EM BITMASKS
----------------------------------------------------

local DEFAULT_MASK = 0xFFFFFFFF
local groupMap: {[string]: number} = {}

if currentMap.groups then
	for idx, groupName in ipairs(currentMap.groups) do
		groupMap[groupName] = idx
	end
end

local function buildBitmask(
	list: {string} | string | nil
): number
	if not list
		or list == "all"
		or list == "ALL"
	then
		return DEFAULT_MASK
	end

	if list == "none"
		or list == "NONE"
	then
		return 0
	end

	local mask = 0

	if typeof(list) == "table" then
		for _, name in ipairs(list) do
			local bitIndex = groupMap[name]

			if bitIndex then
				mask = bit32.bor(
					mask,
					bit32.lshift(1, bitIndex - 1)
				)
			end
		end
	end

	return mask
end

----------------------------------------------------
-- OBJETO DE PLAYER
----------------------------------------------------

local playerGameplay = currentMap.gameplay.player
local playerObjectId = playerGameplay.object

if typeof(playerObjectId) ~= "string" then
	error("MapData.gameplay.player.object precisa ser um ID de objeto válido.")
end

----------------------------------------------------
-- DECOMPOSIÇÃO DE SEGMENTOS CURVADOS
----------------------------------------------------

local function processSegments(
	rawSegments: {any}
): {PhysicsEngine.Segment}

	local processed: {PhysicsEngine.Segment} = {}

	if not rawSegments then
		return processed
	end

	for idx, seg in ipairs(rawSegments) do
		local curve = seg.curve or 0

		if curve == 0 then
			processed[#processed + 1] = {
				id = seg.id or ("seg_" .. idx),

				a = seg.a,
				b = seg.b,

				vel = Vector2.zero,

				mass = seg.mass or 1,
				restitution = seg.restitution or 0.5,

				isStatic = (seg.isStatic ~= false),
				isSolid = (seg.isSolid ~= false),

				damping = seg.damping or 0.98,
				thickness = seg.thickness,

				ignoreCapA = seg.ignoreCapA,
				ignoreCapB = seg.ignoreCapB,

				cGroup = buildBitmask(seg.cGroup),
				cMask = buildBitmask(seg.cMask)
			}
		else
			local samples = seg.curveSegments or 10
			local ab = seg.b - seg.a

			if ab.Magnitude == 0 then
				continue
			end

			local normal =
				Vector2.new(-ab.Y, ab.X).Unit

			local control =
				(seg.a + seg.b) / 2
				+ normal * curve

			local prevPoint = seg.a

			for i = 1, samples do
				local t = i / samples
				local invT = 1 - t

				local currentPoint =
					(invT * invT * seg.a)
					+ (2 * invT * t * control)
					+ (t * t * seg.b)

				processed[#processed + 1] = {
					id = (seg.id or ("seg_" .. idx)) .. "_" .. i,

					a = prevPoint,
					b = currentPoint,

					vel = Vector2.zero,

					mass = seg.mass or 1,
					restitution = seg.restitution or 0.5,

					isStatic = (seg.isStatic ~= false),
					isSolid = (seg.isSolid ~= false),

					damping = seg.damping or 0.98,
					thickness = seg.thickness,

					ignoreCapA = seg.ignoreCapA,
					ignoreCapB = seg.ignoreCapB,

					cGroup = buildBitmask(seg.cGroup),
					cMask = buildBitmask(seg.cMask)
				}

				prevPoint = currentPoint
			end
		end
	end

	return processed
end

----------------------------------------------------
-- INICIALIZAÇÃO DOS ELEMENTOS FÍSICOS
----------------------------------------------------

local playersData: {[number]: PhysicsEngine.PlayerObject} = {}
local sortedUserIds: {number} = {}

local discs: {PhysicsEngine.CircleObject} = {}

if currentMap.discs then
	for idx, disc in ipairs(currentMap.discs) do
		-- O objeto referenciado por gameplay.player.object
		-- é um molde do corpo do jogador e não deve existir
		-- simultaneamente como objeto independente do mapa.
		if disc.id ~= playerObjectId then
			discs[#discs + 1] = {
				id = disc.id or ("disc_" .. idx),

				pos = disc.pos,
				vel = Vector2.zero,

				radius = disc.radius,

				mass = disc.mass or 1,
				restitution = disc.restitution or 0.5,

				isStatic = (disc.isStatic ~= false),
				isSolid = (disc.isSolid ~= false),

				damping = disc.damping or 0.98,

				cGroup = buildBitmask(disc.cGroup),
				cMask = buildBitmask(disc.cMask)
			}
		end
	end
end

----------------------------------------------------
-- SEGMENTOS
----------------------------------------------------

local segments: {PhysicsEngine.Segment} =
	processSegments(currentMap.segments)

----------------------------------------------------
-- SHAPES
----------------------------------------------------

local shapes: {PhysicsEngine.PhysicalShape} = {}

if currentMap.shapes then
	for idx, shape in ipairs(currentMap.shapes) do
		-- Assim como no caso dos discs, um shape que seja
		-- o corpo do player é tratado como molde, não como
		-- objeto independente do mapa.
		if shape.id ~= playerObjectId then
			local cornerPx = 0

			if typeof(shape.cornerRadius) == "UDim" then
				cornerPx =
					math.min(
						shape.size.X,
						shape.size.Y
					)
					* shape.cornerRadius.Scale
					+ shape.cornerRadius.Offset

			elseif typeof(shape.cornerRadius) == "number" then
				cornerPx = shape.cornerRadius
			end

			local shapeObject: PhysicsEngine.PhysicalShape = {
				id = shape.id or ("shape_" .. idx),

				pos = shape.pos,
				vel = Vector2.zero,

				mass = shape.mass or 1,
				size = shape.size,

				rotation = shape.rotation or 0,
				cornerRadius = cornerPx,

				restitution = shape.restitution or 0.5,

				isStatic = (shape.isStatic ~= false),
				isSolid = (shape.isSolid ~= false),

				damping = shape.damping or 0.98,

				cGroup = buildBitmask(shape.cGroup),
				cMask = buildBitmask(shape.cMask),

				segmentP1 = Vector2.zero,
				segmentP2 = Vector2.zero,
				segmentRadius = 0
			}

			PhysicsEngine.prepareShape(shapeObject)

			shapes[#shapes + 1] = shapeObject
		end
	end
end

----------------------------------------------------
-- OBJETOS DE MAPA POR ID
----------------------------------------------------

local objectsById: {[string]: any} = {}

for _, object in ipairs(discs) do
	if object.id then
		objectsById[object.id] = object
	end
end

for _, object in ipairs(shapes) do
	if object.id then
		objectsById[object.id] = object
	end
end

for _, object in ipairs(segments) do
	if object.id then
		objectsById[object.id] = object
	end
end

----------------------------------------------------
-- MOLDE DO PLAYER
----------------------------------------------------

local playerTemplate: any = nil

-- Procurar o objeto original no MapData.
if currentMap.discs then
	for _, disc in ipairs(currentMap.discs) do
		if disc.id == playerObjectId then
			playerTemplate = disc
			break
		end
	end
end

if not playerTemplate and currentMap.shapes then
	for _, shape in ipairs(currentMap.shapes) do
		if shape.id == playerObjectId then
			playerTemplate = shape
			break
		end
	end
end

if not playerTemplate and currentMap.segments then
	for _, segment in ipairs(currentMap.segments) do
		if segment.id == playerObjectId then
			playerTemplate = segment
			break
		end
	end
end

if not playerTemplate then
	error(
		"MapData.gameplay.player.object referencia um objeto inexistente: "
		.. playerObjectId
	)
end

----------------------------------------------------
-- OBJETOS CHUTÁVEIS
----------------------------------------------------

local kickableObjects: {any} = {}

local kickableIds =
	currentMap.gameplay
	and currentMap.gameplay.kickable

if kickableIds then
	for _, id in ipairs(kickableIds) do
		local object = objectsById[id]

		if object then
			kickableObjects[#kickableObjects + 1] = object
		end
	end
end

----------------------------------------------------
-- OBJETOS DINÂMICOS
----------------------------------------------------

local dynamicDiscs = {}

for _, d in ipairs(discs) do
	if not d.isStatic then
		dynamicDiscs[#dynamicDiscs + 1] = d
	end
end

local dynamicSegments = {}

for _, seg in ipairs(segments) do
	if not seg.isStatic then
		dynamicSegments[#dynamicSegments + 1] = seg
	end
end

local dynamicShapes = {}

for _, s in ipairs(shapes) do
	if not s.isStatic then
		dynamicShapes[#dynamicShapes + 1] = s
	end
end

----------------------------------------------------
-- OBJETOS DE COLISÃO
----------------------------------------------------

local collisionDiscs = {}

for _, d in ipairs(discs) do
	if d.isSolid ~= false then
		collisionDiscs[#collisionDiscs + 1] = d
	end
end

local collisionSegments = {}

for _, seg in ipairs(segments) do
	if seg.isSolid ~= false then
		collisionSegments[#collisionSegments + 1] = seg
	end
end

local collisionShapes = {}

for _, s in ipairs(shapes) do
	if s.isSolid ~= false then
		collisionShapes[#collisionShapes + 1] = s
	end
end

----------------------------------------------------
-- BROADPHASE
----------------------------------------------------

local broadphase =
	PhysicsEngine.createBroadphase(
		collisionDiscs,
		collisionSegments,
		collisionShapes,
		64
	)

----------------------------------------------------
-- INPUT BUFFER
----------------------------------------------------

local inputBuffer =
	InputBuffer.new(300)

----------------------------------------------------
-- FUNÇÕES UTILITÁRIAS
----------------------------------------------------

local function rebuildSortedUserIds()
	sortedUserIds = {}

	for uId in pairs(playersData) do
		sortedUserIds[#sortedUserIds + 1] = uId
	end

	table.sort(sortedUserIds)
end

----------------------------------------------------
-- CRIAÇÃO DO CORPO FÍSICO DO PLAYER
----------------------------------------------------

local function createPlayerFromTemplate(
	spawnPosition: Vector2,
	team: string
): PhysicsEngine.PlayerObject

	local template = playerTemplate

	local common = {
		id = playerObjectId,

		vel = Vector2.zero,

		mass = template.mass or 1,
		restitution = template.restitution or 0.1,

		isStatic = false,
		isSolid = true,

		team = team,

		input = Vector2.zero,
		isKicking = false,
		lastKickTick = -9999,

		cGroup = buildBitmask(
			playerGameplay.collision.group
		),

		cMask = buildBitmask(
			playerGameplay.collision.mask
		)
	}

	------------------------------------------------
	-- DISC
	------------------------------------------------

	if template.radius then
		local player: PhysicsEngine.PlayerObject = {
			kind = "disc",

			id = common.id,

			pos = spawnPosition,
			vel = common.vel,

			radius = template.radius,

			mass = common.mass,
			restitution = common.restitution,

			isStatic = common.isStatic,
			isSolid = common.isSolid,

			team = common.team,

			input = common.input,
			isKicking = common.isKicking,
			lastKickTick = common.lastKickTick,

			cGroup = common.cGroup,
			cMask = common.cMask
		}

		return player
	end

	------------------------------------------------
	-- SHAPE
	------------------------------------------------

	if template.size then
		local cornerPx = 0

		if typeof(template.cornerRadius) == "UDim" then
			cornerPx =
				math.min(
					template.size.X,
					template.size.Y
				)
				* template.cornerRadius.Scale
				+ template.cornerRadius.Offset

		elseif typeof(template.cornerRadius) == "number" then
			cornerPx = template.cornerRadius
		end

		local player: PhysicsEngine.PlayerObject = {
			kind = "shape",

			id = common.id,

			pos = spawnPosition,
			vel = common.vel,

			mass = common.mass,
			restitution = common.restitution,

			size = template.size,

			rotation = template.rotation or 0,
			cornerRadius = cornerPx,

			segmentP1 = Vector2.zero,
			segmentP2 = Vector2.zero,
			segmentRadius = 0,

			isStatic = common.isStatic,
			isSolid = common.isSolid,

			team = common.team,

			input = common.input,
			isKicking = common.isKicking,
			lastKickTick = common.lastKickTick,

			cGroup = common.cGroup,
			cMask = common.cMask
		}

		local temporaryShape: PhysicsEngine.PhysicalShape = {
			id = playerObjectId,

			pos = spawnPosition,
			vel = Vector2.zero,

			mass = common.mass,
			size = template.size,

			rotation = template.rotation or 0,
			cornerRadius = cornerPx,

			restitution = common.restitution,

			isStatic = false,
			isSolid = true,

			damping = template.damping or 0.98,

			cGroup = common.cGroup,
			cMask = common.cMask,

			segmentP1 = Vector2.zero,
			segmentP2 = Vector2.zero,
			segmentRadius = 0
		}

		PhysicsEngine.prepareShape(
			temporaryShape
		)

		player.segmentP1 =
			temporaryShape.segmentP1

		player.segmentP2 =
			temporaryShape.segmentP2

		player.segmentRadius =
			temporaryShape.segmentRadius

		return player
	end

	------------------------------------------------
	-- SEGMENT
	------------------------------------------------

	if template.a and template.b then
		local originalCenter =
			(template.a + template.b) * 0.5

		local offset =
			spawnPosition - originalCenter

		local player: PhysicsEngine.PlayerObject = {
			kind = "segment",

			id = common.id,

			vel = common.vel,

			a = template.a + offset,
			b = template.b + offset,

			thickness = template.thickness,

			ignoreCapA = template.ignoreCapA,
			ignoreCapB = template.ignoreCapB,

			mass = common.mass,
			restitution = common.restitution,

			isStatic = common.isStatic,
			isSolid = common.isSolid,

			team = common.team,

			input = common.input,
			isKicking = common.isKicking,
			lastKickTick = common.lastKickTick,

			cGroup = common.cGroup,
			cMask = common.cMask
		}

		return player
	end

	error(
		"Objeto de player inválido: "
		.. playerObjectId
	)
end

----------------------------------------------------
-- CICLO DE VIDA DOS JOGADORES
----------------------------------------------------

Players.PlayerAdded:Connect(function(plr)
	local isRed =
		(#Players:GetPlayers() % 2 ~= 0)

	local spawnPosition =
		isRed
		and playerGameplay.spawn.Red
		or playerGameplay.spawn.Blue

	local team =
		isRed
		and "Red"
		or "Blue"

	playersData[plr.UserId] =
		createPlayerFromTemplate(
			spawnPosition,
			team
		)

	rebuildSortedUserIds()
end)

Players.PlayerRemoving:Connect(function(plr)
	playersData[plr.UserId] = nil

	inputBuffer:removePlayer(
		plr.UserId
	)

	rebuildSortedUserIds()
end)

----------------------------------------------------
-- RECEPÇÃO DE INPUTS DOS CLIENTES
----------------------------------------------------

gameInputEvent.OnServerEvent:Connect(
	function(
		plr: Player,
		clientTick: any,
		moveVector: any,
		isKicking: any
	)
		local pData =
			playersData[plr.UserId]

		if not pData then
			return
		end

		local tick =
			(typeof(clientTick) == "number")
			and math.floor(clientTick)
			or 0

		local moveDir: Vector2

		if typeof(moveVector) == "Vector2" then
			moveDir =
				moveVector.Magnitude > 1
				and moveVector.Unit
				or moveVector
		else
			moveDir = Vector2.zero
		end

		local kick =
			(typeof(isKicking) == "boolean")
			and isKicking
			or false

		inputBuffer:set(
			tick,
			plr.UserId,
			{
				moveX = moveDir.X,
				moveY = moveDir.Y,
				kick = kick
			}
		)
	end
)

----------------------------------------------------
-- APLICA INPUTS DO BUFFER
----------------------------------------------------

local function applyInputsForTick(
	tick: number
)
	for _, uId in ipairs(sortedUserIds) do
		local pData =
			playersData[uId]

		if pData then
			local input =
				inputBuffer:get(
					tick,
					uId
				)

			pData.input =
				Vector2.new(
					input.moveX,
					input.moveY
				)

			pData.isKicking =
				input.kick
		end
	end
end

----------------------------------------------------
-- LOOP DE FÍSICA E BROADCAST
----------------------------------------------------

local FIXED_DT = 1 / 60
local SNAPSHOT_INTERVAL = 2

local accumulator = 0
local currentTick = 0

RunService.Heartbeat:Connect(function(dt)
	accumulator +=
		math.min(dt, 0.1)

	while accumulator >= FIXED_DT do
		------------------------------------------------
		-- 1. INPUT
		------------------------------------------------

		applyInputsForTick(
			currentTick
		)

		------------------------------------------------
		-- 2. FÍSICA
		------------------------------------------------

		PhysicsEngine.Step(
			playersData,
			sortedUserIds,

			discs,
			segments,
			shapes,

			collisionDiscs,
			collisionSegments,
			collisionShapes,

			broadphase,

			currentMap.gameplay,
			kickableObjects,

			FIXED_DT,
			currentTick
		)

		------------------------------------------------
		-- 3. GOLS
		------------------------------------------------

		MatchManager.CheckGoals(
			currentMap,
			playersData,
			discs,
			segments,
			shapes
		)

		------------------------------------------------
		-- 4. AVANÇAR TICK
		------------------------------------------------

		currentTick += 1
		accumulator -= FIXED_DT

		------------------------------------------------
		-- 5. LIMPAR INPUTS ANTIGOS
		------------------------------------------------

		if currentTick % 30 == 0 then
			inputBuffer:clearBefore(
				currentTick - 180
			)
		end
	end

	------------------------------------------------
	-- 6. SNAPSHOT
	------------------------------------------------

	if
		currentTick > 0
		and currentTick % SNAPSHOT_INTERVAL == 0
	then
		local scoreRed, scoreBlue =
			MatchManager.GetScore()

		local packed =
			GameState.packLiveState(
				currentTick,

				playersData,

				dynamicDiscs,
				dynamicSegments,
				dynamicShapes,

				scoreRed,
				scoreBlue,

				MatchManager.GetResetCountdown(),

				sortedUserIds
			)

		gameSnapshotEvent:FireAllClients(
			packed
		)
	end
end)
