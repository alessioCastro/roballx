--!strict
-- GameState.luau
-- Módulo de Snapshot/Restore do estado da simulação para Rollback Netcode.

local GameState = {}

-- Cache dos mapas de objetos dinâmicos.
-- A identidade das tabelas de objetos permanece estável durante a partida.
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
	posX: number, posY: number,
	velX: number, velY: number,
	inputX: number, inputY: number,
	isKicking: boolean,
	lastKickTick: number,
	team: string,
}

export type BallSnapshot = {
	posX: number, posY: number,
	velX: number, velY: number,
}

export type DiscSnapshot = {
	id: string,
	posX: number, posY: number,
	velX: number, velY: number,
}

export type SegmentSnapshot = {
	id: string,
	aX: number, aY: number,
	bX: number, bY: number,
	velX: number, velY: number,
}

export type ShapeSnapshot = {
	id: string,
	posX: number, posY: number,
	velX: number, velY: number,
}

export type WorldSnapshot = {
	tick: number,
	ball: BallSnapshot,
	players: { [number]: PlayerSnapshot }, -- keyed by userId
	discs: { DiscSnapshot },
	segments: { SegmentSnapshot },
	shapes: { ShapeSnapshot },
	scoreRed: number,
	scoreBlue: number,
	resetCountdown: number,
}

----------------------------------------------------
-- SNAPSHOT: Captura estado completo
----------------------------------------------------
function GameState.snapshot(
	tick: number,
	ball: any,
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
		ball = {
			posX = ball.pos.X, posY = ball.pos.Y,
			velX = ball.vel.X, velY = ball.vel.Y,
		},
		players = {},
		discs = {},
		segments = {},
		shapes = {},
		scoreRed = scoreRed,
		scoreBlue = scoreBlue,
		resetCountdown = resetCountdown,
	}

	for uId, p in pairs(playersData) do
		snap.players[uId] = {
			posX = p.pos.X, posY = p.pos.Y,
			velX = p.vel.X, velY = p.vel.Y,
			inputX = p.input and p.input.X or 0,
			inputY = p.input and p.input.Y or 0,
			isKicking = p.isKicking or false,
			lastKickTick = p.lastKickTick or -9999,
			team = p.team or "Red",
		}
	end

	for _, d in ipairs(discs) do
		if not d.isStatic then
			table.insert(snap.discs, {
				id = d.id,
				posX = d.pos.X, posY = d.pos.Y,
				velX = (d.vel or Vector2.zero).X, velY = (d.vel or Vector2.zero).Y,
			})
		end
	end

	for _, seg in ipairs(segments) do
		if not seg.isStatic then
			table.insert(snap.segments, {
				id = seg.id,
				aX = seg.a.X, aY = seg.a.Y,
				bX = seg.b.X, bY = seg.b.Y,
				velX = (seg.vel or Vector2.zero).X, velY = (seg.vel or Vector2.zero).Y,
			})
		end
	end

	for _, s in ipairs(shapes) do
		if not s.isStatic then
			table.insert(snap.shapes, {
				id = s.id,
				posX = s.pos.X, posY = s.pos.Y,
				velX = (s.vel or Vector2.zero).X, velY = (s.vel or Vector2.zero).Y,
			})
		end
	end

	return snap
end

----------------------------------------------------
-- RESTORE: Restaura estado a partir de snapshot
----------------------------------------------------
function GameState.restore(
	snap: WorldSnapshot,
	ball: any,
	playersData: { [number]: any },
	discs: { any },
	segments: { any },
	shapes: { any },
	matchManager: any?
)
	-- Restaura estado da partida.
	if matchManager then
		matchManager.SetState(
			snap.scoreRed,
			snap.scoreBlue,
			snap.resetCountdown
		)
	end

	-- Bola
	ball.pos = Vector2.new(
		snap.ball.posX,
		snap.ball.posY
	)

	ball.vel = Vector2.new(
		snap.ball.velX,
		snap.ball.velY
	)

	-- Jogadores
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

	-- Objetos dinâmicos.
	-- Os mapas são construídos apenas na primeira restauração
	-- e reutilizados nas restaurações seguintes.
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
-- PACK FOR NETWORK: Formato compacto servidor → cliente
----------------------------------------------------
function GameState.packForNetwork(snap: WorldSnapshot, sortedUserIds: { number }? ): any
	local packed: any = {}
	packed[1] = snap.tick
	packed[2] = snap.scoreRed
	packed[3] = snap.scoreBlue
	packed[4] = snap.resetCountdown

	-- Bola: {posX, posY, velX, velY}
	packed[5] = {snap.ball.posX, snap.ball.posY, snap.ball.velX, snap.ball.velY}

	-- Jogadores em ordem determinística de UserID
	local playersArr = {}

	if sortedUserIds then
		for _, uId in ipairs(sortedUserIds) do
			local p = snap.players[uId]

			if p then
				table.insert(playersArr, {
					uId,
					p.posX, p.posY,
					p.velX, p.velY,
					p.inputX, p.inputY,
					p.isKicking and 1 or 0,
					p.lastKickTick,
					p.team == "Red" and 1 or 2,
				})
			end
		end
	else
		local playerKeys = {}

		for uId in pairs(snap.players) do
			table.insert(playerKeys, uId)
		end

		table.sort(playerKeys)

		for _, uId in ipairs(playerKeys) do
			local p = snap.players[uId]

			table.insert(playersArr, {
				uId,
				p.posX, p.posY,
				p.velX, p.velY,
				p.inputX, p.inputY,
				p.isKicking and 1 or 0,
				p.lastKickTick,
				p.team == "Red" and 1 or 2,
			})
		end
	end
	packed[6] = playersArr

	-- Dinâmicos (shapes, discs, segments)
	local dynShapes = {}
	for _, s in ipairs(snap.shapes) do
		table.insert(dynShapes, {s.id, s.posX, s.posY, s.velX, s.velY})
	end

	local dynDiscs = {}
	for _, d in ipairs(snap.discs) do
		table.insert(dynDiscs, {d.id, d.posX, d.posY, d.velX, d.velY})
	end

	local dynSegs = {}
	for _, seg in ipairs(snap.segments) do
		table.insert(dynSegs, {seg.id, seg.aX, seg.aY, seg.bX, seg.bY, seg.velX, seg.velY})
	end

	packed[7] = dynShapes
	packed[8] = dynDiscs
	packed[9] = dynSegs

	return packed
end

----------------------------------------------------
-- UNPACK FROM NETWORK: Decodifica no cliente
----------------------------------------------------
function GameState.unpackFromNetwork(packed: any): WorldSnapshot
	local snap: WorldSnapshot = {
		tick = packed[1],
		scoreRed = packed[2],
		scoreBlue = packed[3],
		resetCountdown = packed[4],
		ball = {
			posX = packed[5][1], posY = packed[5][2],
			velX = packed[5][3], velY = packed[5][4],
		},
		players = {},
		shapes = {},
		discs = {},
		segments = {},
	}

	for _, pArr in ipairs(packed[6]) do
		snap.players[pArr[1]] = {
			posX = pArr[2], posY = pArr[3],
			velX = pArr[4], velY = pArr[5],
			inputX = pArr[6], inputY = pArr[7],
			isKicking = pArr[8] == 1,
			lastKickTick = pArr[9],
			team = pArr[10] == 1 and "Red" or "Blue",
		}
	end

	for _, sArr in ipairs(packed[7]) do
		table.insert(snap.shapes, {
			id = sArr[1],
			posX = sArr[2], posY = sArr[3],
			velX = sArr[4], velY = sArr[5],
		})
	end

	for _, dArr in ipairs(packed[8]) do
		table.insert(snap.discs, {
			id = dArr[1],
			posX = dArr[2], posY = dArr[3],
			velX = dArr[4], velY = dArr[5],
		})
	end

	for _, segArr in ipairs(packed[9]) do
		table.insert(snap.segments, {
			id = segArr[1],
			aX = segArr[2], aY = segArr[3],
			bX = segArr[4], bY = segArr[5],
			velX = segArr[6], velY = segArr[7],
		})
	end

	return snap
end

return GameState
