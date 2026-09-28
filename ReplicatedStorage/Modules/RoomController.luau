local ReplicatedStorage = game:GetService("ReplicatedStorage")
local replicatedRoomRemotes = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("RoomRemotes")

local CreateRoomRF = replicatedRoomRemotes:WaitForChild("CreateRoom")
local JoinRoomRF = replicatedRoomRemotes:WaitForChild("JoinRoom")
local LeaveRoomRF = replicatedRoomRemotes:WaitForChild("LeaveRoom")
local GetRoomsRF = replicatedRoomRemotes:WaitForChild("GetRooms")
local RoomListUpdatedRE = replicatedRoomRemotes:WaitForChild("RoomListUpdated")

local RoomController = {}
local isBusy = false

local function invokeWithTimeout(remote, ...)
	if isBusy then return false, "Aguarde a requisição anterior..." end
	isBusy = true

	local args = {...}
	local callSuccess, serverSuccess, result

	-- Safety timeout de 10 segundos caso a conexão caia no meio do Invoke
	task.delay(10, function()
		if isBusy then isBusy = false end
	end)

	callSuccess, serverSuccess, result = pcall(function()
		return remote:InvokeServer(unpack(args))
	end)

	isBusy = false

	if not callSuccess then
		return false, "Erro de conexão com o servidor."
	end

	return serverSuccess, result
end

function RoomController.CreateRoom(name, maxPlayers, password, isVisible)
	return invokeWithTimeout(CreateRoomRF, {
		Name = name,
		MaxPlayers = maxPlayers,
		Password = password,
		IsVisible = isVisible
	})
end

function RoomController.JoinRoom(roomId, password)
	return invokeWithTimeout(JoinRoomRF, roomId, password)
end

function RoomController.LeaveRoom()
	return invokeWithTimeout(LeaveRoomRF)
end

function RoomController.FetchRooms()
	local callSuccess, rooms = pcall(function()
		return GetRoomsRF:InvokeServer()
	end)

	if not callSuccess or type(rooms) ~= "table" then
		return {}
	end

	return rooms
end

RoomController.OnListUpdated = RoomListUpdatedRE.OnClientEvent

return RoomController