--!strict
-- ClientEngine.client.luau
-- Cliente com Predição Local + Rollback & Reconciliação.
-- Roda a mesma simulação de física localmente para resposta imediata.
-- Quando recebe snapshot do servidor, faz rollback e re-simula.
-- Simulação roda no Heartbeat (fixed timestep), renderização no RenderStepped.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local replicatedModules = ReplicatedStorage:WaitForChild("Modules")
local replicatedGameRemotes = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("GameRemotes")

local MapData = require(replicatedModules:WaitForChild("MapData"))
local PhysicsEngine = require(replicatedModules:WaitForChild("PhysicsEngine"))
local GameState = require(replicatedModules:WaitForChild("GameState"))
local InputBuffer = require(replicatedModules:WaitForChild("InputBuffer"))

local Renderers = replicatedModules:WaitForChild("Renderers")
local UIPrimitives = require(Renderers:WaitForChild("UIPrimitives"))
local MapRenderer = require(Renderers:WaitForChild("MapRenderer"))
local HUDRenderer = require(Renderers:WaitForChild("HUDRenderer"))

local inReservedServer = ReplicatedStorage:GetAttribute("IsRoomServer")
if inReservedServer == nil then
	ReplicatedStorage:GetAttributeChangedSignal("IsRoomServer"):Wait()
	inReservedServer = ReplicatedStorage:GetAttribute("IsRoomServer")
end

if not inReservedServer then return end

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local gameInputEvent = replicatedGameRemotes:WaitForChild("GameInput")
local gameSnapshotEvent = replicatedGameRemotes:WaitForChild("GameSnapshot")
local inputFolder = replicatedModules:WaitForChild("Inputs")

local currentMap = MapData.Default
local phys = currentMap.physics

----------------------------------------------------
-- CONVERSOR DE BITMASK (idêntico ao servidor)
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
-- DECOMPOSIÇÃO DE SEGMENTOS CURVADOS (idêntico ao servidor)
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
-- ESTADO LOCAL DA SIMULAÇÃO (cópia completa do mundo)
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
local sortedUserIds: { number } = {}

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

----------------------------------------------------
-- BUFFERS E ESTADO DE REDE
----------------------------------------------------
local localInputBuffer = InputBuffer.new(300)
local FIXED_DT = 1 / 60
local localTick = 0
local lastConfirmedTick = -1
local accumulator = 0

-- Input atual (capturado no Heartbeat, lido no RenderStepped para envio)
local currentMoveVector = Vector2.zero
local currentIsKicking = false

-- Placar local (atualizado por snapshots do servidor)
local localScoreRed = 0
local localScoreBlue = 0
local localResetCountdown = 0

local function rebuildSortedUserIds()
	sortedUserIds = {}
	for uId, _ in pairs(playersData) do
		table.insert(sortedUserIds, uId)
	end
	table.sort(sortedUserIds)
end

-- MatchManager local simplificado para uso no rollback
local function localCheckGoals()
	if localResetCountdown > 0 then
		localResetCountdown -= 1
		if localResetCountdown == 0 then
			ball.pos = currentMap.spawns.ball
			ball.vel = Vector2.zero
			for _, pData in pairs(playersData) do
				pData.pos = pData.team == "Red" and currentMap.spawns.red or currentMap.spawns.blue
				pData.vel = Vector2.zero
				pData.input = Vector2.zero
			end
		end
		return
	end

	local goals = currentMap.goals
	if not goals then return end

	for _, goal in ipairs(goals) do
		if ball.pos.X >= goal.min.X and ball.pos.X <= goal.max.X and
			ball.pos.Y >= goal.min.Y and ball.pos.Y <= goal.max.Y then
			if goal.teamScored == "Red" then
				localScoreRed += 1
			elseif goal.teamScored == "Blue" then
				localScoreBlue += 1
			end
			localResetCountdown = 90 -- 1.5s a 60fps
			break
		end
	end
end

-- Aplica inputs do buffer para um tick
local function applyInputsForTick(tick: number)
	local myId = player.UserId
	for _, uId in ipairs(sortedUserIds) do
		local pData = playersData[uId]
		if pData then
			local input: InputBuffer.InputData
			if uId == myId then
				-- Para o jogador local, usa o input do buffer local
				input = localInputBuffer:getLocal(tick)
			else
				-- Para jogadores remotos, usa o último input do snapshot
				input = { moveX = pData.input.X, moveY = pData.input.Y, kick = pData.isKicking }
			end
			pData.input = Vector2.new(input.moveX, input.moveY)
			pData.isKicking = input.kick
		end
	end
end

----------------------------------------------------
-- RENDERIZAÇÃO (setup inicial)
----------------------------------------------------
local mapElements = MapRenderer.Build(currentMap, playerGui)
local hud = HUDRenderer.Build(mapElements.screenGui)

-- Posições de renderização (interpoladas)
local renderBallPos = currentMap.spawns.ball

local ballFrame = UIPrimitives.CreateDisc(
	mapElements.field,
	renderBallPos,
	phys.ballRadius,
	Color3.fromRGB(255, 255, 255),
	3,
	Color3.fromRGB(0, 0, 0)
)

type PlayerRender = { frame: Frame, stroke: UIStroke?, renderPos: Vector2 }
local playerRenders: { [number]: PlayerRender } = {}

type DynamicRender = {
	frame: Frame,
	renderPos: Vector2?, simPos: Vector2?,
	renderA: Vector2?, renderB: Vector2?,
	simA: Vector2?, simB: Vector2?
}
local mapDynamicRenders: { [string]: DynamicRender } = {}

for id, frame in pairs(mapElements.dynamicFrames) do
	mapDynamicRenders[id] = {
		frame = frame,
		renderPos = frame.AbsolutePosition,
		simPos = frame.AbsolutePosition,
	}
end

----------------------------------------------------
-- INPUT MODULE
----------------------------------------------------
local InputModule
if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
	InputModule = require(inputFolder.MobileInput)
	InputModule.Init(mapElements.screenGui)
else
	InputModule = require(inputFolder.PCInput)
	InputModule.Init()
end

----------------------------------------------------
-- RECEPÇÃO DE SNAPSHOTS DO SERVIDOR (Rollback & Reconciliação)
----------------------------------------------------
gameSnapshotEvent.OnClientEvent:Connect(function(packed)
	local snap = GameState.unpackFromNetwork(packed)
	local serverTick = snap.tick

	-- Ignora snapshots antigos (já confirmamos um mais recente)
	if serverTick <= lastConfirmedTick then return end
	lastConfirmedTick = serverTick

	-- Atualizar placar autoritativo
	localScoreRed = snap.scoreRed
	localScoreBlue = snap.scoreBlue
	localResetCountdown = snap.resetCountdown
	hud:UpdateScore(localScoreRed, localScoreBlue)

	-- Sincronizar lista de jogadores com o snapshot do servidor
	local activeIds = {}
	for uId, pSnap in pairs(snap.players) do
		activeIds[uId] = true
		if not playersData[uId] then
			-- Novo jogador! Criar dados de física
			playersData[uId] = {
				pos = Vector2.new(pSnap.posX, pSnap.posY),
				vel = Vector2.new(pSnap.velX, pSnap.velY),
				radius = phys.playerRadius,
				mass = phys.playerMass,
				restitution = 0.1,
				team = pSnap.team,
				input = Vector2.new(pSnap.inputX, pSnap.inputY),
				isKicking = pSnap.isKicking,
				lastKickTick = pSnap.lastKickTick,
				isSolid = true,
				isStatic = false,
				cGroup = buildBitmask(phys.playerGroup),
				cMask = buildBitmask(phys.playerMask)
			}
		end
	end

	-- Remover jogadores que saíram
	for uId, _ in pairs(playersData) do
		if not activeIds[uId] then
			playersData[uId] = nil
			if playerRenders[uId] then
				playerRenders[uId].frame:Destroy()
				playerRenders[uId] = nil
			end
		end
	end

	rebuildSortedUserIds()

	-- === ROLLBACK ===
	-- 1. Restaurar estado do servidor
	GameState.restore(snap, ball, playersData, discs, segments, shapes)

	-- 2. Re-simular do serverTick até localTick com inputs locais
	if localTick > serverTick then
		local ticksToReplay = localTick - serverTick
		-- Limitar re-simulação para evitar travamento (máx ~10 ticks = ~166ms de latência)
		local maxReplay = math.min(ticksToReplay, 10)
		local startReplayTick = localTick - maxReplay

		for replayTick = startReplayTick, localTick - 1 do
			applyInputsForTick(replayTick)
			PhysicsEngine.Step(ball, playersData, sortedUserIds, discs, segments, shapes, phys, FIXED_DT, replayTick)
			localCheckGoals()
		end
	else
		-- Cliente está atrás do servidor — sincronizar tick
		localTick = serverTick
	end

	-- Limpar inputs antigos
	localInputBuffer:clearBefore(serverTick - 10)
end)

----------------------------------------------------
-- LOOP DE SIMULAÇÃO (Heartbeat) — Fixed Timestep 60Hz
----------------------------------------------------
local lastSentMoveVector = Vector2.zero
local lastSentKickState = false

RunService.Heartbeat:Connect(function(dt)
	-- === CAPTURA DE INPUT ===
	currentMoveVector, currentIsKicking = InputModule.GetInput()

	-- === PREDIÇÃO LOCAL: Avançar simulação ===
	accumulator += math.min(dt, 0.1)

	while accumulator >= FIXED_DT do
		-- Armazenar input local para este tick
		local inputData: InputBuffer.InputData = {
			moveX = currentMoveVector.X,
			moveY = currentMoveVector.Y,
			kick = currentIsKicking,
		}
		localInputBuffer:setLocal(localTick, inputData)

		-- Aplicar inputs e simular
		applyInputsForTick(localTick)
		PhysicsEngine.Step(ball, playersData, sortedUserIds, discs, segments, shapes, phys, FIXED_DT, localTick)
		localCheckGoals()

		localTick += 1
		accumulator -= FIXED_DT
	end

	-- === ENVIAR INPUT AO SERVIDOR ===
	-- Só envia quando muda (otimização de bandwidth)
	if currentMoveVector ~= lastSentMoveVector or currentIsKicking ~= lastSentKickState then
		lastSentMoveVector = currentMoveVector
		lastSentKickState = currentIsKicking
		gameInputEvent:FireServer(localTick, currentMoveVector, currentIsKicking)
	end
end)

----------------------------------------------------
-- LOOP DE RENDERIZAÇÃO (RenderStepped) — Interpolação Visual
----------------------------------------------------
RunService.RenderStepped:Connect(function(dt)
	-- === RENDERIZAÇÃO ===
	local alpha = 1 - math.exp(-35 * dt)

	-- Bola: interpolar suavemente para a posição da simulação local
	renderBallPos = renderBallPos:Lerp(ball.pos, alpha)
	ballFrame.Position = UDim2.new(0, renderBallPos.X, 0, renderBallPos.Y)

	-- Jogadores
	local myId = player.UserId
	for _, uId in ipairs(sortedUserIds) do
		local pData = playersData[uId]
		if pData then
			local render = playerRenders[uId]
			if not render then
				local teamStr = pData.team
				local color = teamStr == "Red" and Color3.fromRGB(220, 60, 60) or Color3.fromRGB(60, 120, 220)
				local frame, stroke = UIPrimitives.CreateDisc(
					mapElements.field,
					pData.pos,
					phys.playerRadius,
					color,
					3,
					Color3.fromRGB(0, 0, 0)
				)
				render = { frame = frame, stroke = stroke, renderPos = pData.pos }
				playerRenders[uId] = render
			end

			-- Jogador local: interpolação rápida (quase instantâneo)
			-- Jogadores remotos: interpolação suave para mascarar correções
			local interpAlpha
			if uId == myId then
				interpAlpha = 1 - math.exp(-50 * dt) -- muito rápido (~instantâneo)
			else
				interpAlpha = 1 - math.exp(-25 * dt) -- suave para remotos
			end

			render.renderPos = render.renderPos:Lerp(pData.pos, interpAlpha)
			render.frame.Position = UDim2.new(0, render.renderPos.X, 0, render.renderPos.Y)

			if render.stroke then
				render.stroke.Color = pData.isKicking and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(0, 0, 0)
			end
		end
	end

	-- Remover renders de jogadores que saíram
	for uId, render in pairs(playerRenders) do
		if not playersData[uId] then
			render.frame:Destroy()
			playerRenders[uId] = nil
		end
	end

	-- Objetos dinâmicos do mapa
	for id, render in pairs(mapDynamicRenders) do
		-- Buscar posição atual da simulação para shapes/discos
		local simPos: Vector2? = nil
		for _, s in ipairs(shapes) do
			if s.id == id and s.isStatic == false then
				simPos = s.pos
				break
			end
		end
		if not simPos then
			for _, d in ipairs(discs) do
				if d.id == id and d.isStatic == false then
					simPos = d.pos
					break
				end
			end
		end

		if simPos and render.renderPos then
			render.renderPos = (render.renderPos :: Vector2):Lerp(simPos, alpha)
			render.frame.Position = UDim2.new(0, (render.renderPos :: Vector2).X, 0, (render.renderPos :: Vector2).Y)
		end

		-- Segmentos dinâmicos
		for _, seg in ipairs(segments) do
			if seg.id == id and seg.isStatic == false then
				local simA, simB = seg.a, seg.b
				if render.renderA and render.renderB then
					render.renderA = (render.renderA :: Vector2):Lerp(simA, alpha)
					render.renderB = (render.renderB :: Vector2):Lerp(simB, alpha)
				else
					render.renderA = simA
					render.renderB = simB
				end

				local rA = render.renderA :: Vector2
				local rB = render.renderB :: Vector2
				local midPoint = (rA + rB) / 2
				local diff = rB - rA
				local length = diff.Magnitude
				local angle = math.deg(math.atan2(diff.Y, diff.X))

				render.frame.Position = UDim2.new(0, midPoint.X, 0, midPoint.Y)
				render.frame.Size = UDim2.new(0, length, 0, render.frame.Size.Y.Offset)
				render.frame.Rotation = angle
				break
			end
		end
	end

	-- HUD
	hud:UpdateScore(localScoreRed, localScoreBlue)
end)