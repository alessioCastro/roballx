--!strict
-- MapRuntime.luau
--
-- Converte o MapData declarativo, que não utiliza Vector2,
-- para a representação usada pelo runtime.
--
-- MapData:
--     { x = 100, y = -50 }
--
-- Runtime:
--     Vector2.new(100, -50)

local MapRuntime = {}

local function isCoordinateTable(value: any): boolean
	if type(value) ~= "table" then
		return false
	end

	if type(value.x) ~= "number"
		or type(value.y) ~= "number"
	then
		return false
	end

	local count = 0

	for key in pairs(value) do
		count += 1

		if key ~= "x" and key ~= "y" then
			return false
		end
	end

	return count == 2
end

local function convert(value: any): any
	if isCoordinateTable(value) then
		return Vector2.new(
			value.x,
			value.y
		)
	end

	if type(value) ~= "table" then
		return value
	end

	local result = {}

	for key, child in pairs(value) do
		result[key] = convert(child)
	end

	return result
end

function MapRuntime.Build(mapData: any): any
	return convert(mapData)
end

return MapRuntime