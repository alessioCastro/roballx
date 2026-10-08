local UIPrimitives = {}

export type ShapeConfig = {
	id: string?,
	pos: Vector2,
	size: Vector2,
	color: Color3,
	transparency: number?,
	cornerRadius: number | string?,
	strokeWidth: number?,
	strokeColor: Color3?,
	rotation: number?,
	zIndex: number?,
	isStatic: boolean?,
	isSolid: boolean?
}

----------------------------------------------------
-- WORLD -> GUI
----------------------------------------------------

function UIPrimitives.WorldToGui(
	parent: Instance,
	worldPosition: Vector2
): Vector2

	local guiWidth =
		parent.Size.X.Offset

	local guiHeight =
		parent.Size.Y.Offset

	return Vector2.new(
		(guiWidth * 0.5) + worldPosition.X,
		(guiHeight * 0.5) + worldPosition.Y
	)
end

----------------------------------------------------
-- CORNER RADIUS
----------------------------------------------------

local function resolveCornerRadius(
	cornerRadius: number | string
): UDim

	if typeof(cornerRadius) == "number" then

		if cornerRadius < 0 then
			error(
				"cornerRadius cannot be negative"
			)
		end

		return UDim.new(
			0,
			cornerRadius
		)
	end

	if typeof(cornerRadius) ~= "string" then
		error(
			"cornerRadius must be a number or percentage string"
		)
	end

	local percentageText =
		string.match(
			cornerRadius,
			"^(%d+%.?%d*)%%$"
		)

	if not percentageText then
		error(
			"Invalid cornerRadius '" ..
				cornerRadius ..
				"'. Use a number or percentage such as '50%'."
		)
	end

	local percentage =
		tonumber(percentageText)

	if not percentage then
		error(
			"Invalid cornerRadius '" ..
				cornerRadius ..
				"'"
		)
	end

	if percentage < 0 or percentage > 100 then
		error(
			"cornerRadius percentage must be between 0% and 100%"
		)
	end

	return UDim.new(
		percentage / 100,
		0
	)
end

----------------------------------------------------
-- SHAPE
----------------------------------------------------

function UIPrimitives.CreateShape(
	parent: Instance,
	config: ShapeConfig
): (Frame, UIStroke?)

	local strokeWidthVal =
		config.strokeWidth or 0

	local innerWidth =
		math.max(
			0,
			config.size.X - (strokeWidthVal * 2)
		)

	local innerHeight =
		math.max(
			0,
			config.size.Y - (strokeWidthVal * 2)
		)

	local frame =
		Instance.new("Frame")

	frame.Name =
		config.id or "Shape"

	frame.Size =
		UDim2.new(
			0,
			innerWidth,
			0,
			innerHeight
		)

	frame.AnchorPoint =
		Vector2.new(
			0.5,
			0.5
		)

	local guiPosition =
		UIPrimitives.WorldToGui(
			parent,
			config.pos
		)

	frame.Position =
		UDim2.new(
			0,
			guiPosition.X,
			0,
			guiPosition.Y
		)

	frame.BackgroundColor3 =
		config.color

	frame.BackgroundTransparency =
		config.transparency or 0

	frame.Rotation =
		config.rotation or 0

	frame.BorderSizePixel =
		0

	if config.zIndex then
		frame.ZIndex =
			config.zIndex
	end

	if config.cornerRadius then

		local corner =
			Instance.new("UICorner")

		corner.CornerRadius =
			resolveCornerRadius(
				config.cornerRadius
			)

		corner.Parent =
			frame
	end

	local stroke: UIStroke? =
		nil

	if strokeWidthVal > 0 then

		stroke =
			Instance.new("UIStroke")

		stroke.Color =
			config.strokeColor
			or Color3.fromRGB(
				0,
				0,
				0
			)

		stroke.Thickness =
			strokeWidthVal

		stroke.ApplyStrokeMode =
			Enum.ApplyStrokeMode.Border

		stroke.Parent =
			frame
	end

	frame.Parent =
		parent

	return frame, stroke
end

----------------------------------------------------
-- DISC
----------------------------------------------------

function UIPrimitives.CreateDisc(
	parent: Instance,
	pos: Vector2,
	totalRadius: number,
	fillColor: Color3,
	strokeWidth: number?,
	strokeColor: Color3?,
	id: string?
): (Frame, UIStroke?)

	return UIPrimitives.CreateShape(
		parent,
		{
			id = id,

			pos = pos,

			size =
				Vector2.new(
					totalRadius * 2,
					totalRadius * 2
				),

			color =
				fillColor,

			cornerRadius =
				"50%",

			strokeWidth =
				strokeWidth,

			strokeColor =
				strokeColor
		}
	)
end

----------------------------------------------------
-- SEGMENT
----------------------------------------------------

function UIPrimitives.CreateSegment(
	parent: Instance,
	posA: Vector2,
	posB: Vector2,
	thickness: number,
	color: Color3,
	id: string?
): Frame

	local midPoint =
		(posA + posB) / 2

	local diff =
		posB - posA

	local length =
		diff.Magnitude

	local angle =
		math.deg(
			math.atan2(
				diff.Y,
				diff.X
			)
		)

	return UIPrimitives.CreateShape(
		parent,
		{
			id = id,

			pos =
				midPoint,

			size =
				Vector2.new(
					length,
					thickness
				),

			color =
				color,

			rotation =
				angle,

			cornerRadius =
				0
		}
	)
end

return UIPrimitives
