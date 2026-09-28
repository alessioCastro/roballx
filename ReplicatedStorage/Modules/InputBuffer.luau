--!strict
-- InputBuffer.luau
-- Buffer circular de inputs indexado por tick.
-- Usado tanto no servidor (para armazenar inputs de cada jogador)
-- quanto no cliente (para armazenar inputs locais para replay no rollback).

local InputBuffer = {}
InputBuffer.__index = InputBuffer

export type InputData = {
	moveX: number,
	moveY: number,
	kick: boolean,
}

export type InputBufferInstance = typeof(setmetatable({} :: {
	_buffer: { [number]: { [number]: InputData } }, -- tick → userId → InputData
	_lastKnown: { [number]: InputData }, -- userId → last known input
	_maxSize: number,
	_oldestTick: number,
}, InputBuffer))

function InputBuffer.new(maxSize: number?): InputBufferInstance
	local self = setmetatable({
		_buffer = {},
		_lastKnown = {},
		_maxSize = maxSize or 300,
		_oldestTick = 0,
	}, InputBuffer)
	return self
end

function InputBuffer.set(self: InputBufferInstance, tick: number, userId: number, input: InputData)
	if not self._buffer[tick] then
		self._buffer[tick] = {}
	end
	self._buffer[tick][userId] = input
	self._lastKnown[userId] = input
end

function InputBuffer.get(self: InputBufferInstance, tick: number, userId: number): InputData
	local tickData = self._buffer[tick]
	if tickData then
		local input = tickData[userId]
		if input then
			return input
		end
	end

	-- Fallback em caso de pacote perdido: Busca o último tick gravado ANTERIOR a este tick
	for searchTick = tick - 1, math.max(self._oldestTick, tick - 30), -1 do
		local prevData = self._buffer[searchTick]
		if prevData and prevData[userId] then
			return prevData[userId]
		end
	end

	-- Fallback final
	local last = self._lastKnown[userId]
	if last then
		return last
	end

	return { moveX = 0, moveY = 0, kick = false }
end

function InputBuffer.setLocal(self: InputBufferInstance, tick: number, input: InputData)
	self:set(tick, 0, input)
end

function InputBuffer.getLocal(self: InputBufferInstance, tick: number): InputData
	return self:get(tick, 0)
end

function InputBuffer.has(self: InputBufferInstance, tick: number, userId: number): boolean
	local tickData = self._buffer[tick]
	return tickData ~= nil and tickData[userId] ~= nil
end

function InputBuffer.clearBefore(self: InputBufferInstance, minTick: number)
	for tick, _ in pairs(self._buffer) do
		if tick < minTick then
			self._buffer[tick] = nil
		end
	end
	self._oldestTick = minTick
end

function InputBuffer.removePlayer(self: InputBufferInstance, userId: number)
	self._lastKnown[userId] = nil
end

function InputBuffer.getUserIdsForTick(self: InputBufferInstance, tick: number): { number }
	local tickData = self._buffer[tick]
	if not tickData then return {} end
	local ids = {}
	for uId, _ in pairs(tickData) do
		table.insert(ids, uId)
	end
	table.sort(ids)
	return ids
end

return InputBuffer