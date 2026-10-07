--!strict
local PhysicsEngine = {}

local SpatialHash = require(script.Parent.SpatialHash)

local DEFAULT_MASK = 0xFFFFFFFF

export type Object = {
	id: string?,
	pos: Vector2,
	vel: Vector2,

	size: Vector2,
	rotation: number?,
	rotationLocked: boolean?,
	angularVelocity: number?,
	cornerRadius: number?,

	mass: number,
	restitution: number,
	isStatic: boolean?,
	isSolid: boolean?,
	damping: number?,
	resettable: boolean?,

	team: string?,
	input: Vector2?,
	isKicking: boolean?,
	lastKickTick: number?,

	cGroup: number?,
	cMask: number?,

	-- Geometria derivada para a física.
	segmentP1: Vector2?,
	segmentP2: Vector2?,
	segmentRadius: number?
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

export type PlayerObject = {
	id: string?,

	-- O jogador usa a mesma geometria de Object ou Segment.
	kind: "object" | "segment",

	pos: Vector2?,
	vel: Vector2,

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
	staticObjectGrid: SpatialHash.Grid,
	staticSegmentGrid: SpatialHash.Grid,

	dynamicObjectGrid: SpatialHash.Grid,
	dynamicSegmentGrid: SpatialHash.Grid,

	playerGrid: SpatialHash.Grid,

	objectIndex: {[any]: number},
	segmentIndex: {[any]: number},
	playerIndex: {[any]: number},

	dynamicObjectEntries: {[any]: SpatialHash.Entry},
	dynamicSegmentEntries: {[any]: SpatialHash.Entry},

	playerEntries: {[any]: SpatialHash.Entry},
}

----------------------------------------------------
-- GEOMETRY
----------------------------------------------------

local function getObjectAABB(object: Object): SpatialHash.AABB
	local p1 = object.pos + (object.segmentP1 :: Vector2)
	local p2 = object.pos + (object.segmentP2 :: Vector2)
	local radius = object.segmentRadius :: number

	return {
		minX = math.min(p1.X, p2.X) - radius,
		minY = math.min(p1.Y, p2.Y) - radius,
		maxX = math.max(p1.X, p2.X) + radius,
		maxY = math.max(p1.Y, p2.Y) + radius,
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

local function getPlayerAABB(player: PlayerObject): SpatialHash.AABB
	if player.kind == "object" then
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
	if player.kind == "object" then
		return player.pos :: Vector2
	end

	return ((player.a :: Vector2) + (player.b :: Vector2)) * 0.5
end

local function getObjectBoundingRadius(object: Object): number
	local size = object.size

	return math.sqrt(
		(size.X * 0.5) ^ 2
			+ (size.Y * 0.5) ^ 2
	)
end

local function getPlayerBoundingRadius(player: PlayerObject): number
	if player.kind == "object" then
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
	if player.kind == "object" then
		local pos = player.pos :: Vector2

		return
			pos + (player.segmentP1 :: Vector2),
			pos + (player.segmentP2 :: Vector2),
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
	collisionObjects: {Object},
	collisionSegments: {Segment},
	cellSize: number
): Broadphase

	local broadphase: Broadphase = {
		staticObjectGrid = SpatialHash.new(cellSize),
		staticSegmentGrid = SpatialHash.new(cellSize),

		dynamicObjectGrid = SpatialHash.new(cellSize),
		dynamicSegmentGrid = SpatialHash.new(cellSize),

		playerGrid = SpatialHash.new(cellSize),

		objectIndex = {},
		segmentIndex = {},
		playerIndex = {},

		dynamicObjectEntries = {},
		dynamicSegmentEntries = {},

		playerEntries = {},
	}

	for index, object in ipairs(collisionObjects) do
		broadphase.objectIndex[object] = index

		local grid =
			object.isStatic
			and broadphase.staticObjectGrid
			or broadphase.dynamicObjectGrid

		local entry = SpatialHash.insert(
			grid,
			object,
			getObjectAABB(object),
			index
		)

		if object.isStatic ~= true then
			broadphase.dynamicObjectEntries[object] = entry
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

	return broadphase
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
	angularVelocity: number,
	r: Vector2
): Vector2
	local omega =
		math.rad(angularVelocity)

	return Vector2.new(
		-omega * r.Y,
		omega * r.X
	)
end

local function getObjectInertia(
	object: Object
): number
	local mass =
		math.max(
			object.mass,
			0.000001
		)

	local width = object.size.X
	local height = object.size.Y

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

	if object.size ~= nil then
		inertia =
			getObjectInertia(
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

	local angularDeltaRadians =
		crossScalar(
			contactVector,
			impulse
		) * inverseInertia

	object.angularVelocity =
		getAngularVelocity(object)
		+ math.deg(
			angularDeltaRadians
		)
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
-- OBJECT PREPARATION
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

local function integrateSegmentRotation(
	segment: Segment,
	fixedDt: number
)
	if segment.rotationLocked == true then
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
		angularVelocity * fixedDt

	segment.a =
		center
		+ rotateVector(
			segment.a - center,
			angle
		)

	segment.b =
		center
		+ rotateVector(
			segment.b - center,
			angle
		)
end

function PhysicsEngine.prepareObject(
	object: Object
)
	local w = object.size.X
	local h = object.size.Y

	-- Mantém a mesma representação geométrica usada
	-- anteriormente pelos PhysicalShape:
	-- um segmento central com um raio nas extremidades.
	local radius =
		math.min(w, h) / 2

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
		object.rotation or 0

	object.segmentP1 =
		rotateVector(
			p1Local,
			rotation
		)

	object.segmentP2 =
		rotateVector(
			p2Local,
			rotation
		)

	object.segmentRadius =
		radius
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

local function getObjectSegment(
	object: Object
): (Vector2, Vector2, number)
	return
		object.pos + (object.segmentP1 :: Vector2),
		object.pos + (object.segmentP2 :: Vector2),
		object.segmentRadius :: number
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

	local delta =
		bestB - bestA

	local minDistSq =
		delta:Dot(delta)

	local pA = a2

	local pB =
		closestPointOnSegment(
			a2,
			b1,
			b2
		)

	delta =
		pB - pA

	local distSq =
		delta:Dot(delta)

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

	delta =
		pB - pA

	distSq =
		delta:Dot(delta)

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

	delta =
		pB - pA

	distSq =
		delta:Dot(delta)

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
-- OBJECT GEOMETRY
----------------------------------------------------

local function getObjectRadius(
	object: Object
): number
	local size = object.size

	return math.sqrt(
		(size.X * 0.5) ^ 2
			+ (size.Y * 0.5) ^ 2
	)
end

local function getObjectCollisionSegment(
	object: Object
): (Vector2, Vector2, number)
	return getObjectSegment(object)
end

----------------------------------------------------
-- PLAYER GEOMETRY ADAPTER
----------------------------------------------------

local function getPlayerCollisionGeometry(
	player: PlayerObject
): (Vector2, Vector2, number)
	return getPlayerSegment(player)
end

----------------------------------------------------
-- OBJECT VS OBJECT
----------------------------------------------------

function PhysicsEngine.resolveShapeCollision(
	obj: Object,
	object: Object
)
	if not canCollide(obj, object) then
		return
	end

	if
		obj.isSolid == false
		or object.isSolid == false
	then
		return
	end

	local objIsStatic =
		obj.isStatic == true

	local objectIsStatic =
		object.isStatic ~= false

	if objIsStatic and objectIsStatic then
		return
	end

	local object1, object2, objectRadius =
		getObjectCollisionSegment(object)

	local closestOnSegment =
		closestPointOnSegment(
			obj.pos,
			object1,
			object2
		)

	local delta =
		obj.pos - closestOnSegment

	local dist =
		delta.Magnitude

	local minDist =
		getObjectRadius(obj)
		+ objectRadius

	if dist >= minDist then
		return
	end

	local normal =
		dist > 0.0001
		and delta / dist
		or Vector2.new(0, 1)

	local overlap =
		minDist - dist

	local objInverseMass =
		objIsStatic
		and 0
		or 1 / obj.mass

	local objectInverseMass =
		objectIsStatic
		and 0
		or 1 / object.mass

	local totalInverseMass =
		objInverseMass
		+ objectInverseMass

	if totalInverseMass <= 0 then
		return
	end

	------------------------------------------------
	-- POSITION CORRECTION
	------------------------------------------------

	obj.pos +=
		normal
		* overlap
		* (
			objInverseMass
			/ totalInverseMass
		)

	object.pos -=
		normal
		* overlap
		* (
			objectInverseMass
			/ totalInverseMass
		)

	------------------------------------------------
	-- CONTACT POINT
	------------------------------------------------

	local contactPoint =
		obj.pos
		- normal * getObjectRadius(obj)

	local rObj =
		contactPoint - obj.pos

	local rObject =
		contactPoint - object.pos

	------------------------------------------------
	-- RELATIVE CONTACT VELOCITY
	------------------------------------------------

	local objContactVelocity =
		getContactVelocity(
			obj,
			rObj
		)

	local objectContactVelocity =
		getContactVelocity(
			object,
			rObject
		)

	local relativeVelocity =
		objContactVelocity
		- objectContactVelocity

	local velAlongNormal =
		relativeVelocity:Dot(normal)

	if velAlongNormal >= 0 then
		return
	end

	local e =
		getCombinedRestitution(
			obj,
			object
		)

	------------------------------------------------
	-- ROTATIONAL TERMS
	------------------------------------------------

	local objInverseInertia =
		getInverseInertia(obj)

	local objectInverseInertia =
		getInverseInertia(object)

	local rotationalObj =
		crossScalar(
			rObj,
			normal
		)

	local rotationalObject =
		crossScalar(
			rObject,
			normal
		)

	local denominator =
		totalInverseMass
		+ rotationalObj
			* rotationalObj
			* objInverseInertia
		+ rotationalObject
			* rotationalObject
			* objectInverseInertia

	if denominator <= 0 then
		return
	end

	local impulseMagnitude =
		-(1 + e)
		* velAlongNormal
		/ denominator

	local impulse =
		normal * impulseMagnitude

	------------------------------------------------
	-- LINEAR VELOCITY
	------------------------------------------------

	if not objIsStatic then
		obj.vel +=
			impulse * objInverseMass
	end

	if not objectIsStatic then
		object.vel -=
			impulse * objectInverseMass
	end

	------------------------------------------------
	-- ANGULAR VELOCITY
	------------------------------------------------

	applyAngularImpulse(
		obj,
		rObj,
		impulse
	)

	applyAngularImpulse(
		object,
		rObject,
		-impulse
	)
end

----------------------------------------------------
-- OBJECT VS OBJECT
----------------------------------------------------

function PhysicsEngine.resolveShapeVsShapeCollision(
	a: Object,
	b: Object
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

	local aIsStatic =
		a.isStatic ~= false

	local bIsStatic =
		b.isStatic ~= false

	if aIsStatic and bIsStatic then
		return
	end

	local a1, a2, radA =
		getObjectCollisionSegment(a)

	local b1, b2, radB =
		getObjectCollisionSegment(b)

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

	local inverseMassA =
		aIsStatic
		and 0
		or 1 / a.mass

	local inverseMassB =
		bIsStatic
		and 0
		or 1 / b.mass

	local totalInverseMass =
		inverseMassA
		+ inverseMassB

	if totalInverseMass <= 0 then
		return
	end

	------------------------------------------------
	-- POSITION CORRECTION
	------------------------------------------------

	a.pos -=
		normal
		* overlap
		* (
			inverseMassA
			/ totalInverseMass
		)

	b.pos +=
		normal
		* overlap
		* (
			inverseMassB
			/ totalInverseMass
		)

	------------------------------------------------
	-- CONTACT POINTS
	------------------------------------------------

	local contactPoint =
		(pA + pB) * 0.5

	local rA =
		contactPoint - a.pos

	local rB =
		contactPoint - b.pos

	local velocityA =
		getContactVelocity(
			a,
			rA
		)

	local velocityB =
		getContactVelocity(
			b,
			rB
		)

	local relativeVelocity =
		velocityB - velocityA

	local velAlongNormal =
		relativeVelocity:Dot(normal)

	if velAlongNormal >= 0 then
		return
	end

	local e =
		getCombinedRestitution(
			a,
			b
		)

	local inverseInertiaA =
		getInverseInertia(a)

	local inverseInertiaB =
		getInverseInertia(b)

	local rotationalA =
		crossScalar(
			rA,
			normal
		)

	local rotationalB =
		crossScalar(
			rB,
			normal
		)

	local denominator =
		totalInverseMass
		+ rotationalA
			* rotationalA
			* inverseInertiaA
		+ rotationalB
			* rotationalB
			* inverseInertiaB

	if denominator <= 0 then
		return
	end

	local impulseMagnitude =
		-(1 + e)
		* velAlongNormal
		/ denominator

	local impulse =
		normal * impulseMagnitude

	if not aIsStatic then
		a.vel =
			(a.vel or Vector2.zero)
			- impulse * inverseMassA
	end

	if not bIsStatic then
		b.vel =
			(b.vel or Vector2.zero)
			+ impulse * inverseMassB
	end

	applyAngularImpulse(
		a,
		rA,
		-impulse
	)

	applyAngularImpulse(
		b,
		rB,
		impulse
	)
end

----------------------------------------------------
-- OBJECT VS SEGMENT
----------------------------------------------------

function PhysicsEngine.resolveShapeVsSegmentCollision(
	object: Object,
	seg: Segment
)
	if not canCollide(object, seg) then
		return
	end

	if
		object.isSolid == false
		or seg.isSolid == false
	then
		return
	end

	local object1, object2, objectRad =
		getObjectCollisionSegment(object)

	local segRad =
		(seg.thickness or 2) * 0.5

	local pObject, pSeg, dist =
		getClosestPointsBetweenSegments(
			object1,
			object2,
			seg.a,
			seg.b
		)

	local minDist =
		objectRad + segRad

	if dist >= minDist then
		return
	end

	local delta =
		pObject - pSeg

	local normal =
		dist > 0.0001
		and delta / dist
		or Vector2.new(0, 1)

	local overlap =
		minDist - dist

	local objectIsStatic =
		object.isStatic ~= false

	local segIsStatic =
		seg.isStatic ~= false

	local objectVel =
		object.vel or Vector2.zero

	local segVel =
		seg.vel or Vector2.zero

	local objectMass =
		object.mass or 1

	local segMass =
		seg.mass or 1

	local inverseMassObject =
		objectIsStatic
		and 0
		or 1 / objectMass

	local inverseMassSeg =
		segIsStatic
		and 0
		or 1 / segMass

	local totalInverseMass =
		inverseMassObject
		+ inverseMassSeg

	if totalInverseMass <= 0 then
		return
	end

	local e =
		getCombinedRestitution(
			object,
			seg
		)

	------------------------------------------------
	-- POSITION CORRECTION
	------------------------------------------------

	if not objectIsStatic then
		object.pos +=
			normal
			* overlap
			* (
				inverseMassObject
				/ totalInverseMass
			)
	end

	if not segIsStatic then
		local correction =
			normal
			* overlap
			* (
				inverseMassSeg
				/ totalInverseMass
			)

		seg.a -= correction
		seg.b -= correction
	end

	------------------------------------------------
	-- CONTACT POINTS
	------------------------------------------------

	local contactPoint =
		(pObject + pSeg) * 0.5

	local rObject =
		contactPoint - object.pos

	local segmentCenter =
		(seg.a + seg.b) * 0.5

	local rSeg =
		contactPoint - segmentCenter

	local objectContactVelocity =
		getContactVelocity(
			object,
			rObject
		)

	local segmentContactVelocity =
		getContactVelocity(
			seg,
			rSeg
		)

	local relativeVelocity =
		objectContactVelocity
		- segmentContactVelocity

	local velAlongNormal =
		relativeVelocity:Dot(normal)

	if velAlongNormal >= 0 then
		return
	end

	local inverseInertiaObject =
		getInverseInertia(object)

	local inverseInertiaSeg =
		getInverseInertia(seg)

	local rotationalObject =
		crossScalar(
			rObject,
			normal
		)

	local rotationalSeg =
		crossScalar(
			rSeg,
			normal
		)

	local denominator =
		totalInverseMass
		+ rotationalObject
			* rotationalObject
			* inverseInertiaObject
		+ rotationalSeg
			* rotationalSeg
			* inverseInertiaSeg

	if denominator <= 0 then
		return
	end

	local impulseMagnitude =
		-(1 + e)
		* velAlongNormal
		/ denominator

	local impulse =
		normal * impulseMagnitude

	if not objectIsStatic then
		object.vel =
			objectVel
			+ impulse * inverseMassObject
	end

	if not segIsStatic then
		seg.vel =
			segVel
			- impulse * inverseMassSeg
	end

	applyAngularImpulse(
		object,
		rObject,
		impulse
	)

	applyAngularImpulse(
		seg,
		rSeg,
		-impulse
	)
end

----------------------------------------------------
-- OBJECT VS SEGMENT
----------------------------------------------------

function PhysicsEngine.resolveSegmentCollision(
	object: Object,
	seg: Segment
)
	if not canCollide(object, seg) then
		return
	end

	if
		seg.isSolid == false
		or object.isSolid == false
	then
		return
	end

	local ab =
		seg.b - seg.a

	local ap =
		object.pos - seg.a

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
		object.pos - closest

	local dist =
		delta.Magnitude

	local segRadius =
		(seg.thickness or 0) * 0.5

	local objectRadius =
		getObjectRadius(object)

	local minDist =
		objectRadius + segRadius

	if dist >= minDist then
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
		minDist - dist

	local segVel =
		seg.vel or Vector2.zero

	local segIsStatic =
		seg.isStatic ~= false

	local objectIsStatic =
		object.isStatic == true

	local objectMass =
		math.max(
			object.mass,
			0.000001
		)

	local segMass =
		math.max(
			seg.mass or 1,
			0.000001
		)

	local inverseMassObject =
		objectIsStatic
		and 0
		or 1 / objectMass

	local inverseMassSeg =
		segIsStatic
		and 0
		or 1 / segMass

	local totalInverseMass =
		inverseMassObject
		+ inverseMassSeg

	if totalInverseMass <= 0 then
		return
	end

	local e =
		getCombinedRestitution(
			object,
			seg
		)

	------------------------------------------------
	-- POSITION CORRECTION
	------------------------------------------------

	if not objectIsStatic then
		object.pos +=
			normal
			* overlap
			* (
				inverseMassObject
				/ totalInverseMass
			)
	end

	if not segIsStatic then
		local correction =
			normal
			* overlap
			* (
				inverseMassSeg
				/ totalInverseMass
			)

		seg.a -= correction
		seg.b -= correction
	end

	------------------------------------------------
	-- CONTACT POINTS
	------------------------------------------------

	local contactPoint =
		closest
		+ normal * segRadius

	local rObject =
		contactPoint - object.pos

	local segmentCenter =
		(seg.a + seg.b) * 0.5

	local rSeg =
		contactPoint - segmentCenter

	local objectContactVelocity =
		getContactVelocity(
			object,
			rObject
		)

	local segContactVelocity =
		getContactVelocity(
			seg,
			rSeg
		)

	local relativeVelocity =
		objectContactVelocity
		- segContactVelocity

	local velAlongNormal =
		relativeVelocity:Dot(normal)

	if velAlongNormal >= 0 then
		return
	end

	local inverseInertiaObject =
		getInverseInertia(object)

	local inverseInertiaSeg =
		getInverseInertia(seg)

	local rotationalObject =
		crossScalar(
			rObject,
			normal
		)

	local rotationalSeg =
		crossScalar(
			rSeg,
			normal
		)

	local denominator =
		totalInverseMass
		+ rotationalObject
			* rotationalObject
			* inverseInertiaObject
		+ rotationalSeg
			* rotationalSeg
			* inverseInertiaSeg

	if denominator <= 0 then
		return
	end

	local impulseMagnitude =
		-(1 + e)
		* velAlongNormal
		/ denominator

	local impulse =
		normal * impulseMagnitude

	if not objectIsStatic then
		object.vel =
			(object.vel or Vector2.zero)
			+ impulse * inverseMassObject
	end

	if not segIsStatic then
		seg.vel =
			segVel
			- impulse * inverseMassSeg
	end

	applyAngularImpulse(
		object,
		rObject,
		impulse
	)

	applyAngularImpulse(
		seg,
		rSeg,
		-impulse
	)
end

----------------------------------------------------
-- OBJECT VS OBJECT (CIRCLE SPECIAL CASE)
----------------------------------------------------

local function resolveCircleCollision(
	a: Object,
	b: Object
)
	if
		a.isStatic == true
		and b.isStatic == true
	then
		return
	end

	local delta =
		b.pos - a.pos

	local dist =
		delta.Magnitude

	local radiusA =
		getObjectRadius(a)

	local radiusB =
		getObjectRadius(b)

	local minDist =
		radiusA + radiusB

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

	local e =
		getCombinedRestitution(
			a,
			b
		)

	local aInverseMass =
		aIsStatic
		and 0
		or 1 / a.mass

	local bInverseMass =
		bIsStatic
		and 0
		or 1 / b.mass

	local totalInverseMass =
		aInverseMass
		+ bInverseMass

	if totalInverseMass <= 0 then
		return
	end

	------------------------------------------------
	-- POSITION CORRECTION
	------------------------------------------------

	a.pos -=
		normal
		* overlap
		* (
			aInverseMass
			/ totalInverseMass
		)

	b.pos +=
		normal
		* overlap
		* (
			bInverseMass
			/ totalInverseMass
		)

	------------------------------------------------
	-- CONTACT POINTS
	------------------------------------------------

	local contactPoint =
		a.pos
		+ normal * radiusA

	local rA =
		contactPoint - a.pos

	local rB =
		contactPoint - b.pos

	local velocityA =
		getContactVelocity(
			a,
			rA
		)

	local velocityB =
		getContactVelocity(
			b,
			rB
		)

	local relativeVelocity =
		velocityB - velocityA

	local velAlongNormal =
		relativeVelocity:Dot(normal)

	if velAlongNormal >= 0 then
		return
	end

	local inverseInertiaA =
		getInverseInertia(a)

	local inverseInertiaB =
		getInverseInertia(b)

	local rotationalA =
		crossScalar(
			rA,
			normal
		)

	local rotationalB =
		crossScalar(
			rB,
			normal
		)

	local denominator =
		totalInverseMass
		+ rotationalA
			* rotationalA
			* inverseInertiaA
		+ rotationalB
			* rotationalB
			* inverseInertiaB

	if denominator <= 0 then
		return
	end

	local impulseMagnitude =
		-(1 + e)
		* velAlongNormal
		/ denominator

	local impulse =
		normal * impulseMagnitude

	if not aIsStatic then
		a.vel -=
			impulse * aInverseMass
	end

	if not bIsStatic then
		b.vel +=
			impulse * bInverseMass
	end

	applyAngularImpulse(
		a,
		rA,
		-impulse
	)

	applyAngularImpulse(
		b,
		rB,
		impulse
	)
end

----------------------------------------------------
-- PLAYER / GEOMETRY ADAPTERS
----------------------------------------------------

local function playerAsObject(
	player: PlayerObject
): Object?
	if player.kind ~= "object" then
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
-- PLAYER VS OBJECT
----------------------------------------------------

local function resolvePlayerVsObject(
	player: PlayerObject,
	object: Object
)
	if player.kind == "object" then
		PhysicsEngine.resolveShapeVsShapeCollision(
			playerAsObject(player) :: Object,
			object
		)

	elseif player.kind == "segment" then
		PhysicsEngine.resolveShapeVsSegmentCollision(
			object,
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
	if player.kind == "object" then
		PhysicsEngine.resolveShapeVsSegmentCollision(
			playerAsObject(player) :: Object,
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

		local playerIsStatic =
			player.isStatic == true

		local segmentIsStatic =
			segment.isStatic ~= false

		if playerIsStatic and segmentIsStatic then
			return
		end

		local playerMass =
			math.max(
				player.mass or 1,
				0.000001
			)

		local segmentMass =
			math.max(
				segment.mass or 1,
				0.000001
			)

		local inverseMassPlayer =
			playerIsStatic
			and 0
			or 1 / playerMass

		local inverseMassSegment =
			segmentIsStatic
			and 0
			or 1 / segmentMass

		local totalInverseMass =
			inverseMassPlayer
			+ inverseMassSegment

		if totalInverseMass <= 0 then
			return
		end

		------------------------------------------------
		-- POSITION CORRECTION
		------------------------------------------------

		if not playerIsStatic then
			local correction =
				normal
				* overlap
				* (
					inverseMassPlayer
					/ totalInverseMass
				)

			player.a += correction
			player.b += correction
		end

		if not segmentIsStatic then
			local correction =
				normal
				* overlap
				* (
					inverseMassSegment
					/ totalInverseMass
				)

			segment.a -= correction
			segment.b -= correction
		end

		------------------------------------------------
		-- CONTACT POINTS
		------------------------------------------------

		local contactPoint =
			(pA + pB) * 0.5

		local playerCenter =
			(player.a + player.b) * 0.5

		local segmentCenter =
			(segment.a + segment.b) * 0.5

		local rPlayer =
			contactPoint - playerCenter

		local rSegment =
			contactPoint - segmentCenter

		------------------------------------------------
		-- RELATIVE CONTACT VELOCITY
		------------------------------------------------

		local playerContactVelocity =
			getContactVelocity(
				player,
				rPlayer
			)

		local segmentContactVelocity =
			getContactVelocity(
				segment,
				rSegment
			)

		local relativeVelocity =
			playerContactVelocity
			- segmentContactVelocity

		local velAlongNormal =
			relativeVelocity:Dot(normal)

		if velAlongNormal >= 0 then
			return
		end

		local e =
			getCombinedRestitution(
				player,
				segment
			)

		------------------------------------------------
		-- ROTATIONAL TERMS
		------------------------------------------------

		local inverseInertiaPlayer =
			getInverseInertia(player)

		local inverseInertiaSegment =
			getInverseInertia(segment)

		local rotationalPlayer =
			crossScalar(
				rPlayer,
				normal
			)

		local rotationalSegment =
			crossScalar(
				rSegment,
				normal
			)

		local denominator =
			totalInverseMass
			+ rotationalPlayer
				* rotationalPlayer
				* inverseInertiaPlayer
			+ rotationalSegment
				* rotationalSegment
				* inverseInertiaSegment

		if denominator <= 0 then
			return
		end

		------------------------------------------------
		-- IMPULSE
		------------------------------------------------

		local impulseMagnitude =
			-(1 + e)
			* velAlongNormal
			/ denominator

		local impulse =
			normal * impulseMagnitude

		------------------------------------------------
		-- LINEAR VELOCITY
		------------------------------------------------

		if not playerIsStatic then
			player.vel =
				(player.vel or Vector2.zero)
				+ impulse * inverseMassPlayer
		end

		if not segmentIsStatic then
			segment.vel =
				(segment.vel or Vector2.zero)
				- impulse * inverseMassSegment
		end

		------------------------------------------------
		-- ANGULAR VELOCITY
		------------------------------------------------

		applyAngularImpulse(
			player,
			rPlayer,
			impulse
		)

		applyAngularImpulse(
			segment,
			rSegment,
			-impulse
		)
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

	------------------------------------------------
	-- OBJECT × OBJECT
	------------------------------------------------

	if
		a.kind == "object"
		and b.kind == "object"
	then
		PhysicsEngine.resolveShapeVsShapeCollision(
			a :: any,
			b :: any
		)

		return
	end

	------------------------------------------------
	-- OBJECT × SEGMENT
	------------------------------------------------

	if
		a.kind == "object"
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
		and b.kind == "object"
	then
		PhysicsEngine.resolveShapeVsSegmentCollision(
			b :: any,
			a :: any
		)

		return
	end

	------------------------------------------------
	-- SEGMENT × SEGMENT
	------------------------------------------------

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

	local aIsStatic =
		a.isStatic == true

	local bIsStatic =
		b.isStatic == true

	if aIsStatic and bIsStatic then
		return
	end

	local massA =
		math.max(
			a.mass or 1,
			0.000001
		)

	local massB =
		math.max(
			b.mass or 1,
			0.000001
		)

	local inverseMassA =
		aIsStatic
		and 0
		or 1 / massA

	local inverseMassB =
		bIsStatic
		and 0
		or 1 / massB

	local totalInverseMass =
		inverseMassA
		+ inverseMassB

	if totalInverseMass <= 0 then
		return
	end

	------------------------------------------------
	-- POSITION CORRECTION
	------------------------------------------------

	if not aIsStatic then
		local correction =
			normal
			* overlap
			* (
				inverseMassA
				/ totalInverseMass
			)

		a.a -= correction
		a.b -= correction
	end

	if not bIsStatic then
		local correction =
			normal
			* overlap
			* (
				inverseMassB
				/ totalInverseMass
			)

		b.a += correction
		b.b += correction
	end

	------------------------------------------------
	-- CONTACT POINTS
	------------------------------------------------

	local contactPoint =
		(pA + pB) * 0.5

	local centerA =
		(a.a + a.b) * 0.5

	local centerB =
		(b.a + b.b) * 0.5

	local rA =
		contactPoint - centerA

	local rB =
		contactPoint - centerB

	------------------------------------------------
	-- RELATIVE CONTACT VELOCITY
	------------------------------------------------

	local velocityA =
		getContactVelocity(
			a,
			rA
		)

	local velocityB =
		getContactVelocity(
			b,
			rB
		)

	local relativeVelocity =
		velocityB - velocityA

	local velAlongNormal =
		relativeVelocity:Dot(normal)

	if velAlongNormal >= 0 then
		return
	end

	local e =
		getCombinedRestitution(
			a,
			b
		)

	------------------------------------------------
	-- ROTATIONAL TERMS
	------------------------------------------------

	local inverseInertiaA =
		getInverseInertia(a)

	local inverseInertiaB =
		getInverseInertia(b)

	local rotationalA =
		crossScalar(
			rA,
			normal
		)

	local rotationalB =
		crossScalar(
			rB,
			normal
		)

	local denominator =
		totalInverseMass
		+ rotationalA
			* rotationalA
			* inverseInertiaA
		+ rotationalB
			* rotationalB
			* inverseInertiaB

	if denominator <= 0 then
		return
	end

	------------------------------------------------
	-- IMPULSE
	------------------------------------------------

	local impulseMagnitude =
		-(1 + e)
		* velAlongNormal
		/ denominator

	local impulse =
		normal * impulseMagnitude

	------------------------------------------------
	-- LINEAR VELOCITY
	------------------------------------------------

	if not aIsStatic then
		a.vel =
			(a.vel or Vector2.zero)
			- impulse * inverseMassA
	end

	if not bIsStatic then
		b.vel =
			(b.vel or Vector2.zero)
			+ impulse * inverseMassB
	end

	------------------------------------------------
	-- ANGULAR VELOCITY
	------------------------------------------------

	applyAngularImpulse(
		a,
		rA,
		-impulse
	)

	applyAngularImpulse(
		b,
		rB,
		impulse
	)
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

			if object.pos and object.size then
				objectCenter =
					object.pos

				objectRadius =
					getObjectRadius(
						object
					)

			elseif object.a and object.b then
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

				if
					dist <=
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
						kickDir
						* kickPhys.force
				end
			end
		end
	end
end

----------------------------------------------------
-- BROADPHASE UPDATES
----------------------------------------------------

local function updateObjectBroadphase(
	broadphase: Broadphase,
	object: Object
)
	local entry =
		broadphase.dynamicObjectEntries[object]

	if entry then
		broadphase.dynamicObjectEntries[object] =
			SpatialHash.update(
				broadphase.dynamicObjectGrid,
				entry,
				getObjectAABB(object)
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
	objects,
	segments,
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

			if pData.kind == "object" then
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

	for _, segment in ipairs(segments) do
		if segment.isStatic == false then
			local damping =
				segment.damping or 0.98

			segment.vel =
				(segment.vel or Vector2.zero)
				* damping

			segment.angularVelocity =
				(segment.angularVelocity or 0)
				* damping

			local delta =
				segment.vel * fixedDt

			segment.a += delta
			segment.b += delta

			integrateSegmentRotation(
				segment,
				fixedDt
			)

			updateSegmentBroadphase(
				broadphase,
				segment
			)
		end
	end

	------------------------------------------------
	-- FIXED SUBSTEPS
	------------------------------------------------

	-- Mantém o custo do solver estável.
	--
	-- Antes, a quantidade de substeps dependia
	-- da velocidade máxima dos objetos e podia
	-- variar entre 1 e 4 durante a partida.
	--
	-- Agora cada tick possui sempre exatamente
	-- 2 substeps.
	local steps = 2

	local subDt =
		fixedDt / steps

	------------------------------------------------
	-- SIMULATION SUBSTEPS
	------------------------------------------------

	for _ = 1, steps do

		------------------------------------------------
		-- OBJECT INTEGRATION
		------------------------------------------------

		for _, object in ipairs(objects) do
			if object.isStatic ~= true then
				local damping =
					object.damping or 0.98

				local dampingFactor =
					math.pow(
						damping,
						1 / steps
					)

				object.vel *=
					dampingFactor

				object.pos +=
					object.vel * subDt

				object.angularVelocity =
					(object.angularVelocity or 0)
					* dampingFactor

				if object.rotationLocked ~= true then
					object.rotation =
						(object.rotation or 0)
						+ (object.angularVelocity or 0)
						* subDt
				end

				PhysicsEngine.prepareObject(
					object
				)

				updateObjectBroadphase(
					broadphase,
					object
				)
			end
		end

		------------------------------------------------
		-- COLLISION ITERATIONS
		------------------------------------------------

		for _ = 1, 2 do

			------------------------------------------------
			-- OBJECT VS OBJECT
			------------------------------------------------

			for idxA, objectA in ipairs(objects) do
				local objectAABB =
					getObjectAABB(objectA)

				local nearbyObjects =
					SpatialHash.queryCombined(
						broadphase.staticObjectGrid,
						broadphase.dynamicObjectGrid,
						objectAABB
					)

				for _, entry in ipairs(nearbyObjects) do
					local objectB =
						entry.object

					local idxB =
						entry.index

					if
						objectB ~= objectA
						and (
							objectB.isStatic == true
							or idxB > idxA
						)
					then
						PhysicsEngine.resolveShapeVsShapeCollision(
							objectA,
							objectB
						)

						updateObjectBroadphase(
							broadphase,
							objectA
						)

						updateObjectBroadphase(
							broadphase,
							objectB
						)

						objectAABB =
							getObjectAABB(objectA)
					end
				end
			end

			------------------------------------------------
			-- OBJECT VS SEGMENT
			------------------------------------------------

			for _, object in ipairs(objects) do
				local objectAABB =
					getObjectAABB(object)

				local nearbySegments =
					SpatialHash.queryCombined(
						broadphase.staticSegmentGrid,
						broadphase.dynamicSegmentGrid,
						objectAABB
					)

				for _, entry in ipairs(nearbySegments) do
					local segment =
						entry.object

					PhysicsEngine.resolveShapeVsSegmentCollision(
						object,
						segment
					)

					updateObjectBroadphase(
						broadphase,
						object
					)

					updateSegmentBroadphase(
						broadphase,
						segment
					)

					objectAABB =
						getObjectAABB(object)
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
					-- PLAYER VS OBJECT
					------------------------------------------------

					local nearbyObjects =
						SpatialHash.queryCombined(
							broadphase.staticObjectGrid,
							broadphase.dynamicObjectGrid,
							playerAABB
						)

					for _, entry in ipairs(nearbyObjects) do
						local object =
							entry.object

						resolvePlayerVsObject(
							pA,
							object
						)

						updatePlayerBroadphase(
							broadphase,
							pA
						)

						updateObjectBroadphase(
							broadphase,
							object
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
						local segment =
							entry.object

						resolvePlayerVsSegment(
							pA,
							segment
						)

						updatePlayerBroadphase(
							broadphase,
							pA
						)

						updateSegmentBroadphase(
							broadphase,
							segment
						)

						playerAABB =
							getPlayerAABB(pA)
					end
				end
			end
		end
	end
end

return PhysicsEngine
