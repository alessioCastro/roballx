local GameState = {}

export type WorldSnapshot = {
	tick: number,
	ball: {
		pos: Vector2,
		vel: Vector2
	},
	players: {
		[number]: {
			pos: Vector2,
			vel: Vector2,
			input: Vector2,
			isKicking: boolean,
			lastKickTick: number,
			team: string
		}
	},
	discs: {any},
	segments: {any},
	shapes: {any},
	scoreRed: number,
	scoreBlue: number,
	resetCountdown: number
}

local function buildObjectMap(objects)
	local map = {}

	for _, object in ipairs(objects) do
		map[object.id] = object
	end

	return map
end

local function restoreDynamicObjects(snapshotObjects, objectMap)
	for _, state in ipairs(snapshotObjects) do
		local object = objectMap[state.id]

		if object and object.isStatic == false then
			object.pos = state.pos
			object.vel = state.vel
		end
	end
end

function GameState.snapshot(
	tick,
	ball,
	playersData,
	discs,
	segments,
	shapes,
	scoreRed,
	scoreBlue,
	resetCountdown
)
	local snap = {
		tick = tick,

		ball = {
			pos = ball.pos,
			vel = ball.vel
		},

		players = {},

		discs = {},
		segments = {},
		shapes = {},

		scoreRed = scoreRed,
		scoreBlue = scoreBlue,
		resetCountdown = resetCountdown
	}

	for userId, player in pairs(playersData) do
		snap.players[userId] = {
			pos = player.pos,
			vel = player.vel,
			input = player.input,
			isKicking = player.isKicking,
			lastKickTick = player.lastKickTick,
			team = player.team
		}
	end

	for _, disc in ipairs(discs) do
		if disc.isStatic == false then
			table.insert(snap.discs, {
				id = disc.id,
				pos = disc.pos,
				vel = disc.vel
			})
		end
	end

	for _, segment in ipairs(segments) do
		if segment.isStatic == false then
			table.insert(snap.segments, {
				id = segment.id,
				pos = segment.pos,
				vel = segment.vel
			})
		end
	end

	for _, shape in ipairs(shapes) do
		if shape.isStatic == false then
			table.insert(snap.shapes, {
				id = shape.id,
				pos = shape.pos,
				vel = shape.vel
			})
		end
	end

	return snap
end

function GameState.restore(
	snap,
	ball,
	playersData,
	discs,
	segments,
	shapes,
	matchManager
)
	if matchManager then
		matchManager.SetState(
			snap.scoreRed,
			snap.scoreBlue,
			snap.resetCountdown
		)
	end

	ball.pos = snap.ball.pos
	ball.vel = snap.ball.vel

	for userId, state in pairs(snap.players) do
		local player = playersData[userId]

		if player then
			player.pos = state.pos
			player.vel = state.vel
			player.input = state.input
			player.isKicking = state.isKicking
			player.lastKickTick = state.lastKickTick
			player.team = state.team
		end
	end

	local discMap = buildObjectMap(discs)
	local segmentMap = buildObjectMap(segments)
	local shapeMap = buildObjectMap(shapes)

	restoreDynamicObjects(snap.discs, discMap)
	restoreDynamicObjects(snap.segments, segmentMap)
	restoreDynamicObjects(snap.shapes, shapeMap)
end

function GameState.packForNetwork(snap)
	local packed = {}

	packed[1] = snap.tick
	packed[2] = snap.scoreRed
	packed[3] = snap.scoreBlue
	packed[4] = snap.resetCountdown

	packed[5] = {
		snap.ball.pos.X,
		snap.ball.pos.Y,
		snap.ball.vel.X,
		snap.ball.vel.Y
	}

	local playersArr = {}

	for userId, player in pairs(snap.players) do
		playersArr[#playersArr + 1] = {
			userId,
			player.pos.X,
			player.pos.Y,
			player.vel.X,
			player.vel.Y,
			player.input.X,
			player.input.Y,
			player.isKicking,
			player.lastKickTick,
			player.team
		}
	end

	table.sort(playersArr, function(a, b)
		return a[1] < b[1]
	end)

	packed[6] = playersArr

	local discsArr = {}

	for _, disc in ipairs(snap.discs) do
		discsArr[#discsArr + 1] = {
			disc.id,
			disc.pos.X,
			disc.pos.Y,
			disc.vel.X,
			disc.vel.Y
		}
	end

	packed[7] = discsArr

	local segmentsArr = {}

	for _, segment in ipairs(snap.segments) do
		segmentsArr[#segmentsArr + 1] = {
			segment.id,
			segment.pos.X,
			segment.pos.Y,
			segment.vel.X,
			segment.vel.Y
		}
	end

	packed[8] = segmentsArr

	local shapesArr = {}

	for _, shape in ipairs(snap.shapes) do
		shapesArr[#shapesArr + 1] = {
			shape.id,
			shape.pos.X,
			shape.pos.Y,
			shape.vel.X,
			shape.vel.Y
		}
	end

	packed[9] = shapesArr

	return packed
end

function GameState.unpackFromNetwork(packed)
	local snap = {
		tick = packed[1],
		scoreRed = packed[2],
		scoreBlue = packed[3],
		resetCountdown = packed[4],

		ball = {
			pos = Vector2.new(packed[5][1], packed[5][2]),
			vel = Vector2.new(packed[5][3], packed[5][4])
		},

		players = {},
		discs = {},
		segments = {},
		shapes = {}
	}

	for _, data in ipairs(packed[6]) do
		snap.players[data[1]] = {
			pos = Vector2.new(data[2], data[3]),
			vel = Vector2.new(data[4], data[5]),
			input = Vector2.new(data[6], data[7]),
			isKicking = data[8],
			lastKickTick = data[9],
			team = data[10]
		}
	end

	for _, data in ipairs(packed[7]) do
		snap.discs[#snap.discs + 1] = {
			id = data[1],
			pos = Vector2.new(data[2], data[3]),
			vel = Vector2.new(data[4], data[5])
		}
	end

	for _, data in ipairs(packed[8]) do
		snap.segments[#snap.segments + 1] = {
			id = data[1],
			pos = Vector2.new(data[2], data[3]),
			vel = Vector2.new(data[4], data[5])
		}
	end

	for _, data in ipairs(packed[9]) do
		snap.shapes[#snap.shapes + 1] = {
			id = data[1],
			pos = Vector2.new(data[2], data[3]),
			vel = Vector2.new(data[4], data[5])
		}
	end

	return snap
end

return GameState
