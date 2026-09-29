--!strict
-- SpatialHash.luau
-- Broadphase determinística por grid espacial.
--
-- A grid não resolve colisões.
-- Ela apenas retorna candidatos potencialmente próximos.
--
-- IMPORTANTE:
-- Os objetos são armazenados com seu índice original.
-- Os resultados das consultas são ordenados por esse índice
-- para preservar uma ordem determinística de colisão.

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
}

export type Grid = {
	cellSize: number,
	cells: {[string]: {Entry}},
	entries: {Entry},
}

----------------------------------------------------
-- CONSTRUÇÃO
----------------------------------------------------

function SpatialHash.new(cellSize: number): Grid
	assert(cellSize > 0, "SpatialHash.cellSize precisa ser maior que zero")

	return {
		cellSize = cellSize,
		cells = {},
		entries = {},
	}
end

----------------------------------------------------
-- CHAVE DA CÉLULA
----------------------------------------------------

local function getCellCoordinate(value: number, cellSize: number): number
	return math.floor(value / cellSize)
end

local function getCellKey(x: number, y: number): string
	return tostring(x) .. ":" .. tostring(y)
end

----------------------------------------------------
-- INSERIR OBJETO
----------------------------------------------------

function SpatialHash.insert(
	grid: Grid,
	object: any,
	aabb: AABB,
	index: number
)
	local minCellX = getCellCoordinate(aabb.minX, grid.cellSize)
	local maxCellX = getCellCoordinate(aabb.maxX, grid.cellSize)

	local minCellY = getCellCoordinate(aabb.minY, grid.cellSize)
	local maxCellY = getCellCoordinate(aabb.maxY, grid.cellSize)

	local entry: Entry = {
		object = object,
		index = index,
		aabb = aabb,
	}

	grid.entries[#grid.entries + 1] = entry

	for cellX = minCellX, maxCellX do
		for cellY = minCellY, maxCellY do
			local key = getCellKey(cellX, cellY)

			local cell = grid.cells[key]

			if not cell then
				cell = {}
				grid.cells[key] = cell
			end

			cell[#cell + 1] = entry
		end
	end
end

----------------------------------------------------
-- CONSULTAR AABB
----------------------------------------------------

function SpatialHash.query(
	grid: Grid,
	aabb: AABB
): {any}

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

	local objects = table.create(#entries)

	for i, entry in ipairs(entries) do
		objects[i] = entry.object
	end

	return objects
end

----------------------------------------------------
-- LIMPAR
----------------------------------------------------

function SpatialHash.clear(grid: Grid)
	table.clear(grid.cells)
	table.clear(grid.entries)
end

----------------------------------------------------
-- RECONSTRUIR
----------------------------------------------------

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