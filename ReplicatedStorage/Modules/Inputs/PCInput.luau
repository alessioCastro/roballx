--!strict
local ContextActionService = game:GetService("ContextActionService")

local PCInput = {}

local currentMoveVector = Vector2.zero
local isKickPressed = false
local kickLatched = false -- Flag "sticky" para evitar perde-chute entre frames

local keysPressed = {
	Up = false,
	Down = false,
	Left = false,
	Right = false
}

local function updateVector()
	local x = 0
	local y = 0

	if keysPressed.Right then x += 1 end
	if keysPressed.Left then x -= 1 end
	if keysPressed.Down then y += 1 end
	if keysPressed.Up then y -= 1 end

	local vec = Vector2.new(x, y)
	currentMoveVector = vec.Magnitude > 0 and vec.Unit or Vector2.zero
end

local function handleMoveAction(actionName: string, userInputState: Enum.UserInputState, _inputObject: InputObject)
	local isPressed = (userInputState == Enum.UserInputState.Begin or userInputState == Enum.UserInputState.Change)

	if actionName == "MoveUp" then
		keysPressed.Up = isPressed
	elseif actionName == "MoveDown" then
		keysPressed.Down = isPressed
	elseif actionName == "MoveLeft" then
		keysPressed.Left = isPressed
	elseif actionName == "MoveRight" then
		keysPressed.Right = isPressed
	end

	updateVector()
	return Enum.ContextActionResult.Pass
end

local function handleKickAction(_actionName: string, userInputState: Enum.UserInputState, _inputObject: InputObject)
	if userInputState == Enum.UserInputState.Begin then
		isKickPressed = true
		kickLatched = true -- Garante registro no próximo tick do Heartbeat
	elseif userInputState == Enum.UserInputState.End or userInputState == Enum.UserInputState.Cancel then
		isKickPressed = false
	end
	return Enum.ContextActionResult.Pass
end

function PCInput.Init()
	ContextActionService:BindAction("MoveUp", handleMoveAction, false, Enum.KeyCode.W, Enum.KeyCode.Up, Enum.KeyCode.DPadUp)
	ContextActionService:BindAction("MoveDown", handleMoveAction, false, Enum.KeyCode.S, Enum.KeyCode.Down, Enum.KeyCode.DPadDown)
	ContextActionService:BindAction("MoveLeft", handleMoveAction, false, Enum.KeyCode.A, Enum.KeyCode.Left, Enum.KeyCode.DPadLeft)
	ContextActionService:BindAction("MoveRight", handleMoveAction, false, Enum.KeyCode.D, Enum.KeyCode.Right, Enum.KeyCode.DPadRight)

	ContextActionService:BindAction("Kick", handleKickAction, false, Enum.KeyCode.Space, Enum.KeyCode.X, Enum.KeyCode.ButtonA)
end

function PCInput.GetInput(): (Vector2, boolean)
	local kick = isKickPressed or kickLatched
	kickLatched = false -- Consome a flag para o próximo tick
	return currentMoveVector, kick
end

function PCInput.Cleanup()
	ContextActionService:UnbindAction("MoveUp")
	ContextActionService:UnbindAction("MoveDown")
	ContextActionService:UnbindAction("MoveLeft")
	ContextActionService:UnbindAction("MoveRight")
	ContextActionService:UnbindAction("Kick")
end

return PCInput