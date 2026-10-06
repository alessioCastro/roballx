--!strict
-- GameState.luau
-- Módulo de Snapshot/Restore do estado da simulação para Rollback Netcode.

local GameState = {}

local objectMapCache = setmetatable({}, { __mode = "k" })

local function getObjectMap(objects: { any }): { [string]: any }
	local cached = objectMapCache[objects]

	if cached then
		return cached
	end

	local map = {}

	for _, object in ipairs(objects) do
		local id = object.id

		if id then
			map[id] = object
		end
	end

	objectMapCache[objects] = map

	return map
end

export type InputData = {
	moveX: number,
	moveY: number,
	kick: boolean,
}

export type PlayerSnapshot = {
	kind: "object" | "segment",

	posX: number,
	posY: number,

	velX: number,
	velY: number,

	inputX: number,
	inputY: number,

	isKicking: boolean,
	lastKickTick: number,

	team: string,

	aX: number?,
	aY: number?,
	bX: number?,
	bY: number?,
}

export type ObjectSnapshot = {
	id: string,

	posX: number,
	posY: number,

	velX: number,
	velY: number,

	rotation: number,
	angularVelocity: number,
}

export type SegmentSnapshot = {
	id: string,

	aX: number,
	aY: number,

	bX: number,
	bY: number,

	velX: number,
	velY: number,

	rotation: number,
	angularVelocity: number,
}

export type WorldSnapshot = {
	tick: number,

	players: { [number]: PlayerSnapshot },

	objects: { ObjectSnapshot },
	segments: { SegmentSnapshot },

	scoreRed: number,
	scoreBlue: number,
	resetCountdown: number,
}

----------------------------------------------------
-- PLAYER GEOMETRY TYPE
----------------------------------------------------

local function getPlayerKindCode(
	kind: "object" | "segment"
): number
	if kind == "segment" then
		return 2
	end

	return 1
end

local function getPlayerKindFromCode(
	code: number?
): "object" | "segment"
	if code == 2 then
		return "segment"
	end

	return "object"
end

----------------------------------------------------
-- SNAPSHOT
----------------------------------------------------

function GameState.snapshot(
	tick: number,
	playersData: { [number]: any },
	objects: { any },
	segments: { any },
	scoreRed: number,
	scoreBlue: number,
	resetCountdown: number
): WorldSnapshot

	local snap: WorldSnapshot = {
		tick = tick,

		players = {},

		objects = {},
		segments = {},

		scoreRed = scoreRed,
		scoreBlue = scoreBlue,
		resetCountdown = resetCountdown,
	}

	------------------------------------------------
	-- PLAYERS
	------------------------------------------------

	for uId, p in pairs(playersData) do
		local kind =
			p.kind
			or "object"

		local vel =
			p.vel
			or Vector2.zero

		local input =
			p.input
			or Vector2.zero

		local pos = Vector2.zero

		if kind == "segment" then
			local a = p.a :: Vector2
			local b = p.b :: Vector2

			pos = (a + b) * 0.5

			snap.players[uId] = {
				kind = "segment",

				posX = pos.X,
				posY = pos.Y,

				velX = vel.X,
				velY = vel.Y,

				inputX = input.X,
				inputY = input.Y,

				isKicking = p.isKicking or false,
				lastKickTick = p.lastKickTick or -9999,

				team = p.team or "Team1",

				aX = a.X,
				aY = a.Y,

				bX = b.X,
				bY = b.Y,
			}
		else
			pos = p.pos :: Vector2

			snap.players[uId] = {
				kind = kind,

				posX = pos.X,
				posY = pos.Y,

				velX = vel.X,
				velY = vel.Y,

				inputX = input.X,
				inputY = input.Y,

				isKicking = p.isKicking or false,
				lastKickTick = p.lastKickTick or -9999,

				team = p.team or "Team1",

				aX = nil,
				aY = nil,
				bX = nil,
				bY = nil,
			}
		end
	end

	------------------------------------------------
	-- OBJETOS DINÂMICOS
	------------------------------------------------

	for _, object in ipairs(objects) do
		if not object.isStatic then
			local vel =
				object.vel
				or Vector2.zero

			snap.objects[#snap.objects + 1] = {
				id = object.id,

				posX = object.pos.X,
				posY = object.pos.Y,

				velX = vel.X,
				velY = vel.Y,

				rotation = object.rotation or 0,
				angularVelocity = object.angularVelocity or 0,
			}
		end
	end

	------------------------------------------------
	-- SEGMENTOS DINÂMICOS
	------------------------------------------------

	for _, seg in ipairs(segments) do
		if not seg.isStatic then
			local vel =
				seg.vel
				or Vector2.zero

			snap.segments[#snap.segments + 1] = {
				id = seg.id,

				aX = seg.a.X,
				aY = seg.a.Y,

				bX = seg.b.X,
				bY = seg.b.Y,

				velX = vel.X,
				velY = vel.Y,

				rotation = seg.rotation or 0,
				angularVelocity = seg.angularVelocity or 0,
			}
		end
	end

	return snap
end

----------------------------------------------------
-- RESTORE
----------------------------------------------------

function GameState.restore(
	snap: WorldSnapshot,
	playersData: { [number]: any },
	objects: { any },
	segments: { any },
	matchManager: any?
)
	if matchManager then
		matchManager.SetState(
			snap.scoreRed,
			snap.scoreBlue,
			snap.resetCountdown
		)
	end

	------------------------------------------------
	-- PLAYERS
	------------------------------------------------

	for uId, pSnap in pairs(snap.players) do
		local p =
			playersData[uId]

		if p then
			p.vel = Vector2.new(
				pSnap.velX,
				pSnap.velY
			)

			p.input = Vector2.new(
				pSnap.inputX,
				pSnap.inputY
			)

			p.isKicking =
				pSnap.isKicking

			p.lastKickTick =
				pSnap.lastKickTick

			p.kind =
				pSnap.kind

			if pSnap.kind == "segment" then
				if
					pSnap.aX ~= nil
					and pSnap.aY ~= nil
					and pSnap.bX ~= nil
					and pSnap.bY ~= nil
				then
					p.a = Vector2.new(
						pSnap.aX,
						pSnap.aY
					)

					p.b = Vector2.new(
						pSnap.bX,
						pSnap.bY
					)
				end
			else
				p.pos = Vector2.new(
					pSnap.posX,
					pSnap.posY
				)
			end
		end
	end

	------------------------------------------------
	-- OBJETOS
	------------------------------------------------

	if #snap.objects > 0 then
		local objectMap =
			getObjectMap(objects)

		for _, objectSnap in ipairs(snap.objects) do
			local object =
				objectMap[objectSnap.id]

			if object then
				object.pos = Vector2.new(
					objectSnap.posX,
					objectSnap.posY
				)

				object.vel = Vector2.new(
					objectSnap.velX,
					objectSnap.velY
				)

				object.rotation =
					objectSnap.rotation

				object.angularVelocity =
					objectSnap.angularVelocity
			end
		end
	end

	------------------------------------------------
	-- SEGMENTOS
	------------------------------------------------

	if #snap.segments > 0 then
		local segmentMap =
			getObjectMap(segments)

		for _, segmentSnap in ipairs(snap.segments) do
			local seg =
				segmentMap[segmentSnap.id]

			if seg then
				seg.a = Vector2.new(
					segmentSnap.aX,
					segmentSnap.aY
				)

				seg.b = Vector2.new(
					segmentSnap.bX,
					segmentSnap.bY
				)

				seg.vel = Vector2.new(
					segmentSnap.velX,
					segmentSnap.velY
				)

				seg.rotation =
					segmentSnap.rotation

				seg.angularVelocity =
					segmentSnap.angularVelocity
			end
		end
	end
end

----------------------------------------------------
-- PACK LIVE STATE
----------------------------------------------------

function GameState.packLiveState(
	tick: number,
	playersData: { [number]: any },
	objects: { any },
	segments: { any },
	scoreRed: number,
	scoreBlue: number,
	resetCountdown: number,
	sortedUserIds: { number }
): any

	local packed: any = {}

	packed[1] = tick
	packed[2] = scoreRed
	packed[3] = scoreBlue
	packed[4] = resetCountdown

	------------------------------------------------
	-- PLAYERS
	------------------------------------------------

	local playersArr = {}

	for _, uId in ipairs(sortedUserIds) do
		local p =
			playersData[uId]

		if p then
			local input =
				p.input
				or Vector2.zero

			local kind =
				p.kind
				or "object"

			local posX
			local posY

			local aX
			local aY
			local bX
			local bY

			if kind == "segment" then
				local a = p.a :: Vector2
				local b = p.b :: Vector2

				local center =
					(a + b) * 0.5

				posX = center.X
				posY = center.Y

				aX = a.X
				aY = a.Y

				bX = b.X
				bY = b.Y
			else
				local pos = p.pos :: Vector2

				posX = pos.X
				posY = pos.Y
			end

			playersArr[#playersArr + 1] = {
				uId,

				posX,
				posY,

				p.vel.X,
				p.vel.Y,

				input.X,
				input.Y,

				p.isKicking and 1 or 0,

				p.lastKickTick or -9999,

				p.team == "Team1" and 1 or 2,

				getPlayerKindCode(kind),

				aX,
				aY,

				bX,
				bY,
			}
		end
	end

	packed[5] = playersArr

	------------------------------------------------
	-- OBJETOS DINÂMICOS
	------------------------------------------------

	local dynObjects = {}

	for _, object in ipairs(objects) do
		if not object.isStatic then
			local vel =
				object.vel
				or Vector2.zero

			dynObjects[#dynObjects + 1] = {
				object.id,

				object.pos.X,
				object.pos.Y,

				vel.X,
				vel.Y,

				object.rotation or 0,
				object.angularVelocity or 0,
			}
		end
	end

	packed[6] = dynObjects

	------------------------------------------------
	-- SEGMENTOS DINÂMICOS
	------------------------------------------------

	local dynSegs = {}

	for _, seg in ipairs(segments) do
		if not seg.isStatic then
			local vel =
				seg.vel
				or Vector2.zero

			dynSegs[#dynSegs + 1] = {
				seg.id,

				seg.a.X,
				seg.a.Y,

				seg.b.X,
				seg.b.Y,

				vel.X,
				vel.Y,

				seg.rotation or 0,
				seg.angularVelocity or 0,
			}
		end
	end

	packed[7] = dynSegs

	return packed
end

----------------------------------------------------
-- PACK FOR NETWORK
----------------------------------------------------

function GameState.packForNetwork(
	snap: WorldSnapshot,
	sortedUserIds: { number }?
): any

	local packed: any = {}

	packed[1] = snap.tick
	packed[2] = snap.scoreRed
	packed[3] = snap.scoreBlue
	packed[4] = snap.resetCountdown

	local playersArr = {}

	local playerKeys = {}

	if sortedUserIds then
		for _, uId in ipairs(sortedUserIds) do
			playerKeys[#playerKeys + 1] = uId
		end
	else
		for uId in pairs(snap.players) do
			playerKeys[#playerKeys + 1] = uId
		end

		table.sort(playerKeys)
	end

	for _, uId in ipairs(playerKeys) do
		local p =
			snap.players[uId]

		if p then
			playersArr[#playersArr + 1] = {
				uId,

				p.posX,
				p.posY,

				p.velX,
				p.velY,

				p.inputX,
				p.inputY,

				p.isKicking and 1 or 0,

				p.lastKickTick,

				p.team == "Team1" and 1 or 2,

				getPlayerKindCode(
					p.kind
				),

				p.aX,
				p.aY,

				p.bX,
				p.bY,
			}
		end
	end

	packed[5] = playersArr

	------------------------------------------------
	-- OBJETOS
	------------------------------------------------

	local dynObjects = {}

	for _, object in ipairs(snap.objects) do
		dynObjects[#dynObjects + 1] = {
			object.id,

			object.posX,
			object.posY,

			object.velX,
			object.velY,

			object.rotation or 0,
			object.angularVelocity or 0,
		}
	end

	packed[6] = dynObjects

	------------------------------------------------
	-- SEGMENTOS
	------------------------------------------------

	local dynSegs = {}

	for _, seg in ipairs(snap.segments) do
		dynSegs[#dynSegs + 1] = {
			seg.id,

			seg.aX,
			seg.aY,

			seg.bX,
			seg.bY,

			seg.velX,
			seg.velY,

			seg.rotation or 0,
			seg.angularVelocity or 0,
		}
	end

	packed[7] = dynSegs

	return packed
end

----------------------------------------------------
-- RESTORE PACKED
----------------------------------------------------

function GameState.restorePacked(
	packed: any,
	playersData: { [number]: any },
	objects: { any },
	segments: { any }
)
	------------------------------------------------
	-- PLAYERS
	------------------------------------------------

	for _, pArr in ipairs(packed[5]) do
		local p =
			playersData[pArr[1]]

		if p then
			local kind =
				getPlayerKindFromCode(
					pArr[11]
				)

			p.kind = kind

			p.vel = Vector2.new(
				pArr[4],
				pArr[5]
			)

			p.input = Vector2.new(
				pArr[6],
				pArr[7]
			)

			p.isKicking =
				pArr[8] == 1

			p.lastKickTick =
				pArr[9]

			if kind == "segment" then
				p.a = Vector2.new(
					pArr[12],
					pArr[13]
				)

				p.b = Vector2.new(
					pArr[14],
					pArr[15]
				)
			else
				p.pos = Vector2.new(
					pArr[2],
					pArr[3]
				)
			end
		end
	end

	------------------------------------------------
	-- OBJETOS
	------------------------------------------------

	local objectMap =
		getObjectMap(objects)

	for _, objectArr in ipairs(packed[6]) do
		local object =
			objectMap[objectArr[1]]

		if object then
			object.pos = Vector2.new(
				objectArr[2],
				objectArr[3]
			)

			object.vel = Vector2.new(
				objectArr[4],
				objectArr[5]
			)

			object.rotation =
				objectArr[6]

			object.angularVelocity =
				objectArr[7]
		end
	end

	------------------------------------------------
	-- SEGMENTOS
	------------------------------------------------

	local segmentMap =
		getObjectMap(segments)

	for _, segArr in ipairs(packed[7]) do
		local segment =
			segmentMap[segArr[1]]

		if segment then
			segment.a = Vector2.new(
				segArr[2],
				segArr[3]
			)

			segment.b = Vector2.new(
				segArr[4],
				segArr[5]
			)

			segment.vel = Vector2.new(
				segArr[6],
				segArr[7]
			)

			segment.rotation =
				segArr[8]

			segment.angularVelocity =
				segArr[9]
		end
	end
end

----------------------------------------------------
-- UNPACK FROM NETWORK
----------------------------------------------------

function GameState.unpackFromNetwork(
	packed: any
): WorldSnapshot

	local snap: WorldSnapshot = {
		tick = packed[1],

		players = {},

		objects = {},
		segments = {},

		scoreRed = packed[2],
		scoreBlue = packed[3],
		resetCountdown = packed[4],
	}

	------------------------------------------------
	-- PLAYERS
	------------------------------------------------

	for _, pArr in ipairs(packed[5]) do
		local kind =
			getPlayerKindFromCode(
				pArr[11]
			)

		snap.players[pArr[1]] = {
			kind = kind,

			posX = pArr[2],
			posY = pArr[3],

			velX = pArr[4],
			velY = pArr[5],

			inputX = pArr[6],
			inputY = pArr[7],

			isKicking = pArr[8] == 1,
			lastKickTick = pArr[9],

			team =
				pArr[10] == 1
				and "Team1"
				or "Team2",

			aX = pArr[12],
			aY = pArr[13],

			bX = pArr[14],
			bY = pArr[15],
		}
	end

	------------------------------------------------
	-- OBJETOS
	------------------------------------------------

	for _, objectArr in ipairs(packed[6]) do
		snap.objects[#snap.objects + 1] = {
			id = objectArr[1],

			posX = objectArr[2],
			posY = objectArr[3],

			velX = objectArr[4],
			velY = objectArr[5],

			rotation = objectArr[6] or 0,
			angularVelocity = objectArr[7] or 0,
		}
	end

	------------------------------------------------
	-- SEGMENTOS
	------------------------------------------------

	for _, segArr in ipairs(packed[7]) do
		snap.segments[#snap.segments + 1] = {
			id = segArr[1],

			aX = segArr[2],
			aY = segArr[3],

			bX = segArr[4],
			bY = segArr[5],

			velX = segArr[6],
			velY = segArr[7],

			rotation = segArr[8] or 0,
			angularVelocity = segArr[9] or 0,
		}
	end

	return snap
end

return GameState
