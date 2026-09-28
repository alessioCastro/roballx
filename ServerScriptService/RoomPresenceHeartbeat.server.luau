--!strict
-- RoomPresenceHeartbeat.server.luau
--
-- Autoridade do servidor reservado para presenca, host, kick e ban. O lobby
-- somente inicia teletransportes; toda decisao de moderacao e tomada aqui.

local MemoryStoreService = game:GetService("MemoryStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")

local GAME_PLACE_ID = game.PlaceId
local RoomsMap = MemoryStoreService:GetSortedMap("GlobalRoomsList")
local RoomCodesMap = MemoryStoreService:GetHashMap("RoomCodesV1")

local HEARTBEAT_INTERVAL_SECONDS = 30
local ROOM_TTL_SECONDS = 120
local MAX_MEMORYSTORE_ATTEMPTS = 3

type BannedPlayers = { [string]: boolean }

type RoomRecord = {
	Id: string,
	RoomCode: string,
	CodeClaimToken: string,
	Name: string,
	HostName: string,
	HostUserId: number,
	MaxPlayers: number,
	Password: string?,
	IsVisible: boolean,
	AllowHostMigration: boolean,
	BannedPlayers: BannedPlayers,
	AccessCode: string,
	PrivateServerId: string?,
	PlayerCount: number,
	CreatedAt: number,
	LastHeartbeat: number,
}

type CodeIndexRecord = {
	RoomId: string,
	AccessCode: string,
	ClaimToken: string,
	LastHeartbeat: number,
}

type PlayerSummary = {
	UserId: number,
	Name: string,
	IsHost: boolean,
	JoinOrder: number,
}

local IS_ROOM_SERVER = game.PrivateServerId ~= "" and game.VIPServerOwnerId == 0
ReplicatedStorage:SetAttribute("IsRoomServer", IS_ROOM_SERVER)

if not IS_ROOM_SERVER then
	return
end

local roomRemotes = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("RoomRemotes")

local function getOrCreateRemoteFunction(name: string): RemoteFunction
	local existing = roomRemotes:FindFirstChild(name)
	if existing ~= nil then
		assert(existing:IsA("RemoteFunction"), (`{name} deve ser uma RemoteFunction.`))
		return existing
	end

	local remote = Instance.new("RemoteFunction")
	remote.Name = name
	remote.Parent = roomRemotes
	return remote
end

local function getOrCreateRemoteEvent(name: string): RemoteEvent
	local existing = roomRemotes:FindFirstChild(name)
	if existing ~= nil then
		assert(existing:IsA("RemoteEvent"), (`{name} deve ser uma RemoteEvent.`))
		return existing
	end

	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = roomRemotes
	return remote
end

-- RemoteFunctions retornam sucesso/erro ao menu do host. O evento atualiza os
-- clientes quando host, lotacao ou permissao de migracao mudarem.
local KickPlayerRF = getOrCreateRemoteFunction("KickPlayer")
local BanPlayerRF = getOrCreateRemoteFunction("BanPlayer")
local TransferHostRF = getOrCreateRemoteFunction("TransferHost")
local GetRoomManagementRF = getOrCreateRemoteFunction("GetRoomManagement")
local RoomManagementUpdatedRE = getOrCreateRemoteEvent("RoomManagementUpdated")

local function retryMemoryStore<T>(label: string, operation: () -> T): (boolean, T?)
	for attempt = 1, MAX_MEMORYSTORE_ATTEMPTS do
		local ok, result = pcall(operation)
		if ok then
			return true, result :: T
		end

		warn(("[RoomHeartbeat] %s falhou (tentativa %d/%d): %s"):format(
			label,
			attempt,
			MAX_MEMORYSTORE_ATTEMPTS,
			tostring(result)
		))
		if attempt < MAX_MEMORYSTORE_ATTEMPTS then
			task.wait(0.5 * (2 ^ (attempt - 1)))
		end
	end
	return false, nil
end

local function isRoomRecord(value: unknown): boolean
	return type(value) == "table"
		and type(value.Id) == "string"
		and type(value.RoomCode) == "string"
		and type(value.CodeClaimToken) == "string"
		and type(value.HostName) == "string"
		and type(value.HostUserId) == "number"
		and type(value.MaxPlayers) == "number"
		and type(value.AllowHostMigration) == "boolean"
		and type(value.BannedPlayers) == "table"
		and type(value.AccessCode) == "string"
		and type(value.PlayerCount) == "number"
		and type(value.CreatedAt) == "number"
end

local function isCodeIndexRecord(value: unknown): boolean
	return type(value) == "table"
		and type(value.RoomId) == "string"
		and type(value.AccessCode) == "string"
		and type(value.ClaimToken) == "string"
end

local function isPlayerBanned(room: RoomRecord, userId: number): boolean
	return room.BannedPlayers[tostring(userId)] == true
end

local activeRoom: RoomRecord? = nil
local joinOrderByUserId: { [number]: number } = {}
local nextJoinOrder = 0
local returningToLobby: { [number]: boolean } = {}
local roomIsClosing = false
local roomWasCleaned = false

local function getPlayerCount(): number
	local count = 0
	for _, player in ipairs(Players:GetPlayers()) do
		if not returningToLobby[player.UserId] then
			count += 1
		end
	end
	return count
end

local function getPlayerSummaries(): { PlayerSummary }
	local room = activeRoom
	if room == nil then
		return {}
	end

	local summaries: { PlayerSummary } = {}
	for _, player in ipairs(Players:GetPlayers()) do
		if not returningToLobby[player.UserId] then
			table.insert(summaries, {
				UserId = player.UserId,
				Name = player.Name,
				IsHost = player.UserId == room.HostUserId,
				-- Nunca envie math.huge pelo RemoteEvent: numeros infinitos nao sao
				-- serializaveis em todos os caminhos de replicacao do Roblox.
				JoinOrder = joinOrderByUserId[player.UserId] or 0,
			})
		end
	end
	table.sort(summaries, function(left: PlayerSummary, right: PlayerSummary): boolean
		if left.JoinOrder == right.JoinOrder then
			return left.UserId < right.UserId
		end
		return left.JoinOrder < right.JoinOrder
	end)
	return summaries
end

local function getManagementPayload(): { [string]: unknown }?
	local room = activeRoom
	if room == nil then
		return nil
	end
	return {
		RoomId = room.Id,
		RoomCode = room.RoomCode,
		HostUserId = room.HostUserId,
		HostName = room.HostName,
		AllowHostMigration = room.AllowHostMigration,
		Players = getPlayerSummaries(),
	}
end

local function broadcastManagementState()
	local payload = getManagementPayload()
	if payload ~= nil then
		RoomManagementUpdatedRE:FireAllClients(payload)
	end
end

local function loadRoomFromTeleportData(player: Player)
	if activeRoom ~= nil then
		return
	end

	local joinData = player:GetJoinData()
	local teleportData = joinData.TeleportData
	if type(teleportData) ~= "table" or type(teleportData.RoomId) ~= "string" then
		warn("[RoomHeartbeat] Jogador entrou no servidor reservado sem RoomId valido.")
		return
	end

	local readOk, roomValue = retryMemoryStore("carregar sala inicial", function()
		return RoomsMap:GetAsync(teleportData.RoomId)
	end)
	if not readOk or not isRoomRecord(roomValue) then
		warn("[RoomHeartbeat] Registro da sala nao encontrado; TTL nao pode ser renovado.")
		return
	end

	local room = roomValue :: RoomRecord
	if type(teleportData.RoomCode) == "string" and room.RoomCode ~= teleportData.RoomCode then
		warn("[RoomHeartbeat] RoomCode inconsistente no TeleportData.")
		return
	end
	activeRoom = room
end

-- playerCountOverride e usado em PlayerRemoving, quando o jogador que sai ainda
-- pode aparecer em Players:GetPlayers durante a execucao do sinal.
local function refreshRoomPresence(playerCountOverride: number?): boolean
	local room = activeRoom
	if room == nil or roomWasCleaned then
		return false
	end

	local now = os.time()
	room.PlayerCount = playerCountOverride or getPlayerCount()
	room.LastHeartbeat = now

	-- TTL fixo de 120 segundos: sem um novo heartbeat, a sala e o codigo somem.
	local roomOk = retryMemoryStore("renovar sala", function()
		local didSet = RoomsMap:SetAsync(room.Id, room, ROOM_TTL_SECONDS, room.CreatedAt)
		if not didSet then
			error("MemoryStoreSortedMap:SetAsync retornou false")
		end
	end)
	if not roomOk then
		return false
	end

	local freshIndex: CodeIndexRecord = {
		RoomId = room.Id,
		AccessCode = room.AccessCode,
		ClaimToken = room.CodeClaimToken,
		LastHeartbeat = now,
	}

	local codeOk, storedValue = retryMemoryStore("renovar codigo curto", function()
		return RoomCodesMap:UpdateAsync(room.RoomCode, function(previousValue: unknown): unknown
			if previousValue == nil then
				return freshIndex
			end
			if isCodeIndexRecord(previousValue) then
				local previous = previousValue :: CodeIndexRecord
				if previous.ClaimToken == room.CodeClaimToken then
					return freshIndex
				end
			end
			-- Nunca sobrescreve outro possivel dono de um codigo reutilizado.
			return previousValue
		end, ROOM_TTL_SECONDS)
	end)
	if not codeOk or not isCodeIndexRecord(storedValue) then
		warn("[RoomHeartbeat] Nao foi possivel renovar o indice de codigo.")
		return false
	end

	local storedIndex = storedValue :: CodeIndexRecord
	if storedIndex.ClaimToken ~= room.CodeClaimToken then
		warn("[RoomHeartbeat] Codigo curto pertence a outra sala; indice preservado.")
		return false
	end
	return true
end

local function removeActiveRoom()
	if roomWasCleaned then
		return
	end

	local room = activeRoom
	roomWasCleaned = true
	activeRoom = nil
	if room == nil then
		return
	end

	-- Em um fechamento normal a limpeza e imediata. Se o processo cair antes de
	-- terminar, o TTL renovado no ultimo heartbeat e o fallback de dois minutos.
	retryMemoryStore("remover sala ao fechar", function()
		RoomsMap:RemoveAsync(room.Id)
	end)

	local readOk, indexValue = retryMemoryStore("confirmar codigo ao fechar", function()
		return RoomCodesMap:GetAsync(room.RoomCode)
	end)
	if readOk and isCodeIndexRecord(indexValue) then
		local index = indexValue :: CodeIndexRecord
		if index.ClaimToken == room.CodeClaimToken then
			retryMemoryStore("remover codigo ao fechar", function()
				RoomCodesMap:RemoveAsync(room.RoomCode)
			end)
		end
	end
end

local function teleportPlayerToLobby(player: Player, action: string): (boolean, string)
	returningToLobby[player.UserId] = true
	local teleportOk, teleportError = pcall(function()
		TeleportService:TeleportAsync(GAME_PLACE_ID, { player })
	end)
	if teleportOk then
		return true, action
	end

	returningToLobby[player.UserId] = nil
	warn("[RoomHeartbeat] Falha ao enviar jogador ao lobby: " .. tostring(teleportError))
	return false, "Nao foi possivel enviar o jogador ao lobby."
end

local function closeRoomAndReturnToLobby(excludedUserId: number?)
	if roomIsClosing then
		return
	end
	roomIsClosing = true

	local remainingPlayers: { Player } = {}
	for _, player in ipairs(Players:GetPlayers()) do
		if player.UserId ~= excludedUserId then
			returningToLobby[player.UserId] = true
			table.insert(remainingPlayers, player)
		end
	end

	removeActiveRoom()
	if #remainingPlayers == 0 then
		return
	end

	local teleportOk, teleportError = pcall(function()
		TeleportService:TeleportAsync(GAME_PLACE_ID, remainingPlayers)
	end)
	if not teleportOk then
		warn("[RoomHeartbeat] Falha ao encerrar a sala: " .. tostring(teleportError))
		for _, player in ipairs(remainingPlayers) do
			returningToLobby[player.UserId] = nil
		end
	end
end

local function assignJoinOrder(player: Player)
	if joinOrderByUserId[player.UserId] == nil then
		nextJoinOrder += 1
		joinOrderByUserId[player.UserId] = nextJoinOrder
	end
end

local function chooseOldestRemainingPlayer(excludedUserId: number): Player?
	local oldest: Player? = nil
	local oldestOrder = math.huge
	for _, player in ipairs(Players:GetPlayers()) do
		if player.UserId ~= excludedUserId and not returningToLobby[player.UserId] then
			local order = joinOrderByUserId[player.UserId] or math.huge
			if oldest == nil or order < oldestOrder or (order == oldestOrder and player.UserId < oldest.UserId) then
				oldest = player
				oldestOrder = order
			end
		end
	end
	return oldest
end

local function transferHostTo(target: Player, playerCountOverride: number?, rollbackOnFailure: boolean): (boolean, string)
	local room = activeRoom
	if room == nil then
		return false, "Sala nao esta ativa."
	end

	local oldHostUserId = room.HostUserId
	local oldHostName = room.HostName
	room.HostUserId = target.UserId
	room.HostName = target.Name

	if not refreshRoomPresence(playerCountOverride) then
		if rollbackOnFailure then
			room.HostUserId = oldHostUserId
			room.HostName = oldHostName
		end
		return false, "Nao foi possivel salvar o novo host."
	end

	broadcastManagementState()
	return true, ("%s agora e o host."):format(target.Name)
end

local function validateHostRequest(requester: Player): (RoomRecord?, string?)
	local room = activeRoom
	if room == nil or roomIsClosing then
		return nil, "Sala nao esta ativa."
	end
	if requester.UserId ~= room.HostUserId then
		return nil, "Apenas o host pode usar esta acao."
	end
	return room, nil
end

local function validateTarget(targetUserId: unknown, hostUserId: number): (Player?, string?)
	if type(targetUserId) ~= "number" or targetUserId ~= math.floor(targetUserId) then
		return nil, "Jogador invalido."
	end
	if targetUserId == hostUserId then
		return nil, "O host nao pode selecionar a si mesmo."
	end

	local target = Players:GetPlayerByUserId(targetUserId)
	if target == nil or returningToLobby[target.UserId] then
		return nil, "Jogador nao esta mais na sala."
	end
	return target, nil
end

KickPlayerRF.OnServerInvoke = function(requester: Player, targetUserId: unknown): (boolean, string)
	local room, authorizationError = validateHostRequest(requester)
	if room == nil then
		return false, authorizationError or "Acao nao autorizada."
	end

	local target, targetError = validateTarget(targetUserId, room.HostUserId)
	if target == nil then
		return false, targetError or "Jogador invalido."
	end
	return teleportPlayerToLobby(target, "Jogador expulso para o lobby.")
end

BanPlayerRF.OnServerInvoke = function(requester: Player, targetUserId: unknown): (boolean, string)
	local room, authorizationError = validateHostRequest(requester)
	if room == nil then
		return false, authorizationError or "Acao nao autorizada."
	end

	local target, targetError = validateTarget(targetUserId, room.HostUserId)
	if target == nil then
		return false, targetError or "Jogador invalido."
	end

	local userIdKey = tostring(target.UserId)
	room.BannedPlayers[userIdKey] = true
	-- O ban e persistido antes do teleporte; assim uma tentativa de retorno pela
	-- lista ou pelo codigo curto ja sera bloqueada no lobby.
	if not refreshRoomPresence() then
		room.BannedPlayers[userIdKey] = nil
		return false, "Nao foi possivel salvar o banimento."
	end

	local teleportOk, teleportMessage = teleportPlayerToLobby(target, "Jogador banido e enviado ao lobby.")
	broadcastManagementState()
	if not teleportOk then
		return false, "Banimento salvo, mas o teleporte falhou: " .. teleportMessage
	end
	return true, teleportMessage
end

TransferHostRF.OnServerInvoke = function(requester: Player, targetUserId: unknown): (boolean, string)
	local room, authorizationError = validateHostRequest(requester)
	if room == nil then
		return false, authorizationError or "Acao nao autorizada."
	end

	local target, targetError = validateTarget(targetUserId, room.HostUserId)
	if target == nil then
		return false, targetError or "Jogador invalido."
	end
	return transferHostTo(target, nil, true)
end

GetRoomManagementRF.OnServerInvoke = function(player: Player): (boolean, unknown)
	local room = activeRoom
	if room == nil or returningToLobby[player.UserId] or isPlayerBanned(room, player.UserId) then
		return false, "Sala nao esta ativa para este jogador."
	end
	return true, getManagementPayload()
end

local function handlePlayerAdded(player: Player)
	loadRoomFromTeleportData(player)
	local room = activeRoom
	if room == nil then
		return
	end

	-- Defesa em profundidade: quem tentar usar um AccessCode obtido fora do fluxo
	-- do lobby e devolvido imediatamente, antes de participar da partida.
	if isPlayerBanned(room, player.UserId) then
		task.spawn(function()
			teleportPlayerToLobby(player, "Jogador banido devolvido ao lobby.")
		end)
		return
	end

	assignJoinOrder(player)
	refreshRoomPresence()
	broadcastManagementState()
end

-- Processa jogadores presentes caso o Script seja iniciado apos PlayerAdded.
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(handlePlayerAdded, player)
end

Players.PlayerAdded:Connect(handlePlayerAdded)

Players.PlayerRemoving:Connect(function(player: Player)
	local room = activeRoom
	local isReturning = returningToLobby[player.UserId] == true
	joinOrderByUserId[player.UserId] = nil
	returningToLobby[player.UserId] = nil

	if room == nil or roomIsClosing then
		return
	end

	if player.UserId == room.HostUserId and not isReturning then
		if room.AllowHostMigration then
			local nextHost = chooseOldestRemainingPlayer(player.UserId)
			if nextHost ~= nil then
				-- Nao fazemos rollback na migracao automatica: o host antigo ja saiu;
				-- o heartbeat seguinte tentara novamente se MemoryStore falhar agora.
				local migrated, migrationMessage = transferHostTo(nextHost, math.max(0, getPlayerCount() - 1), false)
				if not migrated then
					warn("[RoomHeartbeat] Migracao automatica pendente: " .. migrationMessage)
				end
				return
			end
			removeActiveRoom()
			return
		end

		-- Sem migracao autorizada, a saida do host encerra a sala para todos.
		closeRoomAndReturnToLobby(player.UserId)
		return
	end

	task.defer(function()
		if activeRoom == nil or roomIsClosing then
			return
		end
		if getPlayerCount() == 0 then
			removeActiveRoom()
		else
			refreshRoomPresence()
			broadcastManagementState()
		end
	end)
end)

game:BindToClose(removeActiveRoom)

-- Renovacao inicial e, depois, heartbeat fixo a cada 30 segundos.
task.spawn(function()
	refreshRoomPresence()
	while true do
		task.wait(HEARTBEAT_INTERVAL_SECONDS)
		refreshRoomPresence()
	end
end)
