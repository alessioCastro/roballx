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
-- RESET DE OBJETOS DO MAPA
----------------------------------------------------

local function resetMapObject(
	runtimeObject: any,
	mapObjects: { any }
)
	if runtimeObject.resettable == false then
		return
	end

	if not runtimeObject.id then
		return
	end

	for _, mapObject in ipairs(mapObjects) do
		local mapObjectId =
			mapObject.id

		if mapObjectId == runtimeObject.id then

			------------------------------------------------
			-- DISC / SHAPE
			------------------------------------------------

			if mapObject.pos then
				runtimeObject.pos =
					mapObject.pos
			end

			------------------------------------------------
			-- SEGMENT
			------------------------------------------------

			if mapObject.a
				and mapObject.b
			then
				runtimeObject.a =
					mapObject.a

				runtimeObject.b =
					mapObject.b
			end

			runtimeObject.vel =
				Vector2.zero

			break
		end
	end
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
		local object =
			findObject(
				goal.object,
				discs,
				segments,
				shapes
			)

		if object then
			local objectCenter =
				getObjectCenter(object)

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

					resetCountdown =
						RESET_DELAY_TICKS

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
	local gameplay =
		map.gameplay

	if not gameplay then
		return
	end

	------------------------------------------------
	-- PLAYERS
	------------------------------------------------

	local playerGameplay =
		gameplay.player

	if playerGameplay
		and playerGameplay.spawn
	then

		for _, pData in pairs(playersData) do

			local spawnPositions

			if pData.team == "Red" then
				spawnPositions =
					playerGameplay.spawn.team1Positions
			else
				spawnPositions =
					playerGameplay.spawn.team2Positions
			end

			local spawnIndex =
				pData.spawnIndex

			if spawnIndex
				and spawnPositions
			then
				local spawnPosition =
					spawnPositions[spawnIndex]

				if spawnPosition then

					if pData.kind == "segment" then
						if pData.a
							and pData.b
						then
							local currentCenter =
								(pData.a + pData.b) * 0.5

							local delta =
								spawnPosition
							- currentCenter

							pData.a += delta
							pData.b += delta

							pData.pos =
								spawnPosition
						end
					else
						pData.pos =
							spawnPosition
					end
				end
			end

			pData.vel =
				Vector2.zero

			pData.input =
				Vector2.zero

			pData.isKicking =
				false

			pData.lastKickTick =
				-9999
		end
	end

	------------------------------------------------
	-- OBJETOS DO MAPA
	--
	-- resettable é independente de kickable.
	------------------------------------------------

	for _, object in ipairs(discs) do
		resetMapObject(
			object,
			map.discs
		)
	end

	for _, object in ipairs(segments) do
		resetMapObject(
			object,
			map.segments
		)
	end

	for _, object in ipairs(shapes) do
		resetMapObject(
			object,
			map.shapes
		)
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
