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
	thickness: number?,
	ignoreCapA: boolean?,
	ignoreCapB: boolean?,
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
	cornerRadius: number?,
	restitution: number?,
	isStatic: boolean?,
	isSolid: boolean?,
	damping: number?,
	cGroup: number?,
	cMask: number?,

	segmentP1: Vector2,
	segmentP2: Vector2,
	segmentRadius: number,
}

export type Broadphase = {
	discGrid: SpatialHash.Grid,
	segmentGrid: SpatialHash.Grid,
	shapeGrid: SpatialHash.Grid,

	discIndex: {[any]: number},
	segmentIndex: {[any]: number},
	shapeIndex: {[any]: number},
}

----------------------------------------------------
-- BROADPHASE / AABB
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

	local minX = math.min(segment.a.X, segment.b.X) - halfThickness
	local minY = math.min(segment.a.Y, segment.b.Y) - halfThickness
	local maxX = math.max(segment.a.X, segment.b.X) + halfThickness
	local maxY = math.max(segment.a.Y, segment.b.Y) + halfThickness

	return {
		minX = minX,
		minY = minY,
		maxX = maxX,
		maxY = maxY,
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

function PhysicsEngine.createBroadphase(
	collisionDiscs: {CircleObject},
	collisionSegments: {Segment},
	collisionShapes: {PhysicalShape},
	cellSize: number
): Broadphase

	local broadphase: Broadphase = {
		discGrid = SpatialHash.new(cellSize),
		segmentGrid = SpatialHash.new(cellSize),
		shapeGrid = SpatialHash.new(cellSize),

		discIndex = {},
		segmentIndex = {},
		shapeIndex = {},
	}

	for index, disc in ipairs(collisionDiscs) do
		broadphase.discIndex[disc] = index

		SpatialHash.insert(
			broadphase.discGrid,
			disc,
			getCircleAABB(disc),
			index
		)
	end

	for index, segment in ipairs(collisionSegments) do
		broadphase.segmentIndex[segment] = index

		SpatialHash.insert(
			broadphase.segmentGrid,
			segment,
			getSegmentAABB(segment),
			index
		)
	end

	for index, shape in ipairs(collisionShapes) do
		broadphase.shapeIndex[shape] = index

		SpatialHash.insert(
			broadphase.shapeGrid,
			shape,
			getShapeAABB(shape),
			index
		)
	end

	return broadphase
end

function PhysicsEngine.rebuildBroadphase(
	broadphase: Broadphase,
	collisionDiscs: {CircleObject},
	collisionSegments: {Segment},
	collisionShapes: {PhysicalShape}
)
	SpatialHash.clear(broadphase.discGrid)
	SpatialHash.clear(broadphase.segmentGrid)
	SpatialHash.clear(broadphase.shapeGrid)

	for index, disc in ipairs(collisionDiscs) do
		SpatialHash.insert(
			broadphase.discGrid,
			disc,
			getCircleAABB(disc),
			index
		)
	end

	for index, segment in ipairs(collisionSegments) do
		SpatialHash.insert(
			broadphase.segmentGrid,
			segment,
			getSegmentAABB(segment),
			index
		)
	end

	for index, shape in ipairs(collisionShapes) do
		SpatialHash.insert(
			broadphase.shapeGrid,
			shape,
			getShapeAABB(shape),
			index
		)
	end
end

-- Checagem de colisão por bitmask
local function canCollide(a: any, b: any): boolean
	local groupA = a.cGroup or DEFAULT_MASK
	local maskA = a.cMask or DEFAULT_MASK
	local groupB = b.cGroup or DEFAULT_MASK
	local maskB = b.cMask or DEFAULT_MASK

	return bit32.btest(groupA, maskB) and bit32.btest(groupB, maskA)
end

local function rotateVector(v: Vector2, angleDegrees: number): Vector2
	if angleDegrees == 0 then return v end
	local rad = math.rad(angleDegrees)
	local cos = math.cos(rad)
	local sin = math.sin(rad)
	return Vector2.new(v.X * cos - v.Y * sin, v.X * sin + v.Y * cos)
end

function PhysicsEngine.prepareShape(shape: PhysicalShape)
	local w = shape.size.X
	local h = shape.size.Y

	local radius = math.min(w, h) / 2

	local extentX = math.max(0, (w / 2) - radius)
	local extentY = math.max(0, (h / 2) - radius)

	local p1Local: Vector2
	local p2Local: Vector2

	if extentX >= extentY then
		p1Local = Vector2.new(-extentX, 0)
		p2Local = Vector2.new(extentX, 0)
	else
		p1Local = Vector2.new(0, -extentY)
		p2Local = Vector2.new(0, extentY)
	end

	local rotation = shape.rotation or 0

	shape.segmentP1 = rotateVector(p1Local, rotation)
	shape.segmentP2 = rotateVector(p2Local, rotation)
	shape.segmentRadius = radius
end

local function closestPointOnSegment(p: Vector2, a: Vector2, b: Vector2): Vector2
	local ab = b - a
	local ab2 = ab:Dot(ab)
	if ab2 == 0 then return a end
	local t = math.clamp((p - a):Dot(ab) / ab2, 0, 1)
	return a + ab * t
end

local function getShapeSegment(shape: PhysicalShape): (Vector2, Vector2, number)
	return shape.pos + shape.segmentP1, shape.pos + shape.segmentP2, shape.segmentRadius
end

local function getClosestPointsBetweenSegments(a1: Vector2, a2: Vector2, b1: Vector2, b2: Vector2): (Vector2, Vector2, number)

	local bestA = a1
	local bestB = closestPointOnSegment(a1, b1, b2)

	local delta = bestB - bestA
	local minDistSq = delta:Dot(delta)

	local pA = a2
	local pB = closestPointOnSegment(a2, b1, b2)
	delta = pB - pA
	local distSq = delta:Dot(delta)

	if distSq < minDistSq then
		minDistSq = distSq
		bestA = pA
		bestB = pB
	end

	pA = closestPointOnSegment(b1, a1, a2)
	pB = b1
	delta = pB - pA
	distSq = delta:Dot(delta)

	if distSq < minDistSq then
		minDistSq = distSq
		bestA = pA
		bestB = pB
	end

	pA = closestPointOnSegment(b2, a1, a2)
	pB = b2
	delta = pB - pA
	distSq = delta:Dot(delta)

	if distSq < minDistSq then
		minDistSq = distSq
		bestA = pA
		bestB = pB
	end

	return bestA, bestB, math.sqrt(minDistSq)
end

----------------------------------------------------
-- 1. CÍRCULO VS SHAPE
----------------------------------------------------
function PhysicsEngine.resolveShapeCollision(obj: CircleObject, shape: PhysicalShape)
	if not canCollide(obj, shape) then return end
	if shape.isSolid == false or obj.isSolid == false then return end

	local shapeVel = shape.vel or Vector2.zero
	local shapeMass = shape.mass or 1
	local shapeIsStatic = (shape.isStatic ~= false)
	local objIsStatic = (obj.isStatic == true)

	if shapeIsStatic and objIsStatic then return end

	local s1, s2, shapeRad = getShapeSegment(shape)
	local closestOnSeg = closestPointOnSegment(obj.pos, s1, s2)

	local delta = obj.pos - closestOnSeg
	local dist = delta.Magnitude
	local minDist = obj.radius + shapeRad

	if dist < minDist then
		local normal = dist > 0.0001 and (delta / dist) or Vector2.new(0, 1)
		local overlap = minDist - dist

		if shapeIsStatic then
			obj.pos += normal * overlap
		elseif objIsStatic then
			shape.pos -= normal * overlap
		else
			local totalMass = obj.mass + shapeMass
			obj.pos += normal * (overlap * (shapeMass / totalMass))
			shape.pos -= normal * (overlap * (obj.mass / totalMass))
		end

		local relVel = obj.vel - shapeVel
		local velAlongNormal = relVel:Dot(normal)

		if velAlongNormal < 0 then
			local e = math.min(obj.restitution, shape.restitution or 0.2)
			if shapeIsStatic then
				obj.vel -= (1 + e) * velAlongNormal * normal
			elseif objIsStatic then
				shape.vel = shapeVel + (1 + e) * velAlongNormal * normal
			else
				local impulseMag = -(1 + e) * velAlongNormal / (1/obj.mass + 1/shapeMass)
				local impulse = normal * impulseMag
				obj.vel += impulse / obj.mass
				shape.vel = shapeVel - impulse / shapeMass
			end
		end
	end
end

----------------------------------------------------
-- 2. SHAPE VS SHAPE (CÁPSULA VS CÁPSULA)
----------------------------------------------------
function PhysicsEngine.resolveShapeVsShapeCollision(sA: PhysicalShape, sB: PhysicalShape)
	if not canCollide(sA, sB) then return end
	if sA.isSolid == false or sB.isSolid == false then return end

	local aIsStatic = (sA.isStatic ~= false)
	local bIsStatic = (sB.isStatic ~= false)
	if aIsStatic and bIsStatic then return end

	local a1, a2, radA = getShapeSegment(sA)
	local b1, b2, radB = getShapeSegment(sB)

	local pA, pB, dist = getClosestPointsBetweenSegments(a1, a2, b1, b2)
	local minDist = radA + radB

	if dist < minDist then
		local delta = pB - pA
		local normal = dist > 0.0001 and (delta / dist) or Vector2.new(0, 1)
		local overlap = minDist - dist

		local massA = sA.mass or 1
		local massB = sB.mass or 1
		local velA = sA.vel or Vector2.zero
		local velB = sB.vel or Vector2.zero

		if aIsStatic then
			sB.pos += normal * overlap
			local velAlongNormal = velB:Dot(normal)
			if velAlongNormal < 0 then
				sB.vel = velB - (1 + (sB.restitution or 0.2)) * velAlongNormal * normal
			end
			return
		elseif bIsStatic then
			sA.pos -= normal * overlap
			local velAlongNormal = velA:Dot(normal)
			if velAlongNormal > 0 then
				sA.vel = velA - (1 + (sA.restitution or 0.2)) * velAlongNormal * normal
			end
			return
		end

		local totalMass = massA + massB
		sA.pos -= normal * (overlap * (massB / totalMass))
		sB.pos += normal * (overlap * (massA / totalMass))

		local relVel = velB - velA
		local velAlongNormal = relVel:Dot(normal)

		if velAlongNormal < 0 then
			local e = math.min(sA.restitution or 0.2, sB.restitution or 0.2)
			local impulseMag = -(1 + e) * velAlongNormal / (1/massA + 1/massB)
			local impulse = normal * impulseMag
			sA.vel = velA - impulse / massA
			sB.vel = velB + impulse / massB
		end
	end
end

----------------------------------------------------
-- 3. SHAPE VS SEGMENT (CÁPSULA VS LINHAS/PAREDES)
----------------------------------------------------
function PhysicsEngine.resolveShapeVsSegmentCollision(shape: PhysicalShape, seg: Segment)
	if not canCollide(shape, seg) then return end
	if shape.isSolid == false or seg.isSolid == false then return end

	local shape1, shape2, shapeRad = getShapeSegment(shape)
	local segRad = (seg.thickness or 2) / 2

	local pShape, pSeg, dist = getClosestPointsBetweenSegments(shape1, shape2, seg.a, seg.b)
	local minDist = shapeRad + segRad

	if dist < minDist then
		local delta = pShape - pSeg
		local normal = dist > 0.0001 and (delta / dist) or Vector2.new(0, 1)
		local overlap = minDist - dist

		local shapeIsStatic = (shape.isStatic ~= false)
		local segIsStatic = (seg.isStatic ~= false)
		local shapeVel = shape.vel or Vector2.zero
		local segVel = seg.vel or Vector2.zero

		if segIsStatic and not shapeIsStatic then
			shape.pos += normal * overlap
			local relVel = shapeVel - segVel
			local velAlongNormal = relVel:Dot(normal)
			if velAlongNormal < 0 then
				local e = math.min(shape.restitution or 0.2, seg.restitution or 0.2)
				shape.vel = shapeVel - (1 + e) * velAlongNormal * normal
			end
		elseif shapeIsStatic and not segIsStatic then
			seg.a -= normal * overlap
			seg.b -= normal * overlap
		end
	end
end

----------------------------------------------------
-- 4. CÍRCULO VS SEGMENTO
----------------------------------------------------
function PhysicsEngine.resolveSegmentCollision(obj: CircleObject, seg: Segment)
	if not canCollide(obj, seg) then return end
	if seg.isSolid == false or obj.isSolid == false then return end

	local ab = seg.b - seg.a
	local ap = obj.pos - seg.a
	local ab2 = ab:Dot(ab)
	if ab2 == 0 then return end

	local t = ap:Dot(ab) / ab2
	if seg.ignoreCapA and t < 0 then return end
	if seg.ignoreCapB and t > 1 then return end

	t = math.clamp(t, 0, 1)
	local closest = seg.a + ab * t
	local delta = obj.pos - closest
	local dist = delta.Magnitude

	if dist < obj.radius and dist > 0 then
		local normal = delta / dist
		local overlap = obj.radius - dist
		local segVel = seg.vel or Vector2.zero
		local segIsStatic = (seg.isStatic ~= false)

		if segIsStatic then
			obj.pos += normal * overlap
			local velAlongNormal = (obj.vel - segVel):Dot(normal)
			if velAlongNormal < 0 then
				local bounce = obj.restitution + (seg.restitution or 0.1)
				obj.vel -= (1 + bounce) * velAlongNormal * normal
			end
		end
	end
end

----------------------------------------------------
-- 5. CÍRCULO VS CÍRCULO (CORRIGIDO)
----------------------------------------------------
function PhysicsEngine.resolveCircleCollision(a: CircleObject, b: CircleObject)
	if not canCollide(a, b) then return end
	if a.isSolid == false or b.isSolid == false then return end

	local delta = b.pos - a.pos
	local dist = delta.Magnitude
	local minDist = a.radius + b.radius

	if dist < minDist and dist > 0 then
		local normal = delta / dist
		local overlap = minDist - dist

		local aIsStatic = (a.isStatic == true)
		local bIsStatic = (b.isStatic == true)

		if aIsStatic and bIsStatic then return end

		-- Se 'a' for estático e 'b' dinâmico (ex: Trave = a, Bola = b)
		if aIsStatic then
			b.pos += normal * overlap
			local velAlongNormal = b.vel:Dot(normal)
			if velAlongNormal < 0 then
				local e = math.min(a.restitution or 0.5, b.restitution or 0.5)
				b.vel -= (1 + e) * velAlongNormal * normal
			end
			return
				-- Se 'b' for estático e 'a' dinâmico (ex: Bola = a, Trave = b)
		elseif bIsStatic then
			a.pos -= normal * overlap
			local velAlongNormal = a.vel:Dot(normal)
			if velAlongNormal > 0 then
				local e = math.min(a.restitution or 0.5, b.restitution or 0.5)
				a.vel -= (1 + e) * velAlongNormal * normal
			end
			return
		end

		-- Colisão entre dois círculos dinâmicos
		local totalMass = a.mass + b.mass
		a.pos -= normal * (overlap * (b.mass / totalMass))
		b.pos += normal * (overlap * (a.mass / totalMass))

		local relativeVel = b.vel - a.vel
		local velAlongNormal = relativeVel:Dot(normal)

		if velAlongNormal < 0 then
			local speed = relativeVel.Magnitude
			local eBase = math.min(a.restitution, b.restitution)
			local e = speed < 30 and (eBase * 0.2) or eBase
			local impulseMagnitude = -(1 + e) * velAlongNormal / (1/a.mass + 1/b.mass)
			local impulse = normal * impulseMagnitude
			a.vel -= impulse / a.mass
			b.vel += impulse / b.mass
		end
	end
end

function PhysicsEngine.tryKick(pData: CircleObject, ball: CircleObject, phys: any, currentTick: number)
	local kickCooldownTicks = math.ceil(phys.kickCooldown * 60) -- cooldown em ticks (60 ticks/s)
	if currentTick - (pData.lastKickTick or -9999) < kickCooldownTicks then return end

	local delta = ball.pos - pData.pos
	local dist = delta.Magnitude
	if dist <= (pData.radius + ball.radius + phys.kickRangeExtra) then
		pData.lastKickTick = currentTick
		local kickDir = dist > 0 and delta.Unit or Vector2.new(1, 0)
		ball.vel += kickDir * phys.kickForce
	end
end

----------------------------------------------------
-- 6. STEP DA FÍSICA INTEGRADO
----------------------------------------------------
function function PhysicsEngine.Step(ball, playersData, sortedUserIds, discs, segments, shapes, collisionDiscs, collisionSegments, collisionShapes, broadphase, phys, fixedDt, currentTick)
	-- Iteração em ordem determinística (sortedUserIds em vez de pairs())
	for _, uId in ipairs(sortedUserIds) do
		local pData = playersData[uId]

		if pData then
			-- Freio adicional explícito do Ballser.
			-- É propositalmente separado do friction físico.
			local decelFactor = phys.playerDecelFactor or 0.88

			pData.vel *= decelFactor

			-- Aplicação de força -> aceleração -> velocidade.
			-- playerAccel representa aceleração na unidade interna do Roballx.
			if pData.input and pData.input.Magnitude > 0 then
				local mass = math.max(pData.mass, 0.000001)
				local force = pData.input.Unit * (phys.playerAccel * mass)
				local acceleration = force / mass

				pData.vel += acceleration * fixedDt
			end

			-- Friction com a mesma semântica do Ballser:
			-- v *= (1 - friction * dt)
			local friction = math.clamp(phys.playerFriction or 1, 0, 1)
			local frictionFactor = math.max(0, 1 - friction * fixedDt)

			pData.vel *= frictionFactor

			-- Integração da posição usando dt real.
			pData.pos += pData.vel * fixedDt

			if pData.isKicking then
				PhysicsEngine.tryKick(pData, ball, phys, currentTick)
			end
		end
	end

	for _, disc in ipairs(discs) do
		if disc.isStatic == false then
			disc.vel = (disc.vel or Vector2.zero) * (disc.damping or 0.98)
			disc.pos += disc.vel * fixedDt
		end
	end

	for _, seg in ipairs(segments) do
		if seg.isStatic == false then
			seg.vel = (seg.vel or Vector2.zero) * (seg.damping or 0.98)

			local delta = seg.vel * fixedDt
			seg.a += delta
			seg.b += delta
		end
	end

	for _, shape in ipairs(shapes) do
		if shape.isStatic == false then
			shape.vel = (shape.vel or Vector2.zero) * (shape.damping or 0.98)
			shape.pos += shape.vel * fixedDt
		end
	end

	local steps = math.clamp(math.ceil(ball.vel.Magnitude / 6), 1, 4)
	local subDt = fixedDt / steps
	local dampingFactor = math.pow(phys.ballDamping, 1 / steps)

	for _ = 1, steps do
		ball.vel *= dampingFactor
		ball.pos += ball.vel * subDt

		for iter = 1, 2 do
			for _, disc in ipairs(collisionDiscs) do
				PhysicsEngine.resolveCircleCollision(ball, disc)
			end

			for _, seg in ipairs(collisionSegments) do
				PhysicsEngine.resolveSegmentCollision(ball, seg)
			end

			for _, shape in ipairs(collisionShapes) do
				PhysicsEngine.resolveShapeCollision(ball, shape)
			end
		end
	end

	for iter = 1, 2 do
		for i = 1, #collisionShapes do
			for j = i + 1, #collisionShapes do
				PhysicsEngine.resolveShapeVsShapeCollision(
					collisionShapes[i],
					collisionShapes[j]
				)
			end
		end

		for _, shape in ipairs(collisionShapes) do
			for _, seg in ipairs(collisionSegments) do
				PhysicsEngine.resolveShapeVsSegmentCollision(shape, seg)
			end
		end

		for _, shape in ipairs(collisionShapes) do
			for _, disc in ipairs(collisionDiscs) do
				PhysicsEngine.resolveShapeCollision(disc, shape)
			end
		end

		-- Iteração determinística usando sortedUserIds
		for idxA, uIdA in ipairs(sortedUserIds) do
			local pA = playersData[uIdA]
			if pA then
				PhysicsEngine.resolveCircleCollision(pA, ball)
				for _, disc in ipairs(collisionDiscs) do
					PhysicsEngine.resolveCircleCollision(pA, disc)
				end
				for idxB = idxA + 1, #sortedUserIds do
					local pB = playersData[sortedUserIds[idxB]]
					if pB then
						PhysicsEngine.resolveCircleCollision(pA, pB)
					end
				end
				for _, seg in ipairs(collisionSegments) do
					PhysicsEngine.resolveSegmentCollision(pA, seg)
				end
				for _, shape in ipairs(collisionShapes) do
					PhysicsEngine.resolveShapeCollision(pA, shape)
				end
			end
		end

		for _, disc in ipairs(discs) do
			if disc.isStatic == false then
				for _, seg in ipairs(collisionSegments) do
					PhysicsEngine.resolveSegmentCollision(disc, seg)
				end
			end
		end
	end
end

return PhysicsEngine
