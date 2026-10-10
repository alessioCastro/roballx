--!strict
-- MatchControl.luau
-- Estado autoritativo e configuracoes da partida.
-- Este modulo nao cria interfaces nem executa operacoes de rede.

local MatchControl = {}

export type MatchStatus = "Stopped" | "Running" | "Paused"

export type MatchSettings = {
	TimeLimit: number,
	ScoreLimit: number,
}

export type MatchState = {
	Status: MatchStatus,
	TimeLimit: number,
	ScoreLimit: number,
	ElapsedSeconds: number,
	RemainingSeconds: number?,
}

local DEFAULT_TIME_LIMIT = 5
local DEFAULT_SCORE_LIMIT = 5

local MIN_TIME_LIMIT = 0
local MAX_TIME_LIMIT = 120

local MIN_SCORE_LIMIT = 0
local MAX_SCORE_LIMIT = 99

local status: MatchStatus = "Stopped"

local timeLimit = DEFAULT_TIME_LIMIT
local scoreLimit = DEFAULT_SCORE_LIMIT

local elapsedSeconds = 0

local function isValidInteger(
	value: unknown,
	minimum: number,
	maximum: number
): boolean
	return typeof(value) == "number"
		and value == value
		and value ~= math.huge
		and value ~= -math.huge
		and value == math.floor(value)
		and value >= minimum
		and value <= maximum
end

function MatchControl.GetState(): MatchState
	local remainingSeconds: number? = nil

	if timeLimit > 0 then
		remainingSeconds = math.max(
			0,
			timeLimit * 60 - elapsedSeconds
		)
	end

	return {
		Status = status,
		TimeLimit = timeLimit,
		ScoreLimit = scoreLimit,
		ElapsedSeconds = elapsedSeconds,
		RemainingSeconds = remainingSeconds,
	}
end

function MatchControl.GetSettings(): MatchSettings
	return {
		TimeLimit = timeLimit,
		ScoreLimit = scoreLimit,
	}
end

function MatchControl.SetSettings(
	newTimeLimit: unknown,
	newScoreLimit: unknown
): (boolean, string)
	if status ~= "Stopped" then
		return false, "As configuracoes so podem mudar com a partida parada."
	end

	if not isValidInteger(
		newTimeLimit,
		MIN_TIME_LIMIT,
		MAX_TIME_LIMIT
	) then
		return false, "Time Limit deve ser um inteiro entre 0 e 120."
	end

	if not isValidInteger(
		newScoreLimit,
		MIN_SCORE_LIMIT,
		MAX_SCORE_LIMIT
	) then
		return false, "Score Limit deve ser um inteiro entre 0 e 99."
	end

	timeLimit = newTimeLimit :: number
	scoreLimit = newScoreLimit :: number

	return true, "Configuracoes atualizadas."
end

function MatchControl.Start(): (boolean, string)
	if status ~= "Stopped" then
		return false, "A partida nao esta parada."
	end

	elapsedSeconds = 0
	status = "Running"

	return true, "Partida iniciada."
end

function MatchControl.Stop(): (boolean, string)
	if status == "Stopped" then
		return false, "A partida ja esta parada."
	end

	status = "Stopped"
	elapsedSeconds = 0

	return true, "Partida parada."
end

function MatchControl.TogglePause(): (boolean, string)
	if status == "Running" then
		status = "Paused"
		return true, "Partida pausada."
	end

	if status == "Paused" then
		status = "Running"
		return true, "Partida retomada."
	end

	return false, "Inicie a partida antes de pausa-la."
end

function MatchControl.IsRunning(): boolean
	return status == "Running"
end

function MatchControl.IsPaused(): boolean
	return status == "Paused"
end

function MatchControl.IsStopped(): boolean
	return status == "Stopped"
end

function MatchControl.Advance(
	deltaTime: number,
	scoreTeam1: number,
	scoreTeam2: number
): (boolean, string?)
	if status ~= "Running" then
		return false, nil
	end

	if deltaTime <= 0 or deltaTime ~= deltaTime then
		return false, nil
	end

	elapsedSeconds += deltaTime

	if scoreLimit > 0
		and (
			scoreTeam1 >= scoreLimit
			or scoreTeam2 >= scoreLimit
		)
	then
		status = "Stopped"
		return true, "ScoreLimit"
	end

	if timeLimit > 0
		and elapsedSeconds >= timeLimit * 60
	then
		status = "Stopped"
		return true, "TimeLimit"
	end

	return false, nil
end

return MatchControl