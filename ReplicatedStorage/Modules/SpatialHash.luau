--!strict
-- SpatialHash.luau
-- Broadphase determinística por grid espacial.

local SpatialHash = {}
SpatialHash.__index = SpatialHash

export type AABB = {
	minX: number,
	minY: number,
	maxX: number,
	maxY: number,
}

export type Entry = {
	object: any,
	index: number,
	aabb: AABB,
	cells: {string},
	cellIndices: {[string]: number},
	gridIndex: number,
}

export type Grid = {
	cellSize: number,
	cells: {[string]: {Entry}},
	entries: {Entry},
}

function SpatialHash.new(cellSize: number): Grid
	assert(cellSize > 0, "SpatialHash.cellSize precisa ser maior que zero")

	return {
		cellSize = cellSize,
		cells = {},
		entries = {},
	}
end

local function getCellCoordinate(value: number, cellSize: number): number
	return math.floor(value / cellSize)
end

local function getCellKey(x: number, y: number): string
	return tostring(x) .. ":" .. tostring(y)
end

function SpatialHash.insert(
	grid: Grid,
	object: any,
	aabb: AABB,
	index: number
): Entry

	local minCellX = getCellCoordinate(aabb.minX, grid.cellSize)
	local maxCellX = getCellCoordinate(aabb.maxX, grid.cellSize)

	local minCellY = getCellCoordinate(aabb.minY, grid.cellSize)
	local maxCellY = getCellCoordinate(aabb.maxY, grid.cellSize)

	local entry: Entry = {
		object = object,
		index = index,
		aabb = aabb,
		cells = {},
		cellIndices = {},
		gridIndex = #grid.entries + 1,
	}

	grid.entries[entry.gridIndex] = entry

	for cellX = minCellX, maxCellX do
		for cellY = minCellY, maxCellY do
			local key = getCellKey(cellX, cellY)

			local cell = grid.cells[key]

			if not cell then
				cell = {}
				grid.cells[key] = cell
			end

			local cellIndex = #cell + 1

			cell[cellIndex] = entry
			entry.cells[#entry.cells + 1] = key
			entry.cellIndices[key] = cellIndex
		end
	end

	return entry
end

function SpatialHash.remove(
	grid: Grid,
	entry: Entry
)
	for _, key in ipairs(entry.cells) do
		local cell = grid.cells[key]

		if cell then
			local cellIndex = entry.cellIndices[key]

			if cellIndex then
				local lastIndex = #cell
				local lastEntry = cell[lastIndex]

				if cellIndex ~= lastIndex then
					cell[cellIndex] = lastEntry
					lastEntry.cellIndices[key] = cellIndex
				end

				cell[lastIndex] = nil
			end

			if #cell == 0 then
				grid.cells[key] = nil
			end
		end
	end

	local gridIndex = entry.gridIndex
	local lastIndex = #grid.entries

	if gridIndex ~= lastIndex then
		local lastEntry = grid.entries[lastIndex]

		grid.entries[gridIndex] = lastEntry
		lastEntry.gridIndex = gridIndex
	end

	grid.entries[lastIndex] = nil

	table.clear(entry.cells)
	table.clear(entry.cellIndices)
	entry.gridIndex = 0
end

function SpatialHash.update(
	grid: Grid,
	entry: Entry,
	aabb: AABB
): Entry

	local object = entry.object
	local index = entry.index

	SpatialHash.remove(
		grid,
		entry
	)

	return SpatialHash.insert(
		grid,
		object,
		aabb,
		index
	)
end

function SpatialHash.query(
	grid: Grid,
	aabb: AABB
): {Entry}

	local minCellX = getCellCoordinate(aabb.minX, grid.cellSize)
	local maxCellX = getCellCoordinate(aabb.maxX, grid.cellSize)

	local minCellY = getCellCoordinate(aabb.minY, grid.cellSize)
	local maxCellY = getCellCoordinate(aabb.maxY, grid.cellSize)

	local found: {[any]: Entry} = {}

	for cellX = minCellX, maxCellX do
		for cellY = minCellY, maxCellY do
			local key = getCellKey(cellX, cellY)
			local cell = grid.cells[key]

			if cell then
				for _, entry in ipairs(cell) do
					found[entry.object] = entry
				end
			end
		end
	end

	local entries = {}

	for _, entry in pairs(found) do
		entries[#entries + 1] = entry
	end

	table.sort(entries, function(a, b)
		return a.index < b.index
	end)

	return entries
end

function SpatialHash.queryCombined(
	staticGrid: Grid,
	dynamicGrid: Grid,
	aabb: AABB
): {Entry}

	local found: {[any]: Entry} = {}

	local staticEntries = SpatialHash.query(
		staticGrid,
		aabb
	)

	for _, entry in ipairs(staticEntries) do
		found[entry.object] = entry
	end

	local dynamicEntries = SpatialHash.query(
		dynamicGrid,
		aabb
	)

	for _, entry in ipairs(dynamicEntries) do
		found[entry.object] = entry
	end

	local entries = {}

	for _, entry in pairs(found) do
		entries[#entries + 1] = entry
	end

	table.sort(entries, function(a, b)
		return a.index < b.index
	end)

	return entries
end

function SpatialHash.clear(grid: Grid)
	table.clear(grid.cells)
	table.clear(grid.entries)
end

function SpatialHash.rebuild(
	grid: Grid,
	objects: {any},
	getAABB: (any) -> AABB
)
	SpatialHash.clear(grid)

	for index, object in ipairs(objects) do
		SpatialHash.insert(
			grid,
			object,
			getAABB(object),
			index
		)
	end
end

return SpatialHash
