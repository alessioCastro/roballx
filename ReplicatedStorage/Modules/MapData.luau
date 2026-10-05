--!strict
-- MapData.luau
-- Definição completa do mapa e das regras de gameplay.
--
-- COORDENADAS:
-- O sistema de coordenadas do mapa é centrado em (0, 0).
--
-- X:
--   negativo = esquerda
--   0        = centro
--   positivo = direita
--
-- Y:
--   negativo = cima
--   0        = centro
--   positivo = baixo
--
-- O MapData NÃO usa Vector2.
-- Todas as coordenadas são declaradas como { x = ..., y = ... }.
-- A conversão para Vector2 acontece na camada de runtime.

local MapData = {}

MapData.Default = {

	----------------------------------------------------
	-- INFORMAÇÕES
	----------------------------------------------------

	info = {
		name = "Campo Clássico (Com Formas Flexíveis)",
		author = "Sistema",
	},

	----------------------------------------------------
	-- LIMITES DO MAPA
	----------------------------------------------------

	bounds = {
		width = 800,
		height = 400,
		padding = 0,
	},

	----------------------------------------------------
	-- GRUPOS DE COLISÃO
	----------------------------------------------------

	groups = {
		"player",
		"wall",
		"goal",
		"obstacle",
	},

	----------------------------------------------------
	-- GAMEPLAY
	----------------------------------------------------

	gameplay = {

		------------------------------------------------
		-- JOGADOR
		------------------------------------------------

		player = {

			object = "player_body",

			movement = {
				accel = 1200,
				friction = 1,
				decelFactor = 0.88,
			},

			spawn = {
				team1Positions = {
					{ x = -200, y = 0 },
					{ x = -180, y = 0 },
					{ x = -160, y = 0 },
					{ x = -140, y = 0 },
				},

				team2Positions = {
					{ x = 200, y = 0 },
					{ x = 180, y = 0 },
					{ x = 160, y = 0 },
					{ x = 140, y = 0 },
				},
			},

			collision = {
				group = {"player"},

				mask = {
					"player",
					"goal",
					"obstacle",
				},
			},
		},

		------------------------------------------------
		-- CHUTE
		------------------------------------------------

		kick = {
			force = 300,
			rangeExtra = 4,
			cooldown = 0.3,
		},

		------------------------------------------------
		-- OBJETOS CHUTÁVEIS
		------------------------------------------------

		kickable = {
			"game_object",
		},

		------------------------------------------------
		-- PONTUAÇÃO
		------------------------------------------------

		scoring = {

			{
				id = "left_goal",
				object = "game_object",

				team = "Blue",

				min = { x = -440, y = -75 },
				max = { x = -400, y = 75 },
			},

			{
				id = "right_goal",
				object = "game_object",

				team = "Red",

				min = { x = 400, y = -75 },
				max = { x = 440, y = 75 },
			},
		},
	},

	----------------------------------------------------
	-- SHAPES
	----------------------------------------------------

	shapes = {

		{
			pos = { x = -340, y = 0 },
			size = { x = 120, y = 220 },

			color = Color3.fromRGB(255, 255, 255),
			transparency = 1,

			cornerRadius = 10,

			strokeWidth = 2,
			strokeColor = Color3.fromRGB(255, 255, 255),

			isSolid = false,
		},

		{
			pos = { x = 340, y = 0 },
			size = { x = 120, y = 220 },

			color = Color3.fromRGB(255, 255, 255),
			transparency = 1,

			cornerRadius = 10,

			strokeWidth = 2,
			strokeColor = Color3.fromRGB(255, 255, 255),

			isSolid = false,
		},

		{
			pos = { x = 0, y = 0 },
			size = { x = 140, y = 140 },

			color = Color3.fromRGB(255, 255, 255),
			transparency = 1,

			cornerRadius = UDim.new(0.5, 0),

			strokeWidth = 2,
			strokeColor = Color3.fromRGB(255, 255, 255),

			isSolid = false,
		},

		{
			pos = { x = 0, y = 0 },
			size = { x = 15, y = 15 },

			color = Color3.fromRGB(255, 255, 255),

			cornerRadius = UDim.new(0.5, 0),

			strokeWidth = 0,

			isSolid = false,
		},

		{
			pos = { x = 0, y = 100 },
			size = { x = 160, y = 50 },

			color = Color3.fromRGB(200, 50, 50),

			cornerRadius = UDim.new(0.5, 0),

			strokeWidth = 3,
			strokeColor = Color3.fromRGB(0, 0, 0),

			isSolid = true,
			restitution = 0.5,

			cGroup = {"obstacle"},
			cMask = "all",
		},

		{
			id = "obstaculo_central",

			pos = { x = 100, y = 0 },
			size = { x = 120, y = 40 },

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
		},
	},

	----------------------------------------------------
	-- SEGMENTS
	----------------------------------------------------

	segments = {

		{
			a = { x = -40, y = -200 },
			b = { x = -40, y = 200 },
			thickness = 40,

			color = Color3.fromRGB(60, 121, 49),
			isSolid = false,
		},

		{
			a = { x = -120, y = -200 },
			b = { x = -120, y = 200 },
			thickness = 40,

			color = Color3.fromRGB(60, 121, 49),
			isSolid = false,
		},

		{
			a = { x = -200, y = -200 },
			b = { x = -200, y = 200 },
			thickness = 40,

			color = Color3.fromRGB(60, 121, 49),
			isSolid = false,
		},

		{
			a = { x = -280, y = -200 },
			b = { x = -280, y = 200 },
			thickness = 40,

			color = Color3.fromRGB(60, 121, 49),
			isSolid = false,
		},

		{
			a = { x = -360, y = -200 },
			b = { x = -360, y = 200 },
			thickness = 40,

			color = Color3.fromRGB(60, 121, 49),
			isSolid = false,
		},

		{
			a = { x = 40, y = -200 },
			b = { x = 40, y = 200 },
			thickness = 40,

			color = Color3.fromRGB(60, 121, 49),
			isSolid = false,
		},

		{
			a = { x = 120, y = -200 },
			b = { x = 120, y = 200 },
			thickness = 40,

			color = Color3.fromRGB(60, 121, 49),
			isSolid = false,
		},

		{
			a = { x = 200, y = -200 },
			b = { x = 200, y = 200 },
			thickness = 40,

			color = Color3.fromRGB(60, 121, 49),
			isSolid = false,
		},

		{
			a = { x = 280, y = -200 },
			b = { x = 280, y = 200 },
			thickness = 40,

			color = Color3.fromRGB(60, 121, 49),
			isSolid = false,
		},

		{
			a = { x = 360, y = -200 },
			b = { x = 360, y = 200 },
			thickness = 40,

			color = Color3.fromRGB(60, 121, 49),
			isSolid = false,
		},

		------------------------------------------------
		-- LIMITES SUPERIOR / INFERIOR
		------------------------------------------------

		{
			a = { x = -400, y = -200 },
			b = { x = 400, y = -200 },

			thickness = 2,

			color = Color3.fromRGB(255, 255, 255),
			restitution = 1.2,

			cGroup = {"wall"},
			cMask = "all",
		},

		{
			a = { x = -400, y = 200 },
			b = { x = 400, y = 200 },

			thickness = 2,

			color = Color3.fromRGB(255, 255, 255),
			restitution = 1.2,

			cGroup = {"wall"},
			cMask = "all",
		},

		------------------------------------------------
		-- LIMITES LATERAIS
		------------------------------------------------

		{
			a = { x = -400, y = -200 },
			b = { x = -400, y = -75 },

			thickness = 2,

			color = Color3.fromRGB(255, 255, 255),
			restitution = 1.2,

			cGroup = {"wall"},
			cMask = "all",
		},

		{
			a = { x = -400, y = 75 },
			b = { x = -400, y = 200 },

			thickness = 2,

			color = Color3.fromRGB(255, 255, 255),
			restitution = 1.2,

			cGroup = {"wall"},
			cMask = "all",
		},

		{
			a = { x = 400, y = -200 },
			b = { x = 400, y = -75 },

			thickness = 2,

			color = Color3.fromRGB(255, 255, 255),
			restitution = 1.2,

			cGroup = {"wall"},
			cMask = "all",
		},

		{
			a = { x = 400, y = 75 },
			b = { x = 400, y = 200 },

			thickness = 2,

			color = Color3.fromRGB(255, 255, 255),
			restitution = 1.2,

			cGroup = {"wall"},
			cMask = "all",
		},

		------------------------------------------------
		-- LINHA CENTRAL
		------------------------------------------------

		{
			a = { x = 0, y = -200 },
			b = { x = 0, y = 200 },

			thickness = 2,

			color = Color3.fromRGB(255, 255, 255),

			isSolid = false,
		},

		------------------------------------------------
		-- GOL LATERAL ESQUERDO
		------------------------------------------------

		{
			a = { x = -400, y = -75 },
			b = { x = -440, y = -75 },

			thickness = 2,

			color = Color3.fromRGB(255, 255, 255),

			cGroup = {"wall"},
			cMask = "all",
		},

		{
			a = { x = -400, y = 75 },
			b = { x = -440, y = 75 },

			thickness = 2,

			color = Color3.fromRGB(255, 255, 255),

			cGroup = {"wall"},
			cMask = "all",
		},

		{
			a = { x = -440, y = -75 },
			b = { x = -440, y = 75 },

			curve = -7,
			curveSegments = 10,

			thickness = 2,

			color = Color3.fromRGB(255, 255, 255),
			restitution = 0,

			cGroup = {"wall"},
			cMask = "all",
		},

		------------------------------------------------
		-- GOL LATERAL DIREITO
		------------------------------------------------

		{
			a = { x = 400, y = -75 },
			b = { x = 440, y = -75 },

			thickness = 2,

			color = Color3.fromRGB(255, 255, 255),

			cGroup = {"wall"},
			cMask = "all",
		},

		{
			a = { x = 400, y = 75 },
			b = { x = 440, y = 75 },

			thickness = 2,

			color = Color3.fromRGB(255, 255, 255),

			cGroup = {"wall"},
			cMask = "all",
		},

		{
			a = { x = 440, y = -75 },
			b = { x = 440, y = 75 },

			curve = 7,
			curveSegments = 10,

			thickness = 2,

			color = Color3.fromRGB(255, 255, 255),
			restitution = 0,

			cGroup = {"wall"},
			cMask = "all",
		},
	},

	----------------------------------------------------
	-- DISCS
	----------------------------------------------------

	discs = {

		------------------------------------------------
		-- MODELO DOS JOGADORES
		------------------------------------------------

		{
			id = "player_body",

			pos = { x = 0, y = 0 },

			radius = 18,

			mass = 5,
			restitution = 0.15,

			isStatic = false,
			isSolid = true,

			cGroup = {"player"},

			cMask = {
				"player",
				"goal",
				"obstacle",
			},

			color = Color3.fromRGB(255, 255, 255),

			strokeWidth = 3,
			strokeColor = Color3.fromRGB(0, 0, 0),
		},

		------------------------------------------------
		-- OBJETO FÍSICO USADO PELO GAMEPLAY
		------------------------------------------------

		{
			id = "game_object",

			pos = { x = 0, y = 0 },

			radius = 13,

			mass = 1,
			damping = 0.99,
			restitution = 0.5,

			isStatic = false,
			isSolid = true,

			cGroup = "all",
			cMask = "all",

			color = Color3.fromRGB(255, 255, 255),

			strokeWidth = 3,
			strokeColor = Color3.fromRGB(0, 0, 0),
		},

		------------------------------------------------
		-- MARCADORES DE GOL
		------------------------------------------------

		{
			pos = { x = -400, y = -75 },

			radius = 5,

			color = Color3.fromRGB(255, 255, 255),

			strokeWidth = 1,
			strokeColor = Color3.fromRGB(0, 0, 0),

			cGroup = {"goal"},
			cMask = "all",
		},

		{
			pos = { x = -400, y = 75 },

			radius = 5,

			color = Color3.fromRGB(255, 255, 255, 255),

			strokeWidth = 1,
			strokeColor = Color3.fromRGB(0, 0, 0),

			cGroup = {"goal"},
			cMask = "all",
		},

		{
			pos = { x = 400, y = -75 },

			radius = 5,

			color = Color3.fromRGB(255, 255, 255),

			strokeWidth = 1,
			strokeColor = Color3.fromRGB(0, 0, 0),

			cGroup = {"goal"},
			cMask = "all",
		},

		{
			pos = { x = 400, y = 75 },

			radius = 5,

			color = Color3.fromRGB(255, 255, 255),

			strokeWidth = 1,
			strokeColor = Color3.fromRGB(0, 0, 0),

			cGroup = {"goal"},
			cMask = "all",
		},
	},
}

return MapData
