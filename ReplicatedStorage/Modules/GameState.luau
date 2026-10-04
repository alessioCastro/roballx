--!strict
-- GameState.luau
-- Módulo de Snapshot/Restore do estado da simulação para Rollback Netcode.

local GameState = {}

-- Cache dos mapas de objetos.
-- A identidade das tabelas permanece estável durante a partida.
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
	posX: number,
	posY: number,

	velX: number,
	velY: number,

	inputX: number,
	inputY: number,

	isKicking: boolean,
	lastKickTick: number,

	team: string,
}

export type DiscSnapshot = {
	id: string,

	posX: number,
	posY: number,

	velX: number,
	velY: number,
}

export type SegmentSnapshot = {
	id: string,

	aX: number,
	aY: number,

	bX: number,
	bY: number,

	velX: number,
	velY: number,
}

export type ShapeSnapshot = {
	id: string,

	posX: number,
	posY: number,

	velX: number,
	velY: number,
}

export type WorldSnapshot = {
	tick: number,

	players: { [number]: PlayerSnapshot },

	discs: { DiscSnapshot },
	segments: { SegmentSnapshot },
	shapes: { ShapeSnapshot },

	scoreRed: number,
	scoreBlue: number,
	resetCountdown: number,
}

----------------------------------------------------
-- SNAPSHOT
----------------------------------------------------

function GameState.snapshot(
	tick: number,
	playersData: { [number]: any },
	discs: { any },
	segments: { any },
	shapes: { any },
	scoreRed: number,
	scoreBlue: number,
	resetCountdown: number
): WorldSnapshot

	local snap: WorldSnapshot = {
		tick = tick,

		players = {},

		discs = {},
		segments = {},
		shapes = {},

		scoreRed = scoreRed,
		scoreBlue = scoreBlue,
		resetCountdown = resetCountdown,
	}

	------------------------------------------------
	-- PLAYERS
	------------------------------------------------

	for uId, p in pairs(playersData) do
		snap.players[uId] = {
			posX = p.pos.X,
			posY = p.pos.Y,

			velX = p.vel.X,
			velY = p.vel.Y,

			inputX = p.input and p.input.X or 0,
			inputY = p.input and p.input.Y or 0,

			isKicking = p.isKicking or false,
			lastKickTick = p.lastKickTick or -9999,

			team = p.team or "Red",
		}
	end

	------------------------------------------------
	-- DISCS DINÂMICOS
	------------------------------------------------

	for _, d in ipairs(discs) do
		if not d.isStatic then
			local vel = d.vel or Vector2.zero

			snap.discs[#snap.discs + 1] = {
				id = d.id,

				posX = d.pos.X,
				posY = d.pos.Y,

				velX = vel.X,
				velY = vel.Y,
			}
		end
	end

	------------------------------------------------
	-- SEGMENTS DINÂMICOS
	------------------------------------------------

	for _, seg in ipairs(segments) do
		if not seg.isStatic then
			local vel = seg.vel or Vector2.zero

			snap.segments[#snap.segments + 1] = {
				id = seg.id,

				aX = seg.a.X,
				aY = seg.a.Y,

				bX = seg.b.X,
				bY = seg.b.Y,

				velX = vel.X,
				velY = vel.Y,
			}
		end
	end

	------------------------------------------------
	-- SHAPES DINÂMICOS
	------------------------------------------------

	for _, s in ipairs(shapes) do
		if not s.isStatic then
			local vel = s.vel or Vector2.zero

			snap.shapes[#snap.shapes + 1] = {
				id = s.id,

				posX = s.pos.X,
				posY = s.pos.Y,

				velX = vel.X,
				velY = vel.Y,
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
	discs: { any },
	segments: { any },
	shapes: { any },
	matchManager: any?
)
	------------------------------------------------
	-- ESTADO DA PARTIDA
	------------------------------------------------

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
		local p = playersData[uId]

		if p then
			p.pos = Vector2.new(
				pSnap.posX,
				pSnap.posY
			)

			p.vel = Vector2.new(
				pSnap.velX,
				pSnap.velY
			)

			p.input = Vector2.new(
				pSnap.inputX,
				pSnap.inputY
			)

			p.isKicking = pSnap.isKicking
			p.lastKickTick = pSnap.lastKickTick
		end
	end

	------------------------------------------------
	-- DISCS
	------------------------------------------------

	if #snap.discs > 0 then
		local discMap = getObjectMap(discs)

		for _, dSnap in ipairs(snap.discs) do
			local d = discMap[dSnap.id]

			if d then
				d.pos = Vector2.new(
					dSnap.posX,
					dSnap.posY
				)

				d.vel = Vector2.new(
					dSnap.velX,
					dSnap.velY
				)
			end
		end
	end

	------------------------------------------------
	-- SEGMENTS
	------------------------------------------------

	if #snap.segments > 0 then
		local segmentMap = getObjectMap(segments)

		for _, sSnap in ipairs(snap.segments) do
			local seg = segmentMap[sSnap.id]

			if seg then
				seg.a = Vector2.new(
					sSnap.aX,
					sSnap.aY
				)

				seg.b = Vector2.new(
					sSnap.bX,
					sSnap.bY
				)

				seg.vel = Vector2.new(
					sSnap.velX,
					sSnap.velY
				)
			end
		end
	end

	------------------------------------------------
	-- SHAPES
	------------------------------------------------

	if #snap.shapes > 0 then
		local shapeMap = getObjectMap(shapes)

		for _, sSnap in ipairs(snap.shapes) do
			local s = shapeMap[sSnap.id]

			if s then
				s.pos = Vector2.new(
					sSnap.posX,
					sSnap.posY
				)

				s.vel = Vector2.new(
					sSnap.velX,
					sSnap.velY
				)
			end
		end
	end
end

----------------------------------------------------
-- PACK LIVE STATE
-- Servidor → Cliente
----------------------------------------------------

function GameState.packLiveState(
	tick: number,
	playersData: { [number]: any },
	discs: { any },
	segments: { any },
	shapes: { any },
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
		local p = playersData[uId]

		if p then
			local input = p.input

			playersArr[#playersArr + 1] = {
				uId,

				p.pos.X,
				p.pos.Y,

				p.vel.X,
				p.vel.Y,

				input and input.X or 0,
				input and input.Y or 0,

				p.isKicking and 1 or 0,

				p.lastKickTick or -9999,

				p.team == "Red" and 1 or 2,
			}
		end
	end

	packed[5] = playersArr

	------------------------------------------------
	-- SHAPES DINÂMICOS
	------------------------------------------------

	local dynShapes = {}

	for _, s in ipairs(shapes) do
		local vel = s.vel or Vector2.zero

		dynShapes[#dynShapes + 1] = {
			s.id,

			s.pos.X,
			s.pos.Y,

			vel.X,
			vel.Y,
		}
	end

	packed[6] = dynShapes

	------------------------------------------------
	-- DISCS DINÂMICOS
	------------------------------------------------

	local dynDiscs = {}

	for _, d in ipairs(discs) do
		local vel = d.vel or Vector2.zero

		dynDiscs[#dynDiscs + 1] = {
			d.id,

			d.pos.X,
			d.pos.Y,

			vel.X,
			vel.Y,
		}
	end

	packed[7] = dynDiscs

	------------------------------------------------
	-- SEGMENTS DINÂMICOS
	------------------------------------------------

	local dynSegs = {}

	for _, seg in ipairs(segments) do
		local vel = seg.vel or Vector2.zero

		dynSegs[#dynSegs + 1] = {
			seg.id,

			seg.a.X,
			seg.a.Y,

			seg.b.X,
			seg.b.Y,

			vel.X,
			vel.Y,
		}
	end

	packed[8] = dynSegs

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

	------------------------------------------------
	-- PLAYERS
	------------------------------------------------

	local playersArr = {}

	if sortedUserIds then

		for _, uId in ipairs(sortedUserIds) do
			local p = snap.players[uId]

			if p then
				table.insert(playersArr, {
					uId,

					p.posX,
					p.posY,

					p.velX,
					p.velY,

					p.inputX,
					p.inputY,

					p.isKicking and 1 or 0,

					p.lastKickTick,

					p.team == "Red" and 1 or 2,
				})
			end
		end

	else

		local playerKeys = {}

		for uId in pairs(snap.players) do
			table.insert(
				playerKeys,
				uId
			)
		end

		table.sort(playerKeys)

		for _, uId in ipairs(playerKeys) do
			local p = snap.players[uId]

			table.insert(playersArr, {
				uId,

				p.posX,
				p.posY,

				p.velX,
				p.velY,

				p.inputX,
				p.inputY,

				p.isKicking and 1 or 0,

				p.lastKickTick,

				p.team == "Red" and 1 or 2,
			})
		end
	end

	packed[5] = playersArr

	------------------------------------------------
	-- SHAPES
	------------------------------------------------

	local dynShapes = {}

	for _, s in ipairs(snap.shapes) do
		table.insert(
			dynShapes,
			{
				s.id,
				s.posX,
				s.posY,
				s.velX,
				s.velY,
			}
		)
	end

	packed[6] = dynShapes

	------------------------------------------------
	-- DISCS
	------------------------------------------------

	local dynDiscs = {}

	for _, d in ipairs(snap.discs) do
		table.insert(
			dynDiscs,
			{
				d.id,
				d.posX,
				d.posY,
				d.velX,
				d.velY,
			}
		)
	end

	packed[7] = dynDiscs

	------------------------------------------------
	-- SEGMENTS
	------------------------------------------------

	local dynSegs = {}

	for _, seg in ipairs(snap.segments) do
		table.insert(
			dynSegs,
			{
				seg.id,

				seg.aX,
				seg.aY,

				seg.bX,
				seg.bY,

				seg.velX,
				seg.velY,
			}
		)
	end

	packed[8] = dynSegs

	return packed
end

----------------------------------------------------
-- RESTORE PACKED
----------------------------------------------------

function GameState.restorePacked(
	packed: any,
	playersData: { [number]: any },
	discs: { any },
	segments: { any },
	shapes: { any }
)
	------------------------------------------------
	-- PLAYERS
	------------------------------------------------

	for _, pArr in ipairs(packed[5]) do
		local p = playersData[pArr[1]]

		if p then
			p.pos = Vector2.new(
				pArr[2],
				pArr[3]
			)

			p.vel = Vector2.new(
				pArr[4],
				pArr[5]
			)

			p.input = Vector2.new(
				pArr[6],
				pArr[7]
			)

			p.isKicking = pArr[8] == 1
			p.lastKickTick = pArr[9]
		end
	end

	------------------------------------------------
	-- SHAPES
	------------------------------------------------

	local shapeMap = getObjectMap(shapes)

	for _, sArr in ipairs(packed[6]) do
		local shape = shapeMap[sArr[1]]

		if shape then
			shape.pos = Vector2.new(
				sArr[2],
				sArr[3]
			)

			shape.vel = Vector2.new(
				sArr[4],
				sArr[5]
			)
		end
	end

	------------------------------------------------
	-- DISCS
	------------------------------------------------

	local discMap = getObjectMap(discs)

	for _, dArr in ipairs(packed[7]) do
		local disc = discMap[dArr[1]]

		if disc then
			disc.pos = Vector2.new(
				dArr[2],
				dArr[3]
			)

			disc.vel = Vector2.new(
				dArr[4],
				dArr[5]
			)
		end
	end

	------------------------------------------------
	-- SEGMENTS
	------------------------------------------------

	local segmentMap = getObjectMap(segments)

	for _, segArr in ipairs(packed[8]) do
		local segment = segmentMap[segArr[1]]

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

		scoreRed = packed[2],
		scoreBlue = packed[3],
		resetCountdown = packed[4],

		players = {},

		shapes = {},
		discs = {},
		segments = {},
	}

	------------------------------------------------
	-- PLAYERS
	------------------------------------------------

	for _, pArr in ipairs(packed[5]) do
		snap.players[pArr[1]] = {
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
				and "Red"
				or "Blue",
		}
	end

	------------------------------------------------
	-- SHAPES
	------------------------------------------------

	for _, sArr in ipairs(packed[6]) do
		table.insert(
			snap.shapes,
			{
				id = sArr[1],

				posX = sArr[2],
				posY = sArr[3],

				velX = sArr[4],
				velY = sArr[5],
			}
		)
	end

	------------------------------------------------
	-- DISCS
	------------------------------------------------

	for _, dArr in ipairs(packed[7]) do
		table.insert(
			snap.discs,
			{
				id = dArr[1],

				posX = dArr[2],
				posY = dArr[3],

				velX = dArr[4],
				velY = dArr[5],
			}
		)
	end

	------------------------------------------------
	-- SEGMENTS
	------------------------------------------------

	for _, segArr in ipairs(packed[8]) do
		table.insert(
			snap.segments,
			{
				id = segArr[1],

				aX = segArr[2],
				aY = segArr[3],

				bX = segArr[4],
				bY = segArr[5],

				velX = segArr[6],
				velY = segArr[7],
			}
		)
	end

	return snap
end

return GameState
