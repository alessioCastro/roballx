--!strict
-- RoomServerManager.server.luau
-- Executa tanto no lobby quanto no servidor reservado. O heartbeat que renova
-- o TTL e mantido no script RoomPresenceHeartbeat.server.luau.

local HttpService = game:GetService("HttpService")
local MemoryStoreService = game:GetService("MemoryStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")
local TextService = game:GetService("TextService")

local GAME_PLACE_ID = game.PlaceId
local RoomsMap = MemoryStoreService:GetSortedMap("GlobalRoomsList")
local RoomCodesMap = MemoryStoreService:GetHashMap("RoomCodesV1")

-- Os dois scripts usam estas mesmas constantes. O TTL e renovado a cada 30 s.
local ROOM_TTL_SECONDS = 120
local MAX_MEMORYSTORE_ATTEMPTS = 3
local SHORT_CODE_ATTEMPTS = 20
local SHORT_CODE_ALPHABET = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"
local random = Random.new()

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
	-- UserIds sao strings para que a tabela seja um dicionario serializavel no
	-- MemoryStore. A presenca da chave significa que o jogador esta banido.
	BannedPlayers: { [string]: boolean },
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

type CreateRoomConfig = {
	Name: unknown,
	MaxPlayers: unknown,
	Password: unknown,
	IsVisible: unknown,
	AllowHostMigration: unknown,
}

local replicatedRoomRemotes = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("RoomRemotes")

local CreateRoomRF = replicatedRoomRemotes:WaitForChild("CreateRoom") :: RemoteFunction
local JoinRoomRF = replicatedRoomRemotes:WaitForChild("JoinRoom") :: RemoteFunction
local LeaveRoomRF = replicatedRoomRemotes:WaitForChild("LeaveRoom") :: RemoteFunction
local GetRoomsRF = replicatedRoomRemotes:WaitForChild("GetRooms") :: RemoteFunction
local RoomListUpdatedRE = replicatedRoomRemotes:WaitForChild("RoomListUpdated") :: RemoteEvent
local ResolveRoomCodeRF = replicatedRoomRemotes:WaitForChild("ResolveRoomCode") :: RemoteFunction
local JoinRoomByCodeRF = replicatedRoomRemotes:WaitForChild("JoinRoomByCode") :: RemoteFunction

-- ReserveServerAsync cria PrivateServerId sem owner; um VIP server tem owner.
local IS_ROOM_SERVER = game.PrivateServerId ~= "" and game.VIPServerOwnerId == 0
ReplicatedStorage:SetAttribute("IsRoomServer", IS_ROOM_SERVER)

local function retryMemoryStore<T>(label: string, operation: () -> T): (boolean, T?)
	for attempt = 1, MAX_MEMORYSTORE_ATTEMPTS do
		local ok, result = pcall(operation)
		if ok then
			return true, result :: T
		end

		warn(("[RoomSystem] %s falhou (tentativa %d/%d): %s"):format(
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

local function filterRoomName(rawName: string, player: Player): string
	local ok, filteredOrError = pcall(function(): string
		local result = TextService:FilterStringAsync(rawName, player.UserId)
		return result:GetNonChatStringForBroadcastAsync()
	end)
	if ok and type(filteredOrError) == "string" and #filteredOrError > 0 then
		return filteredOrError
	end

	warn("[RoomSystem] Nao foi possivel filtrar nome: " .. tostring(filteredOrError))
	return "Sala de Jogo"
end

local function normalizeRoomCode(value: unknown): string?
	if type(value) ~= "string" then
		return nil
	end

	local normalized = string.upper((value:gsub("%s+", "")))
	if #normalized < 5 or #normalized > 6 or not string.match(normalized, "^[A-Z0-9]+$") then
		return nil
	end
	return normalized
end

local function generateCandidateCode(): string
	local length = random:NextInteger(5, 6)
	local characters: { string } = table.create(length)
	for position = 1, length do
		local index = random:NextInteger(1, #SHORT_CODE_ALPHABET)
		characters[position] = string.sub(SHORT_CODE_ALPHABET, index, index)
	end
	return table.concat(characters)
end

local function isRoomRecord(value: unknown): boolean
	return type(value) == "table"
		and type(value.Id) == "string"
		and type(value.RoomCode) == "string"
		and type(value.CodeClaimToken) == "string"
		and type(value.Name) == "string"
		and type(value.HostName) == "string"
		and type(value.HostUserId) == "number"
		and type(value.MaxPlayers) == "number"
		and type(value.IsVisible) == "boolean"
		and type(value.AllowHostMigration) == "boolean"
		and type(value.BannedPlayers) == "table"
		and type(value.AccessCode) == "string"
		and type(value.PlayerCount) == "number"
end

local function isPlayerBanned(room: RoomRecord, userId: number): boolean
	return room.BannedPlayers[tostring(userId)] == true
end

local function isCodeIndexRecord(value: unknown): boolean
	return type(value) == "table"
		and type(value.RoomId) == "string"
		and type(value.AccessCode) == "string"
		and type(value.ClaimToken) == "string"
end

-- Reivindicacao atomica: dois lobbies nao conseguem registrar o mesmo codigo.
local function claimUniqueShortCode(roomId: string, accessCode: string): (string?, string?)
	for _ = 1, SHORT_CODE_ATTEMPTS do
		local candidate = generateCandidateCode()
		local claimToken = HttpService:GenerateGUID(false)
		local codeRecord: CodeIndexRecord = {
			RoomId = roomId,
			AccessCode = accessCode,
			ClaimToken = claimToken,
			LastHeartbeat = os.time(),
		}

		local requestOk, storedValue = retryMemoryStore("reservar codigo curto", function()
			return RoomCodesMap:UpdateAsync(candidate, function(previousValue: unknown): unknown
				if previousValue ~= nil then
					return previousValue
				end
				return codeRecord
			end, ROOM_TTL_SECONDS)
		end)

		if requestOk and isCodeIndexRecord(storedValue) then
			local storedRecord = storedValue :: CodeIndexRecord
			if storedRecord.ClaimToken == claimToken then
				return candidate, claimToken
			end
		end
	end
	return nil, nil
end

local function removeCreatedRoom(roomId: string, roomCode: string, claimToken: string)
	-- RoomId e UUID, portanto pode ser removido diretamente. O codigo e removido
	-- somente se ainda pertence a esta sala, identificado pelo token de claim.
	retryMemoryStore("remover sala criada", function()
		RoomsMap:RemoveAsync(roomId)
	end)

	local indexOk, indexValue = retryMemoryStore("confirmar codigo para limpeza", function()
		return RoomCodesMap:GetAsync(roomCode)
	end)
	if indexOk and isCodeIndexRecord(indexValue) then
		local index = indexValue :: CodeIndexRecord
		if index.ClaimToken == claimToken then
			retryMemoryStore("remover codigo da sala", function()
				RoomCodesMap:RemoveAsync(roomCode)
			end)
		end
	end
end

-- A busca por codigo so e valida se o indice E a sala principal ainda existem.
local function findRoomByCode(rawCode: unknown): (RoomRecord?, string?)
	local roomCode = normalizeRoomCode(rawCode)
	if roomCode == nil then
		return nil, "Use um codigo de 5 ou 6 caracteres alfanumericos."
	end

	local indexOk, indexValue = retryMemoryStore("buscar codigo curto", function()
		return RoomCodesMap:GetAsync(roomCode)
	end)
	if not indexOk then
		return nil, "Nao foi possivel consultar a sala. Tente novamente."
	end
	if not isCodeIndexRecord(indexValue) then
		return nil, "Codigo de sala invalido ou expirado."
	end

	local index = indexValue :: CodeIndexRecord
	local roomOk, roomValue = retryMemoryStore("validar sala do codigo", function()
		return RoomsMap:GetAsync(index.RoomId)
	end)
	if not roomOk then
		return nil, "Nao foi possivel validar a sala. Tente novamente."
	end
	if not isRoomRecord(roomValue) then
		return nil, "Esta sala expirou ou nao existe mais."
	end

	local room = roomValue :: RoomRecord
	-- Garante que um indice defasado nunca aponte para outro servidor reservado.
	if room.Id ~= index.RoomId
		or room.RoomCode ~= roomCode
		or room.AccessCode ~= index.AccessCode
		or room.CodeClaimToken ~= index.ClaimToken then
		return nil, "Codigo de sala invalido ou expirado."
	end
	return room, nil
end

local isTeleporting: { [Player]: boolean } = {}

local function setPlayerTeleporting(player: Player, state: boolean)
	if state then
		isTeleporting[player] = true
		task.delay(15, function()
			isTeleporting[player] = nil
		end)
	else
		isTeleporting[player] = nil
	end
end

local function teleportPlayerToRoom(player: Player, room: RoomRecord): (boolean, string)
	-- Esta verificacao acontece no lobby, antes do TeleportAsync. A mesma regra
	-- tambem e verificada no servidor reservado contra acessos diretos.
	if isPlayerBanned(room, player.UserId) then
		return false, "Voce foi banido desta sala."
	end
	if room.PlayerCount >= room.MaxPlayers then
		return false, "A sala esta cheia."
	end

	setPlayerTeleporting(player, true)
	local teleportOk, teleportError = pcall(function()
		local options = Instance.new("TeleportOptions")
		options.ReservedServerAccessCode = room.AccessCode
		-- AccessCode nao entra em TeleportData; o servidor reservado o le do
		-- MemoryStore e, portanto, ele permanece no backend nesse fluxo.
		options:SetTeleportData({
			RoomId = room.Id,
			RoomCode = room.RoomCode,
			HostUserId = room.HostUserId,
		})
		TeleportService:TeleportAsync(GAME_PLACE_ID, { player }, options)
	end)
	if not teleportOk then
		setPlayerTeleporting(player, false)
		warn("[RoomSystem] Falha no teleporte: " .. tostring(teleportError))
		return false, "Erro ao conectar a sala."
	end
	return true, "Conectando..."
end

--------------------------------------------------------------------------------
-- SERVIDOR RESERVADO
--------------------------------------------------------------------------------
if IS_ROOM_SERVER then
	-- A manutencao do registro pertence ao RoomPresenceHeartbeat.server.luau.
	LeaveRoomRF.OnServerInvoke = function(player: Player): (boolean, string)
		local teleportOk, teleportError = pcall(function()
			TeleportService:TeleportAsync(GAME_PLACE_ID, { player })
		end)
		if teleportOk then
			return true, "Saindo..."
		end
		warn("[RoomSystem] Falha ao retornar ao lobby: " .. tostring(teleportError))
		return false, "Nao foi possivel voltar ao lobby."
	end
	return
end

--------------------------------------------------------------------------------
-- LOBBY
--------------------------------------------------------------------------------
local function fetchPublicRooms(): { [number]: { [string]: unknown } }
	local readOk, entries = retryMemoryStore("listar salas", function()
		return RoomsMap:GetRangeAsync(Enum.SortDirection.Ascending, 100)
	end)

	local publicRooms: { [number]: { [string]: unknown } } = {}
	if not readOk or type(entries) ~= "table" then
		return publicRooms
	end

	for _, entry in ipairs(entries) do
		if type(entry) == "table" and isRoomRecord(entry.value) then
			local room = entry.value :: RoomRecord
			if room.IsVisible then
				table.insert(publicRooms, {
					Id = room.Id,
					RoomCode = room.RoomCode,
					Name = room.Name,
					HostName = room.HostName,
					PlayerCount = room.PlayerCount,
					MaxPlayers = room.MaxPlayers,
					HasPassword = room.Password ~= nil and room.Password ~= "",
				})
			end
		end
	end
	return publicRooms
end

local function broadcastRoomList()
	RoomListUpdatedRE:FireAllClients(fetchPublicRooms())
end

task.spawn(function()
	while true do
		task.wait(8)
		broadcastRoomList()
	end
end)

CreateRoomRF.OnServerInvoke = function(player: Player, configValue: unknown): (boolean, unknown)
	if isTeleporting[player] then
		return false, "Teleporte em andamento..."
	end
	if type(configValue) ~= "table" then
		return false, "Configuracao invalida."
	end

	local config = configValue :: CreateRoomConfig
	local rawName = tostring(config.Name or ("Sala de " .. player.Name)):sub(1, 24)
	local filteredName = filterRoomName(rawName, player)
	local maxPlayers = math.clamp(tonumber(config.MaxPlayers) or 4, 2, 12)
	local password = if type(config.Password) == "string" and #config.Password > 0
		then config.Password:sub(1, 64)
		else nil
	local isVisible = config.IsVisible ~= false
	local allowHostMigration = config.AllowHostMigration == true

	setPlayerTeleporting(player, true)
	local reserveOk, accessCodeValue, privateServerIdValue = pcall(function()
		return TeleportService:ReserveServerAsync(GAME_PLACE_ID)
	end)
	if not reserveOk or type(accessCodeValue) ~= "string" or accessCodeValue == "" then
		setPlayerTeleporting(player, false)
		warn("[RoomSystem] Falha ao reservar servidor: " .. tostring(accessCodeValue))
		return false, "Falha ao criar servidor reservado."
	end

	local roomId = "room_" .. HttpService:GenerateGUID(false)
	local roomCode, claimToken = claimUniqueShortCode(roomId, accessCodeValue)
	if roomCode == nil or claimToken == nil then
		setPlayerTeleporting(player, false)
		return false, "Nao foi possivel gerar um codigo de sala. Tente novamente."
	end

	local now = os.time()
	local room: RoomRecord = {
		Id = roomId,
		RoomCode = roomCode,
		CodeClaimToken = claimToken,
		Name = filteredName,
		HostName = player.Name,
		HostUserId = player.UserId,
		MaxPlayers = maxPlayers,
		Password = password,
		IsVisible = isVisible,
		AllowHostMigration = allowHostMigration,
		BannedPlayers = {},
		AccessCode = accessCodeValue,
		PrivateServerId = if type(privateServerIdValue) == "string" then privateServerIdValue else nil,
		PlayerCount = 1,
		CreatedAt = now,
		LastHeartbeat = now,
	}

	local storeOk = retryMemoryStore("registrar sala", function()
		local didSet = RoomsMap:SetAsync(roomId, room, ROOM_TTL_SECONDS, now)
		if not didSet then
			error("MemoryStoreSortedMap:SetAsync retornou false")
		end
	end)
	if not storeOk then
		removeCreatedRoom(roomId, roomCode, claimToken)
		setPlayerTeleporting(player, false)
		return false, "Erro ao registrar sala."
	end

	local teleportOk, teleportError = pcall(function()
		local options = Instance.new("TeleportOptions")
		options.ReservedServerAccessCode = accessCodeValue
		options:SetTeleportData({
			RoomId = roomId,
			RoomCode = roomCode,
			HostUserId = player.UserId,
		})
		TeleportService:TeleportAsync(GAME_PLACE_ID, { player }, options)
	end)
	if not teleportOk then
		warn("[RoomSystem] Falha ao teleportar criador: " .. tostring(teleportError))
		removeCreatedRoom(roomId, roomCode, claimToken)
		setPlayerTeleporting(player, false)
		return false, "Falha ao teleportar para a sala."
	end

	broadcastRoomList()
	return true, {
		Name = filteredName,
		RoomCode = roomCode,
		AllowHostMigration = allowHostMigration,
	}
end

JoinRoomRF.OnServerInvoke = function(player: Player, roomIdValue: unknown, passwordInput: unknown): (boolean, string)
	if isTeleporting[player] then
		return false, "Teleporte em andamento..."
	end
	if type(roomIdValue) ~= "string" then
		return false, "Sala invalida."
	end

	local readOk, roomValue = retryMemoryStore("buscar sala", function()
		return RoomsMap:GetAsync(roomIdValue)
	end)
	if not readOk then
		return false, "Nao foi possivel consultar a sala. Tente novamente."
	end
	if not isRoomRecord(roomValue) then
		return false, "Sala nao encontrada."
	end

	local room = roomValue :: RoomRecord
	if room.Password ~= nil and room.Password ~= passwordInput then
		return false, "Senha incorreta."
	end
	return teleportPlayerToRoom(player, room)
end

-- RemoteFunction solicitada: valida o codigo e, somente para uma sala ativa,
-- devolve o AccessCode que pode ser usado pelo TeleportService no servidor.
ResolveRoomCodeRF.OnServerInvoke = function(player: Player, rawCode: unknown, passwordInput: unknown): (boolean, unknown)
	local room, errorMessage = findRoomByCode(rawCode)
	if room == nil then
		return false, errorMessage
	end
	if isPlayerBanned(room, player.UserId) then
		return false, "Voce foi banido desta sala."
	end
	-- Sem esta verificacao, uma sala protegida por senha poderia ter seu
	-- AccessCode obtido apenas pela funcao de resolucao de codigo.
	if room.Password ~= nil and room.Password ~= passwordInput then
		return false, "Senha incorreta."
	end
	return true, {
		RoomId = room.Id,
		RoomCode = room.RoomCode,
		AccessCode = room.AccessCode,
		HostUserId = room.HostUserId,
	}
end

-- Preferivel para o cliente: o servidor resolve e usa o AccessCode sem expo-lo.
JoinRoomByCodeRF.OnServerInvoke = function(player: Player, rawCode: unknown, passwordInput: unknown): (boolean, string)
	if isTeleporting[player] then
		return false, "Teleporte em andamento..."
	end
	local room, errorMessage = findRoomByCode(rawCode)
	if room == nil then
		return false, errorMessage or "Codigo de sala invalido."
	end
	if room.Password ~= nil and room.Password ~= passwordInput then
		return false, "Senha incorreta."
	end
	return teleportPlayerToRoom(player, room)
end

GetRoomsRF.OnServerInvoke = function(_player: Player)
	return fetchPublicRooms()
end

LeaveRoomRF.OnServerInvoke = function(_player: Player): (boolean, string)
	return false, "Voce ja esta no lobby."
end

Players.PlayerRemoving:Connect(function(player: Player)
	isTeleporting[player] = nil
end)
