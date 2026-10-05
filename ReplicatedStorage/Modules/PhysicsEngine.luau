--!strict
local PhysicsEngine = {}

local SpatialHash = require(script.Parent.SpatialHash)

local DEFAULT_MASK = 0xFFFFFFFF

export type CircleObject = {
	id: string?,
	pos: Vector2,
	vel: Vector2,
	radius: number,
	mass: number,
	restitution: number,
	isStatic: boolean?,
	isSolid: boolean?,
	damping: number?,
	resettable: boolean?,

	rotation: number?,
	rotationLocked: boolean?,
	angularVelocity: number?,

	team: string?,
	input: Vector2?,
	isKicking: boolean?,
	lastKickTick: number?,
	cGroup: number?,
	cMask: number?
}

export type Segment = {
	id: string?,
	a: Vector2,
	b: Vector2,
	vel: Vector2?,
	mass: number?,
	restitution: number?,
	isStatic: boolean?,
	isSolid: boolean?,
	damping: number?,
	resettable: boolean?,
	thickness: number?,
	ignoreCapA: boolean?,
	ignoreCapB: boolean?,

	rotation: number?,
	rotationLocked: boolean?,
	angularVelocity: number?,

	cGroup: number?,
	cMask: number?
}

export type PhysicalShape = {
	id: string?,
	pos: Vector2,
	vel: Vector2?,
	mass: number?,
	size: Vector2,
	rotation: number?,
	rotationLocked: boolean?,
	angularVelocity: number?,
	cornerRadius: number?,
	restitution: number?,
	isStatic: boolean?,
	isSolid: boolean?,
	damping: number?,
	resettable: boolean?,
	cGroup: number?,
	cMask: number?,

	segmentP1: Vector2,
	segmentP2: Vector2,
	segmentRadius: number,
}

export type PlayerObject = {
	id: string?,
	kind: "disc" | "shape" | "segment",

	pos: Vector2?,
	vel: Vector2,

	radius: number?,
	mass: number,
	restitution: number,

	size: Vector2?,
	rotation: number?,
	cornerRadius: number?,
	segmentP1: Vector2?,
	segmentP2: Vector2?,
	segmentRadius: number?,

	a: Vector2?,
	b: Vector2?,
	thickness: number?,
	ignoreCapA: boolean?,
	ignoreCapB: boolean?,

	isStatic: boolean?,
	isSolid: boolean?,
	damping: number?,

	team: string?,
	spawnIndex: number?,
	input: Vector2?,
	isKicking: boolean?,
	lastKickTick: number?,
	cGroup: number?,
	cMask: number?
}

export type Broadphase = {
	staticDiscGrid: SpatialHash.Grid,
	staticSegmentGrid: SpatialHash.Grid,
	staticShapeGrid: SpatialHash.Grid,

	dynamicDiscGrid: SpatialHash.Grid,
	dynamicSegmentGrid: SpatialHash.Grid,
	dynamicShapeGrid: SpatialHash.Grid,

	playerGrid: SpatialHash.Grid,

	discIndex: {[any]: number},
	segmentIndex: {[any]: number},
	shapeIndex: {[any]: number},
	playerIndex: {[any]: number},

	dynamicDiscEntries: {[any]: SpatialHash.Entry},
	dynamicSegmentEntries: {[any]: SpatialHash.Entry},
	dynamicShapeEntries: {[any]: SpatialHash.Entry},

	playerEntries: {[any]: SpatialHash.Entry},
}

----------------------------------------------------
-- GEOMETRY
----------------------------------------------------

local function getCircleAABB(circle: CircleObject): SpatialHash.AABB
	local radius = circle.radius

	return {
		minX = circle.pos.X - radius,
		minY = circle.pos.Y - radius,
		maxX = circle.pos.X + radius,
		maxY = circle.pos.Y + radius,
	}
end

local function getSegmentAABB(segment: Segment): SpatialHash.AABB
	local halfThickness = (segment.thickness or 0) * 0.5

	return {
		minX = math.min(segment.a.X, segment.b.X) - halfThickness,
		minY = math.min(segment.a.Y, segment.b.Y) - halfThickness,
		maxX = math.max(segment.a.X, segment.b.X) + halfThickness,
		maxY = math.max(segment.a.Y, segment.b.Y) + halfThickness,
	}
end

local function getShapeAABB(shape: PhysicalShape): SpatialHash.AABB
	local p1 = shape.pos + shape.segmentP1
	local p2 = shape.pos + shape.segmentP2
	local radius = shape.segmentRadius

	return {
		minX = math.min(p1.X, p2.X) - radius,
		minY = math.min(p1.Y, p2.Y) - radius,
		maxX = math.max(p1.X, p2.X) + radius,
		maxY = math.max(p1.Y, p2.Y) + radius,
	}
end

local function getPlayerAABB(player: PlayerObject): SpatialHash.AABB
	if player.kind == "disc" then
		local pos = player.pos :: Vector2
		local radius = player.radius :: number

		return {
			minX = pos.X - radius,
			minY = pos.Y - radius,
			maxX = pos.X + radius,
			maxY = pos.Y + radius,
		}
	end

	if player.kind == "shape" then
		local pos = player.pos :: Vector2
		local p1 = pos + (player.segmentP1 :: Vector2)
		local p2 = pos + (player.segmentP2 :: Vector2)
		local radius = player.segmentRadius :: number

		return {
			minX = math.min(p1.X, p2.X) - radius,
			minY = math.min(p1.Y, p2.Y) - radius,
			maxX = math.max(p1.X, p2.X) + radius,
			maxY = math.max(p1.Y, p2.Y) + radius,
		}
	end

	local a = player.a :: Vector2
	local b = player.b :: Vector2
	local halfThickness = (player.thickness or 0) * 0.5

	return {
		minX = math.min(a.X, b.X) - halfThickness,
		minY = math.min(a.Y, b.Y) - halfThickness,
		maxX = math.max(a.X, b.X) + halfThickness,
		maxY = math.max(a.Y, b.Y) + halfThickness,
	}
end

local function getPlayerCenter(player: PlayerObject): Vector2
	if player.kind == "disc" or player.kind == "shape" then
		return player.pos :: Vector2
	end

	return ((player.a :: Vector2) + (player.b :: Vector2)) * 0.5
end

local function getPlayerBoundingRadius(player: PlayerObject): number
	if player.kind == "disc" then
		return player.radius :: number
	end

	if player.kind == "shape" then
		local size = player.size :: Vector2

		return math.sqrt(
			(size.X * 0.5) ^ 2
				+ (size.Y * 0.5) ^ 2
		)
	end

	return
		((player.b :: Vector2) - (player.a :: Vector2)).Magnitude * 0.5
		+ ((player.thickness or 0) * 0.5)
end

local function getPlayerSegment(
	player: PlayerObject
): (Vector2, Vector2, number)
	if player.kind == "shape" then
		return
			(player.pos :: Vector2) + (player.segmentP1 :: Vector2),
			(player.pos :: Vector2) + (player.segmentP2 :: Vector2),
			player.segmentRadius :: number
	end

	return
		player.a :: Vector2,
		player.b :: Vector2,
		(player.thickness or 0) * 0.5
end

----------------------------------------------------
-- BROADPHASE
----------------------------------------------------

function PhysicsEngine.createBroadphase(
	collisionDiscs: {CircleObject},
	collisionSegments: {Segment},
	collisionShapes: {PhysicalShape},
	cellSize: number
): Broadphase

	local broadphase: Broadphase = {
		staticDiscGrid = SpatialHash.new(cellSize),
		staticSegmentGrid = SpatialHash.new(cellSize),
		staticShapeGrid = SpatialHash.new(cellSize),

		dynamicDiscGrid = SpatialHash.new(cellSize),
		dynamicSegmentGrid = SpatialHash.new(cellSize),
		dynamicShapeGrid = SpatialHash.new(cellSize),

		playerGrid = SpatialHash.new(cellSize),

		discIndex = {},
		segmentIndex = {},
		shapeIndex = {},
		playerIndex = {},

		dynamicDiscEntries = {},
		dynamicSegmentEntries = {},
		dynamicShapeEntries = {},

		playerEntries = {},
	}

	for index, disc in ipairs(collisionDiscs) do
		broadphase.discIndex[disc] = index

		local grid =
			disc.isStatic
			and broadphase.staticDiscGrid
			or broadphase.dynamicDiscGrid

		local entry = SpatialHash.insert(
			grid,
			disc,
			getCircleAABB(disc),
			index
		)

		if disc.isStatic ~= true then
			broadphase.dynamicDiscEntries[disc] = entry
		end
	end

	for index, segment in ipairs(collisionSegments) do
		broadphase.segmentIndex[segment] = index

		local grid =
			segment.isStatic
			and broadphase.staticSegmentGrid
			or broadphase.dynamicSegmentGrid

		local entry = SpatialHash.insert(
			grid,
			segment,
			getSegmentAABB(segment),
			index
		)

		if segment.isStatic ~= true then
			broadphase.dynamicSegmentEntries[segment] = entry
		end
	end

	for index, shape in ipairs(collisionShapes) do
		broadphase.shapeIndex[shape] = index

		local grid =
			shape.isStatic
			and broadphase.staticShapeGrid
			or broadphase.dynamicShapeGrid

		local entry = SpatialHash.insert(
			grid,
			shape,
			getShapeAABB(shape),
			index
		)

		if shape.isStatic ~= true then
			broadphase.dynamicShapeEntries[shape] = entry
		end
	end

	return broadphase
end

function PhysicsEngine.rebuildBroadphase(
	broadphase: Broadphase,
	collisionDiscs: {CircleObject},
	collisionSegments: {Segment},
	collisionShapes: {PhysicalShape}
)
	SpatialHash.clear(broadphase.dynamicDiscGrid)
	SpatialHash.clear(broadphase.dynamicSegmentGrid)
	SpatialHash.clear(broadphase.dynamicShapeGrid)

	table.clear(broadphase.dynamicDiscEntries)
	table.clear(broadphase.dynamicSegmentEntries)
	table.clear(broadphase.dynamicShapeEntries)

	for index, disc in ipairs(collisionDiscs) do
		if disc.isStatic ~= true then
			broadphase.dynamicDiscEntries[disc] =
				SpatialHash.insert(
					broadphase.dynamicDiscGrid,
					disc,
					getCircleAABB(disc),
					index
				)
		end
	end

	for index, segment in ipairs(collisionSegments) do
		if segment.isStatic ~= true then
			broadphase.dynamicSegmentEntries[segment] =
				SpatialHash.insert(
					broadphase.dynamicSegmentGrid,
					segment,
					getSegmentAABB(segment),
					index
				)
		end
	end

	for index, shape in ipairs(collisionShapes) do
		if shape.isStatic ~= true then
			broadphase.dynamicShapeEntries[shape] =
				SpatialHash.insert(
					broadphase.dynamicShapeGrid,
					shape,
					getShapeAABB(shape),
					index
				)
		end
	end
end

function PhysicsEngine.rebuildPlayerBroadphase(
	broadphase: Broadphase,
	playersData,
	sortedUserIds
)
	local activePlayers = {}

	for index, userId in ipairs(sortedUserIds) do
		local player = playersData[userId]

		if player then
			activePlayers[player] = true
			broadphase.playerIndex[player] = index

			local entry = broadphase.playerEntries[player]

			if entry then
				entry.index = index
				broadphase.playerEntries[player] =
					SpatialHash.update(
						broadphase.playerGrid,
						entry,
						getPlayerAABB(player)
					)
			else
				broadphase.playerEntries[player] =
					SpatialHash.insert(
						broadphase.playerGrid,
						player,
						getPlayerAABB(player),
						index
					)
			end
		end
	end

	for player, entry in pairs(broadphase.playerEntries) do
		if not activePlayers[player] then
			SpatialHash.remove(
				broadphase.playerGrid,
				entry
			)

			broadphase.playerEntries[player] = nil
			broadphase.playerIndex[player] = nil
		end
	end
end

local function getCombinedRestitution(
	a: any,
	b: any
): number
	return
		math.max(0, a.restitution or 0)
		* math.max(0, b.restitution or 0)
end

----------------------------------------------------
-- ANGULAR PHYSICS
----------------------------------------------------

local function crossScalar(
	a: Vector2,
	b: Vector2
): number
	return a.X * b.Y - a.Y * b.X
end

local function crossOmegaVector(
	omega: number,
	r: Vector2
): Vector2
	return Vector2.new(
		-omega * r.Y,
		omega * r.X
	)
end

local function getCircleInertia(
	object: CircleObject
): number
	local mass = math.max(object.mass, 0.000001)
	local radius = object.radius

	return 0.5 * mass * radius * radius
end

local function getShapeInertia(
	shape: PhysicalShape
): number
	local mass = math.max(shape.mass or 1, 0.000001)
	local width = shape.size.X
	local height = shape.size.Y

	return mass * (
		width * width
			+ height * height
	) / 12
end

local function getSegmentInertia(
	segment: Segment
): number
	local mass =
		math.max(
			segment.mass or 1,
			0.000001
		)

	local length =
		(segment.b - segment.a).Magnitude

	return mass * length * length / 12
end

local function getInverseInertia(
	object: any
): number
	if object.isStatic == true then
		return 0
	end

	if object.rotationLocked == true then
		return 0
	end

	local inertia

	if object.radius ~= nil then
		inertia =
			getCircleInertia(
				object
			)
	elseif object.size ~= nil then
		inertia =
			getShapeInertia(
				object
			)
	elseif object.a ~= nil and object.b ~= nil then
		inertia =
			getSegmentInertia(
				object
			)
	else
		return 0
	end

	if inertia <= 0 then
		return 0
	end

	return 1 / inertia
end

local function getObjectCenter(
	object: any
): Vector2
	if object.pos ~= nil then
		return object.pos
	end

	return (
		object.a
			+ object.b
	) * 0.5
end

local function getAngularVelocity(
	object: any
): number
	return object.angularVelocity or 0
end

local function applyAngularImpulse(
	object: any,
	contactVector: Vector2,
	impulse: Vector2
)
	local inverseInertia =
		getInverseInertia(object)

	if inverseInertia == 0 then
		return
	end

	object.angularVelocity =
		getAngularVelocity(object)
		+ crossScalar(
			contactVector,
			impulse
		) * inverseInertia
end

local function getContactVelocity(
	object: any,
	contactVector: Vector2
): Vector2
	return
		(object.vel or Vector2.zero)
		+ crossOmegaVector(
			getAngularVelocity(object),
			contactVector
		)
end

local function integrateSegmentRotation(
	segment: Segment,
	deltaTime: number
)
	if
		segment.isStatic == true
		or segment.rotationLocked == true
	then
		return
	end

	local angularVelocity =
		segment.angularVelocity or 0

	if angularVelocity == 0 then
		return
	end

	local center =
		(segment.a + segment.b) * 0.5

	local angle =
		angularVelocity * deltaTime

	local relativeA =
		segment.a - center

	local relativeB =
		segment.b - center

	segment.a =
		center
		+ rotateVector(
			relativeA,
			angle
		)

	segment.b =
		center
		+ rotateVector(
			relativeB,
			angle
		)

	segment.rotation =
		(segment.rotation or 0)
		+ angle
end

----------------------------------------------------
-- COLLISION FILTER
----------------------------------------------------

local function canCollide(a: any, b: any): boolean
	local groupA = a.cGroup or DEFAULT_MASK
	local maskA = a.cMask or DEFAULT_MASK
	local groupB = b.cGroup or DEFAULT_MASK
	local maskB = b.cMask or DEFAULT_MASK

	return
		bit32.btest(groupA, maskB)
		and bit32.btest(groupB, maskA)
end

----------------------------------------------------
-- SHAPE PREPARATION
----------------------------------------------------

local function rotateVector(
	v: Vector2,
	angleDegrees: number
): Vector2
	if angleDegrees == 0 then
		return v
	end

	local rad = math.rad(angleDegrees)
	local cos = math.cos(rad)
	local sin = math.sin(rad)

	return Vector2.new(
		v.X * cos - v.Y * sin,
		v.X * sin + v.Y * cos
	)
end

function PhysicsEngine.prepareShape(
	shape: PhysicalShape
)
	local w = shape.size.X
	local h = shape.size.Y

	local radius = math.min(w, h) / 2

	local extentX =
		math.max(0, (w / 2) - radius)

	local extentY =
		math.max(0, (h / 2) - radius)

	local p1Local: Vector2
	local p2Local: Vector2

	if extentX >= extentY then
		p1Local =
			Vector2.new(-extentX, 0)

		p2Local =
			Vector2.new(extentX, 0)
	else
		p1Local =
			Vector2.new(0, -extentY)

		p2Local =
			Vector2.new(0, extentY)
	end

	local rotation =
		shape.rotation or 0

	shape.segmentP1 =
		rotateVector(
			p1Local,
			rotation
		)

	shape.segmentP2 =
		rotateVector(
			p2Local,
			rotation
		)

	shape.segmentRadius = radius
end

----------------------------------------------------
-- SEGMENT HELPERS
----------------------------------------------------

local function closestPointOnSegment(
	p: Vector2,
	a: Vector2,
	b: Vector2
): Vector2
	local ab = b - a
	local ab2 = ab:Dot(ab)

	if ab2 == 0 then
		return a
	end

	local t = math.clamp(
		(p - a):Dot(ab) / ab2,
		0,
		1
	)

	return a + ab * t
end

local function getShapeSegment(
	shape: PhysicalShape
): (Vector2, Vector2, number)
	return
		shape.pos + shape.segmentP1,
		shape.pos + shape.segmentP2,
		shape.segmentRadius
end

local function getClosestPointsBetweenSegments(
	a1: Vector2,
	a2: Vector2,
	b1: Vector2,
	b2: Vector2
): (Vector2, Vector2, number)

	local bestA = a1
	local bestB =
		closestPointOnSegment(
			a1,
			b1,
			b2
		)

	local delta = bestB - bestA
	local minDistSq = delta:Dot(delta)

	local pA = a2
	local pB =
		closestPointOnSegment(
			a2,
			b1,
			b2
		)

	delta = pB - pA
	local distSq = delta:Dot(delta)

	if distSq < minDistSq then
		minDistSq = distSq
		bestA = pA
		bestB = pB
	end

	pA =
		closestPointOnSegment(
			b1,
			a1,
			a2
		)

	pB = b1

	delta = pB - pA
	distSq = delta:Dot(delta)

	if distSq < minDistSq then
		minDistSq = distSq
		bestA = pA
		bestB = pB
	end

	pA =
		closestPointOnSegment(
			b2,
			a1,
			a2
		)

	pB = b2

	delta = pB - pA
	distSq = delta:Dot(delta)

	if distSq < minDistSq then
		minDistSq = distSq
		bestA = pA
		bestB = pB
	end

	return
		bestA,
		bestB,
		math.sqrt(minDistSq)
end

----------------------------------------------------
-- CIRCLE VS SHAPE
----------------------------------------------------

function PhysicsEngine.resolveShapeCollision(
	obj: CircleObject,
	shape: PhysicalShape
)
	if not canCollide(obj, shape) then
		return
	end

	if
		shape.isSolid == false
		or obj.isSolid == false
	then
		return
	end

	local shapeVel =
		shape.vel or Vector2.zero

	local shapeMass =
		shape.mass or 1

	local shapeIsStatic =
		shape.isStatic ~= false

	local objIsStatic =
		obj.isStatic == true

	if shapeIsStatic and objIsStatic then
		return
	end

	local s1, s2, shapeRad =
		getShapeSegment(shape)

	local closestOnSeg =
		closestPointOnSegment(
			obj.pos,
			s1,
			s2
		)

	local delta =
		obj.pos - closestOnSeg

	local dist =
		delta.Magnitude

	local minDist =
		obj.radius + shapeRad

	if dist >= minDist then
		return
	end

	local normal =
		dist > 0.0001
		and delta / dist
		or Vector2.new(0, 1)

	local overlap =
		minDist - dist

	if shapeIsStatic then
		obj.pos +=
			normal * overlap

	elseif objIsStatic then
		shape.pos -=
			normal * overlap

	else
		local totalMass =
			obj.mass + shapeMass

		obj.pos +=
			normal
			* overlap
			* (shapeMass / totalMass)

		shape.pos -=
			normal
			* overlap
			* (obj.mass / totalMass)
	end

	local relVel =
		obj.vel - shapeVel

	local velAlongNormal =
		relVel:Dot(normal)

	if velAlongNormal >= 0 then
		return
	end

	local e =
		getCombinedRestitution(
			obj,
			shape
		)

	if shapeIsStatic then
		obj.vel -=
			(1 + e)
			* velAlongNormal
			* normal

	elseif objIsStatic then
		shape.vel =
			shapeVel
			+ (1 + e)
			* velAlongNormal
			* normal

	else
		local impulseMag =
			-(1 + e)
			* velAlongNormal
			/ (
				1 / obj.mass
				+ 1 / shapeMass
			)

		local impulse =
			normal * impulseMag

		obj.vel +=
			impulse / obj.mass

		shape.vel =
			shapeVel
			- impulse / shapeMass
	end
end

----------------------------------------------------
-- SHAPE VS SHAPE
----------------------------------------------------

function PhysicsEngine.resolveShapeVsShapeCollision(
	sA: PhysicalShape,
	sB: PhysicalShape
)
	if not canCollide(sA, sB) then
		return
	end

	if
		sA.isSolid == false
		or sB.isSolid == false
	then
		return
	end

	local aIsStatic =
		sA.isStatic ~= false

	local bIsStatic =
		sB.isStatic ~= false

	if aIsStatic and bIsStatic then
		return
	end

	local a1, a2, radA =
		getShapeSegment(sA)

	local b1, b2, radB =
		getShapeSegment(sB)

	local pA, pB, dist =
		getClosestPointsBetweenSegments(
			a1,
			a2,
			b1,
			b2
		)

	local minDist =
		radA + radB

	if dist >= minDist then
		return
	end

	local delta =
		pB - pA

	local normal =
		dist > 0.0001
		and delta / dist
		or Vector2.new(0, 1)

	local overlap =
		minDist - dist

	local massA =
		sA.mass or 1

	local massB =
		sB.mass or 1

	local velA =
		sA.vel or Vector2.zero

	local velB =
		sB.vel or Vector2.zero

	local e =
		getCombinedRestitution(
			sA,
			sB
		)

	if aIsStatic then
		sB.pos +=
			normal * overlap

		local velAlongNormal =
			velB:Dot(normal)

		if velAlongNormal < 0 then
			sB.vel =
				velB
				- (1 + e)
				* velAlongNormal
				* normal
		end

		return
	end

	if bIsStatic then
		sA.pos -=
			normal * overlap

		local velAlongNormal =
			velA:Dot(normal)

		if velAlongNormal > 0 then
			sA.vel =
				velA
				- (1 + e)
				* velAlongNormal
				* normal
		end

		return
	end

	local totalMass =
		massA + massB

	sA.pos -=
		normal
		* overlap
		* (massB / totalMass)

	sB.pos +=
		normal
		* overlap
		* (massA / totalMass)

	local relVel =
		velB - velA

	local velAlongNormal =
		relVel:Dot(normal)

	if velAlongNormal < 0 then
		local impulseMag =
			-(1 + e)
			* velAlongNormal
			/ (
				1 / massA
				+ 1 / massB
			)

		local impulse =
			normal * impulseMag

		sA.vel =
			velA - impulse / massA

		sB.vel =
			velB + impulse / massB
	end
end

----------------------------------------------------
-- SHAPE VS SEGMENT
----------------------------------------------------

function PhysicsEngine.resolveShapeVsSegmentCollision(
	shape: PhysicalShape,
	seg: Segment
)
	if not canCollide(shape, seg) then
		return
	end

	if
		shape.isSolid == false
		or seg.isSolid == false
	then
		return
	end

	local shape1, shape2, shapeRad =
		getShapeSegment(shape)

	local segRad =
		(seg.thickness or 2) * 0.5

	local pShape, pSeg, dist =
		getClosestPointsBetweenSegments(
			shape1,
			shape2,
			seg.a,
			seg.b
		)

	local minDist =
		shapeRad + segRad

	if dist >= minDist then
		return
	end

	local delta =
		pShape - pSeg

	local normal =
		dist > 0.0001
		and delta / dist
		or Vector2.new(0, 1)

	local overlap =
		minDist - dist

	local shapeIsStatic =
		shape.isStatic ~= false

	local segIsStatic =
		seg.isStatic ~= false

	local shapeVel =
		shape.vel or Vector2.zero

	local segVel =
		seg.vel or Vector2.zero

	local shapeMass =
		shape.mass or 1

	local segMass =
		seg.mass or 1

	local e =
		getCombinedRestitution(
			shape,
			seg
		)

	if segIsStatic and not shapeIsStatic then
		shape.pos +=
			normal * overlap

		local relVel =
			shapeVel - segVel

		local velAlongNormal =
			relVel:Dot(normal)

		if velAlongNormal < 0 then
			shape.vel =
				shapeVel
				- (1 + e)
				* velAlongNormal
				* normal
		end

		return
	end

	if shapeIsStatic and not segIsStatic then
		seg.a -=
			normal * overlap

		seg.b -=
			normal * overlap

		local relVel =
			shapeVel - segVel

		local velAlongNormal =
			relVel:Dot(normal)

		if velAlongNormal > 0 then
			seg.vel =
				segVel
				+ (1 + e)
				* velAlongNormal
				* normal
		end

		return
	end

	if not shapeIsStatic and not segIsStatic then
		local totalMass =
			shapeMass + segMass

		shape.pos +=
			normal
			* overlap
			* (segMass / totalMass)

		seg.a -=
			normal
			* overlap
			* (shapeMass / totalMass)

		seg.b -=
			normal
			* overlap
			* (shapeMass / totalMass)

		local relVel =
			shapeVel - segVel

		local velAlongNormal =
			relVel:Dot(normal)

		if velAlongNormal < 0 then
			local impulseMag =
				-(1 + e)
				* velAlongNormal
				/ (
					1 / shapeMass
					+ 1 / segMass
				)

			local impulse =
				normal * impulseMag

			shape.vel =
				shapeVel
				+ impulse / shapeMass

			seg.vel =
				segVel
				- impulse / segMass
		end
	end
end

----------------------------------------------------
-- CIRCLE VS SEGMENT
----------------------------------------------------

function PhysicsEngine.resolveSegmentCollision(
	obj: CircleObject,
	seg: Segment
)
	if not canCollide(obj, seg) then
		return
	end

	if
		seg.isSolid == false
		or obj.isSolid == false
	then
		return
	end

	local ab =
		seg.b - seg.a

	local ap =
		obj.pos - seg.a

	local ab2 =
		ab:Dot(ab)

	if ab2 == 0 then
		return
	end

	local t =
		ap:Dot(ab) / ab2

	if
		seg.ignoreCapA
		and t < 0
	then
		return
	end

	if
		seg.ignoreCapB
		and t > 1
	then
		return
	end

	t =
		math.clamp(t, 0, 1)

	local closest =
		seg.a + ab * t

	local delta =
		obj.pos - closest

	local dist =
		delta.Magnitude

	if dist >= obj.radius then
		return
	end

	local normal

	if dist > 0.0001 then
		normal =
			delta / dist
	else
		normal =
			Vector2.new(
				-ab.Y,
				ab.X
			).Unit
	end

	local overlap =
		obj.radius - dist

	local segVel =
		seg.vel or Vector2.zero

	local segIsStatic =
		seg.isStatic ~= false

	local objIsStatic =
		obj.isStatic == true

	local segMass =
		seg.mass or 1

	local e =
		getCombinedRestitution(
			obj,
			seg
		)

	if segIsStatic and not objIsStatic then
		obj.pos +=
			normal * overlap

		local relVel =
			obj.vel - segVel

		local velAlongNormal =
			relVel:Dot(normal)

		if velAlongNormal < 0 then
			obj.vel -=
				(1 + e)
				* velAlongNormal
				* normal
		end

		return
	end

	if objIsStatic and not segIsStatic then
		seg.a -=
			normal * overlap

		seg.b -=
			normal * overlap

		local relVel =
			obj.vel - segVel

		local velAlongNormal =
			relVel:Dot(normal)

		if velAlongNormal > 0 then
			seg.vel =
				segVel
				+ (1 + e)
				* velAlongNormal
				* normal
		end

		return
	end

	if not objIsStatic and not segIsStatic then
		local totalMass =
			obj.mass + segMass

		obj.pos +=
			normal
			* overlap
			* (segMass / totalMass)

		seg.a -=
			normal
			* overlap
			* (obj.mass / totalMass)

		seg.b -=
			normal
			* overlap
			* (obj.mass / totalMass)

		local relativeVel =
			obj.vel - segVel

		local velAlongNormal =
			relativeVel:Dot(normal)

		if velAlongNormal < 0 then
			local impulseMagnitude =
				-(1 + e)
				* velAlongNormal
				/ (
					1 / obj.mass
					+ 1 / segMass
				)

			local impulse =
				normal * impulseMagnitude

			obj.vel +=
				impulse / obj.mass

			seg.vel =
				segVel
				- impulse / segMass
		end
	end
end

----------------------------------------------------
-- CIRCLE VS CIRCLE
----------------------------------------------------

function PhysicsEngine.resolveCircleCollision(
	a: CircleObject,
	b: CircleObject
)
	if not canCollide(a, b) then
		return
	end

	if
		a.isSolid == false
		or b.isSolid == false
	then
		return
	end

	local delta =
		b.pos - a.pos

	local dist =
		delta.Magnitude

	local minDist =
		a.radius + b.radius

	if dist >= minDist then
		return
	end

	local normal

	if dist > 0.0001 then
		normal =
			delta / dist
	else
		normal =
			Vector2.new(1, 0)
	end

	local overlap =
		minDist - dist

	local aIsStatic =
		a.isStatic == true

	local bIsStatic =
		b.isStatic == true

	if aIsStatic and bIsStatic then
		return
	end

	local e =
		getCombinedRestitution(
			a,
			b
		)

	if aIsStatic then
		b.pos +=
			normal * overlap

		local velAlongNormal =
			b.vel:Dot(normal)

		if velAlongNormal < 0 then
			b.vel -=
				(1 + e)
				* velAlongNormal
				* normal
		end

		return
	end

	if bIsStatic then
		a.pos -=
			normal * overlap

		local velAlongNormal =
			a.vel:Dot(normal)

		if velAlongNormal > 0 then
			a.vel -=
				(1 + e)
				* velAlongNormal
				* normal
		end

		return
	end

	local totalMass =
		a.mass + b.mass

	a.pos -=
		normal
		* overlap
		* (b.mass / totalMass)

	b.pos +=
		normal
		* overlap
		* (a.mass / totalMass)

	local relativeVel =
		b.vel - a.vel

	local velAlongNormal =
		relativeVel:Dot(normal)

	if velAlongNormal < 0 then
		local impulseMagnitude =
			-(1 + e)
			* velAlongNormal
			/ (
				1 / a.mass
				+ 1 / b.mass
			)

		local impulse =
			normal * impulseMagnitude

		a.vel -=
			impulse / a.mass

		b.vel +=
			impulse / b.mass
	end
end

----------------------------------------------------
-- PLAYER / GEOMETRY ADAPTERS
----------------------------------------------------

local function playerAsCircle(
	player: PlayerObject
): CircleObject?
	if player.kind ~= "disc" then
		return nil
	end

	return player :: any
end

local function playerAsShape(
	player: PlayerObject
): PhysicalShape?
	if player.kind ~= "shape" then
		return nil
	end

	return player :: any
end

local function playerAsSegment(
	player: PlayerObject
): Segment?
	if player.kind ~= "segment" then
		return nil
	end

	return player :: any
end

----------------------------------------------------
-- PLAYER VS DISC
----------------------------------------------------

local function resolvePlayerVsDisc(
	player: PlayerObject,
	disc: CircleObject
)
	if player.kind == "disc" then
		PhysicsEngine.resolveCircleCollision(
			playerAsCircle(player) :: CircleObject,
			disc
		)

	elseif player.kind == "shape" then
		PhysicsEngine.resolveShapeCollision(
			disc,
			playerAsShape(player) :: PhysicalShape
		)

	elseif player.kind == "segment" then
		local segment =
			playerAsSegment(player) :: Segment

		PhysicsEngine.resolveSegmentCollision(
			disc,
			segment
		)
	end
end

----------------------------------------------------
-- PLAYER VS SHAPE
----------------------------------------------------

local function resolvePlayerVsShape(
	player: PlayerObject,
	shape: PhysicalShape
)
	if player.kind == "disc" then
		PhysicsEngine.resolveShapeCollision(
			playerAsCircle(player) :: CircleObject,
			shape
		)

	elseif player.kind == "shape" then
		PhysicsEngine.resolveShapeVsShapeCollision(
			playerAsShape(player) :: PhysicalShape,
			shape
		)

	elseif player.kind == "segment" then
		PhysicsEngine.resolveShapeVsSegmentCollision(
			shape,
			playerAsSegment(player) :: Segment
		)
	end
end

----------------------------------------------------
-- PLAYER VS SEGMENT
----------------------------------------------------

local function resolvePlayerVsSegment(
	player: PlayerObject,
	segment: Segment
)
	if player.kind == "disc" then
		PhysicsEngine.resolveSegmentCollision(
			playerAsCircle(player) :: CircleObject,
			segment
		)

	elseif player.kind == "shape" then
		PhysicsEngine.resolveShapeVsSegmentCollision(
			playerAsShape(player) :: PhysicalShape,
			segment
		)

	elseif player.kind == "segment" then
		local a1, a2, radA =
			getPlayerSegment(player)

		local b1 = segment.a
		local b2 = segment.b

		local radB =
			(segment.thickness or 0) * 0.5

		local pA, pB, dist =
			getClosestPointsBetweenSegments(
				a1,
				a2,
				b1,
				b2
			)

		local minDist =
			radA + radB

		if dist >= minDist then
			return
		end

		local delta =
			pA - pB

		local normal =
			dist > 0.0001
			and delta / dist
			or Vector2.new(0, 1)

		local overlap =
			minDist - dist

		local segmentIsStatic =
			segment.isStatic ~= false

		local e =
			getCombinedRestitution(
				player,
				segment
			)

		if not segmentIsStatic then
			local segmentVel =
				segment.vel or Vector2.zero

			local playerVel =
				player.vel

			local relativeVel =
				playerVel - segmentVel

			local velAlongNormal =
				relativeVel:Dot(normal)

			player.a -=
				normal
				* overlap
				* 0.5

			player.b -=
				normal
				* overlap
				* 0.5

			segment.a +=
				normal
				* overlap
				* 0.5

			segment.b +=
				normal
				* overlap
				* 0.5

			if velAlongNormal < 0 then
				local impulse =
					-(1 + e)
					* velAlongNormal

				player.vel +=
					normal
					* impulse
					* 0.5

				segment.vel =
					segmentVel
					- normal
					* impulse
					* 0.5
			end

		else
			player.a +=
				normal * overlap

			player.b +=
				normal * overlap

			local velAlongNormal =
				player.vel:Dot(normal)

			if velAlongNormal < 0 then
				player.vel -=
					(1 + e)
					* velAlongNormal
					* normal
			end
		end
	end
end

----------------------------------------------------
-- PLAYER VS PLAYER
----------------------------------------------------

local function resolvePlayerVsPlayer(
	a: PlayerObject,
	b: PlayerObject
)
	if not canCollide(a, b) then
		return
	end

	if
		a.isSolid == false
		or b.isSolid == false
	then
		return
	end

	if
		a.kind == "disc"
		and b.kind == "disc"
	then
		PhysicsEngine.resolveCircleCollision(
			a :: any,
			b :: any
		)

		return
	end

	if
		a.kind == "shape"
		and b.kind == "shape"
	then
		PhysicsEngine.resolveShapeVsShapeCollision(
			a :: any,
			b :: any
		)

		return
	end

	if
		a.kind == "shape"
		and b.kind == "disc"
	then
		PhysicsEngine.resolveShapeCollision(
			b :: any,
			a :: any
		)

		return
	end

	if
		a.kind == "disc"
		and b.kind == "shape"
	then
		PhysicsEngine.resolveShapeCollision(
			a :: any,
			b :: any
		)

		return
	end

	-- Segment player against shape/disc.
	if
		a.kind == "segment"
		and b.kind == "shape"
	then
		PhysicsEngine.resolveShapeVsSegmentCollision(
			b :: any,
			a :: any
		)

		return
	end

	if
		a.kind == "shape"
		and b.kind == "segment"
	then
		PhysicsEngine.resolveShapeVsSegmentCollision(
			a :: any,
			b :: any
		)

		return
	end

	if
		a.kind == "segment"
		and b.kind == "disc"
	then
		PhysicsEngine.resolveSegmentCollision(
			b :: any,
			a :: any
		)

		return
	end

	if
		a.kind == "disc"
		and b.kind == "segment"
	then
		PhysicsEngine.resolveSegmentCollision(
			a :: any,
			b :: any
		)

		return
	end

	-- Segment vs segment.
	local a1, a2, radA =
		getPlayerSegment(a)

	local b1, b2, radB =
		getPlayerSegment(b)

	local pA, pB, dist =
		getClosestPointsBetweenSegments(
			a1,
			a2,
			b1,
			b2
		)

	local minDist =
		radA + radB

	if dist >= minDist then
		return
	end

	local delta =
		pA - pB

	local normal =
		dist > 0.0001
		and delta / dist
		or Vector2.new(0, 1)

	local overlap =
		minDist - dist

	local aStatic =
		a.isStatic == true

	local bStatic =
		b.isStatic == true

	if aStatic and bStatic then
		return
	end

	if aStatic then
	b.a += normal * overlap
	b.b += normal * overlap

	local velAlongNormal =
		b.vel:Dot(normal)

	if velAlongNormal < 0 then
		local e =
			getCombinedRestitution(
				a,
				b
			)

		b.vel -=
			(1 + e)
			* velAlongNormal
			* normal
	end

	return
end

if bStatic then
	a.a -= normal * overlap
	a.b -= normal * overlap

	local velAlongNormal =
		a.vel:Dot(normal)

	if velAlongNormal > 0 then
		local e =
			getCombinedRestitution(
				a,
				b
			)

		a.vel -=
			(1 + e)
			* velAlongNormal
			* normal
	end

	return
end

	local totalMass =
		a.mass + b.mass

	a.a -=
		normal
		* overlap
		* (b.mass / totalMass)

	a.b -=
		normal
		* overlap
		* (b.mass / totalMass)

	b.a +=
		normal
		* overlap
		* (a.mass / totalMass)

	b.b +=
		normal
		* overlap
		* (a.mass / totalMass)

	local relativeVel =
	b.vel - a.vel

local velAlongNormal =
	relativeVel:Dot(normal)

if velAlongNormal < 0 then
	local e =
		getCombinedRestitution(
			a,
			b
		)

	local impulseMagnitude =
		-(1 + e)
		* velAlongNormal
		/ (
			1 / a.mass
			+ 1 / b.mass
		)

	local impulse =
		normal * impulseMagnitude

	a.vel -=
		impulse / a.mass

	b.vel +=
		impulse / b.mass
end
end

----------------------------------------------------
-- KICK
----------------------------------------------------

function PhysicsEngine.tryKick(
	pData: PlayerObject,
	kickableObjects: {any},
	kickPhys: any,
	currentTick: number
)
	local kickCooldownTicks =
		math.ceil(
			kickPhys.cooldown * 60
		)

	if
		currentTick
		- (pData.lastKickTick or -9999)
			< kickCooldownTicks
	then
		return
	end

	local playerCenter =
		getPlayerCenter(pData)

	local playerRadius =
		getPlayerBoundingRadius(pData)

	for _, object in ipairs(kickableObjects) do
		if
			object.isStatic ~= true
			and object.vel
		then
			local objectCenter: Vector2?
			local objectRadius: number?

			if
				object.pos
				and object.radius
			then
				objectCenter = object.pos
				objectRadius = object.radius
			elseif
				object.pos
				and object.size
			then
				objectCenter = object.pos
				objectRadius =
					math.sqrt(
						(object.size.X * 0.5) ^ 2
						+ (object.size.Y * 0.5) ^ 2
					)
			elseif
				object.a
				and object.b
			then
				objectCenter =
					(object.a + object.b) * 0.5

				objectRadius =
					(object.b - object.a).Magnitude
					* 0.5
					+ ((object.thickness or 0) * 0.5)
			end

			if
				objectCenter
				and objectRadius
			then
				local delta =
					objectCenter
				- playerCenter

				local dist =
					delta.Magnitude

				if dist <=
					playerRadius
					+ objectRadius
					+ kickPhys.rangeExtra
				then
					pData.lastKickTick =
						currentTick

					local kickDir =
						dist > 0
						and delta.Unit
						or Vector2.new(1, 0)

					object.vel +=
						kickDir * kickPhys.force
				end
			end
		end
	end
end

----------------------------------------------------
-- BROADPHASE UPDATES
----------------------------------------------------

local function updateDiscBroadphase(
	broadphase: Broadphase,
	disc: CircleObject
)
	local entry =
		broadphase.dynamicDiscEntries[disc]

	if entry then
		broadphase.dynamicDiscEntries[disc] =
			SpatialHash.update(
				broadphase.dynamicDiscGrid,
				entry,
				getCircleAABB(disc)
			)
	end
end

local function updateSegmentBroadphase(
	broadphase: Broadphase,
	segment: Segment
)
	local entry =
		broadphase.dynamicSegmentEntries[segment]

	if entry then
		broadphase.dynamicSegmentEntries[segment] =
			SpatialHash.update(
				broadphase.dynamicSegmentGrid,
				entry,
				getSegmentAABB(segment)
			)
	end
end

local function updateShapeBroadphase(
	broadphase: Broadphase,
	shape: PhysicalShape
)
	local entry =
		broadphase.dynamicShapeEntries[shape]

	if entry then
		broadphase.dynamicShapeEntries[shape] =
			SpatialHash.update(
				broadphase.dynamicShapeGrid,
				entry,
				getShapeAABB(shape)
			)
	end
end

local function updatePlayerBroadphase(
	broadphase: Broadphase,
	player: PlayerObject
)
	local entry =
		broadphase.playerEntries[player]

	if entry then
		broadphase.playerEntries[player] =
			SpatialHash.update(
				broadphase.playerGrid,
				entry,
				getPlayerAABB(player)
			)
	end
end

----------------------------------------------------
-- STEP
----------------------------------------------------

function PhysicsEngine.Step(
	playersData,
	sortedUserIds,
	discs,
	segments,
	shapes,
	collisionDiscs,
	collisionSegments,
	collisionShapes,
	broadphase,
	gameplay,
	kickableObjects,
	fixedDt,
	currentTick
)
	local playerPhys =
		gameplay.player.movement

	local kickPhys =
		gameplay.kick

	PhysicsEngine.rebuildPlayerBroadphase(
		broadphase,
		playersData,
		sortedUserIds
	)

	------------------------------------------------
	-- PLAYERS
	------------------------------------------------

	for _, userId in ipairs(sortedUserIds) do
		local pData =
			playersData[userId]

		if pData then
			local decelFactor =
				playerPhys.decelFactor
				or 0.88

			pData.vel *=
				decelFactor

			if
				pData.input
				and pData.input.Magnitude > 0
			then
				local mass =
					math.max(
						pData.mass,
						0.000001
					)

				local force =
					pData.input.Unit
					* (
						playerPhys.accel
						* mass
					)

				local acceleration =
					force / mass

				pData.vel +=
					acceleration * fixedDt
			end

			local friction =
				math.clamp(
					playerPhys.friction or 1,
					0,
					1
				)

			local frictionFactor =
				math.max(
					0,
					1 - friction * fixedDt
				)

			pData.vel *=
				frictionFactor

			if pData.kind == "disc" then
				pData.pos =
					(pData.pos :: Vector2)
					+ pData.vel * fixedDt

			elseif pData.kind == "shape" then
				pData.pos =
					(pData.pos :: Vector2)
					+ pData.vel * fixedDt

			elseif pData.kind == "segment" then
				local delta =
					pData.vel * fixedDt

				pData.a =
					(pData.a :: Vector2)
					+ delta

				pData.b =
					(pData.b :: Vector2)
					+ delta
			end

			if pData.isKicking then
				PhysicsEngine.tryKick(
					pData,
					kickableObjects,
					kickPhys,
					currentTick
				)
			end

			updatePlayerBroadphase(
				broadphase,
				pData
			)
		end
	end

	------------------------------------------------
	-- SEGMENTS
	------------------------------------------------

	for _, seg in ipairs(segments) do
		if seg.isStatic == false then
			seg.vel =
				(seg.vel or Vector2.zero)
				* (seg.damping or 0.98)

			seg.angularVelocity =
				(seg.angularVelocity or 0)
				* (seg.damping or 0.98)

			local delta =
				seg.vel * fixedDt

			seg.a += delta
			seg.b += delta

			integrateSegmentRotation(
				seg,
				fixedDt
			)
		end
	end

	------------------------------------------------
	-- SHAPES
	------------------------------------------------

	for _, shape in ipairs(shapes) do
		if shape.isStatic == false then
			local damping =
				shape.damping or 0.98

			shape.vel =
				(shape.vel or Vector2.zero)
				* damping

			shape.angularVelocity =
				(shape.angularVelocity or 0)
				* damping

			shape.pos +=
				shape.vel * fixedDt

			if shape.rotationLocked ~= true then
				shape.rotation =
					(shape.rotation or 0)
					+ (shape.angularVelocity or 0)
					* fixedDt

				PhysicsEngine.prepareShape(
					shape
				)
			end
		end
	end

	------------------------------------------------
	-- BROADPHASE
	------------------------------------------------

	PhysicsEngine.rebuildBroadphase(
		broadphase,
		collisionDiscs,
		collisionSegments,
		collisionShapes
	)

	------------------------------------------------
	-- DISCS
	------------------------------------------------

	for _, disc in ipairs(discs) do
		if disc.isStatic ~= true then
			local steps =
				math.clamp(
					math.ceil(
						disc.vel.Magnitude / 6
					),
					1,
					4
				)

			local subDt =
				fixedDt / steps

			local damping =
				disc.damping or 0.99

			local dampingFactor =
				math.pow(
					damping,
					1 / steps
				)

			for _ = 1, steps do
				disc.vel *=
					dampingFactor

				disc.pos +=
					disc.vel * subDt

				for _ = 1, 2 do
					local discAABB =
						getCircleAABB(disc)

					local nearbyDiscs =
						SpatialHash.queryCombined(
							broadphase.staticDiscGrid,
							broadphase.dynamicDiscGrid,
							discAABB
						)

					for _, entry in ipairs(nearbyDiscs) do
						local other =
							entry.object

						if other ~= disc then
							PhysicsEngine.resolveCircleCollision(
								disc,
								other
							)

							updateDiscBroadphase(
								broadphase,
								other
							)

							updateDiscBroadphase(
								broadphase,
								disc
							)
						end
					end

					discAABB =
						getCircleAABB(disc)

					local nearbySegments =
						SpatialHash.queryCombined(
							broadphase.staticSegmentGrid,
							broadphase.dynamicSegmentGrid,
							discAABB
						)

					for _, entry in ipairs(nearbySegments) do
						PhysicsEngine.resolveSegmentCollision(
							disc,
							entry.object
						)

						updateDiscBroadphase(
							broadphase,
							disc
						)
					end

					discAABB =
						getCircleAABB(disc)

					local nearbyShapes =
						SpatialHash.queryCombined(
							broadphase.staticShapeGrid,
							broadphase.dynamicShapeGrid,
							discAABB
						)

					for _, entry in ipairs(nearbyShapes) do
						local shape =
							entry.object

						PhysicsEngine.resolveShapeCollision(
							disc,
							shape
						)

						updateDiscBroadphase(
							broadphase,
							disc
						)

						updateShapeBroadphase(
							broadphase,
							shape
						)
					end
				end
			end
		end
	end

	------------------------------------------------
	-- SHAPES / SEGMENTS / PLAYERS
	------------------------------------------------

	for _ = 1, 2 do
		------------------------------------------------
		-- SHAPE VS SHAPE
		------------------------------------------------

		for idxA, shapeA in ipairs(collisionShapes) do
			local shapeAABB =
				getShapeAABB(shapeA)

			local nearbyShapes =
				SpatialHash.queryCombined(
					broadphase.staticShapeGrid,
					broadphase.dynamicShapeGrid,
					shapeAABB
				)

			for _, entry in ipairs(nearbyShapes) do
				local shapeB =
					entry.object

				local idxB =
					entry.index

				if idxB > idxA then
					PhysicsEngine.resolveShapeVsShapeCollision(
						shapeA,
						shapeB
					)

					updateShapeBroadphase(
						broadphase,
						shapeA
					)

					updateShapeBroadphase(
						broadphase,
						shapeB
					)
				end
			end
		end

		------------------------------------------------
		-- SHAPE VS SEGMENT
		------------------------------------------------

		for _, shape in ipairs(collisionShapes) do
			local shapeAABB =
				getShapeAABB(shape)

			local nearbySegments =
				SpatialHash.queryCombined(
					broadphase.staticSegmentGrid,
					broadphase.dynamicSegmentGrid,
					shapeAABB
				)

			for _, entry in ipairs(nearbySegments) do
				local segment =
					entry.object

				PhysicsEngine.resolveShapeVsSegmentCollision(
					shape,
					segment
				)

				updateShapeBroadphase(
					broadphase,
					shape
				)

				updateSegmentBroadphase(
					broadphase,
					segment
				)
			end
		end

		------------------------------------------------
		-- SHAPE VS DISC
		------------------------------------------------

		for _, shape in ipairs(collisionShapes) do
			local shapeAABB =
				getShapeAABB(shape)

			local nearbyDiscs =
				SpatialHash.queryCombined(
					broadphase.staticDiscGrid,
					broadphase.dynamicDiscGrid,
					shapeAABB
				)

			for _, entry in ipairs(nearbyDiscs) do
				local disc =
					entry.object

				PhysicsEngine.resolveShapeCollision(
					disc,
					shape
				)

				updateDiscBroadphase(
					broadphase,
					disc
				)

				updateShapeBroadphase(
					broadphase,
					shape
				)
			end
		end

		------------------------------------------------
		-- PLAYERS
		------------------------------------------------

		for idxA, userIdA in ipairs(sortedUserIds) do
			local pA =
				playersData[userIdA]

			if pA then
				local playerAABB =
					getPlayerAABB(pA)

				------------------------------------------------
				-- PLAYER VS DISC
				------------------------------------------------

				local nearbyDiscs =
					SpatialHash.queryCombined(
						broadphase.staticDiscGrid,
						broadphase.dynamicDiscGrid,
						playerAABB
					)

				for _, entry in ipairs(nearbyDiscs) do
					local disc =
						entry.object

					resolvePlayerVsDisc(
						pA,
						disc
					)

					updatePlayerBroadphase(
						broadphase,
						pA
					)

					updateDiscBroadphase(
						broadphase,
						disc
					)

					playerAABB =
						getPlayerAABB(pA)
				end

				------------------------------------------------
				-- PLAYER VS PLAYER
				------------------------------------------------

				local nearbyPlayers =
					SpatialHash.query(
						broadphase.playerGrid,
						playerAABB
					)

				for _, entry in ipairs(nearbyPlayers) do
					local pB =
						entry.object

					local idxB =
						entry.index

					if idxB > idxA then
						resolvePlayerVsPlayer(
							pA,
							pB
						)

						updatePlayerBroadphase(
							broadphase,
							pA
						)

						updatePlayerBroadphase(
							broadphase,
							pB
						)

						playerAABB =
							getPlayerAABB(pA)
					end
				end

				------------------------------------------------
				-- PLAYER VS SEGMENT
				------------------------------------------------

				local nearbySegments =
					SpatialHash.queryCombined(
						broadphase.staticSegmentGrid,
						broadphase.dynamicSegmentGrid,
						playerAABB
					)

				for _, entry in ipairs(nearbySegments) do
					resolvePlayerVsSegment(
						pA,
						entry.object
					)

					updatePlayerBroadphase(
						broadphase,
						pA
					)

					updateSegmentBroadphase(
						broadphase,
						entry.object
					)

					playerAABB =
						getPlayerAABB(pA)
				end

				------------------------------------------------
				-- PLAYER VS SHAPE
				------------------------------------------------

				local nearbyShapes =
					SpatialHash.queryCombined(
						broadphase.staticShapeGrid,
						broadphase.dynamicShapeGrid,
						playerAABB
					)

				for _, entry in ipairs(nearbyShapes) do
					local shape =
						entry.object

					resolvePlayerVsShape(
						pA,
						shape
					)

					updatePlayerBroadphase(
						broadphase,
						pA
					)

					updateShapeBroadphase(
						broadphase,
						shape
					)

					playerAABB =
						getPlayerAABB(pA)
				end
			end
		end

		------------------------------------------------
		-- DISC VS SEGMENT
		------------------------------------------------

		for _, disc in ipairs(discs) do
			if disc.isStatic == false then
				local discAABB =
					getCircleAABB(disc)

				local nearbySegments =
					SpatialHash.queryCombined(
						broadphase.staticSegmentGrid,
						broadphase.dynamicSegmentGrid,
						discAABB
					)

				for _, entry in ipairs(nearbySegments) do
					PhysicsEngine.resolveSegmentCollision(
						disc,
						entry.object
					)

					updateDiscBroadphase(
						broadphase,
						disc
					)

					discAABB =
						getCircleAABB(disc)
				end
			end
		end
	end
end

return PhysicsEngine
