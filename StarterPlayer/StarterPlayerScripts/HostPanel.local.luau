
--!strict
-- HostPanel.local.luau
-- Painel unificado da sala.
-- O servidor permanece como autoridade para equipes, moderacao e partida.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer
local playerGui = LocalPlayer:WaitForChild("PlayerGui")

local isRoomServer = ReplicatedStorage:GetAttribute("IsRoomServer")
if isRoomServer == nil then
	ReplicatedStorage:GetAttributeChangedSignal("IsRoomServer"):Wait()
	isRoomServer = ReplicatedStorage:GetAttribute("IsRoomServer")
end

if isRoomServer ~= true then
	return
end

local RoomController = require(
	ReplicatedStorage:WaitForChild("Modules"):WaitForChild("RoomController")
)

local TeamSettings = require(
	ReplicatedStorage:WaitForChild("Modules"):WaitForChild("TeamSettings")
)

local roomRemotes =
	ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("RoomRemotes")

local KickPlayerRF = roomRemotes:WaitForChild("KickPlayer") :: RemoteFunction
local BanPlayerRF = roomRemotes:WaitForChild("BanPlayer") :: RemoteFunction
local TransferHostRF = roomRemotes:WaitForChild("TransferHost") :: RemoteFunction
local GetRoomManagementRF = roomRemotes:WaitForChild("GetRoomManagement") :: RemoteFunction
local RoomManagementUpdatedRE = roomRemotes:WaitForChild("RoomManagementUpdated") :: RemoteEvent
local SetPlayerTeamRF = roomRemotes:WaitForChild("SetPlayerTeam") :: RemoteFunction
local MatchControlRequestRF = roomRemotes:WaitForChild("MatchControlRequest") :: RemoteFunction
local MatchStateUpdatedRE = roomRemotes:WaitForChild("MatchStateUpdated") :: RemoteEvent

type PlayerInfo = {
	UserId: number,
	Name: string,
	IsHost: boolean,
	JoinOrder: number,
	TeamKey: string,
}

type MatchState = {
	Status: string,
	TimeLimit: number,
	ScoreLimit: number,
	ElapsedSeconds: number,
	RemainingSeconds: number?,
}

type RoomState = {
	RoomId: string,
	RoomCode: string,
	RoomName: string,
	HostUserId: number,
	HostName: string,
	AllowHostMigration: boolean,
	Players: { PlayerInfo },
	MatchState: MatchState?,
}

local previousGui = playerGui:FindFirstChild("HostPanelGui")
if previousGui then
	previousGui:Destroy()
end

local function corner(parent: Instance, radius: number)
	local value = Instance.new("UICorner")
	value.CornerRadius = UDim.new(0, radius)
	value.Parent = parent
end

local function stroke(parent: Instance, color: Color3)
	local value = Instance.new("UIStroke")
	value.Color = color
	value.Thickness = 1
	value.Parent = parent
end

local function makeButton(
	parent: Instance,
	name: string,
	text: string,
	size: UDim2,
	position: UDim2,
	color: Color3
): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.Size = size
	button.Position = position
	button.BackgroundColor3 = color
	button.BorderSizePixel = 0
	button.Text = text
	button.TextColor3 = Color3.fromRGB(255, 255, 255)
	button.TextSize = 13
	button.Font = Enum.Font.GothamBold
	button.AutoButtonColor = true
	button.Parent = parent
	corner(button, 6)
	return button
end

local function makeLabel(
	parent: Instance,
	name: string,
	text: string,
	size: UDim2,
	position: UDim2
): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.Size = size
	label.Position = position
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = Color3.fromRGB(230, 233, 240)
	label.TextSize = 13
	label.Font = Enum.Font.Gotham
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = parent
	return label
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "HostPanelGui"
screenGui.ResetOnSpawn = false
screenGui.DisplayOrder = 10
screenGui.Parent = playerGui

local openButton = makeButton(
	screenGui,
	"OpenRoomPanel",
	"☰  SALA",
	UDim2.fromOffset(112, 36),
	UDim2.new(1, -128, 0, 16),
	Color3.fromRGB(35, 39, 49)
)
stroke(openButton, Color3.fromRGB(92, 101, 121))

local panel = Instance.new("Frame")
panel.Name = "RoomPanel"
panel.Size = UDim2.fromOffset(660, 550)
panel.Position = UDim2.new(0.5, -330, 0.5, -275)
panel.BackgroundColor3 = Color3.fromRGB(25, 27, 34)
panel.BorderSizePixel = 0
panel.Visible = false
panel.Parent = screenGui
corner(panel, 10)
stroke(panel, Color3.fromRGB(74, 80, 96))

local title = makeLabel(
	panel,
	"RoomTitle",
	"SALA",
	UDim2.new(1, -90, 0, 34),
	UDim2.fromOffset(18, 10)
)
title.Font = Enum.Font.GothamBold
title.TextSize = 19

local subtitle = makeLabel(
	panel,
	"RoomSubtitle",
	"Jogadores e controles da partida",
	UDim2.new(1, -36, 0, 20),
	UDim2.fromOffset(18, 43)
)
subtitle.TextColor3 = Color3.fromRGB(155, 163, 180)
subtitle.TextSize = 12

local closeButton = makeButton(
	panel,
	"CloseRoomPanel",
	"×",
	UDim2.fromOffset(32, 32),
	UDim2.new(1, -44, 0, 9),
	Color3.fromRGB(60, 64, 76)
)
closeButton.TextSize = 22

-- Controles da partida.
local controls = Instance.new("Frame")
controls.Name = "MatchControls"
controls.Size = UDim2.new(1, -36, 0, 112)
controls.Position = UDim2.fromOffset(18, 73)
controls.BackgroundColor3 = Color3.fromRGB(19, 21, 27)
controls.BorderSizePixel = 0
controls.Parent = panel
corner(controls, 7)

local timeLabel = makeLabel(
	controls,
	"TimeLimitLabel",
	"Time Limit (min; 0 = sem limite)",
	UDim2.fromOffset(220, 20),
	UDim2.fromOffset(12, 8)
)
timeLabel.TextSize = 11

local timeInput = Instance.new("TextBox")
timeInput.Name = "TimeLimitInput"
timeInput.Size = UDim2.fromOffset(90, 30)
timeInput.Position = UDim2.fromOffset(12, 31)
timeInput.BackgroundColor3 = Color3.fromRGB(44, 48, 59)
timeInput.BorderSizePixel = 0
timeInput.Text = "5"
timeInput.PlaceholderText = "Minutos"
timeInput.TextColor3 = Color3.new(1, 1, 1)
timeInput.PlaceholderColor3 = Color3.fromRGB(160, 165, 177)
timeInput.TextSize = 14
timeInput.Font = Enum.Font.GothamMedium
timeInput.ClearTextOnFocus = false
timeInput.Parent = controls
corner(timeInput, 5)

local scoreLabel = makeLabel(
	controls,
	"ScoreLimitLabel",
	"Score Limit (gols; 0 = sem limite)",
	UDim2.fromOffset(240, 20),
	UDim2.fromOffset(116, 8)
)
scoreLabel.TextSize = 11

local scoreInput = Instance.new("TextBox")
scoreInput.Name = "ScoreLimitInput"
scoreInput.Size = UDim2.fromOffset(90, 30)
scoreInput.Position = UDim2.fromOffset(116, 31)
scoreInput.BackgroundColor3 = Color3.fromRGB(44, 48, 59)
scoreInput.BorderSizePixel = 0
scoreInput.Text = "5"
scoreInput.PlaceholderText = "Gols"
scoreInput.TextColor3 = Color3.new(1, 1, 1)
scoreInput.PlaceholderColor3 = Color3.fromRGB(160, 165, 177)
scoreInput.TextSize = 14
scoreInput.Font = Enum.Font.GothamMedium
scoreInput.ClearTextOnFocus = false
scoreInput.Parent = controls
corner(scoreInput, 5)

local saveSettingsButton = makeButton(
	controls,
	"SaveMatchSettings",
	"Salvar",
	UDim2.fromOffset(86, 30),
	UDim2.fromOffset(220, 31),
	Color3.fromRGB(66, 91, 130)
)

local startStopButton = makeButton(
	controls,
	"StartStopMatch",
	"Iniciar",
	UDim2.fromOffset(105, 34),
	UDim2.new(1, -235, 0, 30),
	Color3.fromRGB(46, 125, 70)
)

local pauseButton = makeButton(
	controls,
	"PauseMatch",
	"Pausar",
	UDim2.fromOffset(105, 34),
	UDim2.new(1, -120, 0, 30),
	Color3.fromRGB(161, 113, 42)
)

local matchStatusLabel = makeLabel(
	controls,
	"MatchStatus",
	"Partida parada",
	UDim2.new(1, -24, 0, 24),
	UDim2.fromOffset(12, 77)
)
matchStatusLabel.TextColor3 = Color3.fromRGB(181, 188, 204)
matchStatusLabel.TextSize = 12

local playersHeading = makeLabel(
	panel,
	"PlayersHeading",
	"JOGADORES",
	UDim2.new(1, -36, 0, 22),
	UDim2.fromOffset(18, 193)
)
playersHeading.Font = Enum.Font.GothamBold
playersHeading.TextSize = 12

local playerList = Instance.new("ScrollingFrame")
playerList.Name = "PlayerList"
playerList.Size = UDim2.new(1, -36, 1, -264)
playerList.Position = UDim2.fromOffset(18, 218)
playerList.BackgroundColor3 = Color3.fromRGB(19, 21, 27)
playerList.BorderSizePixel = 0
playerList.CanvasSize = UDim2.fromOffset(0, 0)
playerList.ScrollBarThickness = 6
playerList.ScrollBarImageColor3 = Color3.fromRGB(104, 111, 132)
playerList.Parent = panel
corner(playerList, 7)

local listPadding = Instance.new("UIPadding")
listPadding.PaddingTop = UDim.new(0, 6)
listPadding.PaddingBottom = UDim.new(0, 6)
listPadding.PaddingLeft = UDim.new(0, 6)
listPadding.PaddingRight = UDim.new(0, 6)
listPadding.Parent = playerList

local listLayout = Instance.new("UIListLayout")
listLayout.Padding = UDim.new(0, 5)
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Parent = playerList

listLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
	playerList.CanvasSize = UDim2.fromOffset(
		0,
		listLayout.AbsoluteContentSize.Y + 12
	)
end)

local statusLabel = makeLabel(
	panel,
	"RoomStatus",
	"",
	UDim2.new(1, -210, 0, 25),
	UDim2.new(0, 18, 1, -35)
)
statusLabel.TextSize = 11
statusLabel.TextTruncate = Enum.TextTruncate.AtEnd

local leaveButton = makeButton(
	panel,
	"LeaveRoom",
	"Voltar ao Lobby",
	UDim2.fromOffset(160, 32),
	UDim2.new(1, -178, 1, -39),
	Color3.fromRGB(158, 51, 51)
)

-- Menu de contexto para moderação. Só é mostrado ao host.
local contextMenu = Instance.new("Frame")
contextMenu.Name = "PlayerContextMenu"
contextMenu.Size = UDim2.fromOffset(154, 124)
contextMenu.BackgroundColor3 = Color3.fromRGB(30, 33, 42)
contextMenu.BorderSizePixel = 0
contextMenu.Visible = false
contextMenu.ZIndex = 30
contextMenu.Parent = screenGui
corner(contextMenu, 7)
stroke(contextMenu, Color3.fromRGB(85, 92, 110))

local contextKickButton = makeButton(
	contextMenu,
	"KickPlayer",
	"Kick",
	UDim2.new(1, -8, 0, 32),
	UDim2.fromOffset(4, 4),
	Color3.fromRGB(173, 106, 43)
)
contextKickButton.ZIndex = 31

local contextBanButton = makeButton(
	contextMenu,
	"BanPlayer",
	"Banir",
	UDim2.new(1, -8, 0, 32),
	UDim2.fromOffset(4, 44),
	Color3.fromRGB(174, 57, 57)
)
contextBanButton.ZIndex = 31

local contextHostButton = makeButton(
	contextMenu,
	"TransferHost",
	"Transferir host",
	UDim2.new(1, -8, 0, 32),
	UDim2.fromOffset(4, 84),
	Color3.fromRGB(62, 112, 174)
)
contextHostButton.ZIndex = 31

local banConfirm = Instance.new("Frame")
banConfirm.Name = "BanConfirmation"
banConfirm.Size = UDim2.fromOffset(360, 145)
banConfirm.Position = UDim2.new(0.5, -180, 0.5, -72)
banConfirm.BackgroundColor3 = Color3.fromRGB(39, 31, 34)
banConfirm.BorderSizePixel = 0
banConfirm.Visible = false
banConfirm.ZIndex = 40
banConfirm.Parent = screenGui
corner(banConfirm, 9)
stroke(banConfirm, Color3.fromRGB(160, 70, 70))

local banConfirmText = makeLabel(
	banConfirm,
	"BanConfirmationText",
	"",
	UDim2.new(1, -28, 0, 70),
	UDim2.fromOffset(14, 8)
)
banConfirmText.TextWrapped = true
banConfirmText.ZIndex = 41

local cancelBanButton = makeButton(
	banConfirm,
	"CancelBan",
	"Cancelar",
	UDim2.fromOffset(130, 32),
	UDim2.new(0, 14, 1, -42),
	Color3.fromRGB(73, 77, 89)
)
cancelBanButton.ZIndex = 41

local confirmBanButton = makeButton(
	banConfirm,
	"ConfirmBan",
	"Confirmar ban",
	UDim2.fromOffset(166, 32),
	UDim2.new(1, -180, 1, -42),
	Color3.fromRGB(190, 57, 57)
)
confirmBanButton.ZIndex = 41

local currentState: RoomState? = nil
local contextTarget: PlayerInfo? = nil
local pendingBan: PlayerInfo? = nil
local draggingPlayer: PlayerInfo? = nil
local actionInFlight = false
local refreshQueued = false
local statusSequence = 0

local function setStatus(message: string, isError: boolean?)
	statusSequence += 1
	local sequence = statusSequence

	statusLabel.Text = message
	statusLabel.TextColor3 = if isError
		then Color3.fromRGB(255, 113, 113)
		else Color3.fromRGB(184, 190, 205)

	if message ~= "" then
		task.delay(4, function()
			if statusSequence == sequence then
				statusLabel.Text = ""
			end
		end)
	end
end

local function isLocalHost(): boolean
	return currentState ~= nil
		and currentState.HostUserId == LocalPlayer.UserId
end

local function parseMatchState(value: unknown): MatchState?
	if type(value) ~= "table" then
		return nil
	end

	local raw = value :: { [string]: unknown }

	if type(raw.Status) ~= "string"
		or type(raw.TimeLimit) ~= "number"
		or type(raw.ScoreLimit) ~= "number"
		or type(raw.ElapsedSeconds) ~= "number"
	then
		return nil
	end

	return {
		Status = raw.Status,
		TimeLimit = raw.TimeLimit,
		ScoreLimit = raw.ScoreLimit,
		ElapsedSeconds = raw.ElapsedSeconds,
		RemainingSeconds = if type(raw.RemainingSeconds) == "number"
			then raw.RemainingSeconds
			else nil,
	}
end

local function parsePlayerInfo(value: unknown): PlayerInfo?
	if type(value) ~= "table" then
		return nil
	end

	local raw = value :: { [string]: unknown }

	if type(raw.UserId) ~= "number"
		or type(raw.Name) ~= "string"
		or type(raw.IsHost) ~= "boolean"
	then
		return nil
	end

	local teamKey = raw.TeamKey
	if teamKey ~= "Team1"
		and teamKey ~= "Team2"
		and teamKey ~= "Spectators"
	then
		teamKey = "Spectators"
	end

	return {
		UserId = raw.UserId,
		Name = raw.Name,
		IsHost = raw.IsHost,
		JoinOrder = if type(raw.JoinOrder) == "number"
			then raw.JoinOrder
			else 0,
		TeamKey = teamKey :: string,
	}
end

local function parseRoomState(value: unknown): RoomState?
	if type(value) ~= "table" then
		return nil
	end

	local raw = value :: { [string]: unknown }

	if type(raw.RoomId) ~= "string"
		or type(raw.RoomCode) ~= "string"
		or type(raw.HostUserId) ~= "number"
		or type(raw.HostName) ~= "string"
		or type(raw.AllowHostMigration) ~= "boolean"
		or type(raw.Players) ~= "table"
	then
		return nil
	end

	local parsedPlayers: { PlayerInfo } = {}

	for _, item in ipairs(raw.Players :: { unknown }) do
		local playerInfo = parsePlayerInfo(item)
		if playerInfo then
			table.insert(parsedPlayers, playerInfo)
		end
	end

	table.sort(parsedPlayers, function(a: PlayerInfo, b: PlayerInfo)
		if a.JoinOrder == b.JoinOrder then
			return a.UserId < b.UserId
		end
		return a.JoinOrder < b.JoinOrder
	end)

	return {
		RoomId = raw.RoomId,
		RoomCode = raw.RoomCode,
		RoomName = if type(raw.RoomName) == "string"
			then raw.RoomName
			else "Sala",
		HostUserId = raw.HostUserId,
		HostName = raw.HostName,
		AllowHostMigration = raw.AllowHostMigration,
		Players = parsedPlayers,
		MatchState = parseMatchState(raw.MatchState),
	}
end

local function applyMatchState(value: unknown)
	local parsed = parseMatchState(value)
	if not parsed then
		return
	end

	if currentState then
		currentState.MatchState = parsed
	end

	timeInput.Text = tostring(parsed.TimeLimit)
	scoreInput.Text = tostring(parsed.ScoreLimit)

	local statusText = parsed.Status
	if statusText == "Running" then
		matchStatusLabel.Text = "Partida em andamento"
		startStopButton.Text = "Parar"
		pauseButton.Text = "Pausar"
	elseif statusText == "Paused" then
		matchStatusLabel.Text = "Partida pausada"
		startStopButton.Text = "Parar"
		pauseButton.Text = "Retomar"
	else
		matchStatusLabel.Text = "Partida parada"
		startStopButton.Text = "Iniciar"
		pauseButton.Text = "Pausar"
	end

	local host = isLocalHost()
	saveSettingsButton.Visible = host
	timeInput.TextEditable = host and parsed.Status == "Stopped"
	scoreInput.TextEditable = host and parsed.Status == "Stopped"

	startStopButton.Visible = host
	pauseButton.Visible = host
	saveSettingsButton.Active = host and parsed.Status == "Stopped"
end

local function renderPlayerList()
	for _, child in ipairs(playerList:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	local state = currentState
	if not state then
		return
	end

	local teamNames = {
		Spectators = "Espectadores",
		Team1 = tostring(TeamSettings.teams.Team1.name),
		Team2 = tostring(TeamSettings.teams.Team2.name),
	}

	local grouped: { [string]: { PlayerInfo } } = {
		Spectators = {},
		Team1 = {},
		Team2 = {},
	}

	for _, info in ipairs(state.Players) do
		table.insert(grouped[info.TeamKey], info)
	end

	local draggingEnabled = isLocalHost()
	local sectionOrder = 0

	for _, teamKey in ipairs({ "Spectators", "Team1", "Team2" }) do
		local members = grouped[teamKey]
		sectionOrder += 1

		local section = Instance.new("Frame")
		section.Name = "Group_" .. teamKey
		section.Size = UDim2.new(1, 0, 0, 32 + #members * 36)
		section.LayoutOrder = sectionOrder
		section.BackgroundTransparency = 1
		section.BorderSizePixel = 0
		section.Parent = playerList

		local header = Instance.new("TextLabel")
		header.Name = "Header"
		header.Size = UDim2.new(1, 0, 0, 28)
		header.BackgroundColor3 = Color3.fromRGB(35, 39, 49)
		header.BorderSizePixel = 0
		header.Text = string.format("  %s  (%d)", teamNames[teamKey], #members)
		header.TextColor3 = Color3.fromRGB(255, 213, 105)
		header.TextSize = 12
		header.TextXAlignment = Enum.TextXAlignment.Left
		header.Font = Enum.Font.GothamBold
		header.Parent = section
		corner(header, 5)

		for memberIndex, info in ipairs(members) do
			local row = Instance.new("Frame")
			row.Name = "Player_" .. tostring(info.UserId)
			row.Size = UDim2.new(1, 0, 0, 32)
			row.Position = UDim2.fromOffset(0, 32 + (memberIndex - 1) * 36)
			row.BackgroundColor3 = if info.UserId == LocalPlayer.UserId
				then Color3.fromRGB(64, 55, 35)
				else Color3.fromRGB(45, 49, 61)
			row.BorderSizePixel = 0
			row.Active = true
			row.Parent = section
			corner(row, 5)

			local nameLabel = Instance.new("TextLabel")
			nameLabel.Name = "PlayerName"
			nameLabel.Size = UDim2.new(1, -16, 1, 0)
			nameLabel.Position = UDim2.fromOffset(10, 0)
			nameLabel.BackgroundTransparency = 1
			nameLabel.Text = if info.IsHost
				then info.Name .. "  (Host)"
				else info.Name
			nameLabel.TextColor3 = if info.IsHost
				then Color3.fromRGB(255, 220, 112)
				else Color3.fromRGB(241, 243, 248)
			nameLabel.TextSize = 13
			nameLabel.TextXAlignment = Enum.TextXAlignment.Left
			nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
			nameLabel.Font = Enum.Font.GothamMedium
			nameLabel.Parent = row

			row.InputBegan:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseButton2 then
					if not isLocalHost()
						or actionInFlight
						or info.UserId == LocalPlayer.UserId
					then
						return
					end

					contextTarget = info
					draggingPlayer = nil

					local mouse = UserInputService:GetMouseLocation()
					local inset = GuiService:GetGuiInset()
					local camera = workspace.CurrentCamera
					local viewport = if camera
						then camera.ViewportSize
						else Vector2.new(800, 600)

					contextMenu.Position = UDim2.fromOffset(
						math.clamp(mouse.X - inset.X, 0, math.max(0, viewport.X - 154)),
						math.clamp(mouse.Y - inset.Y, 0, math.max(0, viewport.Y - 124))
					)
					contextMenu.Visible = true
					return
				end

				if input.UserInputType == Enum.UserInputType.MouseButton1
					and draggingEnabled
					and not actionInFlight
				then
					contextMenu.Visible = false
					contextTarget = nil
					draggingPlayer = info
				end
			end)
		end
	end
end

local function updateHostAccess()
	local host = isLocalHost()

	saveSettingsButton.Visible = host
	startStopButton.Visible = host
	pauseButton.Visible = host

	if not host then
		contextMenu.Visible = false
		banConfirm.Visible = false
		contextTarget = nil
		pendingBan = nil
		draggingPlayer = nil
	end

	if currentState and currentState.MatchState then
		applyMatchState(currentState.MatchState)
	end

	renderPlayerList()
end

local function applyRoomState(value: unknown)
	local parsed = parseRoomState(value)
	if not parsed then
		return
	end

	currentState = parsed
	title.Text = parsed.RoomName
	subtitle.Text = string.format(
		"Código: %s   •   Host: %s",
		parsed.RoomCode,
		parsed.HostName
	)

	updateHostAccess()
end

local function requestRoomState()
	local callOk, serverOk, value = pcall(function()
		return GetRoomManagementRF:InvokeServer()
	end)

	if not callOk then
		setStatus("Falha de conexão ao consultar a sala.", true)
		return
	end

	if serverOk ~= true then
		setStatus(
			if type(value) == "string" then value else "Não foi possível consultar a sala.",
			true
		)
		return
	end

	applyRoomState(value)
end

local function queueStateRefresh()
	if refreshQueued then
		return
	end

	refreshQueued = true
	task.delay(0.2, function()
		refreshQueued = false
		requestRoomState()
	end)
end

local function invokeMatchAction(
	action: string,
	timeLimit: number?,
	scoreLimit: number?
)
	if actionInFlight or not isLocalHost() then
		return
	end

	actionInFlight = true

	task.spawn(function()
		local callOk, serverOk, response = pcall(function()
			return MatchControlRequestRF:InvokeServer(
				action,
				timeLimit,
				scoreLimit
			)
		end)

		actionInFlight = false

		if not callOk then
			setStatus("Falha de conexão ao controlar a partida.", true)
			return
		end

		setStatus(
			if type(response) == "string" then response else "Comando processado.",
			serverOk ~= true
		)

		queueStateRefresh()
	end)
end

local function invokePlayerAction(
	remote: RemoteFunction,
	info: PlayerInfo,
	actionName: string
)
	if actionInFlight or not isLocalHost() then
		return
	end

	actionInFlight = true
	contextMenu.Visible = false

	task.spawn(function()
		local callOk, serverOk, response = pcall(function()
			return remote:InvokeServer(info.UserId)
		end)

		actionInFlight = false

		if not callOk then
			setStatus("Falha de conexão ao executar a ação.", true)
			return
		end

		setStatus(
			if type(response) == "string" then response else actionName .. " concluído.",
			serverOk ~= true
		)

		queueStateRefresh()
	end)
end

local function saveMatchSettings()
	if not isLocalHost() then
		return
	end

	local timeLimit = tonumber(timeInput.Text)
	local scoreLimit = tonumber(scoreInput.Text)

	if not timeLimit or not scoreLimit
		or timeLimit ~= math.floor(timeLimit)
		or scoreLimit ~= math.floor(scoreLimit)
		or timeLimit < 0 or timeLimit > 120
		or scoreLimit < 0 or scoreLimit > 99
	then
		setStatus("Time Limit: inteiro de 0 a 120. Score Limit: inteiro de 0 a 99.", true)
		return
	end

	invokeMatchAction("SetSettings", timeLimit, scoreLimit)
end

local function showBanConfirmation(info: PlayerInfo)
	if not isLocalHost() or actionInFlight then
		return
	end

	pendingBan = info
	banConfirmText.Text = string.format(
		"Banir %s? O jogador será enviado ao lobby e não poderá voltar a esta sala.",
		info.Name
	)
	banConfirm.Visible = true
	contextMenu.Visible = false
end

openButton.Activated:Connect(function()
	panel.Visible = not panel.Visible
	contextMenu.Visible = false

	if panel.Visible then
		requestRoomState()
	end
end)

closeButton.Activated:Connect(function()
	panel.Visible = false
	contextMenu.Visible = false
	banConfirm.Visible = false
end)

UserInputService.InputBegan:Connect(function(input)
	if input.KeyCode ~= Enum.KeyCode.Escape then
		return
	end

	if UserInputService:GetFocusedTextBox() ~= nil then
		return
	end

	panel.Visible = not panel.Visible
	contextMenu.Visible = false
	banConfirm.Visible = false

	if panel.Visible then
		requestRoomState()
	end
end)

saveSettingsButton.Activated:Connect(saveMatchSettings)

startStopButton.Activated:Connect(function()
	local state = currentState and currentState.MatchState
	if not state then
		requestRoomState()
		return
	end

	if state.Status == "Stopped" then
		invokeMatchAction("Start")
	else
		invokeMatchAction("Stop")
	end
end)

pauseButton.Activated:Connect(function()
	local state = currentState and currentState.MatchState
	if not state or state.Status == "Stopped" then
		setStatus("Inicie a partida antes de pausá-la.", true)
		return
	end

	invokeMatchAction("TogglePause")
end)

leaveButton.Activated:Connect(function()
	if actionInFlight then
		return
	end

	actionInFlight = true
	setStatus("Voltando ao lobby...")

	task.spawn(function()
		local callOk, success, response = pcall(function()
			return RoomController.LeaveRoom()
		end)

		actionInFlight = false

		if not callOk then
			setStatus("Falha de conexão ao sair da sala.", true)
			return
		end

		if success ~= true then
			setStatus(
				if type(response) == "string" then response else "Não foi possível sair da sala.",
				true
			)
		end
	end)
end)

cancelBanButton.Activated:Connect(function()
	banConfirm.Visible = false
	pendingBan = nil
end)

confirmBanButton.Activated:Connect(function()
	local info = pendingBan
	pendingBan = nil
	banConfirm.Visible = false

	if info then
		invokePlayerAction(BanPlayerRF, info, "Banir")
	end
end)

contextKickButton.Activated:Connect(function()
	local info = contextTarget
	contextTarget = nil

	if info then
		invokePlayerAction(KickPlayerRF, info, "Kick")
	end
end)

contextBanButton.Activated:Connect(function()
	local info = contextTarget
	contextTarget = nil

	if info then
		showBanConfirmation(info)
	end
end)

contextHostButton.Activated:Connect(function()
	local info = contextTarget
	contextTarget = nil

	if info then
		invokePlayerAction(TransferHostRF, info, "Transferir host")
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
		return
	end

	local info = draggingPlayer
	draggingPlayer = nil

	if not info or not isLocalHost() or actionInFlight then
		return
	end

	local mouse = UserInputService:GetMouseLocation()
	local inset = GuiService:GetGuiInset()
	mouse -= inset

	local targetTeam: string? = nil

	for _, child in ipairs(playerList:GetChildren()) do
		if not child:IsA("Frame") then
			continue
		end

		local teamKey = child.Name:gsub("^Group_", "")
		if teamKey ~= "Spectators"
			and teamKey ~= "Team1"
			and teamKey ~= "Team2"
		then
			continue
		end

		local position = child.AbsolutePosition
		local size = child.AbsoluteSize

		if mouse.X >= position.X
			and mouse.X <= position.X + size.X
			and mouse.Y >= position.Y
			and mouse.Y <= position.Y + size.Y
		then
			targetTeam = teamKey
			break
		end
	end

	if not targetTeam or targetTeam == info.TeamKey then
		return
	end

	actionInFlight = true

	task.spawn(function()
		local callOk, serverOk, response = pcall(function()
			return SetPlayerTeamRF:InvokeServer(info.UserId, targetTeam)
		end)

		actionInFlight = false

		if not callOk then
			setStatus("Falha de conexão ao alterar a equipe.", true)
		else
			setStatus(
				if type(response) == "string" then response else "Equipe atualizada.",
				serverOk ~= true
			)
		end

		queueStateRefresh()
	end)
end)

RoomManagementUpdatedRE.OnClientEvent:Connect(function(value: unknown)
	applyRoomState(value)
end)

MatchStateUpdatedRE.OnClientEvent:Connect(function(value: unknown)
	applyMatchState(value)
end)

Players.PlayerAdded:Connect(queueStateRefresh)
Players.PlayerRemoving:Connect(queueStateRefresh)

requestRoomState()
