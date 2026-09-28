local MapData = {}

MapData.Default = {
	info = {
		name = "Campo Clássico (Com Formas Flexíveis)",
		author = "Sistema"
	},

	groups = {
		"ball",      -- Bit 1
		"player",    -- Bit 2
		"wall",      -- Bit 3
		"goal",      -- Bit 4
		"obstacle",  -- Bit 5
	},

	bounds = {
		width = 800,
		height = 400,
		padding = 0,
	},

	physics = {
		playerRadius = 18,
		playerMass = 5,
		playerAccel = 1200,
		playerFriction = 1,
		playerDecelFactor = 0.88,
		
		kickForce = 300,
		kickRangeExtra = 4,
		kickCooldown = 0.3,

		ballRadius = 13,
		ballMass = 1,
		ballDamping = 0.99,

		ballGroup = {"ball"},
		ballMask = "all",

		playerGroup = {"player"},
		playerMask = {
			"ball",
			"player",
			"goal",
			"obstacle"
		},
	},

	spawns = {
		ball = Vector2.new(400, 200),
		red = Vector2.new(200, 200),
		blue = Vector2.new(600, 200),
	},

	goals = {
		{ teamScored = "Blue", min = Vector2.new(-40, 125), max = Vector2.new(0, 275) },
		{ teamScored = "Red",  min = Vector2.new(800, 125), max = Vector2.new(840, 275) },
	},

	----------------------------------------------------
	-- FORMAS VISUAIS E FÍSICAS (SHAPES)
	----------------------------------------------------
	shapes = {
		-- 1. Grande Área Esquerda
		{
			pos = Vector2.new(60, 200),
			size = Vector2.new(120, 220),
			color = Color3.fromRGB(255, 255, 255),
			transparency = 1,
			cornerRadius = 10,
			strokeWidth = 2,
			strokeColor = Color3.fromRGB(255, 255, 255),
			isSolid = false,
		},

		-- 2. Grande Área Direita
		{
			pos = Vector2.new(740, 200),
			size = Vector2.new(120, 220),
			color = Color3.fromRGB(255, 255, 255),
			transparency = 1,
			cornerRadius = 10,
			strokeWidth = 2,
			strokeColor = Color3.fromRGB(255, 255, 255),
			isSolid = false,
		},

		-- 3. Círculo do Meio Campo
		{
			pos = Vector2.new(400, 200),
			size = Vector2.new(140, 140),
			color = Color3.fromRGB(255, 255, 255),
			transparency = 1,
			cornerRadius = UDim.new(0.5, 0),
			strokeWidth = 2,
			strokeColor = Color3.fromRGB(255, 255, 255),
			isSolid = false,
		},

		{
			pos = Vector2.new(400, 200),
			size = Vector2.new(15, 15),
			color = Color3.fromRGB(255, 255, 255),
			cornerRadius = UDim.new(0.5, 0),
			strokeWidth = 0,
			isSolid = false,
		},

		-- Obstáculo Cápsula Estático
		{
			pos = Vector2.new(400, 300),
			size = Vector2.new(160, 50),
			color = Color3.fromRGB(200, 50, 50),
			cornerRadius = UDim.new(0.5, 0),
			strokeWidth = 3,
			strokeColor = Color3.fromRGB(0, 0, 0),
			isSolid = true,
			restitution = 0.1,
			cGroup = {"obstacle"},
			cMask = "all",
		},

		-- Cápsula móvel
		{
			id = "obstaculo_central",
			pos = Vector2.new(500, 200),
			size = Vector2.new(120, 40),
			color = Color3.fromRGB(240, 180, 50),
			cornerRadius = UDim.new(0.5, 0),
			strokeWidth = 2,
			strokeColor = Color3.fromRGB(0, 0, 0),
			isSolid = true,
			isStatic = false,
			mass = 1,
			damping = 0.96,
			restitution = 0.1,
			cGroup = {"obstacle"},
			cMask = {"goal", "player"},
		}
	},

	----------------------------------------------------
	-- PAREDES / LINHAS (SUPORTAM `curve` E `curveSegments`)
	----------------------------------------------------
	segments = {
		{ a = Vector2.new(360, 0), b = Vector2.new(360, 400), thickness = 40, color = Color3.fromRGB(60, 121, 49), isSolid = false },
		{ a = Vector2.new(280, 0), b = Vector2.new(280, 400), thickness = 40, color = Color3.fromRGB(60, 121, 49), isSolid = false },
		{ a = Vector2.new(200, 0), b = Vector2.new(200, 400), thickness = 40, color = Color3.fromRGB(60, 121, 49), isSolid = false },
		{ a = Vector2.new(120, 0), b = Vector2.new(120, 400), thickness = 40, color = Color3.fromRGB(60, 121, 49), isSolid = false },
		{ a = Vector2.new(40, 0), b = Vector2.new(40, 400), thickness = 40, color = Color3.fromRGB(60, 121, 49), isSolid = false },
		{ a = Vector2.new(440, 0), b = Vector2.new(440, 400), thickness = 40, color = Color3.fromRGB(60, 121, 49), isSolid = false },
		{ a = Vector2.new(520, 0), b = Vector2.new(520, 400), thickness = 40, color = Color3.fromRGB(60, 121, 49), isSolid = false },
		{ a = Vector2.new(600, 0), b = Vector2.new(600, 400), thickness = 40, color = Color3.fromRGB(60, 121, 49), isSolid = false },
		{ a = Vector2.new(680, 0), b = Vector2.new(680, 400), thickness = 40, color = Color3.fromRGB(60, 121, 49), isSolid = false },
		{ a = Vector2.new(760, 0), b = Vector2.new(760, 400), thickness = 40, color = Color3.fromRGB(60, 121, 49), isSolid = false },

		-- Borda Externa do Campo
		{ a = Vector2.new(0, 0), b = Vector2.new(800, 0), thickness = 2, color = Color3.fromRGB(255, 255, 255), restitution = 0.1, cGroup = {"wall"}, cMask = "all" },
		{ a = Vector2.new(0, 400), b = Vector2.new(800, 400), thickness = 2, color = Color3.fromRGB(255, 255, 255), restitution = 0.1, cGroup = {"wall"}, cMask = "all" },
		{ a = Vector2.new(0, 0), b = Vector2.new(0, 125), thickness = 2, color = Color3.fromRGB(255, 255, 255), restitution = 0.1, cGroup = {"wall"}, cMask = "all" },
		{ a = Vector2.new(0, 275), b = Vector2.new(0, 400), thickness = 2, color = Color3.fromRGB(255, 255, 255), restitution = 0.1, cGroup = {"wall"}, cMask = "all" },
		{ a = Vector2.new(800, 0), b = Vector2.new(800, 125), thickness = 2, color = Color3.fromRGB(255, 255, 255), restitution = 0.1, cGroup = {"wall"}, cMask = "all" },
		{ a = Vector2.new(800, 275), b = Vector2.new(800, 400), thickness = 2, color = Color3.fromRGB(255, 255, 255), restitution = 0.1, cGroup = {"wall"}, cMask = "all" },

		-- Linha do Meio Campo
		{ a = Vector2.new(400, 0), b = Vector2.new(400, 400), thickness = 2, color = Color3.fromRGB(255, 255, 255), isSolid = false },

		-- Redes Esquerda (Exemplo de Rede Curvada com `curve = -7`)
		{ a = Vector2.new(0, 125), b = Vector2.new(-40, 125), thickness = 2, color = Color3.fromRGB(255, 255, 255), cGroup = {"wall"}, cMask = "all" },
		{ a = Vector2.new(0, 275), b = Vector2.new(-40, 275), thickness = 2, color = Color3.fromRGB(255, 255, 255), cGroup = {"wall"}, cMask = "all" },
		{ a = Vector2.new(-40, 125), b = Vector2.new(-40, 275), curve = -7, curveSegments = 10, thickness = 2, color = Color3.fromRGB(255, 255, 255), restitution = 0, cGroup = {"wall"}, cMask = "all" },

		-- Redes Direita (Exemplo de Rede Curvada com `curve = 7`)
		{ a = Vector2.new(800, 125), b = Vector2.new(840, 125), thickness = 2, color = Color3.fromRGB(255, 255, 255), cGroup = {"wall"}, cMask = "all" },
		{ a = Vector2.new(800, 275), b = Vector2.new(840, 275), thickness = 2, color = Color3.fromRGB(255, 255, 255), cGroup = {"wall"}, cMask = "all" },
		{ a = Vector2.new(840, 125), b = Vector2.new(840, 275), curve = 7, curveSegments = 10, thickness = 2, color = Color3.fromRGB(255, 255, 255), restitution = 0, cGroup = {"wall"}, cMask = "all" },
	},

	-- Traves
	discs = {
		{ pos = Vector2.new(0, 125), radius = 5, color = Color3.fromRGB(255, 255, 255), strokeWidth = 1, strokeColor = Color3.fromRGB(0, 0, 0), cGroup = {"goal"}, cMask = "all" },
		{ pos = Vector2.new(0, 275), radius = 5, color = Color3.fromRGB(255, 255, 255), strokeWidth = 1, strokeColor = Color3.fromRGB(0, 0, 0), cGroup = {"goal"}, cMask = "all" },
		{ pos = Vector2.new(800, 125), radius = 5, color = Color3.fromRGB(255, 255, 255), strokeWidth = 1, strokeColor = Color3.fromRGB(0, 0, 0), cGroup = {"goal"}, cMask = "all" },
		{ pos = Vector2.new(800, 275), radius = 5, color = Color3.fromRGB(255, 255, 255), strokeWidth = 1, strokeColor = Color3.fromRGB(0, 0, 0), cGroup = {"goal"}, cMask = "all" },
	}
}

return MapData
