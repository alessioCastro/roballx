--!strict
-- HostPanel.local.luau
-- Painel exclusivamente visual. O servidor continua sendo a autoridade para
-- kick, ban e transferencia de host; este cliente apenas solicita as acoes.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer

-- O mesmo lugar e usado para lobby e partidas. Nao criamos UI de moderacao no
-- lobby, nem esperamos os remotes exclusivos de uma partida nele.
local isRoomServer = ReplicatedStorage:GetAttribute("IsRoomServer")
if isRoomServer == nil then
	ReplicatedStorage:GetAttributeChangedSignal("IsRoomServer"):Wait()
	isRoomServer = ReplicatedStorage:GetAttribute("IsRoomServer")
end
if isRoomServer ~= true then
	return
end

type PlayerInfo = {
	UserId: number,
	Name: string,
	IsHost: boolean,
	JoinOrder: number,
	TeamKey: string,
}

type RoomManagementState = {
	RoomId: string,
	RoomCode: string,
	HostUserId: number,
	HostName: string,
	AllowHostMigration: boolean,
	Players: { PlayerInfo },
}

local roomRemotes = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("RoomRemotes")

-- O backend atual usa RemoteFunctions porque cada acao devolve sucesso/erro ao
-- host. RoomManagementUpdated e um RemoteEvent de atualizacao em tempo real.
local KickPlayerRF = roomRemotes:WaitForChild("KickPlayer") :: RemoteFunction
local BanPlayerRF = roomRemotes:WaitForChild("BanPlayer") :: RemoteFunction
local TransferHostRF = roomRemotes:WaitForChild("TransferHost") :: RemoteFunction
local GetRoomManagementRF = roomRemotes:WaitForChild("GetRoomManagement") :: RemoteFunction
local RoomManagementUpdatedRE = roomRemotes:WaitForChild("RoomManagementUpdated") :: RemoteEvent
local SetPlayerTeamRF = roomRemotes:WaitForChild("SetPlayerTeam") :: RemoteFunction

local playerGui = LocalPlayer:WaitForChild("PlayerGui")
local previousGui = playerGui:FindFirstChild("HostPanelGui")
if previousGui ~= nil then
	previousGui:Destroy()
end

local function addCorner(parent: Instance, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = parent
end

local function addStroke(parent: Instance, color: Color3)
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = 1
	stroke.Parent = parent
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "HostPanelGui"
screenGui.ResetOnSpawn = false
screenGui.DisplayOrder = 10
screenGui.Parent = playerGui

local openButton = Instance.new("TextButton")
openButton.Name = "OpenHostPanel"
openButton.Size = UDim2.fromOffset(138, 36)
openButton.Position = UDim2.new(1, -153, 0, 16)
openButton.BackgroundColor3 = Color3.fromRGB(236, 173, 44)
openButton.Text = "PAINEL DO HOST"
openButton.TextColor3 = Color3.fromRGB(28, 25, 19)
openButton.TextSize = 13
openButton.Font = Enum.Font.GothamBold
openButton.Visible = false
openButton.Parent = screenGui
addCorner(openButton, 7)
addStroke(openButton, Color3.fromRGB(255, 215, 100))

local panel = Instance.new("Frame")
panel.Name = "HostManagementPanel"
panel.Size = UDim2.fromOffset(490, 410)
panel.Position = UDim2.new(0.5, -245, 0.5, -205)
panel.BackgroundColor3 = Color3.fromRGB(25, 27, 34)
panel.BorderSizePixel = 0
panel.Visible = false
panel.Parent = screenGui
addCorner(panel, 10)
addStroke(panel, Color3.fromRGB(74, 80, 96))

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -54, 0, 46)
title.Position = UDim2.fromOffset(18, 0)
title.BackgroundTransparency = 1
title.Text = "PAINEL DO HOST"
title.TextColor3 = Color3.fromRGB(255, 255, 255)
title.TextSize = 18
title.TextXAlignment = Enum.TextXAlignment.Left
title.Font = Enum.Font.GothamBold
title.Parent = panel

local closeButton = Instance.new("TextButton")
closeButton.Size = UDim2.fromOffset(30, 30)
closeButton.Position = UDim2.new(1, -40, 0, 8)
closeButton.BackgroundColor3 = Color3.fromRGB(60, 64, 76)
closeButton.Text = "×"
closeButton.TextColor3 = Color3.fromRGB(235, 235, 235)
closeButton.TextSize = 22
closeButton.Font = Enum.Font.GothamBold
closeButton.Parent = panel
addCorner(closeButton, 6)

local subtitle = Instance.new("TextLabel")
subtitle.Size = UDim2.new(1, -36, 0, 30)
subtitle.Position = UDim2.fromOffset(18, 42)
subtitle.BackgroundTransparency = 1
subtitle.Text = "Gerencie os jogadores conectados à sala."
subtitle.TextColor3 = Color3.fromRGB(172, 178, 193)
subtitle.TextSize = 12
subtitle.TextXAlignment = Enum.TextXAlignment.Left
subtitle.Font = Enum.Font.Gotham
subtitle.Parent = panel

local playerList = Instance.new("ScrollingFrame")
playerList.Name = "PlayerList"
playerList.Size = UDim2.new(1, -36, 1, -132)
playerList.Position = UDim2.fromOffset(18, 80)
playerList.BackgroundColor3 = Color3.fromRGB(19, 21, 27)
playerList.BorderSizePixel = 0
playerList.CanvasSize = UDim2.fromOffset(0, 0)
playerList.ScrollBarThickness = 6
playerList.ScrollBarImageColor3 = Color3.fromRGB(104, 111, 132)
playerList.Parent = panel
addCorner(playerList, 7)

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
	playerList.CanvasSize = UDim2.fromOffset(0, listLayout.AbsoluteContentSize.Y + 12)
end)

local statusLabel = Instance.new("TextLabel")
statusLabel.Size = UDim2.new(1, -36, 0, 30)
statusLabel.Position = UDim2.new(0, 18, 1, -39)
statusLabel.BackgroundTransparency = 1
statusLabel.Text = ""
statusLabel.TextColor3 = Color3.fromRGB(184, 190, 205)
statusLabel.TextSize = 12
statusLabel.TextXAlignment = Enum.TextXAlignment.Left
statusLabel.TextTruncate = Enum.TextTruncate.AtEnd
statusLabel.Font = Enum.Font.Gotham
statusLabel.Parent = panel

-- Confirmacao pequena e modal para banimentos, evitando um clique irreversivel.
local banConfirm = Instance.new("Frame")
banConfirm.Name = "BanConfirmation"
banConfirm.Size = UDim2.fromOffset(370, 154)
banConfirm.Position = UDim2.new(0.5, -185, 0.5, -77)
banConfirm.BackgroundColor3 = Color3.fromRGB(39, 31, 34)
banConfirm.BorderSizePixel = 0
banConfirm.Visible = false
banConfirm.ZIndex = 20
banConfirm.Parent = screenGui
addCorner(banConfirm, 10)
addStroke(banConfirm, Color3.fromRGB(160, 70, 70))

local banConfirmText = Instance.new("TextLabel")
banConfirmText.Size = UDim2.new(1, -34, 0, 76)
banConfirmText.Position = UDim2.fromOffset(17, 14)
banConfirmText.BackgroundTransparency = 1
banConfirmText.Text = ""
banConfirmText.TextWrapped = true
banConfirmText.TextColor3 = Color3.fromRGB(255, 235, 235)
banConfirmText.TextSize = 14
banConfirmText.Font = Enum.Font.GothamMedium
banConfirmText.ZIndex = 21
banConfirmText.Parent = banConfirm

local cancelBanButton = Instance.new("TextButton")
cancelBanButton.Size = UDim2.fromOffset(142, 34)
cancelBanButton.Position = UDim2.new(0, 17, 1, -48)
cancelBanButton.BackgroundColor3 = Color3.fromRGB(73, 77, 89)
cancelBanButton.Text = "Cancelar"
cancelBanButton.TextColor3 = Color3.fromRGB(245, 245, 245)
cancelBanButton.TextSize = 13
cancelBanButton.Font = Enum.Font.GothamBold
cancelBanButton.ZIndex = 21
cancelBanButton.Parent = banConfirm
addCorner(cancelBanButton, 6)

local confirmBanButton = Instance.new("TextButton")
confirmBanButton.Size = UDim2.fromOffset(182, 34)
confirmBanButton.Position = UDim2.new(1, -199, 1, -48)
confirmBanButton.BackgroundColor3 = Color3.fromRGB(190, 57, 57)
confirmBanButton.Text = "Banir jogador"
confirmBanButton.TextColor3 = Color3.fromRGB(255, 255, 255)
confirmBanButton.TextSize = 13
confirmBanButton.Font = Enum.Font.GothamBold
confirmBanButton.ZIndex = 21
confirmBanButton.Parent = banConfirm
addCorner(confirmBanButton, 6)


local contextTarget: PlayerInfo? = nil

local contextMenu = Instance.new("Frame")
contextMenu.Name = "PlayerContextMenu"
contextMenu.Size = UDim2.fromOffset(150, 124)
contextMenu.BackgroundColor3 = Color3.fromRGB(30, 33, 42)
contextMenu.BorderSizePixel = 0
contextMenu.Visible = false
contextMenu.ZIndex = 30
contextMenu.Parent = screenGui
addCorner(contextMenu, 7)
addStroke(contextMenu, Color3.fromRGB(85, 92, 110))

local contextKickButton = Instance.new("TextButton")
contextKickButton.Size = UDim2.new(1, -8, 0, 34)
contextKickButton.Position = UDim2.fromOffset(4, 4)
contextKickButton.BackgroundColor3 = Color3.fromRGB(197, 121, 46)
contextKickButton.Text = "Kick"
contextKickButton.TextColor3 = Color3.new(1, 1, 1)
contextKickButton.TextSize = 13
contextKickButton.Font = Enum.Font.GothamBold
contextKickButton.ZIndex = 31
contextKickButton.Parent = contextMenu
addCorner(contextKickButton, 5)

local contextBanButton = Instance.new("TextButton")
contextBanButton.Size = UDim2.new(1, -8, 0, 34)
contextBanButton.Position = UDim2.fromOffset(4, 44)
contextBanButton.BackgroundColor3 = Color3.fromRGB(185, 62, 62)
contextBanButton.Text = "Ban"
contextBanButton.TextColor3 = Color3.new(1, 1, 1)
contextBanButton.TextSize = 13
contextBanButton.Font = Enum.Font.GothamBold
contextBanButton.ZIndex = 31
contextBanButton.Parent = contextMenu
addCorner(contextBanButton, 5)

local contextHostButton = Instance.new("TextButton")
contextHostButton.Size = UDim2.new(1, -8, 0, 34)
contextHostButton.Position = UDim2.fromOffset(4, 84)
contextHostButton.BackgroundColor3 = Color3.fromRGB(62, 128, 205)
contextHostButton.Text = "Dar Host"
contextHostButton.TextColor3 = Color3.new(1, 1, 1)
contextHostButton.TextSize = 13
contextHostButton.Font = Enum.Font.GothamBold
contextHostButton.ZIndex = 31
contextHostButton.Parent = contextMenu
addCorner(contextHostButton, 5)

local currentState: RoomManagementState? = nil
local pendingBan: PlayerInfo? = nil
local actionInFlight = false
local refreshQueued = false
local statusSequence = 0

local function setStatus(message: string, isError: boolean?)
	statusSequence += 1
	local sequence = statusSequence
	statusLabel.Text = message
	statusLabel.TextColor3 = if isError then Color3.fromRGB(255, 113, 113) else Color3.fromRGB(184, 190, 205)
	if message ~= "" then
		task.delay(4, function()
			if statusSequence == sequence then
				statusLabel.Text = ""
			end
		end)
	end
end

local function isLocalHost(): boolean
	return currentState ~= nil and currentState.HostUserId == LocalPlayer.UserId
end

local function parsePlayerInfo(value: unknown): PlayerInfo?
	if type(value) ~= "table" then
		return nil
	end
	local raw = value :: { [string]: unknown }
	if type(raw.UserId) ~= "number" or type(raw.Name) ~= "string" or type(raw.IsHost) ~= "boolean" then
		return nil
	end

	return {
		UserId = raw.UserId,
		Name = raw.Name,
		IsHost = raw.IsHost,
		JoinOrder = if type(raw.JoinOrder) == "number" then raw.JoinOrder else 0,
		TeamKey = if raw.TeamKey == "Team1"
			or raw.TeamKey == "Team2"
			or raw.TeamKey == "Spectators"
			then raw.TeamKey
			else "Spectators",
	}
end

local function parseManagementState(value: unknown): RoomManagementState?
	if type(value) ~= "table" then
		return nil
	end
	local raw = value :: { [string]: unknown }
	if type(raw.RoomId) ~= "string"
		or type(raw.RoomCode) ~= "string"
		or type(raw.HostUserId) ~= "number"
		or type(raw.HostName) ~= "string"
		or type(raw.AllowHostMigration) ~= "boolean"
		or type(raw.Players) ~= "table" then
		return nil
	end

	local playerInfos: { PlayerInfo } = {}
	for _, valueInList in ipairs(raw.Players :: { unknown }) do
		local playerInfo = parsePlayerInfo(valueInList)
		if playerInfo ~= nil then
			table.insert(playerInfos, playerInfo)
		end
	end
	table.sort(playerInfos, function(left: PlayerInfo, right: PlayerInfo): boolean
		if left.JoinOrder == right.JoinOrder then
			return left.UserId < right.UserId
		end
		return left.JoinOrder < right.JoinOrder
	end)

	return {
		RoomId = raw.RoomId,
		RoomCode = raw.RoomCode,
		HostUserId = raw.HostUserId,
		HostName = raw.HostName,
		AllowHostMigration = raw.AllowHostMigration,
		Players = playerInfos,
	}
end

local queueStateRefresh: () -> ()
local invokePlayerAction: (RemoteFunction, PlayerInfo, string) -> ()
local showBanConfirmation: (PlayerInfo) -> ()

local function createActionButton(parent: Instance, text: string, color: Color3, position: UDim2): TextButton
	local button = Instance.new("TextButton")
	button.Size = UDim2.fromOffset(64, 28)
	button.Position = position
	button.BackgroundColor3 = color
	button.Text = text
	button.TextColor3 = Color3.fromRGB(255, 255, 255)
	button.TextSize = 11
	button.Font = Enum.Font.GothamBold
	button.Parent = parent
	addCorner(button, 5)
	return button
end

local draggingPlayer: PlayerInfo? = nil

local function renderPlayerList()
	for _, child in ipairs(playerList:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	local state = currentState
	if state == nil or not isLocalHost() then
		return
	end

	local teamSettings = require(
		ReplicatedStorage:WaitForChild("Modules"):WaitForChild("TeamSettings")
	)

	local teamNames = {
		Spectators = "Espectadores",
		Team1 = tostring(teamSettings.teams.Team1.name),
		Team2 = tostring(teamSettings.teams.Team2.name),
	}

	local groupedPlayers: { [string]: { PlayerInfo } } = {
		Spectators = {},
		Team1 = {},
		Team2 = {},
	}

	for _, playerInfo in ipairs(state.Players) do
		local teamKey = playerInfo.TeamKey

		if groupedPlayers[teamKey] == nil then
			teamKey = "Spectators"
		end

		table.insert(groupedPlayers[teamKey], playerInfo)
	end

	local teamOrder = {
		"Spectators",
		"Team1",
		"Team2",
	}

	local sectionOrder = 0

	for _, teamKey in ipairs(teamOrder) do
		local members = groupedPlayers[teamKey]
		sectionOrder += 1

		local section = Instance.new("Frame")
		section.Name = "Group_" .. teamKey
		section.Size = UDim2.new(1, 0, 0, 32 + #members * 38)
		section.LayoutOrder = sectionOrder
		section.BackgroundTransparency = 1
		section.BorderSizePixel = 0
		section.Parent = playerList

		local header = Instance.new("TextLabel")
		header.Name = "Header"
		header.Size = UDim2.new(1, 0, 0, 28)
		header.Position = UDim2.fromOffset(0, 0)
		header.BackgroundColor3 = Color3.fromRGB(35, 39, 49)
		header.BorderSizePixel = 0
		header.Text = string.format(
			"  %s  (%d)",
			teamNames[teamKey],
			#members
		)
		header.TextColor3 = Color3.fromRGB(255, 213, 105)
		header.TextSize = 12
		header.TextXAlignment = Enum.TextXAlignment.Left
		header.Font = Enum.Font.GothamBold
		header.Parent = section
		addCorner(header, 5)

		for memberIndex, playerInfo in ipairs(members) do
			local row = Instance.new("Frame")
			row.Name = "Player_" .. tostring(playerInfo.UserId)
			row.Size = UDim2.new(1, 0, 0, 34)
			row.Position = UDim2.fromOffset(0, 32 + (memberIndex - 1) * 38)
			row.BackgroundColor3 =
				if playerInfo.UserId == LocalPlayer.UserId
				then Color3.fromRGB(64, 55, 35)
				else Color3.fromRGB(45, 49, 61)
			row.BorderSizePixel = 0
			row.Active = true
			row.Parent = section
			addCorner(row, 5)

			row.InputBegan:Connect(function(input)
				if not isLocalHost() or actionInFlight then
					return
				end

				if input.UserInputType == Enum.UserInputType.MouseButton2 then
					if playerInfo.UserId == LocalPlayer.UserId then
						return
					end

					contextTarget = playerInfo
					draggingPlayer = nil

					local mousePosition = UserInputService:GetMouseLocation()
					local topLeftInset = GuiService:GetGuiInset()
					local viewportSize = workspace.CurrentCamera.ViewportSize

					local x = mousePosition.X - topLeftInset.X
					local y = mousePosition.Y - topLeftInset.Y

					contextMenu.Position = UDim2.fromOffset(
						math.clamp(x, 0, math.max(0, viewportSize.X - 150)),
						math.clamp(y, 0, math.max(0, viewportSize.Y - 124))
					)
					contextMenu.Visible = true
					return
				end

				if input.UserInputType == Enum.UserInputType.MouseButton1 then
					contextMenu.Visible = false
					contextTarget = nil
					draggingPlayer = playerInfo
				end
			end)

			local name = Instance.new("TextLabel")
			name.Name = "PlayerName"
			name.Size = UDim2.new(1, -12, 1, 0)
			name.Position = UDim2.fromOffset(10, 0)
			name.BackgroundTransparency = 1
			name.Text =
				if playerInfo.UserId == LocalPlayer.UserId
				then playerInfo.Name .. "  (Você — Host)"
				elseif playerInfo.IsHost
				then playerInfo.Name .. "  (Host)"
				else playerInfo.Name
			name.TextColor3 =
				if playerInfo.UserId == LocalPlayer.UserId
				then Color3.fromRGB(255, 220, 112)
				else Color3.fromRGB(241, 243, 248)
			name.TextSize = 13
			name.TextXAlignment = Enum.TextXAlignment.Left
			name.TextTruncate = Enum.TextTruncate.AtEnd
			name.Font = Enum.Font.GothamMedium
			name.Parent = row
		end
	end
end

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
		return
	end

	local playerInfo = draggingPlayer
	draggingPlayer = nil

	if playerInfo == nil or not isLocalHost() or actionInFlight then
		return
	end

	local mousePosition = UserInputService:GetMouseLocation()
	local topLeftInset = GuiService:GetGuiInset()

	mousePosition -= topLeftInset

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

		local inside =
			mousePosition.X >= position.X
			and mousePosition.X <= position.X + size.X
			and mousePosition.Y >= position.Y
			and mousePosition.Y <= position.Y + size.Y

		if inside then
			targetTeam = teamKey
			break
		end
	end

	if targetTeam == nil or targetTeam == playerInfo.TeamKey then
		return
	end

	actionInFlight = true
	setStatus("Alterando equipe de " .. playerInfo.Name .. "...")

	task.spawn(function()
		local callOk, serverOk, response = pcall(function()
			return SetPlayerTeamRF:InvokeServer(
				playerInfo.UserId,
				targetTeam
			)
		end)

		actionInFlight = false

		if not callOk then
			setStatus("Falha de conexão ao alterar a equipe.", true)
			queueStateRefresh()
			return
		end

		local message =
			if type(response) == "string"
			then response
			else "Não foi possível alterar a equipe."

		if serverOk ~= true then
			setStatus(message, true)
		else
			setStatus(message)
		end

		queueStateRefresh()
	end)
end)

local function updateHostAccess()
	local localIsHost = isLocalHost()
	openButton.Visible = localIsHost
	if not localIsHost then
		-- A transferencia de host fecha tambem qualquer confirmacao pendente no
		-- cliente do host antigo, impedindo pedidos atrasados.
		panel.Visible = false
		banConfirm.Visible = false
		pendingBan = nil
		return
	end
	renderPlayerList()
end

local function applyManagementState(value: unknown)
	local parsedState = parseManagementState(value)
	if parsedState == nil then
		currentState = nil
		updateHostAccess()
		return
	end
	currentState = parsedState
	updateHostAccess()
end

local function requestManagementState()
	local callOk, serverOk, stateOrMessage = pcall(function()
		return GetRoomManagementRF:InvokeServer()
	end)
	if not callOk then
		setStatus("Falha de conexao ao consultar a sala.", true)
		return
	end
	if serverOk ~= true then
		currentState = nil
		updateHostAccess()
		return
	end
	applyManagementState(stateOrMessage)
end

queueStateRefresh = function()
	if refreshQueued then
		return
	end
	refreshQueued = true
	task.delay(0.2, function()
		refreshQueued = false
		requestManagementState()
	end)
end

invokePlayerAction = function(remote: RemoteFunction, playerInfo: PlayerInfo, actionName: string)
	if actionInFlight or not isLocalHost() then
		return
	end
	actionInFlight = true
	setStatus(actionName .. " em " .. playerInfo.Name .. "...")

	task.spawn(function()
		local callOk, serverOk, response = pcall(function()
			return remote:InvokeServer(playerInfo.UserId)
		end)
		actionInFlight = false

		if not callOk then
			setStatus("Falha de conexao ao executar a acao.", true)
			return
		end

		local message = if type(response) == "string" then response else "Acao concluida."
		if serverOk ~= true then
			setStatus(message, true)
			queueStateRefresh()
			return
		end

		setStatus(message)
		queueStateRefresh()
	end)
end

showBanConfirmation = function(playerInfo: PlayerInfo)
	if actionInFlight or not isLocalHost() then
		return
	end
	pendingBan = playerInfo
	banConfirmText.Text = ("Tem certeza que deseja banir %s?\nEle sera enviado ao lobby e nao podera voltar a esta sala."):format(playerInfo.Name)
	banConfirm.Visible = true
end

openButton.MouseButton1Click:Connect(function()
	if not isLocalHost() then
		return
	end
	panel.Visible = not panel.Visible
	contextMenu.Visible = false
	contextTarget = nil
	if panel.Visible then
		renderPlayerList()
		requestManagementState()
	end
end)

closeButton.MouseButton1Click:Connect(function()
	panel.Visible = false
	banConfirm.Visible = false
	pendingBan = nil
	contextMenu.Visible = false
	contextTarget = nil
end)

cancelBanButton.MouseButton1Click:Connect(function()
	banConfirm.Visible = false
	pendingBan = nil
end)

confirmBanButton.MouseButton1Click:Connect(function()
	local playerInfo = pendingBan
	banConfirm.Visible = false
	pendingBan = nil
	if playerInfo ~= nil then
		invokePlayerAction(BanPlayerRF, playerInfo, "Banir")
	end
end)

contextKickButton.MouseButton1Click:Connect(function()
	local playerInfo = contextTarget
	contextTarget = nil
	contextMenu.Visible = false

	if playerInfo ~= nil then
		invokePlayerAction(KickPlayerRF, playerInfo, "Kick")
	end
end)

contextBanButton.MouseButton1Click:Connect(function()
	local playerInfo = contextTarget
	contextTarget = nil
	contextMenu.Visible = false

	if playerInfo ~= nil then
		showBanConfirmation(playerInfo)
	end
end)

contextHostButton.MouseButton1Click:Connect(function()
	local playerInfo = contextTarget
	contextTarget = nil
	contextMenu.Visible = false

	if playerInfo ~= nil then
		invokePlayerAction(TransferHostRF, playerInfo, "Transferir host")
	end
end)

-- A fonte principal e o payload autoritativo do servidor. Os sinais locais sao
-- uma segunda via para atualizar a UI mesmo se o evento chegar antes deste
-- LocalScript terminar de iniciar.
RoomManagementUpdatedRE.OnClientEvent:Connect(function(state: unknown)
	applyManagementState(state)
end)

Players.PlayerAdded:Connect(function()
	queueStateRefresh()
end)

Players.PlayerRemoving:Connect(function()
	queueStateRefresh()
end)

requestManagementState()
