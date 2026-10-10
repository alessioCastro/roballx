local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local replicatedModules = ReplicatedStorage:WaitForChild("Modules")

local LocalPlayer = Players.LocalPlayer
local RoomController = require(replicatedModules:WaitForChild("RoomController"))

-- 1. AGUARDA DE FORMA RESILIENTE A REPLICAÇÃO DO ATRIBUTO
local inReservedServer = ReplicatedStorage:GetAttribute("IsRoomServer")
if inReservedServer == nil then
	ReplicatedStorage:GetAttributeChangedSignal("IsRoomServer"):Wait()
	inReservedServer = ReplicatedStorage:GetAttribute("IsRoomServer")
end

if inReservedServer == true then
	return
end

-- 2. ESTRUTURA BASE DA GUI
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "RoomSystemGui"
screenGui.ResetOnSpawn = false
screenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")

-- BOTÃO FLUTUANTE (Canto superior esquerdo) - Para abrir/fechar o menu sem poluir a tela
local btnToggleMenu = Instance.new("TextButton")
btnToggleMenu.Name = "ToggleMenuButton"
btnToggleMenu.Size = UDim2.new(0, 130, 0, 34)
btnToggleMenu.Position = UDim2.new(0, 15, 0, 15)
btnToggleMenu.BackgroundColor3 = Color3.fromRGB(35, 35, 42)
btnToggleMenu.Text = inReservedServer and "⚙️ Menu da Sala" or "📋 Lista de Salas"
btnToggleMenu.TextColor3 = Color3.fromRGB(255, 255, 255)
btnToggleMenu.Font = Enum.Font.SourceSansBold
btnToggleMenu.TextSize = 14
btnToggleMenu.Parent = screenGui
Instance.new("UICorner", btnToggleMenu).CornerRadius = UDim.new(0, 6)

local mainFrame = Instance.new("Frame")
mainFrame.Name = "MainFrame"
mainFrame.Size = UDim2.new(0, 500, 0, 380)
mainFrame.Position = UDim2.new(0.5, -250, 0.5, -190)
mainFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
mainFrame.BorderSizePixel = 0
-- Se estiver na SALA DE JOGO, inicia OCULTO para não atrapalhar a partida!
mainFrame.Visible = not inReservedServer 
mainFrame.Parent = screenGui
Instance.new("UICorner", mainFrame).CornerRadius = UDim.new(0, 8)

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, 0, 0, 40)
title.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
title.Text = inReservedServer and "SALA DE JOGO" or "LOBBY DE SALAS"
title.TextColor3 = Color3.fromRGB(255, 255, 255)
title.TextSize = 16
title.Font = Enum.Font.SourceSansBold
title.Parent = mainFrame
Instance.new("UICorner", title).CornerRadius = UDim.new(0, 8)

-- BOTÃO FECHAR (X) no topo do painel
local btnClose = Instance.new("TextButton")
btnClose.Size = UDim2.new(0, 28, 0, 28)
btnClose.Position = UDim2.new(1, -34, 0, 6)
btnClose.BackgroundColor3 = Color3.fromRGB(50, 50, 58)
btnClose.Text = "✕"
btnClose.TextColor3 = Color3.fromRGB(200, 200, 200)
btnClose.Font = Enum.Font.SourceSansBold
btnClose.TextSize = 14
btnClose.ZIndex = 3
btnClose.Parent = mainFrame
Instance.new("UICorner", btnClose).CornerRadius = UDim.new(0, 6)

local scroll = Instance.new("ScrollingFrame")
scroll.Size = UDim2.new(1, -20, 1, -100)
scroll.Position = UDim2.new(0, 10, 0, 50)
scroll.BackgroundColor3 = Color3.fromRGB(20, 20, 22)
scroll.BorderSizePixel = 0
scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
scroll.Visible = not inReservedServer
scroll.Parent = mainFrame

local listLayout = Instance.new("UIListLayout")
listLayout.Padding = UDim.new(0, 5)
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Parent = scroll

listLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
	scroll.CanvasSize = UDim2.new(0, 0, 0, listLayout.AbsoluteContentSize.Y)
end)

-- Botões Inferiores
local btnCreate = Instance.new("TextButton")
btnCreate.Size = UDim2.new(0, 120, 0, 35)
btnCreate.Position = UDim2.new(0, 10, 1, -42)
btnCreate.BackgroundColor3 = Color3.fromRGB(46, 125, 50)
btnCreate.Text = "Criar Sala"
btnCreate.TextColor3 = Color3.fromRGB(255, 255, 255)
btnCreate.Font = Enum.Font.SourceSansBold
btnCreate.TextSize = 15
btnCreate.Visible = not inReservedServer
btnCreate.Parent = mainFrame
Instance.new("UICorner", btnCreate).CornerRadius = UDim.new(0, 6)

local btnLeave = Instance.new("TextButton")
btnLeave.Size = UDim2.new(0, 140, 0, 35)
btnLeave.Position = UDim2.new(1, -150, 1, -42)
btnLeave.BackgroundColor3 = Color3.fromRGB(198, 40, 40)
btnLeave.Text = "Voltar ao Lobby"
btnLeave.TextColor3 = Color3.fromRGB(255, 255, 255)
btnLeave.Font = Enum.Font.SourceSansBold
btnLeave.TextSize = 15
btnLeave.Visible = inReservedServer
btnLeave.Parent = mainFrame
Instance.new("UICorner", btnLeave).CornerRadius = UDim.new(0, 6)

local statusLabel = Instance.new("TextLabel")
statusLabel.Size = UDim2.new(0, 210, 0, 35)
statusLabel.Position = UDim2.new(0, 140, 1, -42)
statusLabel.BackgroundTransparency = 1
statusLabel.Text = inReservedServer and "Status: Em Partida" or "Status: No Lobby"
statusLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
statusLabel.Font = Enum.Font.SourceSans
statusLabel.TextSize = 14
statusLabel.Parent = mainFrame

local function setStatusError(message)
	statusLabel.TextColor3 = Color3.fromRGB(255, 85, 85)
	statusLabel.Text = message
	task.delay(4, function()
		if statusLabel.Text == message then
			statusLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
			statusLabel.Text = inReservedServer and "Status: Em Partida" or "Status: No Lobby"
		end
	end)
end

if inReservedServer then
	local roomMsg = Instance.new("TextLabel")
	roomMsg.Size = UDim2.new(1, -40, 0, 80)
	roomMsg.Position = UDim2.new(0, 20, 0.35, 0)
	roomMsg.BackgroundTransparency = 1
	roomMsg.Text = "Você está em uma sala privada reservada.\nPara voltar ao menu principal, clique abaixo."
	roomMsg.TextColor3 = Color3.fromRGB(200, 200, 200)
	roomMsg.Font = Enum.Font.SourceSans
	roomMsg.TextSize = 16
	roomMsg.Parent = mainFrame
end

-- 3. MODAIS (Lobby)
local createModal = Instance.new("Frame")
createModal.Size = UDim2.new(0, 280, 0, 230)
createModal.Position = UDim2.new(0.5, -140, 0.5, -115)
createModal.BackgroundColor3 = Color3.fromRGB(40, 40, 45)
createModal.Visible = false
createModal.ZIndex = 5
createModal.Parent = screenGui
Instance.new("UICorner", createModal).CornerRadius = UDim.new(0, 8)

local inputName = Instance.new("TextBox")
inputName.Size = UDim2.new(0.9, 0, 0, 30)
inputName.Position = UDim2.new(0.05, 0, 0.08, 0)
inputName.PlaceholderText = "Nome da Sala"
inputName.Text = ""
inputName.ZIndex = 6
inputName.Parent = createModal

local inputMax = Instance.new("TextBox")
inputMax.Size = UDim2.new(0.9, 0, 0, 30)
inputMax.Position = UDim2.new(0.05, 0, 0.26, 0)
inputMax.PlaceholderText = "Max Jogadores (2 - 12)"
inputMax.Text = "4"
inputMax.ZIndex = 6
inputMax.Parent = createModal

local inputPass = Instance.new("TextBox")
inputPass.Size = UDim2.new(0.9, 0, 0, 30)
inputPass.Position = UDim2.new(0.05, 0, 0.44, 0)
inputPass.PlaceholderText = "Senha (Opcional)"
inputPass.Text = ""
inputPass.ZIndex = 6
inputPass.Parent = createModal

local toggleVisible = Instance.new("TextButton")
toggleVisible.Size = UDim2.new(0.9, 0, 0, 30)
toggleVisible.Position = UDim2.new(0.05, 0, 0.62, 0)
toggleVisible.Text = "Visível na Lista: SIM"
toggleVisible.BackgroundColor3 = Color3.fromRGB(60, 60, 70)
toggleVisible.TextColor3 = Color3.fromRGB(255, 255, 255)
toggleVisible.ZIndex = 6
toggleVisible.Parent = createModal

local isVisibleValue = true
toggleVisible.MouseButton1Click:Connect(function()
	isVisibleValue = not isVisibleValue
	toggleVisible.Text = "Visível na Lista: " .. (isVisibleValue and "SIM" or "NÃO")
end)

local btnConfirmCreate = Instance.new("TextButton")
btnConfirmCreate.Size = UDim2.new(0.42, 0, 0, 30)
btnConfirmCreate.Position = UDim2.new(0.05, 0, 0.82, 0)
btnConfirmCreate.BackgroundColor3 = Color3.fromRGB(46, 125, 50)
btnConfirmCreate.Text = "Confirmar"
btnConfirmCreate.TextColor3 = Color3.fromRGB(255, 255, 255)
btnConfirmCreate.ZIndex = 6
btnConfirmCreate.Parent = createModal

local btnCancelCreate = Instance.new("TextButton")
btnCancelCreate.Size = UDim2.new(0.42, 0, 0, 30)
btnCancelCreate.Position = UDim2.new(0.53, 0, 0.82, 0)
btnCancelCreate.BackgroundColor3 = Color3.fromRGB(198, 40, 40)
btnCancelCreate.Text = "Cancelar"
btnCancelCreate.TextColor3 = Color3.fromRGB(255, 255, 255)
btnCancelCreate.ZIndex = 6
btnCancelCreate.Parent = createModal

local passModal = Instance.new("Frame")
passModal.Size = UDim2.new(0, 260, 0, 130)
passModal.Position = UDim2.new(0.5, -130, 0.5, -65)
passModal.BackgroundColor3 = Color3.fromRGB(40, 40, 45)
passModal.Visible = false
passModal.ZIndex = 5
passModal.Parent = screenGui
Instance.new("UICorner", passModal).CornerRadius = UDim.new(0, 8)

local inputJoinPass = Instance.new("TextBox")
inputJoinPass.Size = UDim2.new(0.9, 0, 0, 35)
inputJoinPass.Position = UDim2.new(0.05, 0, 0.15, 0)
inputJoinPass.PlaceholderText = "Digite a Senha da Sala"
inputJoinPass.Text = ""
inputJoinPass.ZIndex = 6
inputJoinPass.Parent = passModal

local btnConfirmJoin = Instance.new("TextButton")
btnConfirmJoin.Size = UDim2.new(0.42, 0, 0, 30)
btnConfirmJoin.Position = UDim2.new(0.05, 0, 0.6, 0)
btnConfirmJoin.BackgroundColor3 = Color3.fromRGB(46, 125, 50)
btnConfirmJoin.Text = "Entrar"
btnConfirmJoin.TextColor3 = Color3.fromRGB(255, 255, 255)
btnConfirmJoin.ZIndex = 6
btnConfirmJoin.Parent = passModal

local btnCancelJoin = Instance.new("TextButton")
btnCancelJoin.Size = UDim2.new(0.42, 0, 0, 30)
btnCancelJoin.Position = UDim2.new(0.53, 0, 0.6, 0)
btnCancelJoin.BackgroundColor3 = Color3.fromRGB(198, 40, 40)
btnCancelJoin.Text = "Cancelar"
btnCancelJoin.TextColor3 = Color3.fromRGB(255, 255, 255)
btnCancelJoin.ZIndex = 6
btnCancelJoin.Parent = passModal

local selectedRoomId = nil

-- 4. RENDERIZAÇÃO
local function renderRoomList(rooms)
	if inReservedServer then return end

	for _, child in ipairs(scroll:GetChildren()) do
		if child:IsA("Frame") then child:Destroy() end
	end

	for _, room in ipairs(rooms) do
		local item = Instance.new("Frame")
		item.Size = UDim2.new(1, 0, 0, 35)
		item.BackgroundColor3 = Color3.fromRGB(45, 45, 50)
		item.Parent = scroll
		Instance.new("UICorner", item).CornerRadius = UDim.new(0, 4)

		local info = Instance.new("TextLabel")
		info.Size = UDim2.new(0.7, 0, 1, 0)
		info.Position = UDim2.new(0, 10, 0, 0)
		info.BackgroundTransparency = 1
		info.TextColor3 = Color3.fromRGB(255, 255, 255)
		info.TextXAlignment = Enum.TextXAlignment.Left
		info.Font = Enum.Font.SourceSans
		info.TextSize = 14

		local lockIcon = room.HasPassword and " [🔒]" or ""
		info.Text = string.format("%s (%s)%s - %d/%d", room.Name, room.HostName, lockIcon, room.PlayerCount, room.MaxPlayers)
		info.Parent = item

		local btnJoin = Instance.new("TextButton")
		btnJoin.Size = UDim2.new(0.22, -5, 0.7, 0)
		btnJoin.Position = UDim2.new(0.78, 0, 0.15, 0)
		btnJoin.BackgroundColor3 = Color3.fromRGB(25, 118, 210)
		btnJoin.Text = "Entrar"
		btnJoin.TextColor3 = Color3.fromRGB(255, 255, 255)
		btnJoin.Font = Enum.Font.SourceSansBold
		btnJoin.TextSize = 13
		btnJoin.Parent = item
		Instance.new("UICorner", btnJoin).CornerRadius = UDim.new(0, 4)

		btnJoin.MouseButton1Click:Connect(function()
			if room.HasPassword then
				selectedRoomId = room.Id
				inputJoinPass.Text = ""
				passModal.Visible = true
			else
				statusLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
				statusLabel.Text = "Status: Teleportando..."
				local ok, err = RoomController.JoinRoom(room.Id, "")
				if not ok then
					setStatusError(err or "Falha ao entrar na sala.")
				end
			end
		end)
	end
end

-- 5. CONTROLE DE ABRIR/FECHAR MENU
btnToggleMenu.MouseButton1Click:Connect(function()
	mainFrame.Visible = not mainFrame.Visible
end)

btnClose.MouseButton1Click:Connect(function()
	mainFrame.Visible = false
end)

-- 6. EVENTOS E CONEXÕES DE UI
btnCreate.MouseButton1Click:Connect(function() createModal.Visible = true end)
btnCancelCreate.MouseButton1Click:Connect(function() createModal.Visible = false end)

btnConfirmCreate.MouseButton1Click:Connect(function()
	local name = inputName.Text
	local maxP = tonumber(inputMax.Text) or 4
	local pass = inputPass.Text

	statusLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
	statusLabel.Text = "Status: Criando sala..."
	createModal.Visible = false

	local ok, res = RoomController.CreateRoom(name, maxP, pass, isVisibleValue)
	if not ok then
		setStatusError(typeof(res) == "string" and res or "Erro ao criar sala.")
	end
end)

btnCancelJoin.MouseButton1Click:Connect(function()
	passModal.Visible = false
	selectedRoomId = nil
end)

btnConfirmJoin.MouseButton1Click:Connect(function()
	if not selectedRoomId then return end
	passModal.Visible = false
	statusLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
	statusLabel.Text = "Status: Teleportando..."

	local ok, err = RoomController.JoinRoom(selectedRoomId, inputJoinPass.Text)
	if not ok then
		setStatusError(err or "Erro de senha/conexão.")
	end
end)

btnLeave.MouseButton1Click:Connect(function()
	statusLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
	statusLabel.Text = "Status: Voltando ao Lobby..."
	local ok, err = RoomController.LeaveRoom()
	if not ok then
		setStatusError(err or "Erro ao sair da sala.")
	end
end)

if not inReservedServer then
	RoomController.OnListUpdated:Connect(renderRoomList)
	task.spawn(function()
		local rooms = RoomController.FetchRooms()
		if rooms then renderRoomList(rooms) end
	end)
end
