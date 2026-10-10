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


----------------------------------------------------
-- POSIÇÕES DE SPAWN DOS JOGADORES
----------------------------------------------------

local SPAWN_GAP = 12

local function getPlayerHalfSize(): Vector2
	if playerTemplate.size then
		return playerTemplate.size * 0.5
	end

	if playerTemplate.a and playerTemplate.b then
		local length = (playerTemplate.b - playerTemplate.a).Magnitude
		local radius = (playerTemplate.thickness or 0) * 0.5
		local halfSize = (length * 0.5) + radius

		return Vector2.new(halfSize, halfSize)
	end

	return Vector2.new(18, 18)
end

local function pointSegmentDistance(
	point: Vector2,
	a: Vector2,
	b: Vector2
): number
	local ab = b - a
	local lengthSquared = ab:Dot(ab)

	if lengthSquared <= 0 then
		return (point - a).Magnitude
	end

	local t = math.clamp(
		(point - a):Dot(ab) / lengthSquared,
		0,
		1
	)

	return (point - (a + ab * t)).Magnitude
end

local function isInsideMapBounds(position: Vector2): boolean
	local bounds = currentMap.bounds

	if not bounds then
		return true
	end

	local halfSize = getPlayerHalfSize()
	local width = bounds.width
	local height = bounds.height
	local padding = bounds.padding or 0

	if typeof(width) ~= "number"
		or typeof(height) ~= "number"
	then
		return true
	end

	return math.abs(position.X) + halfSize.X
			<= width * 0.5 - padding
		and math.abs(position.Y) + halfSize.Y
			<= height * 0.5 - padding
end

local function overlapsSolidObject(position: Vector2): boolean
	local playerHalfSize = getPlayerHalfSize()

	for _, object in ipairs(collisionObjects) do
		local objectHalfSize = object.size * 0.5
		local radians = math.rad(object.rotation or 0)
		local cos = math.abs(math.cos(radians))
		local sin = math.abs(math.sin(radians))

		local rotatedHalfSize = Vector2.new(
			objectHalfSize.X * cos + objectHalfSize.Y * sin,
			objectHalfSize.X * sin + objectHalfSize.Y * cos
		)

		local delta = position - object.pos

		if math.abs(delta.X)
				< playerHalfSize.X + rotatedHalfSize.X + SPAWN_GAP
			and math.abs(delta.Y)
				< playerHalfSize.Y + rotatedHalfSize.Y + SPAWN_GAP
		then
			return true
		end
	end

	return false
end

local function overlapsSolidSegment(position: Vector2): boolean
	local halfSize = getPlayerHalfSize()
	local playerRadius = halfSize.Magnitude

	for _, segment in ipairs(collisionSegments) do
		local thickness = segment.thickness or 0
		local segmentRadius = playerRadius + thickness * 0.5 + SPAWN_GAP

		if pointSegmentDistance(position, segment.a, segment.b)
			< segmentRadius
		then
			return true
		end
	end

	return false
end

local function overlapsExistingPlayer(position: Vector2): boolean
	local halfSize = getPlayerHalfSize()

	for _, player in pairs(playersData) do
		if player.kind == "object" and player.pos and player.size then
			local otherHalfSize = player.size * 0.5
			local delta = position - player.pos

			if math.abs(delta.X)
					< halfSize.X + otherHalfSize.X + SPAWN_GAP
				and math.abs(delta.Y)
					< halfSize.Y + otherHalfSize.Y + SPAWN_GAP
			then
				return true
			end
		elseif player.kind == "segment" and player.a and player.b then
			local radius = halfSize.Magnitude
				+ (player.thickness or 0) * 0.5
				+ SPAWN_GAP

			if pointSegmentDistance(position, player.a, player.b) < radius then
				return true
			end
		end
	end

	return false
end

local function isSpawnPositionAvailable(position: Vector2): boolean
	if not isInsideMapBounds(position) then
		return false
	end

	if overlapsExistingPlayer(position) then
		return false
	end

	if overlapsSolidObject(position) then
		return false
	end

	if overlapsSolidSegment(position) then
		return false
	end

	return true
end

local function getConfiguredSpawnPositions(team: string): {any}
	local spawn = playerGameplay.spawn

	if not spawn then
		return {}
	end

	local positions

	if team == "Team1" then
		positions = spawn.team1Positions
	else
		positions = spawn.team2Positions
	end

	if typeof(positions) ~= "table" then
		return {}
	end

	return positions
end

local function getAutomaticSpawnPosition(
	team: string
): (Vector2?, number?)
	local halfSize = getPlayerHalfSize()
	local bounds = currentMap.bounds

	local mapWidth = 800
	local mapHeight = 400
	local padding = 0

	if bounds then
		mapWidth = bounds.width or mapWidth
		mapHeight = bounds.height or mapHeight
		padding = bounds.padding or 0
	end

	local minY = -mapHeight * 0.5 + padding + halfSize.Y
	local maxY = mapHeight * 0.5 - padding - halfSize.Y

	local verticalSpacing = halfSize.Y * 2 + SPAWN_GAP
	local horizontalSpacing = halfSize.X * 2 + SPAWN_GAP

	if minY > maxY then
		return nil, nil
	end

	local side = if team == "Team1" then -1 else 1

	-- A primeira coluna fica no lado da equipe.
	-- As próximas avançam em direção à lateral do campo.
	local firstX = mapWidth * 0.25 * side
	local maxX = mapWidth * 0.5 - padding - halfSize.X

	local columnCount = math.floor(
		(math.max(0, maxX - math.abs(firstX))) / horizontalSpacing
	) + 1

	local rowCount = math.floor(
		(maxY - minY) / verticalSpacing
	) + 1

	for column = 0, columnCount do
		local distanceFromCenter = math.abs(firstX)
			+ column * horizontalSpacing

		if distanceFromCenter > maxX then
			break
		end

		local x = side * distanceFromCenter

		for row = 0, rowCount do
			local y = minY + row * verticalSpacing
			local candidate = Vector2.new(x, y)

			if isSpawnPositionAvailable(candidate) then
				return candidate, column * (rowCount + 1) + row + 1
			end
		end
	end

	return nil, nil
end

local function getPlayerSpawnPosition(
	team: string
): (Vector2?, number?)
	-- As posições manuais têm prioridade, mas não podem
	-- sobrepor jogadores, sair dos limites ou ocupar obstáculos.
	local configuredPositions = getConfiguredSpawnPositions(team)

	for index, position in ipairs(configuredPositions) do
		if typeof(position) == "Vector2"
			and isSpawnPositionAvailable(position)
		then
			return position, index
		end
	end

	-- Sem posições configuradas, ou quando elas acabam,
	-- procurar uma posição livre automaticamente.
	return getAutomaticSpawnPosition(team)
end


local team1 = Teams:WaitForChild("Team1") :: Team
local team2 = Teams:WaitForChild("Team2") :: Team

local spectatorsTeam = Teams:FindFirstChild("Spectators") :: Team?

if not spectatorsTeam then
	spectatorsTeam = Instance.new("Team")
	spectatorsTeam.Name = "Spectators"
	spectatorsTeam.TeamColor = BrickColor.new("Medium stone grey")
	spectatorsTeam.Parent = Teams
end

local TeamSettings = require(
	replicatedModules:WaitForChild("TeamSettings")
)

team1.Name = TeamSettings.teams.Team1.name
team2.Name = TeamSettings.teams.Team2.name

team1.AutoAssignable = false
team2.AutoAssignable = false
spectatorsTeam.AutoAssignable = false

----------------------------------------------------
-- CICLO DE VIDA E ATRIBUIÇÃO DE EQUIPE
----------------------------------------------------

local function getTeamSettingsKey(
	plr: Player
): string?
	if plr.Team == team1 then
		return "Team1"
	elseif plr.Team == team2 then
		return "Team2"
	end

	return nil
end

local function getClothingTemplate(
	value: any
): string
	if value == nil then
		return ""
	end

	local text = tostring(value)

	if text == "" then
		return ""
	end

	if string.find(text, "://") then
		return text
	end

	return "rbxassetid://" .. text
end

local function applyTeamUniform(
	plr: Player,
	character: Model
)
	local teamKey = getTeamSettingsKey(plr)

	if not teamKey then
		return
	end

	local settings = TeamSettings.teams[teamKey]

	if not settings or not settings.uniform then
		return
	end

	local uniform = settings.uniform
	local shirtTemplate = getClothingTemplate(uniform.shirt)
	local pantsTemplate = getClothingTemplate(uniform.pants)

	if shirtTemplate ~= "" then
		local shirt = character:FindFirstChildOfClass("Shirt")

		if not shirt then
			shirt = Instance.new("Shirt")
			shirt.Parent = character
		end

		shirt.ShirtTemplate = shirtTemplate
	end

	if pantsTemplate ~= "" then
		local pants = character:FindFirstChildOfClass("Pants")

		if not pants then
			pants = Instance.new("Pants")
			pants.Parent = character
		end

		pants.PantsTemplate = pantsTemplate
	end
end

----------------------------------------------------
-- ATRIBUIÇÃO CONTROLADA DE EQUIPE
----------------------------------------------------

local function setPlayerTeam(
	plr: Player,
	teamKey: string
): boolean
	if teamKey ~= "Spectators"
		and teamKey ~= "Team1"
		and teamKey ~= "Team2"
	then
		return false
	end

	local oldPlayerData = playersData[plr.UserId]
	local oldTeam = plr.Team
	local oldNeutral = plr.Neutral
	local oldGameTeam = plr:GetAttribute("GameTeam")

	if teamKey == "Spectators" then
		playersData[plr.UserId] = nil

		inputBuffer:removePlayer(plr.UserId)
		rebuildSortedUserIds()

		plr.Team = spectatorsTeam
		plr.Neutral = false
		plr:SetAttribute("GameTeam", "Spectators")

		return true
	end

	if oldGameTeam == teamKey and oldPlayerData then
		return true
	end

	-- Retira temporariamente o próprio jogador da simulação
	-- para que ele não bloqueie a busca pelo seu novo spawn.
	playersData[plr.UserId] = nil

	local spawnPosition, spawnIndex =
		getPlayerSpawnPosition(teamKey)

	if not spawnPosition or not spawnIndex then
		-- Se não houver spawn livre, mantém a situação anterior.
		playersData[plr.UserId] = oldPlayerData
		rebuildSortedUserIds()

		warn(
			"Não foi possível mover "
				.. plr.Name
				.. " para "
				.. teamKey
				.. ": não há spawn livre."
		)

		return false
	end

	local newPlayerData = createPlayerFromTemplate(
		spawnPosition,
		teamKey,
		spawnIndex
	)

	playersData[plr.UserId] = newPlayerData

	inputBuffer:removePlayer(plr.UserId)
	rebuildSortedUserIds()

	if teamKey == "Team1" then
		plr.Team = team1
	else
		plr.Team = team2
	end

	plr.Neutral = false
	plr:SetAttribute("GameTeam", teamKey)

	local character = plr.Character

	if character then
		applyTeamUniform(plr, character)
	end

	return true
end

----------------------------------------------------
-- SOLICITAÇÕES DE MUDANÇA DE EQUIPE
----------------------------------------------------

local setPlayerTeamRequest =
	script.Parent:FindFirstChild("SetPlayerTeamRequest")

if setPlayerTeamRequest == nil then
	local bindable = Instance.new("BindableFunction")
	bindable.Name = "SetPlayerTeamRequest"
	bindable.Parent = script.Parent
	setPlayerTeamRequest = bindable
end

local teamRequestFunction =
	setPlayerTeamRequest :: BindableFunction

teamRequestFunction.OnInvoke = function(
	targetUserId: number,
	teamKey: string
): (boolean, string)

	local target = Players:GetPlayerByUserId(targetUserId)

	if not target then
		return false, "Jogador não está mais na sala."
	end

	if teamKey ~= "Spectators"
		and teamKey ~= "Team1"
		and teamKey ~= "Team2"
	then
		return false, "Equipe inválida."
	end

	if setPlayerTeam(target, teamKey) then
		return true, "Equipe atualizada."
	end

	return false, "Não foi possível alterar a equipe."
end

----------------------------------------------------
-- ENTRADA: TODOS COMEÇAM COMO ESPECTADORES
----------------------------------------------------

Players.PlayerAdded:Connect(function(plr)
	plr.CharacterAdded:Connect(function(character)
		applyTeamUniform(plr, character)
	end)

	setPlayerTeam(plr, "Spectators")
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

				objects,
				segments,

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
