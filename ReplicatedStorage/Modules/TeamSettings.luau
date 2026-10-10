--!strict

local TeamSettings = {}

TeamSettings.teams = {

	Team1 = {
		name = "White",

		uniform = {

			-- Cor/base do corpo
			base = {
				color = Color3.fromRGB(255, 255, 255),
			},

			layers = {

				--[[{
					type = "frame",

					position = {
						x = 0.5,
						y = 0.5,
					},

					size = {
						x = 0.35,
						y = 1,
					},

					color =
						Color3.fromRGB(255, 255, 255),

					transparency = 0,

					rotation = 0,
				},

				{
					type = "image",

					image = "rbxassetid://167034677",

					position = {
						x = 0.3,
						y = 0.3,
					},

					size = {
						x = 0.3,
						y = 0.3,
					},

					transparency = 0,

					rotation = 0,
				},]]

			},
		},
	},

	Team2 = {
		name = "Black",

		uniform = {

			base = {
				color = Color3.fromRGB(0, 0, 0),
			},

			layers = {

			},
		},
	},

}

return TeamSettings
