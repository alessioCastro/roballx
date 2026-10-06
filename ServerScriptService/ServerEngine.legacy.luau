--!strict
-- ServerEngine.server.luau
-- Servidor Autoritativo com Tick-Based Physics e Broadcast de Snapshots.
-- O servidor é a verdade absoluta. Nunca faz rollback.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Teams = game:GetService("Teams")
local RunService = game:GetService("RunService")

local replicatedModules = ReplicatedStorage:WaitForChild("Modules")
local replicatedGameRemotes =
	ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("GameRemotes")
local serverModules = script.Parent.Modules

local MapData = require(replicatedModules:WaitForChild("MapData"))
local MapRuntime = require(replicatedModules:WaitForChild("MapRuntime"))
local PhysicsEngine = require(replicatedModules:WaitForChild("PhysicsEngine"))
local GameState = require(replicatedModules:WaitForChild("GameState"))
local InputBuffer = require(replicatedModules:WaitForChild("InputBuffer"))
local MatchManager = require(serverModules:WaitForChild("MatchManager"))

local gameInputEvent =
	replicatedGameRemotes:WaitForChild("GameInput")

----------------------------------------------------
-- SNAPSHOT REMOTE
----------------------------------------------------

local gameSnapshotEvent =
	replicatedGameRemotes:FindFirstChild("GameSnapshot")

if not gameSnapshotEvent then
	gameSnapshotEvent = Instance.new("UnreliableRemoteEvent")
	gameSnapshotEvent.Name = "GameSnapshot"
	gameSnapshotEvent.Parent = replicatedGameRemotes
end

local currentMap = MapRuntime.Build(MapData.Default)

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
-- CONFIGURAÇÃO DO PLAYER
----------------------------------------------------

local playerGameplay = currentMap.gameplay.player
local playerObjectId = playerGameplay.object

if typeof(playerObjectId) ~= "string" then
	error(
		"MapData.gameplay.player.object precisa ser um ID de objeto válido."
	)
end

----------------------------------------------------
-- DECOMPOSIÇÃO DE SEGMENTOS CURVADOS
----------------------------------------------------

local function rotateSegmentPoints(
	a: Vector2,
	b: Vector2,
	rotation: number
): (Vector2, Vector2)

	if rotation == 0 then
		return a, b
	end

	local center =
		(a + b) * 0.5

	local radians =
		math.rad(rotation)

	local cos =
		math.cos(radians)

	local sin =
		math.sin(radians)

	local function rotatePoint(
		point: Vector2
	): Vector2
		local relative =
			point - center

		return center
			+ Vector2.new(
				relative.X * cos
					- relative.Y * sin,
				relative.X * sin
					+ relative.Y * cos
			)
	end

	return
		rotatePoint(a),
		rotatePoint(b)
end

local function processSegments(
	rawSegments: {any}
): {PhysicsEngine.Segment}

	local processed: {PhysicsEngine.Segment} = {}

	if not rawSegments then
		return processed
	end

	for idx, seg in ipairs(rawSegments) do

		------------------------------------------------
		-- O SEGMENTO USADO COMO PLAYER É APENAS
		-- UM MOLDE E NÃO DEVE ENTRAR NO MUNDO.
		------------------------------------------------

		if seg.id == playerObjectId then
			continue
		end

		local curve = seg.curve or 0
		local rotation = seg.rotation or 0

		if curve == 0 then
			local rotatedA, rotatedB =
				rotateSegmentPoints(
					seg.a,
					seg.b,
					rotation
				)

			processed[#processed + 1] = {
				id = seg.id or ("seg_" .. idx),

				a = rotatedA,
				b = rotatedB,

				vel = Vector2.zero,

				mass = seg.mass or 1,
				restitution = seg.restitution or 0.5,

				isStatic = (seg.isStatic ~= false),
				isSolid = (seg.isSolid ~= false),

				damping = seg.damping or 0.98,
				resettable = (seg.resettable ~= false),

				rotation = seg.rotation or 0,
				rotationLocked = (seg.rotationLocked ~= false),
				angularVelocity = seg.angularVelocity or 0,

				thickness = seg.thickness,

				ignoreCapA = seg.ignoreCapA,
				ignoreCapB = seg.ignoreCapB,

				cGroup = buildBitmask(seg.cGroup),
				cMask = buildBitmask(seg.cMask)
			}
		else
			local rotatedA, rotatedB =
				rotateSegmentPoints(
					seg.a,
					seg.b,
					rotation
				)

			local samples = seg.curveSegments or 10
			local ab = rotatedB - rotatedA

			if ab.Magnitude == 0 then
				continue
			end

			local normal =
				Vector2.new(-ab.Y, ab.X).Unit

			local control =
				(rotatedA + rotatedB) / 2
				+ normal * curve

			local prevPoint = rotatedA

			for i = 1, samples do
				local t = i / samples
				local invT = 1 - t

				local currentPoint =
					(invT * invT * rotatedA)
					+ (2 * invT * t * control)
					+ (t * t * rotatedB)

				processed[#processed + 1] = {
					id = (seg.id or ("seg_" .. idx)) .. "_" .. i,

					sourceId = seg.id or ("seg_" .. idx),
					curvePieceIndex = i,
					curvePieceCount = samples,

					a = prevPoint,
					b = currentPoint,

					vel = Vector2.zero,

					mass = seg.mass or 1,
					restitution = seg.restitution or 0.5,

					isStatic = (seg.isStatic ~= false),
					isSolid = (seg.isSolid ~= false),

					damping = seg.damping or 0.98,
					resettable = (seg.resettable ~= false),

					rotation = seg.rotation or 0,
					rotationLocked = (seg.rotationLocked ~= false),
					angularVelocity = seg.angularVelocity or 0,

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

----------------------------------------------------
-- OBJETOS
----------------------------------------------------

local objects: {PhysicsEngine.Object} = {}

if currentMap.objects then
	for idx, object in ipairs(currentMap.objects) do

		------------------------------------------------
		-- O objeto usado como corpo do player é apenas
		-- um molde e não entra no mundo como objeto.
		------------------------------------------------

		if object.id ~= playerObjectId then
			local cornerPx = 0

			if typeof(object.cornerRadius) == "UDim" then
				cornerPx =
					math.min(
						object.size.X,
						object.size.Y
					)
					* object.cornerRadius.Scale
					+ object.cornerRadius.Offset

			elseif typeof(object.cornerRadius) == "number" then
				cornerPx =
					object.cornerRadius
			end

			local physicalObject: PhysicsEngine.Object = {
				id =
					object.id
					or ("object_" .. idx),

				pos =
					object.pos,

				vel =
					Vector2.zero,

				size =
					object.size,

				rotation =
					object.rotation
					or 0,

				rotationLocked =
					(object.rotationLocked ~= false),

				angularVelocity =
					object.angularVelocity
					or 0,

				cornerRadius =
					cornerPx,

				mass =
					object.mass
					or 1,

				restitution =
					object.restitution
					or 0.5,

				isStatic =
					(object.isStatic ~= false),

				isSolid =
					(object.isSolid ~= false),

				damping =
					object.damping
					or 0.98,

				resettable =
					(object.resettable ~= false),

				cGroup =
					buildBitmask(
						object.cGroup
					),

				cMask =
					buildBitmask(
						object.cMask
					),

				segmentP1 =
					Vector2.zero,

				segmentP2 =
					Vector2.zero,

				segmentRadius =
					0
			}

			PhysicsEngine.prepareObject(
				physicalObject
			)

			objects[#objects + 1] =
				physicalObject
		end
	end
end

----------------------------------------------------
-- SEGMENTOS
----------------------------------------------------

local segments: {PhysicsEngine.Segment} =
	processSegments(
		currentMap.segments
	)

----------------------------------------------------
-- OBJETOS DO MAPA POR ID
----------------------------------------------------

local objectsById: {[string]: any} = {}

for _, object in ipairs(objects) do
	if object.id then
		objectsById[object.id] =
			object
	end
end

for _, segment in ipairs(segments) do
	if segment.id then
		objectsById[segment.id] =
			segment
	end
end

----------------------------------------------------
-- MOLDE DO PLAYER
----------------------------------------------------

local playerTemplate: any = nil

if currentMap.objects then
	for _, object in ipairs(currentMap.objects) do
		if object.id == playerObjectId then
			playerTemplate =
				object
			break
		end
	end
end

if not playerTemplate and currentMap.segments then
	for _, segment in ipairs(currentMap.segments) do
		if segment.id == playerObjectId then
			playerTemplate =
				segment
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
		local object =
			objectsById[id]

		if object then
			kickableObjects[#kickableObjects + 1] =
				object
		end
	end
end

----------------------------------------------------
-- OBJETOS DE COLISÃO
----------------------------------------------------

local collisionObjects = {}

for _, object in ipairs(objects) do
	if object.isSolid ~= false then
		collisionObjects[#collisionObjects + 1] =
			object
	end
end

local collisionSegments = {}

for _, segment in ipairs(segments) do
	if segment.isSolid ~= false then
		collisionSegments[#collisionSegments + 1] =
			segment
	end
end

----------------------------------------------------
-- BROADPHASE
----------------------------------------------------

local broadphase =
	PhysicsEngine.createBroadphase(
		collisionObjects,
		collisionSegments,
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
	team: string,
	spawnIndex: number
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
		spawnIndex = spawnIndex,

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
	-- OBJECT
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
			cornerPx =
				template.cornerRadius
		end

		local player: PhysicsEngine.PlayerObject = {
			kind = "object",

			id = common.id,

			pos = spawnPosition,
			vel = common.vel,

			mass = common.mass,
			restitution = common.restitution,

			size = template.size,

			rotation =
				template.rotation
				or 0,

			cornerRadius =
				cornerPx,

			isStatic =
				common.isStatic,

			isSolid =
				common.isSolid,

			team =
				common.team,

			spawnIndex =
				common.spawnIndex,

			input =
				common.input,

			isKicking =
				common.isKicking,

			lastKickTick =
				common.lastKickTick,

			cGroup =
				common.cGroup,

			cMask =
				common.cMask
		}

		local temporaryObject: PhysicsEngine.Object = {
			id = playerObjectId,

			pos = spawnPosition,
			vel = Vector2.zero,

			size = template.size,

			rotation =
				template.rotation
				or 0,

			rotationLocked =
				(template.rotationLocked ~= false),

			angularVelocity =
				template.angularVelocity
				or 0,

			cornerRadius =
				cornerPx,

			mass =
				common.mass,

			restitution =
				common.restitution,

			isStatic = false,
			isSolid = true,

			damping =
				template.damping
				or 0.98,

			cGroup =
				common.cGroup,

			cMask =
				common.cMask,

			segmentP1 =
				Vector2.zero,

			segmentP2 =
				Vector2.zero,

			segmentRadius =
				0
		}

		PhysicsEngine.prepareObject(
			temporaryObject
		)

		player.segmentP1 =
			temporaryObject.segmentP1

		player.segmentP2 =
			temporaryObject.segmentP2

		player.segmentRadius =
			temporaryObject.segmentRadius

		return player
	end

	------------------------------------------------
	-- SEGMENT
	------------------------------------------------

	if template.a and template.b then
		local originalCenter =
			(template.a + template.b) * 0.5

		local offset =
			spawnPosition
			- originalCenter

		return {
			kind = "segment",

			id = common.id,

			vel = common.vel,

			a =
				template.a
				+ offset,

			b =
				template.b
				+ offset,

			thickness =
				template.thickness,

			ignoreCapA =
				template.ignoreCapA,

			ignoreCapB =
				template.ignoreCapB,

			mass =
				common.mass,

			restitution =
				common.restitution,

			isStatic =
				common.isStatic,

			isSolid =
				common.isSolid,

			team =
				common.team,

			spawnIndex =
				common.spawnIndex,

			input =
				common.input,

			isKicking =
				common.isKicking,

			lastKickTick =
				common.lastKickTick,

			cGroup =
				common.cGroup,

			cMask =
				common.cMask
		}
	end

	error(
		"Objeto de player inválido: "
			.. playerObjectId
	)
end

local function getNextSpawnIndex(
    team: string
): number
    local spawnPositions

    if team == "Team1" then
        spawnPositions =
            playerGameplay.spawn.team1Positions
    else
        spawnPositions =
            playerGameplay.spawn.team2Positions
    end

    for index = 1, #spawnPositions do
        local occupied = false

        for _, pData in pairs(playersData) do
            if pData.team == team
                and pData.spawnIndex == index
            then
                occupied = true
                break
            end
        end

        if not occupied then
            return index
        end
    end

    error(
        "Não existem posições de spawn suficientes para o time "
        .. team
    )
end

local team1 = Teams:WaitForChild("Team1")
local team2 = Teams:WaitForChild("Team2")

local TeamSettings =require(replicatedModules:WaitForChild("TeamSettings"))

team1.Name = TeamSettings.teams.Team1.name

team2.Name = TeamSettings.teams.Team2.name

----------------------------------------------------
-- CICLO DE VIDA DOS JOGADORES
----------------------------------------------------

Players.PlayerAdded:Connect(function(plr)
	local isTeam1 =
		(#Players:GetPlayers() % 2 ~= 0)

	local robloxTeam =
		isTeam1
		and team1
		or team2

	local team =
		isTeam1
		and "Team1"
		or "Team2"

	plr.Team = robloxTeam
	plr.Neutral = false

	local spawnIndex =
		getNextSpawnIndex(team)

	local spawnPositions =
		isTeam1
		and playerGameplay.spawn.team1Positions
		or playerGameplay.spawn.team2Positions

	local spawnPosition =
		spawnPositions[spawnIndex]

	playersData[plr.UserId] =
		createPlayerFromTemplate(
			spawnPosition,
			team,
			spawnIndex
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

			objects,
			segments,

			broadphase,

			currentMap.gameplay,
			kickableObjects,

			FIXED_DT,
			currentTick
		)

		------------------------------------------------
		-- 3. GOLS
		------------------------------------------------

		MatchManager.CheckGoals(currentMap, playersData, objects, segments)

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
