local InputBuffer = {}
InputBuffer.__index = InputBuffer

export type InputData = {
	moveX: number,
	moveY: number,
	kick: boolean
}

function InputBuffer.new(maxSize: number?)
	return setmetatable({
		_buffer = {},
		_lastKnown = {},
		_maxSize = maxSize or 300,
		_oldestTick = 0
	}, InputBuffer)
end

function InputBuffer.set(self, tick: number, userId: number, input: InputData)
	local tickData = self._buffer[tick]

	if not tickData then
		tickData = {}
		self._buffer[tick] = tickData
	end

	tickData[userId] = input
	self._lastKnown[userId] = input
end

function InputBuffer.get(self, tick: number, userId: number): InputData
	local tickData = self._buffer[tick]

	if tickData then
		local input = tickData[userId]

		if input then
			return input
		end
	end

	local last = self._lastKnown[userId]

	if last then
		return last
	end

	return {
		moveX = 0,
		moveY = 0,
		kick = false
	}
end

function InputBuffer.setLocal(self, tick: number, input: InputData)
	self:set(tick, 0, input)
end

function InputBuffer.getLocal(self, tick: number): InputData
	return self:get(tick, 0)
end

function InputBuffer.has(self, tick: number, userId: number): boolean
	local tickData = self._buffer[tick]

	return tickData ~= nil and tickData[userId] ~= nil
end

function InputBuffer.clearBefore(self, minTick: number)
	if minTick <= self._oldestTick then
		return
	end

	-- Remove only the ticks that have newly become obsolete.
	local tick = self._oldestTick

	while tick < minTick do
		self._buffer[tick] = nil
		tick += 1
	end

	self._oldestTick = minTick
end

function InputBuffer.removePlayer(self, userId: number)
	self._lastKnown[userId] = nil
end

return InputBuffer
