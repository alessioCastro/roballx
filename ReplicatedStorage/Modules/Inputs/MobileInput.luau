--!strict
local UserInputService = game:GetService("UserInputService")

local MobileInput = {}

local currentMoveVector = Vector2.zero
local isKickPressed = false
local kickLatched = false

function MobileInput.Init(screenGui: ScreenGui)
	local mobileContainer = Instance.new("Frame")
	mobileContainer.Name = "MobileControls"
	mobileContainer.Size = UDim2.fromScale(1, 1)
	mobileContainer.BackgroundTransparency = 1
	mobileContainer.Parent = screenGui

	----------------------------------------------------
	-- 1. JOYSTICK VIRTUAL
	----------------------------------------------------
	local joyBase = Instance.new("Frame")
	joyBase.Size = UDim2.fromOffset(120, 120)
	joyBase.Position = UDim2.new(0, 40, 1, -160)
	joyBase.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	joyBase.BackgroundTransparency = 0.6
	joyBase.Parent = mobileContainer

	local joyBaseCorner = Instance.new("UICorner")
	joyBaseCorner.CornerRadius = UDim.new(1, 0)
	joyBaseCorner.Parent = joyBase

	local joyThumb = Instance.new("Frame")
	joyThumb.Size = UDim2.fromOffset(50, 50)
	joyThumb.AnchorPoint = Vector2.new(0.5, 0.5)
	joyThumb.Position = UDim2.fromScale(0.5, 0.5)
	joyThumb.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	joyThumb.BackgroundTransparency = 0.2
	joyThumb.Parent = joyBase

	local joyThumbCorner = Instance.new("UICorner")
	joyThumbCorner.CornerRadius = UDim.new(1, 0)
	joyThumbCorner.Parent = joyThumb

	local isDraggingJoy = false
	local touchObject: InputObject? = nil

	joyBase.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.Touch and not isDraggingJoy then
			isDraggingJoy = true
			touchObject = input
		end
	end)

	local function updateJoystick(inputObj: InputObject)
		local baseCenter = joyBase.AbsolutePosition + (joyBase.AbsoluteSize / 2)
		local touchPos = Vector2.new(inputObj.Position.X, inputObj.Position.Y)
		local delta = touchPos - baseCenter
		local maxRadius = joyBase.AbsoluteSize.X / 2

		if delta.Magnitude > maxRadius then
			delta = delta.Unit * maxRadius
		end

		joyThumb.Position = UDim2.fromOffset((joyBase.AbsoluteSize.X / 2) + delta.X, (joyBase.AbsoluteSize.Y / 2) + delta.Y)

		local rawVector = delta / maxRadius
		if rawVector.Magnitude > 0.2 then
			currentMoveVector = rawVector.Unit
		else
			currentMoveVector = Vector2.zero
		end
	end

	UserInputService.InputChanged:Connect(function(input: InputObject)
		if isDraggingJoy and input == touchObject then
			updateJoystick(input)
		end
	end)

	local function stopJoystick(input: InputObject)
		if input == touchObject then
			isDraggingJoy = false
			touchObject = nil
			joyThumb.Position = UDim2.fromScale(0.5, 0.5)
			currentMoveVector = Vector2.zero
		end
	end

	UserInputService.InputEnded:Connect(stopJoystick)

	----------------------------------------------------
	-- 2. BOTÃO DE CHUTE
	----------------------------------------------------
	local kickBtn = Instance.new("TextButton")
	kickBtn.Size = UDim2.fromOffset(100, 100)
	kickBtn.Position = UDim2.new(1, -120, 1, -140)
	kickBtn.BackgroundColor3 = Color3.fromRGB(230, 50, 50)
	kickBtn.Text = "KICK"
	kickBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	kickBtn.Font = Enum.Font.FredokaOne
	kickBtn.TextSize = 22
	kickBtn.Parent = mobileContainer

	local kickCorner = Instance.new("UICorner")
	kickCorner.CornerRadius = UDim.new(1, 0)
	kickCorner.Parent = kickBtn

	kickBtn.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.Touch then
			isKickPressed = true
			kickLatched = true
		end
	end)

	kickBtn.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.Touch then
			isKickPressed = false
		end
	end)
end

function MobileInput.GetInput(): (Vector2, boolean)
	local kick = isKickPressed or kickLatched
	kickLatched = false
	return currentMoveVector, kick
end

return MobileInput