--!strict

local PlayerSettings = {}

PlayerSettings.controls = {
	moveUp = {
		Enum.KeyCode.W,
		Enum.KeyCode.Up,
		Enum.KeyCode.DPadUp,
	},

	moveDown = {
		Enum.KeyCode.S,
		Enum.KeyCode.Down,
		Enum.KeyCode.DPadDown,
	},

	moveLeft = {
		Enum.KeyCode.A,
		Enum.KeyCode.Left,
		Enum.KeyCode.DPadLeft,
	},

	moveRight = {
		Enum.KeyCode.D,
		Enum.KeyCode.Right,
		Enum.KeyCode.DPadRight,
	},

	kick = {
		Enum.KeyCode.Space,
		Enum.KeyCode.X,
		Enum.KeyCode.ButtonA,
	},
}

return PlayerSettings