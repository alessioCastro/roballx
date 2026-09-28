local HUDRenderer = {}

export type HUDController = {
	container: Instance,
	scoreboardFrame: Frame,
	leftScoreLabel: TextLabel,
	rightScoreLabel: TextLabel,
	timerLabel: TextLabel,
	UpdateScore: (self: HUDController, scoreRed: number, scoreBlue: number) -> (),
	UpdateTimer: (self: HUDController, timeText: string) -> ()
}

function HUDRenderer.Build(parentField: Instance): HUDController
	-- 1. Frame Container do Placar
	local scoreboardFrame = Instance.new("Frame")
	scoreboardFrame.Name = "ScoreboardFrame"
	scoreboardFrame.Size = UDim2.new(0, 220, 0, 52)
	scoreboardFrame.Position = UDim2.new(0.5, 0, 0, 0)
	scoreboardFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	scoreboardFrame.BackgroundColor3 = Color3.fromRGB(30, 35, 48)
	scoreboardFrame.BackgroundTransparency = 0.25
	scoreboardFrame.BorderSizePixel = 0
	scoreboardFrame.Parent = parentField

	local frameCorner = Instance.new("UICorner")
	frameCorner.CornerRadius = UDim.new(0, 10)
	frameCorner.Parent = scoreboardFrame

	local frameStroke = Instance.new("UIStroke")
	frameStroke.Color = Color3.fromRGB(70, 78, 95)
	frameStroke.Thickness = 1.5
	frameStroke.Parent = scoreboardFrame

	-- Layout horizontal
	local listLayout = Instance.new("UIListLayout")
	listLayout.FillDirection = Enum.FillDirection.Horizontal
	listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	listLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Padding = UDim.new(0, 12)
	listLayout.Parent = scoreboardFrame

	-- 2. Placar Vermelho (Esquerda - LayoutOrder 1)
	local leftScore = Instance.new("TextLabel")
	leftScore.Name = "LeftScore"
	leftScore.LayoutOrder = 1
	leftScore.Size = UDim2.new(0, 36, 0, 36)
	leftScore.BackgroundColor3 = Color3.fromRGB(225, 60, 45)
	leftScore.BorderSizePixel = 0
	leftScore.Font = Enum.Font.GothamBold
	leftScore.Text = "0"
	leftScore.TextColor3 = Color3.fromRGB(255, 255, 255)
	leftScore.TextSize = 20
	leftScore.Parent = scoreboardFrame

	local leftCorner = Instance.new("UICorner")
	leftCorner.CornerRadius = UDim.new(0, 8)
	leftCorner.Parent = leftScore

	-- 3. Cronômetro / Centro (LayoutOrder 2)
	local timerLabel = Instance.new("TextLabel")
	timerLabel.Name = "TimerLabel"
	timerLabel.LayoutOrder = 2
	timerLabel.Size = UDim2.new(0, 75, 0, 36)
	timerLabel.BackgroundTransparency = 1
	timerLabel.Font = Enum.Font.GothamBold
	timerLabel.Text = "00:00"
	timerLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	timerLabel.TextSize = 20
	timerLabel.Parent = scoreboardFrame

	-- 4. Placar Azul (Direita - LayoutOrder 3)
	local rightScore = Instance.new("TextLabel")
	rightScore.Name = "RightScore"
	rightScore.LayoutOrder = 3
	rightScore.Size = UDim2.new(0, 36, 0, 36)
	rightScore.BackgroundColor3 = Color3.fromRGB(45, 115, 230)
	rightScore.BorderSizePixel = 0
	rightScore.Font = Enum.Font.GothamBold
	rightScore.Text = "0"
	rightScore.TextColor3 = Color3.fromRGB(255, 255, 255)
	rightScore.TextSize = 20
	rightScore.Parent = scoreboardFrame

	local rightCorner = Instance.new("UICorner")
	rightCorner.CornerRadius = UDim.new(0, 8)
	rightCorner.Parent = rightScore

	--[[local goalText = Instance.new("TextLabel")
	goalText.Name = "GoalText"
	goalText.Size = UDim2.new(1, 0, 1, 0)
	goalText.AnchorPoint = Vector2.new(0.5, 0.5)
	goalText.Position = UDim2.new(0.5, 0, 0.5, 0)
	goalText.BackgroundTransparency = 1
	goalText.Font = Enum.Font.GothamBold
	goalText.Text = "GOAL!"
	goalText.TextColor3 = Color3.fromRGB(255, 255, 255)
	goalText.TextSize = 50
	goalText.TextXAlignment = Enum.TextXAlignment.Center
	goalText.TextYAlignment = Enum.TextYAlignment.Center
	goalText.Parent = parentField]]

	local self: HUDController = {
		container = parentField,
		scoreboardFrame = scoreboardFrame,
		leftScoreLabel = leftScore,
		rightScoreLabel = rightScore,
		timerLabel = timerLabel,
		UpdateScore = function(_, scoreRed, scoreBlue)
			leftScore.Text = tostring(scoreRed)
			rightScore.Text = tostring(scoreBlue)
		end,
		UpdateTimer = function(_, timeText)
			timerLabel.Text = timeText
		end
	}

	return self
end

return HUDRenderer