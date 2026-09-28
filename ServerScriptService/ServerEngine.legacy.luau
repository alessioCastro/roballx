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
local phys = currentMap.physics

----------------------------------------------------
-- CONVERSOR DE STRINGS DE GRUPOS EM BITMASKS
----------------------------------------------------
local DEFAULT_MASK = 0xFFFFFFFF
local groupMap: { [string]: number } = {}

if currentMap.groups then
	for idx, groupName in ipairs(currentMap.groups) do
		groupMap[groupName] = idx
	end
end

local function buildBitmask(list: {string} | string | nil): number
	if not list or list == "all" or list == "ALL" then return DEFAULT_MASK end
	if list == "none" or list == "NONE" then return 0 end

	local mask = 0
	if typeof(list) == "table" then
		for _, name in ipairs(list) do
			local bitIndex = groupMap[name]
			if bitIndex then
				mask = bit32.bor(mask, bit32.lshift(1, bitIndex - 1))
			end
		end
	end
	return mask
end

----------------------------------------------------
-- DECOMPOSIÇÃO DE SEGMENTOS CURVADOS
----------------------------------------------------
local function processSegments(rawSegments: { any }): { PhysicsEngine.Segment }
	local processed = {}
	if not rawSegments then return processed end

	for idx, seg in ipairs(rawSegments) do
		local curve = seg.curve or 0
		if curve == 0 then
			table.insert(processed, {
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
				cGroup = buildBitmask(seg.cGroup),
				cMask = buildBitmask(seg.cMask)
			})
		else
			local samples = seg.curveSegments or 10
			local ab = seg.b - seg.a
			if ab.Magnitude == 0 then continue end

			local normal = Vector2.new(-ab.Y, ab.X).Unit
			local control = (seg.a + seg.b) / 2 + normal * curve

			local prevPoint = seg.a
			for i = 1, samples do
				local t = i / samples
				local invT = 1 - t
				local currentPoint = (invT * invT * seg.a) + (2 * invT * t * control) + (t * t * seg.b)

				table.insert(processed, {
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
					cGroup = buildBitmask(seg.cGroup),
					cMask = buildBitmask(seg.cMask)
				})
				prevPoint = currentPoint
			end
		end
	end

	return processed
end

----------------------------------------------------
-- INICIALIZAÇÃO DA BOLA E ELEMENTOS FÍSICOS
----------------------------------------------------
local ball: PhysicsEngine.CircleObject = {
	pos = currentMap.spawns.ball,
	vel = Vector2.zero,
	radius = phys.ballRadius,
	mass = phys.ballMass,
	restitution = 0.5,
	isSolid = true,
	isStatic = false,
	cGroup = buildBitmask(phys.ballGroup),
	cMask = buildBitmask(phys.ballMask)
}

local playersData: { [number]: PhysicsEngine.CircleObject } = {}
local sortedUserIds: { number } = {} -- lista ordenada para iteração determinística

local discs: { PhysicsEngine.CircleObject } = {}
if currentMap.discs then
	for idx, disc in ipairs(currentMap.discs) do
		table.insert(discs, {
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
		})
	end
end

local segments: { PhysicsEngine.Segment } = processSegments(currentMap.segments)

local shapes: { PhysicsEngine.PhysicalShape } = {}
if currentMap.shapes then
	for idx, shape in ipairs(currentMap.shapes) do
		local cornerPx = 0
		if typeof(shape.cornerRadius) == "UDim" then
			cornerPx = math.min(shape.size.X, shape.size.Y) * shape.cornerRadius.Scale + shape.cornerRadius.Offset
		elseif typeof(shape.cornerRadius) == "number" then
			cornerPx = shape.cornerRadius
		end

		table.insert(shapes, {
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
			cMask = buildBitmask(shape.cMask)
		})
	end
end

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
-- INPUT BUFFER
----------------------------------------------------
local inputBuffer = InputBuffer.new(300)

----------------------------------------------------
-- FUNÇÕES UTILITÁRIAS
----------------------------------------------------
local function rebuildSortedUserIds()
	sortedUserIds = {}
	for uId, _ in pairs(playersData) do
		table.insert(sortedUserIds, uId)
	end
	table.sort(sortedUserIds)
end

-- Aplica inputs do buffer no playersData para um tick
local function applyInputsForTick(tick: number)
	for _, uId in ipairs(sortedUserIds) do
		local pData = playersData[uId]
		if pData then
			local input = inputBuffer:get(tick, uId)
			pData.input = Vector2.new(input.moveX, input.moveY)
			pData.isKicking = input.kick
		end
	end
end

----------------------------------------------------
-- CICLO DE VIDA DOS JOGADORES
----------------------------------------------------
Players.PlayerAdded:Connect(function(plr)
	local isRed = (#Players:GetPlayers() % 2 ~= 0)
	playersData[plr.UserId] = {
		pos = isRed and currentMap.spawns.red or currentMap.spawns.blue,
		vel = Vector2.zero,
		radius = phys.playerRadius,
		mass = phys.playerMass,
		restitution = 0.1,
		team = isRed and "Red" or "Blue",
		input = Vector2.zero,
		isKicking = false,
		lastKickTick = -9999,
		isSolid = true,
		isStatic = false,
		cGroup = buildBitmask(phys.playerGroup),
		cMask = buildBitmask(phys.playerMask)
	}
	rebuildSortedUserIds()
end)

Players.PlayerRemoving:Connect(function(plr)
	playersData[plr.UserId] = nil
	inputBuffer:removePlayer(plr.UserId)
	rebuildSortedUserIds()
end)

----------------------------------------------------
-- RECEPÇÃO DE INPUTS DOS CLIENTES
----------------------------------------------------
gameInputEvent.OnServerEvent:Connect(function(plr: Player, clientTick: any, moveVector: any, isKicking: any)
	local pData = playersData[plr.UserId]
	if not pData then return end

	-- Validação de tipos
	local tick = (typeof(clientTick) == "number") and math.floor(clientTick) or 0
	local moveDir: Vector2
	if typeof(moveVector) == "Vector2" then
		moveDir = moveVector.Magnitude > 1 and moveVector.Unit or moveVector
	else
		moveDir = Vector2.zero
	end
	local kick = (typeof(isKicking) == "boolean") and isKicking or false

	-- Armazena no buffer
	inputBuffer:set(tick, plr.UserId, {
		moveX = moveDir.X,
		moveY = moveDir.Y,
		kick = kick,
	})
end)

----------------------------------------------------
-- LOOP DE FÍSICA E BROADCAST DE SNAPSHOTS
----------------------------------------------------
local FIXED_DT = 1 / 60
local SNAPSHOT_INTERVAL = 2 -- enviar snapshot a cada N ticks
local accumulator = 0
local currentTick = 0

RunService.Heartbeat:Connect(function(dt)
	accumulator += math.min(dt, 0.1)

	while accumulator >= FIXED_DT do
		-- 1. Aplicar inputs para este tick
		applyInputsForTick(currentTick)

		-- 2. Step da física
		PhysicsEngine.Step(ball, playersData, sortedUserIds, discs, segments, shapes, phys, FIXED_DT, currentTick)

		-- 3. Checar gols (determinístico, tick-based)
		MatchManager.CheckGoals(ball, currentMap, playersData)

		-- 4. Avançar tick
		currentTick += 1
		accumulator -= FIXED_DT
		
		if currentTick % 30 == 0 then
			inputBuffer:clearBefore(currentTick - 180)
		end
	end

	-- 5. Broadcast de snapshot a cada N ticks
	if currentTick > 0 and currentTick % SNAPSHOT_INTERVAL == 0 then
		local scoreRed, scoreBlue = MatchManager.GetScore()
		local packed = GameState.packLiveState(
			currentTick,
			ball,
			playersData,
			dynamicDiscs,
			dynamicSegments,
			dynamicShapes,
			scoreRed,
			scoreBlue,
			MatchManager.GetResetCountdown(),
			sortedUserIds
		)
		gameSnapshotEvent:FireAllClients(packed)
	end
end)
