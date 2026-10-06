--!strict
-- ClientEngine.local.luau
-- Predição Local + Rollback & Reconciliação.
-- Simulação fixa em 60 Hz.
-- Renderização separada no RenderStepped.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local replicatedModules =
	ReplicatedStorage:WaitForChild("Modules")

local replicatedGameRemotes =
	ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("GameRemotes")

local MapData =
	require(replicatedModules:WaitForChild("MapData"))

local MapRuntime =
	require(replicatedModules:WaitForChild("MapRuntime"))

local PhysicsEngine =
	require(replicatedModules:WaitForChild("PhysicsEngine"))

local GameState =
	require(replicatedModules:WaitForChild("GameState"))

local InputBuffer =
	require(replicatedModules:WaitForChild("InputBuffer"))

local Renderers =
	replicatedModules:WaitForChild("Renderers")

local UIPrimitives =
	require(Renderers:WaitForChild("UIPrimitives"))

local MapRenderer =
	require(Renderers:WaitForChild("MapRenderer"))

local HUDRenderer =
	require(Renderers:WaitForChild("HUDRenderer"))

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

local player =
	Players.LocalPlayer

local playerGui = player:WaitForChild("PlayerGui")

local gameInputEvent =
	replicatedGameRemotes:WaitForChild("GameInput")

local gameSnapshotEvent =
	replicatedGameRemotes:WaitForChild("GameSnapshot")

local inputFolder =
	replicatedModules:WaitForChild("Inputs")

local currentMap =
	MapRuntime.Build(MapData.Default)

local playerGameplay =
	currentMap.gameplay.player

local playerObjectId =
	playerGameplay.object

----------------------------------------------------
-- BITMASK
----------------------------------------------------

local DEFAULT_MASK =
	0xFFFFFFFF

local groupMap:
	{[string]: number} = {}

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
			local bitIndex =
				groupMap[name]

			if bitIndex then
				mask = bit32.bor(
					mask,
					bit32.lshift(
						1,
						bitIndex - 1
					)
				)
			end
		end
	end

	return mask
end

----------------------------------------------------
-- SEGMENTOS
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

	local processed:
		{PhysicsEngine.Segment} = {}

	if not rawSegments then
		return processed
	end

	for idx, seg in ipairs(rawSegments) do

		------------------------------------------------
		-- O OBJETO USADO COMO PLAYER É APENAS MOLDE.
		------------------------------------------------

		if seg.id == playerObjectId then
			continue
		end

		local curve =
			seg.curve or 0

		local rotation =
			seg.rotation or 0

		if curve == 0 then

			local rotatedA, rotatedB =
				rotateSegmentPoints(
					seg.a,
					seg.b,
					rotation
				)

			processed[#processed + 1] = {
				id =
					seg.id
					or ("seg_" .. idx),

				a =
					rotatedA,

				b =
					rotatedB,

				vel =
					Vector2.zero,

				mass =
					seg.mass or 1,

				restitution =
					seg.restitution or 0.5,

				isStatic =
					(seg.isStatic ~= false),

				isSolid =
					(seg.isSolid ~= false),

				damping =
					seg.damping or 0.98,

				resettable =
					(seg.resettable ~= false),

				rotation =
					seg.rotation or 0,

				rotationLocked =
					(seg.rotationLocked ~= false),

				angularVelocity =
					seg.angularVelocity or 0,

				thickness =
					seg.thickness,

				ignoreCapA =
					seg.ignoreCapA,

				ignoreCapB =
					seg.ignoreCapB,

				cGroup =
					buildBitmask(
						seg.cGroup
					),

				cMask =
					buildBitmask(
						seg.cMask
					)
			}

		else

			local rotatedA, rotatedB =
				rotateSegmentPoints(
					seg.a,
					seg.b,
					rotation
				)

			local samples =
				seg.curveSegments or 10

			local ab =
				rotatedB - rotatedA

			if ab.Magnitude == 0 then
				continue
			end

			local normal =
				Vector2.new(
					-ab.Y,
					ab.X
				).Unit

			local control =
				(rotatedA + rotatedB) / 2
				+ normal * curve

			local prevPoint =
				rotatedA

			for i = 1, samples do

				local t =
					i / samples

				local invT =
					1 - t

				local currentPoint =
					(invT * invT * rotatedA)
					+ (2 * invT * t * control)
					+ (t * t * rotatedB)

				processed[#processed + 1] = {

					id =
						(seg.id or ("seg_" .. idx))
						.. "_"
						.. i,

					sourceId =
						seg.id
						or ("seg_" .. idx),

					curvePieceIndex =
						i,

					curvePieceCount =
						samples,

					a =
						prevPoint,

					b =
						currentPoint,

					vel =
						Vector2.zero,

					mass =
						seg.mass or 1,

					restitution =
						seg.restitution or 0.5,

					isStatic =
						(seg.isStatic ~= false),

					isSolid =
						(seg.isSolid ~= false),

					damping =
						seg.damping or 0.98,

					resettable =
						(seg.resettable ~= false),

					rotation =
						seg.rotation or 0,

					rotationLocked =
						(seg.rotationLocked ~= false),

					angularVelocity =
						seg.angularVelocity or 0,

					thickness =
						seg.thickness,

					ignoreCapA =
						seg.ignoreCapA,

					ignoreCapB =
						seg.ignoreCapB,

					cGroup =
						buildBitmask(
							seg.cGroup
						),

					cMask =
						buildBitmask(
							seg.cMask
						)
				}

				prevPoint =
					currentPoint
			end
		end
	end

	return processed
end

----------------------------------------------------
-- ESTADO LOCAL
----------------------------------------------------

local playersData:
	{[number]: PhysicsEngine.PlayerObject} = {}

local sortedUserIds:
	{number} = {}

----------------------------------------------------
-- OBJETOS
----------------------------------------------------

local objects:
	{PhysicsEngine.Object} = {}

if currentMap.objects then
	for idx, objectData in ipairs(currentMap.objects) do

		-- O playerObject é um molde, não um objeto
		-- físico independente do mapa.

		if objectData.id ~= playerObjectId then

			local cornerPx = 0

			if typeof(objectData.cornerRadius) == "UDim" then

				cornerPx =
					math.min(
						objectData.size.X,
						objectData.size.Y
					)
					* objectData.cornerRadius.Scale
					+ objectData.cornerRadius.Offset

			elseif typeof(objectData.cornerRadius) == "number" then

				cornerPx =
					objectData.cornerRadius
			end

			local object:
				PhysicsEngine.Object = {

				id =
					objectData.id
					or ("object_" .. idx),

				pos =
					objectData.pos,

				vel =
					Vector2.zero,

				size =
					objectData.size,

				mass =
					objectData.mass or 1,

				restitution =
					objectData.restitution or 0.5,

				isStatic =
					(objectData.isStatic ~= false),

				isSolid =
					(objectData.isSolid ~= false),

				damping =
					objectData.damping or 0.98,

				resettable =
					(objectData.resettable ~= false),

				rotation =
					objectData.rotation or 0,

				rotationLocked =
					(objectData.rotationLocked ~= false),

				angularVelocity =
					objectData.angularVelocity or 0,

				cornerRadius =
					cornerPx,

				cGroup =
					buildBitmask(
						objectData.cGroup
					),

				cMask =
					buildBitmask(
						objectData.cMask
					),

				segmentP1 =
					Vector2.zero,

				segmentP2 =
					Vector2.zero,

				segmentRadius =
					0
			}

			PhysicsEngine.prepareObject(
				object
			)

			objects[#objects + 1] =
				object
		end
	end
end

----------------------------------------------------
-- SEGMENTOS
----------------------------------------------------

local segments:
	{PhysicsEngine.Segment} =
	processSegments(
		currentMap.segments
	)

----------------------------------------------------
-- MOLDE DO PLAYER
----------------------------------------------------

local playerTemplate:
	any = nil

if currentMap.objects then

	for _, object in ipairs(currentMap.objects) do

		if object.id == playerObjectId then

			playerTemplate =
				object

			break
		end
	end
end

if not playerTemplate
	and currentMap.segments
then

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
			.. tostring(playerObjectId)
	)
end

----------------------------------------------------
-- OBJETOS DINÂMICOS
----------------------------------------------------

local dynamicObjects:
	{[string]: any} = {}

for _, object in ipairs(objects) do

	if object.isStatic == false then

		dynamicObjects[object.id] =
			object
	end
end

for _, segment in ipairs(segments) do

	if segment.isStatic == false then

		dynamicObjects[segment.id] =
			segment
	end
end

----------------------------------------------------
-- OBJETOS POR ID
----------------------------------------------------

local objectsById:
	{[string]: any} = {}

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
-- OBJETOS CHUTÁVEIS
----------------------------------------------------

local kickableObjects:
	{any} = {}

local kickableIds =
	currentMap.gameplay.kickable

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

local collisionObjects:
	{PhysicsEngine.Object} = {}

for _, object in ipairs(objects) do

	if object.isSolid ~= false then

		collisionObjects[#collisionObjects + 1] =
			object
	end
end

local collisionSegments:
	{PhysicsEngine.Segment} = {}

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
-- MOLDE DO PLAYER
----------------------------------------------------

local playerTemplate:any = nil

if currentMap.objects then

	for _, object in ipairs(currentMap.objects) do

		if object.id == playerObjectId then

			playerTemplate = object

			break
		end
	end
end

if not playerTemplate
	and currentMap.segments
then

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
			.. tostring(playerObjectId)
	)
end

----------------------------------------------------
-- OBJETOS DINÂMICOS
----------------------------------------------------

local dynamicObjects:
	{[string]: any} = {}

for _, object in ipairs(shapes) do

	if object.isStatic == false then

		dynamicObjects[object.id] =
			object
	end
end

for _, object in ipairs(discs) do

	if object.isStatic == false then

		dynamicObjects[object.id] =
			object
	end
end

for _, object in ipairs(segments) do

	if object.isStatic == false then

		dynamicObjects[object.id] =
			object
	end
end

----------------------------------------------------
-- OBJETOS POR ID
----------------------------------------------------

local objectsById:
	{[string]: any} = {}

for _, object in ipairs(discs) do

	if object.id then

		objectsById[object.id] =
			object
	end
end

for _, object in ipairs(segments) do

	if object.id then

		objectsById[object.id] =
			object
	end
end

for _, object in ipairs(shapes) do

	if object.id then

		objectsById[object.id] =
			object
	end
end

----------------------------------------------------
-- OBJETOS CHUTÁVEIS
----------------------------------------------------

local kickableObjects:
	{any} = {}

local kickableIds =
	currentMap.gameplay.kickable

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

local collisionDiscs = {}

for _, d in ipairs(discs) do

	if d.isSolid ~= false then

		collisionDiscs[#collisionDiscs + 1] =
			d
	end
end

local collisionSegments = {}

for _, seg in ipairs(segments) do

	if seg.isSolid ~= false then

		collisionSegments[#collisionSegments + 1] =
			seg
	end
end

local collisionShapes = {}

for _, s in ipairs(shapes) do

	if s.isSolid ~= false then

		collisionShapes[#collisionShapes + 1] =
			s
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
-- ESTADO DE REDE
----------------------------------------------------

local localInputBuffer =
	InputBuffer.new(300)

local FIXED_DT =
	1 / 60

local localTick =
	0

local lastConfirmedTick =
	-1

local accumulator =
	0

local currentMoveVector =
	Vector2.zero

local currentIsKicking =
	false

local localScoreRed =
	0

local localScoreBlue =
	0

local localResetCountdown =
	0

----------------------------------------------------
-- FUNÇÕES UTILITÁRIAS
----------------------------------------------------

local function rebuildSortedUserIds()

	sortedUserIds = {}

	for uId in pairs(playersData) do

		sortedUserIds[#sortedUserIds + 1] =
			uId
	end

	table.sort(
		sortedUserIds
	)
end

----------------------------------------------------
-- CRIAÇÃO DE PLAYER A PARTIR DO SNAPSHOT
----------------------------------------------------

local function createPlayerFromSnapshot(
	pArr: any
): PhysicsEngine.PlayerObject

	local kindCode =
		pArr[11]

	local kind:
		"object" | "segment"

	if kindCode == 2 then

		kind =
			"segment"

	else

		kind =
			"object"
	end

	local team =
		pArr[10] == 1
		and "Team1"
		or "Team2"

	local collisionGroup =
		buildBitmask(
			playerGameplay.collision.group
		)

	local collisionMask =
		buildBitmask(
			playerGameplay.collision.mask
		)

	------------------------------------------------
	-- SEGMENT
	------------------------------------------------

	if kind == "segment" then

		return {

			kind =
				"segment",

			id =
				playerObjectId,

			vel =
				Vector2.new(
					pArr[4],
					pArr[5]
				),

			a =
				Vector2.new(
					pArr[12],
					pArr[13]
				),

			b =
				Vector2.new(
					pArr[14],
					pArr[15]
				),

			thickness =
				playerTemplate.thickness,

			ignoreCapA =
				playerTemplate.ignoreCapA,

			ignoreCapB =
				playerTemplate.ignoreCapB,

			mass =
				playerTemplate.mass or 1,

			restitution =
				playerTemplate.restitution or 0.1,

			isStatic =
				false,

			isSolid =
				true,

			team =
				team,

			input =
				Vector2.new(
					pArr[6],
					pArr[7]
				),

			isKicking =
				pArr[8] == 1,

			lastKickTick =
				pArr[9],

			cGroup =
				collisionGroup,

			cMask =
				collisionMask
		}
	end

	------------------------------------------------
	-- OBJECT
	------------------------------------------------

	local cornerPx = 0

	if typeof(playerTemplate.cornerRadius) == "UDim" then

		cornerPx =
			math.min(
				playerTemplate.size.X,
				playerTemplate.size.Y
			)
			* playerTemplate.cornerRadius.Scale
			+ playerTemplate.cornerRadius.Offset

	elseif typeof(playerTemplate.cornerRadius) == "number" then

		cornerPx =
			playerTemplate.cornerRadius
	end

	local playerObject:
		PhysicsEngine.PlayerObject = {

		kind =
			"object",

		id =
			playerObjectId,

		pos =
			Vector2.new(
				pArr[2],
				pArr[3]
			),

		vel =
			Vector2.new(
				pArr[4],
				pArr[5]
			),

		size =
			playerTemplate.size,

		mass =
			playerTemplate.mass or 1,

		restitution =
			playerTemplate.restitution or 0.1,

		isStatic =
			false,

		isSolid =
			true,

		team =
			team,

		input =
			Vector2.new(
				pArr[6],
				pArr[7]
			),

		isKicking =
			pArr[8] == 1,

		lastKickTick =
			pArr[9],

		rotation =
			playerTemplate.rotation or 0,

		rotationLocked =
			(playerTemplate.rotationLocked ~= false),

		angularVelocity =
			0,

		cornerRadius =
			cornerPx,

		cGroup =
			collisionGroup,

		cMask =
			collisionMask,

		segmentP1 =
			Vector2.zero,

		segmentP2 =
			Vector2.zero,

		segmentRadius =
			0
	}

	local temporaryObject:
		PhysicsEngine.Object = {

		id =
			playerObjectId,

		pos =
			playerObject.pos :: Vector2,

		vel =
			Vector2.zero,

		size =
			playerTemplate.size,

		mass =
			playerObject.mass,

		restitution =
			playerObject.restitution,

		isStatic =
			false,

		isSolid =
			true,

		damping =
			playerTemplate.damping or 0.98,

		resettable =
			false,

		rotation =
			playerTemplate.rotation or 0,

		rotationLocked =
			(playerTemplate.rotationLocked ~= false),

		angularVelocity =
			0,

		cornerRadius =
			cornerPx,

		cGroup =
			collisionGroup,

		cMask =
			collisionMask,

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

	playerObject.segmentP1 =
		temporaryObject.segmentP1

	playerObject.segmentP2 =
		temporaryObject.segmentP2

	playerObject.segmentRadius =
		temporaryObject.segmentRadius

	return playerObject
end

----------------------------------------------------
-- INPUTS
----------------------------------------------------

local function applyInputsForTick(
	tick: number
)

	local myId =
		player.UserId

	for _, uId in ipairs(sortedUserIds) do

		local pData =
			playersData[uId]

		if pData
			and uId == myId
		then

			local input =
				localInputBuffer:getLocal(
					tick
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
-- RENDERIZAÇÃO DO MAPA
----------------------------------------------------

local mapElements =
	MapRenderer.Build(
		currentMap,
		playerGui
	)

----------------------------------------------------
-- REMOVER O MOLDE DO PLAYER DO MAPA
----------------------------------------------------

local playerTemplateFrame =
	mapElements.field:FindFirstChild(
		playerObjectId
	)

if playerTemplateFrame then
	playerTemplateFrame:Destroy()
end

----------------------------------------------------
-- HUD
----------------------------------------------------

local hud =
	HUDRenderer.Build(
		mapElements.screenGui
	)

----------------------------------------------------
-- PLAYER RENDER
----------------------------------------------------

type PlayerRender = {
	frame: Frame,
	stroke: UIStroke?,
	kind: "disc" | "segment",
	renderPos: Vector2?,
	renderA: Vector2?,
	renderB: Vector2?,
	lastKicking: boolean
}

local playerRenders:
	{[number]: PlayerRender} = {}

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

local mapDynamicRenders:
	{[string]: DynamicRender} = {}

for id, frame in pairs(
	mapElements.dynamicFrames
	) do

	mapDynamicRenders[id] = {

		frame =
			frame,

		object =
			dynamicObjects[id],

		renderPos =
			nil,

		renderA =
			nil,

		renderB =
			nil
	}
end

----------------------------------------------------
-- INPUT MODULE
----------------------------------------------------

local InputModule

if UserInputService.TouchEnabled
	and not UserInputService.KeyboardEnabled
then

	InputModule =
		require(
			inputFolder.MobileInput
		)

	InputModule.Init(
		mapElements.screenGui
	)

else

	InputModule =
		require(
			inputFolder.PCInput
		)

	InputModule.Init()
end

----------------------------------------------------
-- CRIAÇÃO DO RENDER DO PLAYER
----------------------------------------------------

local function createPlayerRender(
	pData: PhysicsEngine.PlayerObject
): PlayerRender

	local color =
		pData.team == "Team1"
		and Color3.fromRGB(
			220,
			60,
			60
		)
		or Color3.fromRGB(
			60,
			120,
			220
		)

	------------------------------------------------
	-- OBJECT
	------------------------------------------------

	if pData.kind == "object" then

		local frame, stroke =
			UIPrimitives.CreateShape(
				mapElements.field,
				{
					id =
						"Player_" .. tostring(pData.id),

					pos =
						pData.pos :: Vector2,

					size =
						pData.size :: Vector2,

					color =
						color,

					cornerRadius =
						pData.cornerRadius,

					strokeWidth =
						3,

					strokeColor =
						Color3.fromRGB(
							0,
							0,
							0
						),

					rotation =
						pData.rotation or 0
				}
			)

		return {

			frame =
				frame,

			stroke =
				stroke,

			kind =
				"object",

			renderPos =
				pData.pos,

			renderA =
				nil,

			renderB =
				nil,

			lastKicking =
				pData.isKicking or false
		}
	end

	------------------------------------------------
	-- SEGMENT
	------------------------------------------------

	local frame =
		UIPrimitives.CreateSegment(
			mapElements.field,

			pData.a :: Vector2,

			pData.b :: Vector2,

			pData.thickness or 1,

			color,

			"Player_" .. tostring(pData.id)
		)

	return {

		frame =
			frame,

		stroke =
			nil,

		kind =
			"segment",

		renderPos =
			nil,

		renderA =
			pData.a,

		renderB =
			pData.b,

		lastKicking =
			pData.isKicking or false
	}
end

----------------------------------------------------
-- SNAPSHOTS
----------------------------------------------------

gameSnapshotEvent.OnClientEvent:Connect(
	function(packed)

		local serverTick =
			packed[1]

		if serverTick <=
			lastConfirmedTick
		then
			return
		end

		lastConfirmedTick =
			serverTick

		------------------------------------------------
		-- HUD
		------------------------------------------------

		localScoreRed =
			packed[2]

		localScoreBlue =
			packed[3]

		localResetCountdown =
			packed[4]

		hud:UpdateScore(
			localScoreRed,
			localScoreBlue
		)

		------------------------------------------------
		-- PLAYERS
		------------------------------------------------

		local activeIds:
			{[number]: boolean} = {}

		for _, pArr in ipairs(
			packed[5]
			) do

			local uId =
				pArr[1]

			activeIds[uId] =
				true

			if not playersData[uId] then

				playersData[uId] =
					createPlayerFromSnapshot(
						pArr
					)
			end
		end

		------------------------------------------------
		-- REMOVER PLAYERS
		------------------------------------------------

		for uId in pairs(playersData) do

			if not activeIds[uId] then

				playersData[uId] =
					nil

				local render =
					playerRenders[uId]

				if render then

					render.frame:Destroy()

					playerRenders[uId] =
						nil
				end
			end
		end

		rebuildSortedUserIds()

		------------------------------------------------
		-- RESTORE DO SNAPSHOT
		------------------------------------------------

		GameState.restorePacked(packed, playersData, objects, segments)

		------------------------------------------------
		-- ROLLBACK
		------------------------------------------------

		if localTick > serverTick then

			for replayTick =
				serverTick,
				localTick - 1
			do
				applyInputsForTick(replayTick)
				PhysicsEngine.Step(playersData, sortedUserIds, objects, segments, broadphase, currentMap.gameplay, kickableObjects, FIXED_DT, replayTick)
			end

		else
			localTick = serverTick
		end

		------------------------------------------------
		-- LIMPAR INPUTS ANTIGOS
		------------------------------------------------

		localInputBuffer:clearBefore(serverTick - 10)
	end
)

----------------------------------------------------
-- ENVIO DE INPUT
----------------------------------------------------

local lastSentMoveX =
	0

local lastSentMoveY =
	0

local lastSentKickState =
	false

----------------------------------------------------
-- SIMULAÇÃO
----------------------------------------------------

RunService.Heartbeat:Connect(
	function(dt)

		------------------------------------------------
		-- INPUT
		------------------------------------------------

		currentMoveVector,
		currentIsKicking =
			InputModule.GetInput()

		------------------------------------------------
		-- FIXED TIMESTEP
		------------------------------------------------

		accumulator +=
			math.min(
				dt,
				0.1
			)

		while accumulator >= FIXED_DT do

			local inputData:
				InputBuffer.InputData = {

					moveX = currentMoveVector.X,

					moveY = currentMoveVector.Y,

					kick = currentIsKicking
				}

			localInputBuffer:setLocal(localTick, inputData)

			applyInputsForTick(localTick)

			PhysicsEngine.Step(playersData, sortedUserIds, objects, segments, broadphase, currentMap.gameplay, kickableObjects, FIXED_DT, localTick)

			localTick += 1

			accumulator -= FIXED_DT
		end

		------------------------------------------------
		-- ENVIO DE INPUT
		------------------------------------------------

		local moveX = currentMoveVector.X

		local moveY = currentMoveVector.Y

		if
			moveX ~= lastSentMoveX
			or moveY ~= lastSentMoveY
			or currentIsKicking
			~= lastSentKickState
		then

			lastSentMoveX = moveX

			lastSentMoveY = moveY

			lastSentKickState = currentIsKicking

			gameInputEvent:FireServer(localTick, currentMoveVector, currentIsKicking)
		end
	end
)

local function worldToGui(
	worldPosition: Vector2
): Vector2

	return UIPrimitives.WorldToGui(
		mapElements.field,
		worldPosition
	)
end

----------------------------------------------------
-- RENDERIZAÇÃO
----------------------------------------------------

RunService.RenderStepped:Connect(
	function(dt)

		local alpha =
			1 - math.exp(
				-35 * dt
			)

		local myId =
			player.UserId

		------------------------------------------------
		-- PLAYERS
		------------------------------------------------

		for _, uId in ipairs(
			sortedUserIds
			) do

			local pData =
				playersData[uId]

			if pData then

				local render =
					playerRenders[uId]

				------------------------------------------------
				-- CRIAR RENDER
				------------------------------------------------

				if not render then

					render =
						createPlayerRender(
							pData
						)

					playerRenders[uId] =
						render
				end

				------------------------------------------------
				-- CASO O TIPO TENHA MUDADO
				------------------------------------------------

				if render.kind
					~= pData.kind
				then

					render.frame:Destroy()

					render =
						createPlayerRender(
							pData
						)

					playerRenders[uId] =
						render
				end

				local interpAlpha

				if uId == myId then

					interpAlpha =
						1 - math.exp(
							-50 * dt
						)

				else

					interpAlpha =
						1 - math.exp(
							-25 * dt
						)
				end

				------------------------------------------------
				-- DISC / SHAPE
				------------------------------------------------

				if pData.kind == "object" then

					local pos =
						pData.pos :: Vector2

					render.renderPos =
						(render.renderPos :: Vector2):Lerp(
							pos,
							interpAlpha
						)

					local guiPosition =
						worldToGui(
							render.renderPos :: Vector2
						)

					render.frame.Position =
						UDim2.new(
							0,
							guiPosition.X,
							0,
							guiPosition.Y
						)

					render.frame.Rotation = pData.rotation or 0

					------------------------------------------------
					-- SEGMENT
					------------------------------------------------

				else

					local a =
						pData.a :: Vector2

					local b =
						pData.b :: Vector2

					render.renderA =
						(render.renderA :: Vector2):Lerp(
							a,
							interpAlpha
						)

					render.renderB =
						(render.renderB :: Vector2):Lerp(
							b,
							interpAlpha
						)

					local rA =
						render.renderA :: Vector2

					local rB =
						render.renderB :: Vector2

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

					local guiPosition =
						worldToGui(
							midPoint
						)

					render.frame.Position =
						UDim2.new(
							0,
							guiPosition.X,
							0,
							guiPosition.Y
						)

					render.frame.Size =
						UDim2.new(
							0,
							length,
							0,
							render.frame.Size.Y.Offset
						)

					render.frame.Rotation =
						angle
				end

				------------------------------------------------
				-- KICK VISUAL
				------------------------------------------------

				if
					render.stroke
					and render.lastKicking
					~= pData.isKicking
				then

					render.stroke.Color =
						pData.isKicking
						and Color3.fromRGB(
							255,
							255,
							255
						)
						or Color3.fromRGB(
							0,
							0,
							0
						)

					render.lastKicking =
						pData.isKicking
				end
			end
		end

		------------------------------------------------
		-- REMOVER RENDER DE PLAYERS
		------------------------------------------------

		for uId, render in pairs(
			playerRenders
			) do

			if not playersData[uId] then

				render.frame:Destroy()

				playerRenders[uId] =
					nil
			end
		end

		------------------------------------------------
		-- OBJETOS DINÂMICOS
		------------------------------------------------

		for _, render in pairs(
			mapDynamicRenders
			) do

			local object =
				render.object

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

						render.renderPos =
							object.pos
					end

					local pos =
						render.renderPos

					local guiPosition =
						worldToGui(
							pos
						)

					render.frame.Position =
						UDim2.new(
							0,
							guiPosition.X,
							0,
							guiPosition.Y
						)

					------------------------------------------------
					-- SHAPE ROTATION
					------------------------------------------------

					if object.size then

						render.frame.Rotation =
							object.rotation or 0
					end

					------------------------------------------------
					-- SEGMENT
					------------------------------------------------

				elseif object.a
					and object.b
				then

					local simA =
						object.a

					local simB =
						object.b

					if render.renderA
						and render.renderB
					then

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

						render.renderA =
							simA

						render.renderB =
							simB
					end

					local rA =
						render.renderA

					local rB =
						render.renderB

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

					local guiPosition =
						worldToGui(
							midPoint
						)

					render.frame.Position =
						UDim2.new(
							0,
							guiPosition.X,
							0,
							guiPosition.Y
						)

					render.frame.Size =
						UDim2.new(
							0,
							length,
							0,
							render.frame.Size.Y.Offset
						)

					render.frame.Rotation =
						angle
				end
			end
		end
	end
)
