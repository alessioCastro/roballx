--!strict
-- SpatialHash.luau
-- Broadphase determinística por grid espacial.

local SpatialHash = {}
SpatialHash.__index = SpatialHash

local queryCounter = 0

export type AABB = {
	minX: number,
	minY: number,
	maxX: number,
	maxY: number,
}

export type CellReference = {
	x: number,
	y: number,
	index: number,
}

export type Entry = {
	object: any,
	index: number,
	aabb: AABB,

	cells: {CellReference},

	gridIndex: number,

	minCellX: number,
	maxCellX: number,
	minCellY: number,
	maxCellY: number,

	queryId: number,
}

export type Grid = {
	cellSize: number,
	cells: {[number]: {[number]: {Entry}}},
	entries: {Entry},
	queryBuffer: {Entry},
}

function SpatialHash.new(cellSize: number): Grid
	assert(
		cellSize > 0,
		"SpatialHash.cellSize precisa ser maior que zero"
	)

	return {
		cellSize = cellSize,
		cells = {},
		entries = {},
		queryBuffer = {},
	}
end

local function getCellCoordinate(
	value: number,
	cellSize: number
): number
	return math.floor(value / cellSize)
end

local function getOrCreateCell(
	grid: Grid,
	cellX: number,
	cellY: number
): {Entry}
	local column = grid.cells[cellX]

	if not column then
		column = {}
		grid.cells[cellX] = column
	end

	local cell = column[cellY]

	if not cell then
		cell = {}
		column[cellY] = cell
	end

	return cell
end

function SpatialHash.insert(
	grid: Grid,
	object: any,
	aabb: AABB,
	index: number
): Entry

	local minCellX =
		getCellCoordinate(
			aabb.minX,
			grid.cellSize
		)

	local maxCellX =
		getCellCoordinate(
			aabb.maxX,
			grid.cellSize
		)

	local minCellY =
		getCellCoordinate(
			aabb.minY,
			grid.cellSize
		)

	local maxCellY =
		getCellCoordinate(
			aabb.maxY,
			grid.cellSize
		)

	local entry: Entry = {
		object = object,
		index = index,
		aabb = aabb,

		cells = {},

		gridIndex = #grid.entries + 1,

		minCellX = minCellX,
		maxCellX = maxCellX,
		minCellY = minCellY,
		maxCellY = maxCellY,

		queryId = 0,
	}

	grid.entries[entry.gridIndex] = entry

	for cellX = minCellX, maxCellX do
		for cellY = minCellY, maxCellY do
			local cell =
				getOrCreateCell(
					grid,
					cellX,
					cellY
				)

			local cellIndex =
				#cell + 1

			cell[cellIndex] =
				entry

			entry.cells[#entry.cells + 1] = {
				x = cellX,
				y = cellY,
				index = cellIndex,
			}
		end
	end

	return entry
end

function SpatialHash.remove(
	grid: Grid,
	entry: Entry
)
	for _, cellReference in ipairs(entry.cells) do
		local column =
			grid.cells[cellReference.x]

		local cell =
			column
			and column[cellReference.y]

		if cell then
			local cellIndex =
				cellReference.index

			local lastIndex =
				#cell

			if cellIndex <= lastIndex then
				local lastEntry =
					cell[lastIndex]

				if cellIndex ~= lastIndex then
					cell[cellIndex] =
						lastEntry

					for _, lastCellReference in
						ipairs(lastEntry.cells)
					do
						if
							lastCellReference.x
							== cellReference.x
							and lastCellReference.y
							== cellReference.y
							and lastCellReference.index
							== lastIndex
						then
							lastCellReference.index =
								cellIndex

							break
						end
					end
				end

				cell[lastIndex] = nil
			end

			if #cell == 0 then
				column[cellReference.y] = nil
			end

			if next(column) == nil then
				grid.cells[cellReference.x] = nil
			end
		end
	end

	local gridIndex =
		entry.gridIndex

	local lastIndex =
		#grid.entries

	if gridIndex ~= lastIndex then
		local lastEntry =
			grid.entries[lastIndex]

		grid.entries[gridIndex] =
			lastEntry

		lastEntry.gridIndex =
			gridIndex
	end

	grid.entries[lastIndex] = nil

	table.clear(entry.cells)

	entry.gridIndex = 0
end

function SpatialHash.update(
	grid: Grid,
	entry: Entry,
	aabb: AABB
): Entry

	local minCellX =
		getCellCoordinate(
			aabb.minX,
			grid.cellSize
		)

	local maxCellX =
		getCellCoordinate(
			aabb.maxX,
			grid.cellSize
		)

	local minCellY =
		getCellCoordinate(
			aabb.minY,
			grid.cellSize
		)

	local maxCellY =
		getCellCoordinate(
			aabb.maxY,
			grid.cellSize
		)

	-- Continua nas mesmas células.
	if
		entry.minCellX == minCellX
		and entry.maxCellX == maxCellX
		and entry.minCellY == minCellY
		and entry.maxCellY == maxCellY
	then
		entry.aabb = aabb

		return entry
	end

	------------------------------------------------
	-- O objeto mudou de célula.
	--
	-- Reutilizamos a mesma Entry e as mesmas
	-- CellReferences sempre que possível.
	-- Isso evita remove() + insert() completos.
	------------------------------------------------

	local cellReferences =
		entry.cells

	local oldCellCount =
		#cellReferences

	------------------------------------------------
	-- REMOVE DAS CÉLULAS ANTIGAS
	------------------------------------------------

	for referenceIndex = 1, oldCellCount do
		local cellReference =
			cellReferences[referenceIndex]

		local column =
			grid.cells[cellReference.x]

		local cell =
			column
			and column[cellReference.y]

		if cell then
			local cellIndex =
				cellReference.index

			local lastIndex =
				#cell

			if cellIndex <= lastIndex then
				local lastEntry =
					cell[lastIndex]

				if cellIndex ~= lastIndex then
					cell[cellIndex] =
						lastEntry

					for _, lastCellReference in
						ipairs(lastEntry.cells)
					do
						if
							lastCellReference.x
							== cellReference.x
							and lastCellReference.y
							== cellReference.y
							and lastCellReference.index
							== lastIndex
						then
							lastCellReference.index =
								cellIndex

							break
						end
					end
				end

				cell[lastIndex] = nil
			end

			if #cell == 0 then
				column[cellReference.y] = nil
			end

			if next(column) == nil then
				grid.cells[cellReference.x] = nil
			end
		end
	end

	------------------------------------------------
	-- ADICIONA ÀS NOVAS CÉLULAS
	------------------------------------------------

	local newCellCount = 0

	for cellX = minCellX, maxCellX do
		for cellY = minCellY, maxCellY do
			local cell =
				getOrCreateCell(
					grid,
					cellX,
					cellY
				)

			local cellIndex =
				#cell + 1

			cell[cellIndex] =
				entry

			newCellCount += 1

			local cellReference =
				cellReferences[newCellCount]

			if not cellReference then
				cellReference = {
					x = cellX,
					y = cellY,
					index = cellIndex,
				}

				cellReferences[newCellCount] =
					cellReference
			else
				cellReference.x =
					cellX

				cellReference.y =
					cellY

				cellReference.index =
					cellIndex
			end
		end
	end

	-- Se a nova AABB ocupa menos células,
	-- descarta apenas as referências excedentes.
	for index = newCellCount + 1, oldCellCount do
		cellReferences[index] =
			nil
	end

	entry.aabb =
		aabb

	entry.minCellX =
		minCellX

	entry.maxCellX =
		maxCellX

	entry.minCellY =
		minCellY

	entry.maxCellY =
		maxCellY

	return entry
end

local function beginQuery(): number
	queryCounter += 1

	-- Evita qualquer possibilidade de overflow
	-- prático do identificador.
	if queryCounter >= 1000000000 then
		queryCounter = 1
	end

	return queryCounter
end

local function appendUnique(
	grid: Grid,
	minCellX: number,
	maxCellX: number,
	minCellY: number,
	maxCellY: number,
	queryId: number,
	entries: {Entry}
)
	for cellX = minCellX, maxCellX do
		local column =
			grid.cells[cellX]

		if column then
			for cellY = minCellY, maxCellY do
				local cell =
					column[cellY]

				if cell then
					for _, entry in ipairs(cell) do
						if entry.queryId ~= queryId then
							entry.queryId =
								queryId

							entries[#entries + 1] =
								entry
						end
					end
				end
			end
		end
	end
end

function SpatialHash.query(
	grid: Grid,
	aabb: AABB
): {Entry}

	local minCellX =
		getCellCoordinate(
			aabb.minX,
			grid.cellSize
		)

	local maxCellX =
		getCellCoordinate(
			aabb.maxX,
			grid.cellSize
		)

	local minCellY =
		getCellCoordinate(
			aabb.minY,
			grid.cellSize
		)

	local maxCellY =
		getCellCoordinate(
			aabb.maxY,
			grid.cellSize
		)

	local entries =
		grid.queryBuffer

	table.clear(entries)

	appendUnique(
		grid,
		minCellX,
		maxCellX,
		minCellY,
		maxCellY,
		beginQuery(),
		entries
	)

	return entries
end

function SpatialHash.queryCombined(
	staticGrid: Grid,
	dynamicGrid: Grid,
	aabb: AABB
): {Entry}

	local minCellX =
		getCellCoordinate(
			aabb.minX,
			staticGrid.cellSize
		)

	local maxCellX =
		getCellCoordinate(
			aabb.maxX,
			staticGrid.cellSize
		)

	local minCellY =
		getCellCoordinate(
			aabb.minY,
			staticGrid.cellSize
		)

	local maxCellY =
		getCellCoordinate(
			aabb.maxY,
			staticGrid.cellSize
		)

	local entries =
		staticGrid.queryBuffer

	table.clear(entries)

	local queryId =
		beginQuery()

	appendUnique(
		staticGrid,
		minCellX,
		maxCellX,
		minCellY,
		maxCellY,
		queryId,
		entries
	)

	appendUnique(
		dynamicGrid,
		minCellX,
		maxCellX,
		minCellY,
		maxCellY,
		queryId,
		entries
	)

	return entries
end

function SpatialHash.clear(grid: Grid)
	table.clear(grid.cells)
	table.clear(grid.entries)
	table.clear(grid.queryBuffer)
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
