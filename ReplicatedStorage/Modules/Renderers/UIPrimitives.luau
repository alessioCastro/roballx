local UIPrimitives = {}

export type ShapeConfig = {
	id: string?,
	pos: Vector2,
	size: Vector2,
	color: Color3,
	transparency: number?,
	cornerRadius: (UDim | number)?,
	strokeWidth: number?,
	strokeColor: Color3?,
	rotation: number?,
	zIndex: number?,
	isStatic: boolean?,
	isSolid: boolean?
}

function UIPrimitives.CreateShape(parent: Instance, config: ShapeConfig): (Frame, UIStroke?)
	local strokeWidthVal = config.strokeWidth or 0
	local innerWidth = math.max(0, config.size.X - (strokeWidthVal * 2))
	local innerHeight = math.max(0, config.size.Y - (strokeWidthVal * 2))

	local frame = Instance.new("Frame")
	frame.Name = config.id or "Shape"
	frame.Size = UDim2.new(0, innerWidth, 0, innerHeight)
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.new(0, config.pos.X, 0, config.pos.Y)
	frame.BackgroundColor3 = config.color
	frame.BackgroundTransparency = config.transparency or 0
	frame.Rotation = config.rotation or 0
	frame.BorderSizePixel = 0
	if config.zIndex then frame.ZIndex = config.zIndex end

	if config.cornerRadius then
		local corner = Instance.new("UICorner")
		if typeof(config.cornerRadius) == "UDim" then
			corner.CornerRadius = config.cornerRadius
		else
			corner.CornerRadius = UDim.new(0, config.cornerRadius)
		end
		corner.Parent = frame
	end

	local stroke: UIStroke? = nil
	if strokeWidthVal > 0 then
		stroke = Instance.new("UIStroke")
		stroke.Color = config.strokeColor or Color3.fromRGB(0, 0, 0)
		stroke.Thickness = strokeWidthVal
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Parent = frame
	end

	frame.Parent = parent
	return frame, stroke
end

function UIPrimitives.CreateDisc(parent: Instance, pos: Vector2, totalRadius: number, fillColor: Color3, strokeWidth: number?, strokeColor: Color3?, id: string?): (Frame, UIStroke?)
	return UIPrimitives.CreateShape(parent, {
		id = id,
		pos = pos,
		size = Vector2.new(totalRadius * 2, totalRadius * 2),
		color = fillColor,
		cornerRadius = UDim.new(0.5, 0),
		strokeWidth = strokeWidth,
		strokeColor = strokeColor
	})
end

function UIPrimitives.CreateSegment(parent: Instance, posA: Vector2, posB: Vector2, thickness: number, color: Color3, id: string?): Frame
	local midPoint = (posA + posB) / 2
	local diff = posB - posA
	local length = diff.Magnitude
	local angle = math.deg(math.atan2(diff.Y, diff.X))

	local frame, _ = UIPrimitives.CreateShape(parent, {
		id = id,
		pos = midPoint,
		size = Vector2.new(length, thickness),
		color = color,
		rotation = angle,
		cornerRadius = UDim.new(0, 0)
	})
	return frame
end

return UIPrimitives