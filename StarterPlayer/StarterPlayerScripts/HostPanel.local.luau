--!strict
-- HostPanel.local.luau
-- Painel exclusivamente visual. O servidor continua sendo a autoridade para
-- kick, ban e transferencia de host; este cliente apenas solicita as acoes.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

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

	for index, playerInfo in ipairs(state.Players) do
		local row = Instance.new("Frame")
		row.Name = "Player_" .. tostring(playerInfo.UserId)
		row.Size = UDim2.new(1, 0, 0, 38)
		row.LayoutOrder = index
		row.BackgroundColor3 = if playerInfo.UserId == LocalPlayer.UserId
			then Color3.fromRGB(52, 48, 35)
			else Color3.fromRGB(45, 49, 61)
		row.BorderSizePixel = 0
		row.Parent = playerList
		addCorner(row, 5)

		local name = Instance.new("TextLabel")
		name.Size = if playerInfo.UserId == LocalPlayer.UserId
			then UDim2.new(1, -20, 1, 0)
			else UDim2.new(1, -218, 1, 0)
		name.Position = UDim2.fromOffset(10, 0)
		name.BackgroundTransparency = 1
		name.Text = if playerInfo.UserId == LocalPlayer.UserId
			then (playerInfo.Name .. "  (Você — Host)")
			elseif playerInfo.IsHost then (playerInfo.Name .. "  (Host)")
			else playerInfo.Name
		name.TextColor3 = if playerInfo.UserId == LocalPlayer.UserId
			then Color3.fromRGB(255, 220, 112)
			else Color3.fromRGB(241, 243, 248)
		name.TextSize = 13
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.TextTruncate = Enum.TextTruncate.AtEnd
		name.Font = Enum.Font.GothamMedium
		name.Parent = row

		-- O proprio host nunca recebe botoes de acao, mesmo se a lista chegar com
		-- estado defasado durante uma transferencia.
		if playerInfo.UserId ~= LocalPlayer.UserId then
			local kickButton = createActionButton(row, "Kick", Color3.fromRGB(197, 121, 46), UDim2.new(1, -202, 0.5, -14))
			local banButton = createActionButton(row, "Ban", Color3.fromRGB(185, 62, 62), UDim2.new(1, -134, 0.5, -14))
			local hostButton = createActionButton(row, "Dar Host", Color3.fromRGB(62, 128, 205), UDim2.new(1, -66, 0.5, -14))

			kickButton.MouseButton1Click:Connect(function()
				invokePlayerAction(KickPlayerRF, playerInfo, "Kick")
			end)
			banButton.MouseButton1Click:Connect(function()
				showBanConfirmation(playerInfo)
			end)
			hostButton.MouseButton1Click:Connect(function()
				invokePlayerAction(TransferHostRF, playerInfo, "Transferir host")
			end)
		end
	end
end

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
	if panel.Visible then
		renderPlayerList()
		requestManagementState()
	end
end)

closeButton.MouseButton1Click:Connect(function()
	panel.Visible = false
	banConfirm.Visible = false
	pendingBan = nil
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
