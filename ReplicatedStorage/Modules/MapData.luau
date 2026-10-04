--!strict
-- MapData.luau
-- Definição completa do mapa e das regras de gameplay.
--
-- IMPORTANTE:
-- Disc, Shape e Segment definem apenas a geometria física do objeto.
-- Gameplay define os papéis que esses objetos assumem na partida.
--
-- Um mesmo objeto físico pode:
--   • ser usado como jogador;
--   • ser chutável;
--   • ser marcável;
--   • ou possuir qualquer combinação desses papéis.
--
-- O ID de um objeto é apenas uma referência técnica.
-- Ele não possui significado semântico como "bola", "jogador", etc.

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
	--
	-- Estes grupos existem somente para o sistema físico.
	-- Eles não definem papéis de gameplay.
	----------------------------------------------------

	groups = {
		"player",
		"wall",
		"goal",
		"obstacle",
	},

	----------------------------------------------------
	-- GAMEPLAY
	--
	-- Os objetos referenciados aqui vêm de:
	--   discs
	--   shapes
	--   segments
	--
	-- O tipo geométrico do objeto não importa para o
	-- papel de gameplay.
	----------------------------------------------------

	gameplay = {

		------------------------------------------------
		-- JOGADOR
		--
		-- "object" é o ID de um objeto físico usado como
		-- modelo para os jogadores.
		--
		-- O objeto pode ser posteriormente:
		--   disc
		--   shape
		--   segment
		--
		-- O PhysicsEngine será responsável por tratar
		-- corretamente a geometria escolhida.
		------------------------------------------------

		player = {

			object = "player_body",

			movement = {
				accel = 1200,
				friction = 1,
				decelFactor = 0.88,
			},

			spawn = {
				Red = Vector2.new(200, 200),
				Blue = Vector2.new(600, 200),
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
		--
		-- Qualquer objeto físico pode aparecer aqui.
		-- Não existe categoria "bola".
		------------------------------------------------

		kickable = {
			"game_object",
		},

		------------------------------------------------
		-- PONTUAÇÃO
		--
		-- "object" é qualquer objeto físico que possa
		-- satisfazer a condição de pontuação.
		--
		-- O mesmo objeto pode aparecer em mais de uma
		-- regra se o mapa precisar.
		------------------------------------------------

		scoring = {

			{
				id = "left_goal",
				object = "game_object",

				team = "Blue",

				min = Vector2.new(-40, 125),
				max = Vector2.new(0, 275),
			},

			{
				id = "right_goal",
				object = "game_object",

				team = "Red",

				min = Vector2.new(800, 125),
				max = Vector2.new(840, 275),
			},
		},
	},

	----------------------------------------------------
	-- SHAPES
	--
	-- Objetos geométricos do mapa.
	--
	-- IMPORTANTE:
	-- O primeiro objeto abaixo é o modelo físico dos
	-- jogadores. Isso é apenas uma escolha deste mapa.
	-- O motor não deverá assumir que jogadores são
	-- necessariamente discs.
	----------------------------------------------------

	shapes = {

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
		},
	},

	----------------------------------------------------
	-- SEGMENTS
	----------------------------------------------------

	segments = {

		{
			a = Vector2.new(360, 0),
			b = Vector2.new(360, 400),
			thickness = 40,

			color = Color3.fromRGB(60, 121, 49),
			isSolid = false,
		},

		{
			a = Vector2.new(280, 0),
			b = Vector2.new(280, 400),
			thickness = 40,

			color = Color3.fromRGB(60, 121, 49),
			isSolid = false,
		},

		{
			a = Vector2.new(200, 0),
			b = Vector2.new(200, 400),
			thickness = 40,

			color = Color3.fromRGB(60, 121, 49),
			isSolid = false,
		},

		{
			a = Vector2.new(120, 0),
			b = Vector2.new(120, 400),
			thickness = 40,

			color = Color3.fromRGB(60, 121, 49),
			isSolid = false,
		},

		{
			a = Vector2.new(40, 0),
			b = Vector2.new(40, 400),
			thickness = 40,

			color = Color3.fromRGB(60, 121, 49),
			isSolid = false,
		},

		{
			a = Vector2.new(440, 0),
			b = Vector2.new(440, 400),
			thickness = 40,

			color = Color3.fromRGB(60, 121, 49),
			isSolid = false,
		},

		{
			a = Vector2.new(520, 0),
			b = Vector2.new(520, 400),
			thickness = 40,

			color = Color3.fromRGB(60, 121, 49),
			isSolid = false,
		},

		{
			a = Vector2.new(600, 0),
			b = Vector2.new(600, 400),
			thickness = 40,

			color = Color3.fromRGB(60, 121, 49),
			isSolid = false,
		},

		{
			a = Vector2.new(680, 0),
			b = Vector2.new(680, 400),
			thickness = 40,

			color = Color3.fromRGB(60, 121, 49),
			isSolid = false,
		},

		{
			a = Vector2.new(760, 0),
			b = Vector2.new(760, 400),
			thickness = 40,

			color = Color3.fromRGB(60, 121, 49),
			isSolid = false,
		},

		------------------------------------------------
		-- LIMITES SUPERIOR / INFERIOR
		------------------------------------------------

		{
			a = Vector2.new(0, 0),
			b = Vector2.new(800, 0),

			thickness = 2,

			color = Color3.fromRGB(255, 255, 255),
			restitution = 0.1,

			cGroup = {"wall"},
			cMask = "all",
		},

		{
			a = Vector2.new(0, 400),
			b = Vector2.new(800, 400),

			thickness = 2,

			color = Color3.fromRGB(255, 255, 255),
			restitution = 0.1,

			cGroup = {"wall"},
			cMask = "all",
		},

		------------------------------------------------
		-- LIMITES LATERAIS
		------------------------------------------------

		{
			a = Vector2.new(0, 0),
			b = Vector2.new(0, 125),

			thickness = 2,

			color = Color3.fromRGB(255, 255, 255),
			restitution = 0.1,

			cGroup = {"wall"},
			cMask = "all",
		},

		{
			a = Vector2.new(0, 275),
			b = Vector2.new(0, 400),

			thickness = 2,

			color = Color3.fromRGB(255, 255, 255),
			restitution = 0.1,

			cGroup = {"wall"},
			cMask = "all",
		},

		{
			a = Vector2.new(800, 0),
			b = Vector2.new(800, 125),

			thickness = 2,

			color = Color3.fromRGB(255, 255, 255),
			restitution = 0.1,

			cGroup = {"wall"},
			cMask = "all",
		},

		{
			a = Vector2.new(800, 275),
			b = Vector2.new(800, 400),

			thickness = 2,

			color = Color3.fromRGB(255, 255, 255),
			restitution = 0.1,

			cGroup = {"wall"},
			cMask = "all",
		},

		------------------------------------------------
		-- LINHA CENTRAL
		------------------------------------------------

		{
			a = Vector2.new(400, 0),
			b = Vector2.new(400, 400),

			thickness = 2,

			color = Color3.fromRGB(255, 255, 255),

			isSolid = false,
		},

		------------------------------------------------
		-- GOL LATERAL ESQUERDO
		------------------------------------------------

		{
			a = Vector2.new(0, 125),
			b = Vector2.new(-40, 125),

			thickness = 2,

			color = Color3.fromRGB(255, 255, 255),

			cGroup = {"wall"},
			cMask = "all",
		},

		{
			a = Vector2.new(0, 275),
			b = Vector2.new(-40, 275),

			thickness = 2,

			color = Color3.fromRGB(255, 255, 255),

			cGroup = {"wall"},
			cMask = "all",
		},

		{
			a = Vector2.new(-40, 125),
			b = Vector2.new(-40, 275),

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
			a = Vector2.new(800, 125),
			b = Vector2.new(840, 125),

			thickness = 2,

			color = Color3.fromRGB(255, 255, 255),

			cGroup = {"wall"},
			cMask = "all",
		},

		{
			a = Vector2.new(800, 275),
			b = Vector2.new(840, 275),

			thickness = 2,

			color = Color3.fromRGB(255, 255, 255),

			cGroup = {"wall"},
			cMask = "all",
		},

		{
			a = Vector2.new(840, 125),
			b = Vector2.new(840, 275),

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
	--
	-- Aqui ficam somente objetos cuja geometria é
	-- circular.
	--
	-- Os papéis de gameplay são definidos em gameplay,
	-- acima, e não aqui.
	----------------------------------------------------

	discs = {

		------------------------------------------------
		-- OBJETO USADO COMO CORPO DOS JOGADORES
		------------------------------------------------

		{
			id = "player_body",

			pos = Vector2.new(400, 200),

			radius = 18,

			mass = 5,
			damping = 0.99,
			restitution = 0.1,

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
		-- OBJETO FÍSICO USADO PELO GAMEPLAY ATUAL
		--
		-- Ele não é "a bola".
		-- É simplesmente um objeto que este mapa escolheu
		-- tornar chutável e marcável.
		------------------------------------------------

		{
			id = "game_object",

			pos = Vector2.new(400, 200),

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
		--
		-- São objetos físicos normais.
		-- Não são "goals" semanticamente para o motor.
		-- O grupo de colisão é apenas uma configuração
		-- física.
		------------------------------------------------

		{
			pos = Vector2.new(0, 125),

			radius = 5,

			color = Color3.fromRGB(255, 255, 255),

			strokeWidth = 1,
			strokeColor = Color3.fromRGB(0, 0, 0),

			cGroup = {"goal"},
			cMask = "all",
		},

		{
			pos = Vector2.new(0, 275),

			radius = 5,

			color = Color3.fromRGB(255, 255, 255),

			strokeWidth = 1,
			strokeColor = Color3.fromRGB(0, 0, 0),

			cGroup = {"goal"},
			cMask = "all",
		},

		{
			pos = Vector2.new(800, 125),

			radius = 5,

			color = Color3.fromRGB(255, 255, 255),

			strokeWidth = 1,
			strokeColor = Color3.fromRGB(0, 0, 0),

			cGroup = {"goal"},
			cMask = "all",
		},

		{
			pos = Vector2.new(800, 275),

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
