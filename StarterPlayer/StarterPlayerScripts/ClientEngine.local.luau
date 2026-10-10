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

local TeamSettings = require(replicatedModules:WaitForChild("TeamSettings"))

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
	for idx, object in ipairs(currentMap.objects) do

		-- O objeto usado como player é apenas molde.
		-- Ele será criado a partir dos snapshots dos players.

		if object.id ~= playerObjectId then

			local objectData:
				PhysicsEngine.Object = {

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
					object.rotation or 0,

				rotationLocked =
					(object.rotationLocked ~= false),

				angularVelocity =
					object.angularVelocity or 0,

				cornerRadius =
					object.cornerRadius,

				mass =
					object.mass or 1,

				restitution =
					object.restitution or 0.5,

				isStatic =
					(object.isStatic ~= false),

				isSolid =
					(object.isSolid ~= false),

				damping =
					object.damping or 0.98,

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
				objectData
			)

			objects[#objects + 1] =
				objectData
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

for _, object in ipairs(objects) do

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

local collisionObjects = {}

for _, object in ipairs(objects) do

	if object.isSolid ~= false then

		collisionObjects[#collisionObjects + 1] =
			object
	end
end

local collisionSegments = {}

for _, seg in ipairs(segments) do

	if seg.isSolid ~= false then

		collisionSegments[#collisionSegments + 1] =
			seg
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

		kind = "segment"

	else

		kind = "object"
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

	local common = {

		id =
			playerObjectId,

		vel =
			Vector2.new(
				pArr[4],
				pArr[5]
			),

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

	------------------------------------------------
	-- OBJECT
	------------------------------------------------

	if kind == "object" then

		local cornerRadius =
			playerTemplate.cornerRadius

		local playerObject:
			PhysicsEngine.PlayerObject = {

			kind =
				"object",

			id =
				common.id,

			pos =
				Vector2.new(
					pArr[2],
					pArr[3]
				),

			vel =
				common.vel,

			mass =
				common.mass,

			restitution =
				common.restitution,

			size =
				playerTemplate.size,

			rotation =
				playerTemplate.rotation or 0,

			cornerRadius =
				cornerRadius,

			segmentP1 =
				Vector2.zero,

			segmentP2 =
				Vector2.zero,

			segmentRadius =
				0,

			isStatic =
				common.isStatic,

			isSolid =
				common.isSolid,

			team =
				common.team,

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

		PhysicsEngine.prepareObject(
			playerObject
		)

		return playerObject
	end

	------------------------------------------------
	-- SEGMENT
	------------------------------------------------

	local a =
		Vector2.new(
			pArr[12],
			pArr[13]
		)

	local b =
		Vector2.new(
			pArr[14],
			pArr[15]
		)

	return {

		kind =
			"segment",

		id =
			common.id,

		vel =
			common.vel,

		a =
			a,

		b =
			b,

		thickness =
			playerTemplate.thickness,

		ignoreCapA =
			playerTemplate.ignoreCapA,

		ignoreCapB =
			playerTemplate.ignoreCapB,

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
	uniformFrame: Frame?,
	kind: "object" | "segment",
	team: string,
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

	local teamSettings =
		pData.team == "Team1"
		and TeamSettings.teams.Team1
		or TeamSettings.teams.Team2

	local color =
		teamSettings.uniform.base.color

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

		------------------------------------------------
		-- CONTAINER DA UNIFORME
		------------------------------------------------

		local uniformFrame =
			Instance.new("Frame")

		uniformFrame.Name =
			"Uniform"

		uniformFrame.Size =
			UDim2.fromScale(
				1,
				1
			)

		uniformFrame.Position =
			UDim2.fromScale(
				0,
				0
			)

		uniformFrame.BackgroundTransparency =
			1

		uniformFrame.BorderSizePixel =
			0

		uniformFrame.ClipsDescendants =
			true

		uniformFrame.ZIndex =
			frame.ZIndex + 1

		uniformFrame.Parent =
			frame

		------------------------------------------------
		-- CAMADAS DA UNIFORME
		------------------------------------------------

		local layers =
			teamSettings.uniform.layers

		for index, layer in ipairs(layers) do

			local element

			if layer.type == "frame" then

				local frameLayer =
					Instance.new("Frame")

				frameLayer.Name =
					"Layer_" .. tostring(index)

				frameLayer.BackgroundColor3 =
					layer.color
					or Color3.new(
						1,
						1,
						1
					)

				frameLayer.BackgroundTransparency =
					layer.transparency
					or 0

				frameLayer.BorderSizePixel =
					0

				element =
					frameLayer

			elseif layer.type == "image" then

				local imageLayer =
					Instance.new("ImageLabel")

				imageLayer.Name =
					"Layer_" .. tostring(index)

				imageLayer.Image =
					layer.image
					or ""

				imageLayer.ImageTransparency =
					layer.transparency
					or 0

				imageLayer.BackgroundTransparency =
					1

				imageLayer.BorderSizePixel =
					0

				imageLayer.ScaleType =
					Enum.ScaleType.Stretch

				element =
					imageLayer
			end

			if element then

				element.AnchorPoint =
					Vector2.new(
						0.5,
						0.5
					)

				element.Position =
					UDim2.fromScale(
						(
							layer.position
							and layer.position.x
						)
						or 0.5,

						(
							layer.position
							and layer.position.y
						)
						or 0.5
					)

				element.Size =
					UDim2.fromScale(
						(
							layer.size
							and layer.size.x
						)
						or 1,

						(
							layer.size
							and layer.size.y
						)
						or 1
					)

				element.Rotation =
					layer.rotation
					or 0

				element.ZIndex =
					uniformFrame.ZIndex
					+ index

				element.Parent =
					uniformFrame
			end
		end

		return {

			frame =
				frame,

			stroke =
				stroke,

			uniformFrame =
				uniformFrame,

			kind =
				"object",

			team =
				pData.team,

			renderPos =
				pData.pos,

			renderA =
				nil,

			renderB =
				nil,

			lastKicking =
				pData.isKicking
				or false
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

		uniformFrame =
			nil,

		kind =
			"segment",

		team =
			pData.team,

		renderPos =
			nil,

		renderA =
			pData.a,

		renderB =
			pData.b,

		lastKicking =
			pData.isKicking
			or false
	}
end

local function captureRenderState()

	------------------------------------------------
	-- PLAYERS
	------------------------------------------------

	for _, uId in ipairs(sortedUserIds) do

		local pData =
			playersData[uId]

		if pData then

			local render =
				playerRenders[uId]

			if not render then
				continue
			end

			if pData.kind == "object" then

				render.renderPos =
					pData.pos

			else

				render.renderA =
					pData.a

				render.renderB =
					pData.b
			end
		end
	end

	------------------------------------------------
	-- DYNAMIC OBJECTS
	------------------------------------------------

	for id, render in pairs(
		mapDynamicRenders
	) do

		local object =
			render.object

		if not object then
			continue
		end

		if object.pos then

			render.renderPos =
				object.pos

		elseif object.a
			and object.b
		then

			render.renderA =
				object.a

			render.renderB =
				object.b
		end
	end
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

		GameState.restorePacked(
			packed,
			playersData,
			objects,
			segments
		)

		------------------------------------------------
		-- ROLLBACK
		------------------------------------------------

		if localTick > serverTick then

			for replayTick =
				serverTick,
				localTick - 1
			do

				applyInputsForTick(
					replayTick
				)

				PhysicsEngine.Step(
					playersData,
					sortedUserIds,
					objects,
					segments,
					broadphase,
					currentMap.gameplay,
					kickableObjects,
					FIXED_DT,
					replayTick
				)
			end

		else

			localTick =
				serverTick
		end

		------------------------------------------------
		-- LIMPAR INPUTS ANTIGOS
		------------------------------------------------

		localInputBuffer:clearBefore(
			serverTick - 10
		)
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

			------------------------------------------------
			-- CAPTURAR ESTADO ANTERIOR AO STEP
			------------------------------------------------

			captureRenderState()

			------------------------------------------------
			-- INPUT DO TICK
			------------------------------------------------

			local inputData:
				InputBuffer.InputData = {

					moveX =
						currentMoveVector.X,

					moveY =
						currentMoveVector.Y,

					kick =
						currentIsKicking
				}

			localInputBuffer:setLocal(
				localTick,
				inputData
			)

			applyInputsForTick(
				localTick
			)

			------------------------------------------------
			-- SIMULAÇÃO
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
				localTick
			)

			localTick +=
				1

			accumulator -=
				FIXED_DT
		end

		------------------------------------------------
		-- ENVIO DE INPUT
		------------------------------------------------

		local moveX =
			currentMoveVector.X

		local moveY =
			currentMoveVector.Y

		if
			moveX ~= lastSentMoveX
			or moveY ~= lastSentMoveY
			or currentIsKicking
			~= lastSentKickState
		then

			lastSentMoveX =
				moveX

			lastSentMoveY =
				moveY

			lastSentKickState =
				currentIsKicking

			gameInputEvent:FireServer(
				localTick,
				currentMoveVector,
				currentIsKicking
			)
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
	function()

		------------------------------------------------
		-- INTERPOLAÇÃO TEMPORAL REAL
		------------------------------------------------

		local interpAlpha =
			math.clamp(
				accumulator / FIXED_DT,
				0,
				1
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

				------------------------------------------------
				-- CASO A EQUIPE TENHA MUDADO
				------------------------------------------------

				if render.team ~= pData.team then

					render.frame:Destroy()

					render =
						createPlayerRender(
							pData
						)

					playerRenders[uId] =
						render
				end

				------------------------------------------------
				-- OBJECT
				------------------------------------------------

				if pData.kind == "object" then

					local currentPos =
						pData.pos :: Vector2

					local previousPos =
						render.renderPos
						or currentPos

					local renderPos =
						previousPos:Lerp(
							currentPos,
							interpAlpha
						)

					local guiPosition =
						worldToGui(
							renderPos
						)

					render.frame.Position =
						UDim2.new(
							0,
							guiPosition.X,
							0,
							guiPosition.Y
						)

					render.frame.Rotation =
						pData.rotation
						or 0

				------------------------------------------------
				-- SEGMENT
				------------------------------------------------

				else

					local currentA =
						pData.a :: Vector2

					local currentB =
						pData.b :: Vector2

					local previousA =
						render.renderA
						or currentA

					local previousB =
						render.renderB
						or currentB

					local renderA =
						previousA:Lerp(
							currentA,
							interpAlpha
						)

					local renderB =
						previousB:Lerp(
							currentB,
							interpAlpha
						)

					local midPoint =
						(renderA + renderB) / 2

					local diff =
						renderB - renderA

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
				-- OBJECT
				------------------------------------------------

				if object.pos then

					local currentPos =
						object.pos

					local previousPos =
						render.renderPos
						or currentPos

					local renderPos =
						previousPos:Lerp(
							currentPos,
							interpAlpha
						)

					local guiPosition =
						worldToGui(
							renderPos
						)

					render.frame.Position =
						UDim2.new(
							0,
							guiPosition.X,
							0,
							guiPosition.Y
						)

					if object.size then

						render.frame.Rotation =
							object.rotation
							or 0
					end

				------------------------------------------------
				-- SEGMENT
				------------------------------------------------

				elseif object.a
					and object.b
				then

					local currentA =
						object.a

					local currentB =
						object.b

					local previousA =
						render.renderA
						or currentA

					local previousB =
						render.renderB
						or currentB

					local renderA =
						previousA:Lerp(
							currentA,
							interpAlpha
						)

					local renderB =
						previousB:Lerp(
							currentB,
							interpAlpha
						)

					local midPoint =
						(renderA + renderB) / 2

					local diff =
						renderB - renderA

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
