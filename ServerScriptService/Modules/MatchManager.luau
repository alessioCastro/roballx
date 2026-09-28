--!strict
-- MatchManager.luau (Tick-Based)

local MatchManager = {}

local scoreRed = 0
local scoreBlue = 0
local resetCountdown = 0
local RESET_DELAY_TICKS = 90 -- 1.5 segundos a 60fps

function MatchManager.CheckGoals(ball: any, map: any, playersData: any): boolean
	if resetCountdown > 0 then
		resetCountdown -= 1
		if resetCountdown == 0 then
			MatchManager.ResetPositions(ball, map, playersData)
		end
		return false
	end

	local goals = map.goals
	if not goals then return false end

	for _, goal in ipairs(goals) do
		if ball.pos.X >= goal.min.X and ball.pos.X <= goal.max.X and
			ball.pos.Y >= goal.min.Y and ball.pos.Y <= goal.max.Y then

			if goal.teamScored == "Red" then
				scoreRed += 1
			elseif goal.teamScored == "Blue" then
				scoreBlue += 1
			end

			resetCountdown = RESET_DELAY_TICKS
			return true
		end
	end

	return false
end

function MatchManager.ResetPositions(ball: any, map: any, playersData: any)
	ball.pos = map.spawns.ball
	ball.vel = Vector2.zero

	for _, pData in pairs(playersData) do
		pData.pos = pData.team == "Red" and map.spawns.red or map.spawns.blue
		pData.vel = Vector2.zero
		pData.input = Vector2.zero
		pData.isKicking = false
		pData.lastKickTick = -9999
	end
end

function MatchManager.GetScore(): (number, number)
	return scoreRed, scoreBlue
end

function MatchManager.GetResetCountdown(): number
	return resetCountdown
end

function MatchManager.SetState(red: number, blue: number, countdown: number)
	scoreRed = red
	scoreBlue = blue
	resetCountdown = countdown
end

return MatchManager