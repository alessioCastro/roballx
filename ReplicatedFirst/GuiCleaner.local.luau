local Players = game:GetService("Players")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
playerGui:WaitForChild("Freecam"):Destroy()

local StarterGui = game:GetService("StarterGui")

-- Oculta elementos comuns do CoreGui
StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, false)

-- Aguarda até que o registrador de comandos da Roblox esteja pronto para desativar o Reset
local function setCoreWithRetry(coreName, value)
	task.spawn(function()
		while true do
			local success = pcall(StarterGui.SetCore, StarterGui, coreName, value)
			if success then break end
			task.wait(0.1)
		end
	end)
end

-- Desativa o botão de regenerar
setCoreWithRetry("ResetButtonCallback", false)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local inReservedServer = ReplicatedStorage:GetAttribute("IsRoomServer")
if inReservedServer == nil then
	ReplicatedStorage:GetAttributeChangedSignal("IsRoomServer"):Wait()
	inReservedServer = ReplicatedStorage:GetAttribute("IsRoomServer")
end

local Workspace = game:GetService("Workspace")
local camera = Workspace.CurrentCamera

local x, y, z = 0, 0, 2000
local rotX, rotY, rotZ = 0, 0, 0 -- Rotação em graus

camera.FieldOfView = 1
camera.CFrame = CFrame.new(x, y, z) * CFrame.Angles(math.rad(rotX), math.rad(rotY), math.rad(rotZ))

--[[local function createCornerPart()
	-- 1. Definir tamanho da Part na proporção 16:9 (Largura, Altura, Espessura)
	local width = 0.1
	local height = 0.056 -- 8 / (16/9) = 4.5
	local depth = 0.01

	local part = Instance.new("Part")
	part.Size = Vector3.new(width, height, depth)
	part.Anchored = true
	part.CanCollide = false
	part.Transparency = 1
	part.CastShadow = false
	
	local x, y, z = -0.435, 0.3, 0
	local rotX, rotY, rotZ = 0, 0, 0 -- Rotação em graus

	-- CFrame.Angles exige radianos, por isso usamos math.rad()
	part.CFrame = CFrame.new(x, y, z) * CFrame.Angles(
		math.rad(rotX),
		math.rad(rotY),
		math.rad(rotZ)
	)

	local adGui = Instance.new("AdGui")
	adGui.Adornee = part
	adGui.Parent = part
	
	part.Parent = Workspace
end

createCornerPart()]]

if inReservedServer then
	-- Ativa o chat
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Chat, true)
end