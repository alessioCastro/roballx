--!strict
-- MatchManager.luau (Tick-Based)

local MatchManager = {}

local scoreRed = 0
local scoreBlue = 0
local resetCountdown = 0

local RESET_DELAY_TICKS = 90

----------------------------------------------------
-- PROCURA UM OBJETO PELO ID
----------------------------------------------------

local function findObject(
	id: string,
	discs: { any },
	segments: { any },
	shapes: { any }
): any?
	for _, object in ipairs(discs) do
		if object.id == id then
			return object
		end
	end

	for _, object in ipairs(segments) do
		if object.id == id then
			return object
		end
	end

	for _, object in ipairs(shapes) do
		if object.id == id then
			return object
		end
	end

	return nil
end

----------------------------------------------------
-- CENTRO DE UM OBJETO
----------------------------------------------------

local function getObjectCenter(object: any): Vector2?
	if object.pos then
		return object.pos
	end

	if object.a and object.b then
		return (object.a + object.b) * 0.5
	end

	return nil
end

----------------------------------------------------
-- CHECAR PONTUAÇÃO
----------------------------------------------------

function MatchManager.CheckGoals(
	map: any,
	playersData: any,
	discs: { any },
	segments: { any },
	shapes: { any }
): boolean

	if resetCountdown > 0 then
		resetCountdown -= 1

		if resetCountdown == 0 then
			MatchManager.ResetPositions(
				map,
				playersData,
				discs,
				segments,
				shapes
			)
		end

		return false
	end

	local gameplay = map.gameplay

	if not gameplay then
		return false
	end

	local scoring = gameplay.scoring

	if not scoring then
		return false
	end

	for _, goal in ipairs(scoring) do
		local object = findObject(
			goal.object,
			discs,
			segments,
			shapes
		)

		if object then
			local objectCenter = getObjectCenter(object)

			if objectCenter then
				if objectCenter.X >= goal.min.X
					and objectCenter.X <= goal.max.X
					and objectCenter.Y >= goal.min.Y
					and objectCenter.Y <= goal.max.Y
				then
					if goal.team == "Red" then
						scoreRed += 1
					elseif goal.team == "Blue" then
						scoreBlue += 1
					end

					resetCountdown = RESET_DELAY_TICKS
					return true
				end
			end
		end
	end

	return false
end

----------------------------------------------------
-- RESET
----------------------------------------------------

function MatchManager.ResetPositions(
	map: any,
	playersData: any,
	discs: { any },
	segments: { any },
	shapes: { any }
)
	local gameplay = map.gameplay

	if not gameplay then
		return
	end

	------------------------------------------------
	-- RESET DOS PLAYERS
	------------------------------------------------

	local playerGameplay = gameplay.player

	if playerGameplay and playerGameplay.spawn then
		for _, pData in pairs(playersData) do
			local spawnPosition =
				pData.team == "Red"
				and playerGameplay.spawn.Red
				or playerGameplay.spawn.Blue

			if pData.kind == "segment" then
				if pData.a and pData.b then
					local currentCenter = (pData.a + pData.b) * 0.5
					local delta = spawnPosition - currentCenter

					pData.a += delta
					pData.b += delta
					pData.pos = spawnPosition
				end
			else
				pData.pos = spawnPosition
			end

			pData.vel = Vector2.zero
			pData.input = Vector2.zero
			pData.isKicking = false
			pData.lastKickTick = -9999
		end
	end

	------------------------------------------------
	-- RESET DOS OBJETOS CHUTÁVEIS
	------------------------------------------------

	local kickable = gameplay.kickable

	if not kickable then
		return
	end

	for _, id in ipairs(kickable) do
		for _, object in ipairs(discs) do
			if object.id == id then
				for _, mapObject in ipairs(map.discs) do
					if mapObject.id == id then
						object.pos = mapObject.pos
						object.vel = Vector2.zero
						break
					end
				end
			end
		end

		for _, object in ipairs(shapes) do
			if object.id == id then
				for _, mapObject in ipairs(map.shapes) do
					if mapObject.id == id then
						object.pos = mapObject.pos
						object.vel = Vector2.zero
						break
					end
				end
			end
		end

		for _, object in ipairs(segments) do
			if object.id == id then
				for _, mapObject in ipairs(map.segments) do
					if mapObject.id == id then
						object.a = mapObject.a
						object.b = mapObject.b
						object.vel = Vector2.zero
						break
					end
				end
			end
		end
	end
end

----------------------------------------------------
-- SCORE
----------------------------------------------------

function MatchManager.GetScore(): (number, number)
	return scoreRed, scoreBlue
end

function MatchManager.GetResetCountdown(): number
	return resetCountdown
end

function MatchManager.SetState(
	red: number,
	blue: number,
	countdown: number
)
	scoreRed = red
	scoreBlue = blue
	resetCountdown = countdown
end

return MatchManager
