local ReplicatedStorage = game:GetService("ReplicatedStorage")
local replicatedModules = ReplicatedStorage:WaitForChild("Modules")
local UIPrimitives = require(replicatedModules:WaitForChild("Renderers"):WaitForChild("UIPrimitives"))

local MapRenderer = {}

function MapRenderer.Build(map: any, playerGui: PlayerGui)
	local existing = playerGui:FindFirstChild("HaxballGui")
	if existing then existing:Destroy() end

	local bounds = map.bounds
	local padding = bounds.padding or 0
	local totalWidth = bounds.width + (padding * 2)
	local totalHeight = bounds.height + (padding * 2) + 60

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "HaxballGui"
	screenGui.ResetOnSpawn = false
	screenGui.Parent = playerGui

	local field = Instance.new("Frame")
	field.Name = "Field"
	field.Size = UDim2.new(0, bounds.width, 0, bounds.height)
	field.AnchorPoint = Vector2.new(0.5, 0.5)
	field.Position = UDim2.new(0.5, 0, 0.5, 0)
	field.BackgroundColor3 = Color3.fromRGB(80, 150, 70)
	field.BorderSizePixel = 0
	field.Parent = screenGui

	local uiScale = Instance.new("UIScale")
	uiScale.Parent = field

	local function resize()
		local viewport = workspace.CurrentCamera.ViewportSize
		if viewport.X == 0 or viewport.Y == 0 then return end
		local scaleX = (viewport.X * 0.9) / totalWidth
		local scaleY = (viewport.Y * 0.8) / totalHeight
		uiScale.Scale = math.min(scaleX, scaleY)
	end

	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(resize)
	resize()

	local dynamicFrames: { [string]: Frame } = {}

	if map.segments then
		for idx, segData in ipairs(map.segments) do
			local curve = segData.curve or 0
			if curve == 0 then
				local id = segData.id or ("seg_" .. idx)
				local frame = UIPrimitives.CreateSegment(field, segData.a, segData.b, segData.thickness, segData.color, id)
				if segData.isStatic == false then dynamicFrames[id] = frame end
			else
				local samples = segData.curveSegments or 10
				local ab = segData.b - segData.a
				if ab.Magnitude > 0 then
					local normal = Vector2.new(-ab.Y, ab.X).Unit
					local control = (segData.a + segData.b) / 2 + normal * curve

					local prevPoint = segData.a
					for i = 1, samples do
						local t = i / samples
						local invT = 1 - t
						local currentPoint = (invT * invT * segData.a) + (2 * invT * t * control) + (t * t * segData.b)

						local id = (segData.id or ("seg_" .. idx)) .. "_" .. i
						local frame = UIPrimitives.CreateSegment(field, prevPoint, currentPoint, segData.thickness, segData.color, id)
						if segData.isStatic == false then dynamicFrames[id] = frame end

						prevPoint = currentPoint
					end
				end
			end
		end
	end

	if map.shapes then
		for idx, shapeData in ipairs(map.shapes) do
			local id = shapeData.id or ("shape_" .. idx)
			local frame = UIPrimitives.CreateShape(field, shapeData)
			if shapeData.isStatic == false then dynamicFrames[id] = frame end
		end
	end

	if map.discs then
		for idx, discData in ipairs(map.discs) do
			local id = discData.id or ("disc_" .. idx)
			local frame = UIPrimitives.CreateDisc(
				field, 
				discData.pos, 
				discData.radius, 
				discData.color, 
				discData.strokeWidth, 
				discData.strokeColor, 
				id
			)
			if discData.isStatic == false then dynamicFrames[id] = frame end
		end
	end

	return {
		screenGui = screenGui,
		field = field,
		dynamicFrames = dynamicFrames
	}
end

return MapRenderer