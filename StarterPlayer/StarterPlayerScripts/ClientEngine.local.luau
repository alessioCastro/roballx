--!strict
-- ClientEngine.client.luau
-- Predição Local + Rollback & Reconciliação.
-- Simulação fixa em 60 Hz.
-- Renderização separada no RenderStepped.

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

----------------------------------------------------
-- SERVIDOR RESERVADO
----------------------------------------------------

local inReservedServer = ReplicatedStorage:GetAttribute("IsRoomServer")

if inReservedServer == nil then
	ReplicatedStorage:GetAttributeChangedSignal("IsRoomServer"):Wait()
	inReservedServer = ReplicatedStorage:GetAttribute("IsRoomServer")
end

--if not inReservedServer then return end

----------------------------------------------------
-- REFERÊNCIAS
----------------------------------------------------

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local gameInputEvent = replicatedGameRemotes:WaitForChild("GameInput")
local gameSnapshotEvent = replicatedGameRemotes:WaitForChild("GameSnapshot")

local inputFolder = replicatedModules:WaitForChild("Inputs")

local currentMap = MapData.Default
local phys = currentMap.physics

----------------------------------------------------
-- BITMASK
----------------------------------------------------

local DEFAULT_MASK = 0xFFFFFFFF
local groupMap: { [string]: number } = {}

if currentMap.groups then
	for idx, groupName in ipairs(currentMap.groups) do
		groupMap[groupName] = idx
	end
end

local function buildBitmask(list: {string} | string | nil): number
	if not list or list == "all" or list == "ALL" then
		return DEFAULT_MASK
	end

	if list == "none" or list == "NONE" then
		return 0
	end

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
-- SEGMENTOS
----------------------------------------------------

local function processSegments(rawSegments: { any }): { PhysicsEngine.Segment }
	local processed = {}

	if not rawSegments then
		return processed
	end

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

			if ab.Magnitude == 0 then
				continue
			end

			local normal = Vector2.new(-ab.Y, ab.X).Unit
			local control = (seg.a + seg.b) / 2 + normal * curve

			local prevPoint = seg.a

			for i = 1, samples do
				local t = i / samples
				local invT = 1 - t

				local currentPoint =
					(invT * invT * seg.a)
					+ (2 * invT * t * control)
					+ (t * t * seg.b)

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
-- ESTADO LOCAL
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

----------------------------------------------------
-- DISCOS
----------------------------------------------------

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

----------------------------------------------------
-- SEGMENTOS
----------------------------------------------------

local segments: { PhysicsEngine.Segment } =
	processSegments(currentMap.segments)

----------------------------------------------------
-- SHAPES
----------------------------------------------------

local shapes: { PhysicsEngine.PhysicalShape } = {}

if currentMap.shapes then
	for idx, shape in ipairs(currentMap.shapes) do
		local cornerPx = 0

		if typeof(shape.cornerRadius) == "UDim" then
			cornerPx =
				math.min(shape.size.X, shape.size.Y)
				* shape.cornerRadius.Scale
				+ shape.cornerRadius.Offset
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
-- MAPA DE OBJETOS DINÂMICOS
--
-- Em vez de procurar o objeto pelo ID a cada frame,
-- guardamos a referência diretamente uma vez.
----------------------------------------------------

local dynamicObjects: {
	[string]: any
} = {}

for _, object in ipairs(shapes) do
	if object.isStatic == false then
		dynamicObjects[object.id] = object
	end
end

for _, object in ipairs(discs) do
	if object.isStatic == false then
		dynamicObjects[object.id] = object
	end
end

for _, object in ipairs(segments) do
	if object.isStatic == false then
		dynamicObjects[object.id] = object
	end
end

----------------------------------------------------
-- ESTADO DE REDE
----------------------------------------------------

local localInputBuffer = InputBuffer.new(300)

local FIXED_DT = 1 / 60

local localTick = 0
local lastConfirmedTick = -1
local accumulator = 0

local currentMoveVector = Vector2.zero
local currentIsKicking = false

local localScoreRed = 0
local localScoreBlue = 0
local localResetCountdown = 0

----------------------------------------------------
-- PLAYERS ORDENADOS
----------------------------------------------------

local function rebuildSortedUserIds()
	sortedUserIds = {}

	for uId in pairs(playersData) do
		table.insert(sortedUserIds, uId)
	end

	table.sort(sortedUserIds)
end

----------------------------------------------------
-- GOALS
----------------------------------------------------

local function localCheckGoals()
	if localResetCountdown > 0 then
		localResetCountdown -= 1

		if localResetCountdown == 0 then
			ball.pos = currentMap.spawns.ball
			ball.vel = Vector2.zero

			for _, pData in pairs(playersData) do
				pData.pos =
					pData.team == "Red"
					and currentMap.spawns.red
					or currentMap.spawns.blue

				pData.vel = Vector2.zero
				pData.input = Vector2.zero
			end
		end

		return
	end

	local goals = currentMap.goals

	if not goals then
		return
	end

	for _, goal in ipairs(goals) do
		if ball.pos.X >= goal.min.X
			and ball.pos.X <= goal.max.X
			and ball.pos.Y >= goal.min.Y
			and ball.pos.Y <= goal.max.Y
		then
			if goal.teamScored == "Red" then
				localScoreRed += 1
			elseif goal.teamScored == "Blue" then
				localScoreBlue += 1
			end

			localResetCountdown = 90
			break
		end
	end
end

----------------------------------------------------
-- INPUTS
----------------------------------------------------

local function applyInputsForTick(tick: number)
	local myId = player.UserId

	for _, uId in ipairs(sortedUserIds) do
		local pData = playersData[uId]

		if pData then
			if uId == myId then
				local input = localInputBuffer:getLocal(tick)

				pData.input = Vector2.new(
					input.moveX,
					input.moveY
				)

				pData.isKicking = input.kick
			end
		end
	end
end

----------------------------------------------------
-- RENDERIZAÇÃO
----------------------------------------------------

local mapElements = MapRenderer.Build(currentMap, playerGui)
local hud = HUDRenderer.Build(mapElements.screenGui)

local renderBallPos = currentMap.spawns.ball

local ballFrame = UIPrimitives.CreateDisc(
	mapElements.field,
	renderBallPos,
	phys.ballRadius,
	Color3.fromRGB(255, 255, 255),
	3,
	Color3.fromRGB(0, 0, 0)
)

----------------------------------------------------
-- PLAYER RENDER
----------------------------------------------------

type PlayerRender = {
	frame: Frame,
	stroke: UIStroke?,
	renderPos: Vector2,
	lastKicking: boolean
}

local playerRenders: { [number]: PlayerRender } = {}

----------------------------------------------------
-- DYNAMIC RENDER
----------------------------------------------------

type DynamicRender = {
	frame: Frame,
	object: any,
	renderPos: Vector2?,
	renderA: Vector2?,
	renderB: Vector2?
}

local mapDynamicRenders: {
	[string]: DynamicRender
} = {}

for id, frame in pairs(mapElements.dynamicFrames) do
	mapDynamicRenders[id] = {
		frame = frame,
		object = dynamicObjects[id],
		renderPos = frame.AbsolutePosition,
		renderA = nil,
		renderB = nil
	}
end

----------------------------------------------------
-- INPUT MODULE
----------------------------------------------------

local InputModule

if UserInputService.TouchEnabled
	and not UserInputService.KeyboardEnabled
then
	InputModule = require(inputFolder.MobileInput)
	InputModule.Init(mapElements.screenGui)
else
	InputModule = require(inputFolder.PCInput)
	InputModule.Init()
end

----------------------------------------------------
-- SNAPSHOTS
----------------------------------------------------

gameSnapshotEvent.OnClientEvent:Connect(function(packed)
	local snap = GameState.unpackFromNetwork(packed)
	local serverTick = packed[1]

	if serverTick <= lastConfirmedTick then
		return
	end

	lastConfirmedTick = serverTick

	------------------------------------------------
	-- HUD
	------------------------------------------------


	localScoreRed = packed[2]
	localScoreBlue = packed[3]
	localResetCountdown = packed[4]

	hud:UpdateScore(
		localScoreRed,
		localScoreBlue
	)

	------------------------------------------------
	-- PLAYERS
	------------------------------------------------

	local activeIds = {}

	for _, pArr in ipairs(packed[6]) do
		local uId = pArr[1]

		activeIds[uId] = true

		if not playersData[uId] then
			playersData[uId] = {
				pos = Vector2.new(
					pArr[2],
					pArr[3]
				),

				vel = Vector2.new(
					pArr[4],
					pArr[5]
				),

				radius = phys.playerRadius,
				mass = phys.playerMass,
				restitution = 0.1,

				team = pArr[10] == 1 and "Red" or "Blue",

				input = Vector2.new(
					pArr[6],
					pArr[7]
				),

				isKicking = pArr[8] == 1,
				lastKickTick = pArr[9],

				isSolid = true,
				isStatic = false,

				cGroup = buildBitmask(phys.playerGroup),
				cMask = buildBitmask(phys.playerMask)
			}
		end
	end

	------------------------------------------------
	-- REMOVER PLAYERS
	------------------------------------------------

	for uId in pairs(playersData) do
		if not activeIds[uId] then
			playersData[uId] = nil

			local render = playerRenders[uId]

			if render then
				render.frame:Destroy()
				playerRenders[uId] = nil
			end
		end
	end

	rebuildSortedUserIds()

	------------------------------------------------
	-- ROLLBACK
	------------------------------------------------

	GameState.restorePacked(
		packed,
		ball,
		playersData,
		discs,
		segments,
		shapes
	)

	if localTick > serverTick then

		-- O estado restaurado é exatamente serverTick.
		-- Portanto, a simulação precisa continuar de serverTick
		-- até localTick - 1 sem pular ticks.

		for replayTick = serverTick, localTick - 1 do
			applyInputsForTick(replayTick)

			PhysicsEngine.Step(
				ball,
				playersData,
				sortedUserIds,
				discs,
				segments,
				shapes,
				phys,
				FIXED_DT,
				replayTick
			)

			localCheckGoals()
		end

	else
		localTick = serverTick
	end

	------------------------------------------------
	-- LIMPAR INPUTS ANTIGOS
	------------------------------------------------

	localInputBuffer:clearBefore(serverTick - 10)
end)

----------------------------------------------------
-- ENVIO DE INPUT
----------------------------------------------------

local lastSentMoveX = 0
local lastSentMoveY = 0
local lastSentKickState = false

----------------------------------------------------
-- SIMULAÇÃO
----------------------------------------------------

RunService.Heartbeat:Connect(function(dt)

	------------------------------------------------
	-- INPUT
	------------------------------------------------

	currentMoveVector, currentIsKicking =
		InputModule.GetInput()

	------------------------------------------------
	-- FIXED TIMESTEP
	------------------------------------------------

	accumulator += math.min(dt, 0.1)

	while accumulator >= FIXED_DT do

		local inputData: InputBuffer.InputData = {
			moveX = currentMoveVector.X,
			moveY = currentMoveVector.Y,
			kick = currentIsKicking
		}

		localInputBuffer:setLocal(
			localTick,
			inputData
		)

		applyInputsForTick(localTick)

		PhysicsEngine.Step(
			ball,
			playersData,
			sortedUserIds,
			discs,
			segments,
			shapes,
			phys,
			FIXED_DT,
			localTick
		)

		localCheckGoals()

		localTick += 1
		accumulator -= FIXED_DT
	end

	------------------------------------------------
	-- ENVIO DE INPUT
	------------------------------------------------

	local moveX = currentMoveVector.X
	local moveY = currentMoveVector.Y

	if moveX ~= lastSentMoveX
		or moveY ~= lastSentMoveY
		or currentIsKicking ~= lastSentKickState
	then
		lastSentMoveX = moveX
		lastSentMoveY = moveY
		lastSentKickState = currentIsKicking

		gameInputEvent:FireServer(
			localTick,
			currentMoveVector,
			currentIsKicking
		)
	end
end)

----------------------------------------------------
-- RENDERIZAÇÃO
----------------------------------------------------

RunService.RenderStepped:Connect(function(dt)

	local alpha = 1 - math.exp(-35 * dt)

	------------------------------------------------
	-- BOLA
	------------------------------------------------

	renderBallPos =
		renderBallPos:Lerp(
			ball.pos,
			alpha
		)

	ballFrame.Position = UDim2.new(
		0,
		renderBallPos.X,
		0,
		renderBallPos.Y
	)

	------------------------------------------------
	-- PLAYERS
	------------------------------------------------

	local myId = player.UserId

	for _, uId in ipairs(sortedUserIds) do
		local pData = playersData[uId]

		if pData then

			local render = playerRenders[uId]

			if not render then
				local color =
					pData.team == "Red"
					and Color3.fromRGB(220, 60, 60)
					or Color3.fromRGB(60, 120, 220)

				local frame, stroke =
					UIPrimitives.CreateDisc(
						mapElements.field,
						pData.pos,
						phys.playerRadius,
						color,
						3,
						Color3.fromRGB(0, 0, 0)
					)

				render = {
					frame = frame,
					stroke = stroke,
					renderPos = pData.pos,
					lastKicking = pData.isKicking
				}

				playerRenders[uId] = render
			end

			local interpAlpha

			if uId == myId then
				interpAlpha =
					1 - math.exp(-50 * dt)
			else
				interpAlpha =
					1 - math.exp(-25 * dt)
			end

			render.renderPos =
				render.renderPos:Lerp(
					pData.pos,
					interpAlpha
				)

			render.frame.Position = UDim2.new(
				0,
				render.renderPos.X,
				0,
				render.renderPos.Y
			)

			------------------------------------------------
			-- STROKE: só altera quando o estado muda
			------------------------------------------------

			if render.stroke
				and render.lastKicking ~= pData.isKicking
			then
				render.stroke.Color =
					pData.isKicking
					and Color3.fromRGB(255, 255, 255)
					or Color3.fromRGB(0, 0, 0)

				render.lastKicking = pData.isKicking
			end
		end
	end

	------------------------------------------------
	-- REMOVER RENDER DE PLAYERS
	------------------------------------------------

	for uId, render in pairs(playerRenders) do
		if not playersData[uId] then
			render.frame:Destroy()
			playerRenders[uId] = nil
		end
	end

	------------------------------------------------
	-- OBJETOS DINÂMICOS
	--
	-- IMPORTANTE:
	-- Não fazemos mais:
	--   procurar em shapes
	--   procurar em discs
	--   procurar em segments
	--
	-- O objeto já está em render.object.
	------------------------------------------------

	for _, render in pairs(mapDynamicRenders) do

		local object = render.object

		if object then

			------------------------------------------------
			-- DISC / SHAPE
			------------------------------------------------

			if object.pos then

				if render.renderPos then
					render.renderPos =
						render.renderPos:Lerp(
							object.pos,
							alpha
						)
				else
					render.renderPos = object.pos
				end

				local pos = render.renderPos

				render.frame.Position = UDim2.new(
					0,
					pos.X,
					0,
					pos.Y
				)

				------------------------------------------------
				-- SEGMENT
				------------------------------------------------

			elseif object.a and object.b then

				local simA = object.a
				local simB = object.b

				if render.renderA and render.renderB then
					render.renderA =
						render.renderA:Lerp(
							simA,
							alpha
						)

					render.renderB =
						render.renderB:Lerp(
							simB,
							alpha
						)
				else
					render.renderA = simA
					render.renderB = simB
				end

				local rA = render.renderA
				local rB = render.renderB

				local midPoint =
					(rA + rB) / 2

				local diff =
					rB - rA

				local length =
					diff.Magnitude

				local angle =
					math.deg(
						math.atan2(
							diff.Y,
							diff.X
						)
					)

				render.frame.Position =
					UDim2.new(
						0,
						midPoint.X,
						0,
						midPoint.Y
					)

				render.frame.Size =
					UDim2.new(
						0,
						length,
						0,
						render.frame.Size.Y.Offset
					)

				render.frame.Rotation = angle
			end
		end
	end
end)
