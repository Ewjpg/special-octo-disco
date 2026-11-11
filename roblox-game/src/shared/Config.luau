-- Все настройки баланса в одном месте.
-- Меняй числа здесь — код трогать не нужно.

local Config = {}

Config.GameTitle = "RESONANCE"

-- Side: -1 = ворота на стороне -X, 1 = ворота на стороне +X.
Config.Teams = {
	Home = { Name = "СОЛАР", Color = Color3.fromRGB(255, 124, 48), Side = -1 },
	Away = { Name = "НОКС", Color = Color3.fromRGB(88, 122, 255), Side = 1 },
}

-- Тип аватара. Анимации есть для обоих, основной — R6.
Config.Avatar = {
	RigType = "R6", -- "R6" или "R15"
	ForceRig = true, -- если Roblox выдал аватар другого типа, сервер пересоберёт персонажа в нужный
}

Config.Match = {
	Duration = 300, -- длина матча, секунды
	KickoffCountdown = 3, -- отсчёт перед розыгрышем
	GoalPause = 5.5, -- пауза после гола
	FullTimePause = 10, -- пауза после финального свистка
}

Config.Player = {
	WalkSpeed = 20,
	SprintSpeed = 29,
	DribbleMult = 0.94, -- скорость с мячом
	MaxStamina = 100,
	SprintDrain = 13, -- расход выносливости в секунду
	StaminaRegen = 17,
	StaminaRegenDelay = 0.8,
	ExhaustedThreshold = 14, -- после нуля спринт вернётся только с этого запаса
}

Config.Ball = {
	Radius = 1.2,
	GravityScale = 0.5, -- 1 = обычная гравитация Roblox, меньше = мяч летит дальше
	GroundDrag = 0.55,
	AirDrag = 0.1,
	MaxSpeed = 330,
	PickupRadius = 3.7,
	PickupHeight = 6.2,
	TrapMaxSpeed = 108, -- мяч быстрее этого нельзя принять, только отбить
	TeammateTrapBonus = 1.4, -- партнёр принимает более быстрые мячи
	HoldDistance = 2.5, -- на сколько мяч впереди игрока при ведении
	KickNoPickup = 0.4,
	BlockDamping = 0.34,
}

Config.Shot = {
	MinPower = 64,
	MaxPower = 140,
	ChargeTime = 0.85,
	ChargeMoveMult = 0.55,
	BaseElevation = 15, -- градусы, добавляются к наклону камеры
	MinElevation = 1,
	MaxElevation = 50,
}

Config.Pass = {
	MinSpeed = 62,
	MaxSpeed = 120,
	AssistAngle = 32, -- конус автонаведения на партнёра
	MaxRange = 160,
	Elevation = 3,
}

Config.Lob = {
	Elevation = 40,
	DefaultSpeed = 84,
	MinSpeed = 48,
	MaxSpeed = 122,
}

Config.Tackle = {
	Cooldown = 2.6,
	Stamina = 16,
	Duration = 0.5,
	Speed = 46,
	Radius = 4.8,
	StunTime = 0.75,
	KnockSpeed = 30,
}

Config.Dash = {
	Cooldown = 3,
	Stamina = 14,
	Duration = 0.2,
	Speed = 64,
}

-- Дриблинг: короткий финт с мячом. Пока он длится, подкат по игроку не проходит.
Config.Dribble = {
	Cooldown = 2.4,
	Stamina = 10,
	Duration = 0.2,
	Speed = 54,
	ImmuneTime = 0.5,
}

Config.Resonance = {
	Max = 100,
	Passive = 0.7, -- в секунду
	Goal = 45,
	Assist = 25,
	Steal = 16,
	Dodge = 14,
	Block = 10,
	PassDone = 6,
}

Config.Bots = {
	Goalkeepers = true,
	KeeperSpeed = 23,
	KeeperReach = 4.8, -- радиус, в котором вратарь ловит мяч
	KeeperDiveReach = 6.4,
	KeeperCatchSpeed = 160, -- быстрее — только отбивает
	KeeperDiveSpeed = 40,
	KeeperDiveCooldown = 1.5,
	KeeperReaction = 0.2,
	KeeperHoldTime = 1.1,
}

-- Клавиши. Имена — из Enum.KeyCode / Enum.UserInputType.
Config.Controls = {
	Shoot = { "MouseButton1", "ButtonR2" },
	Action = { "E", "ButtonB" }, -- без мяча — подкат, с мячом — дриблинг
	Pass = { "F", "ButtonX" },
	Lob = { "R", "ButtonY" },
	Dash = { "Q", "ButtonL1" },
	Sprint = { "LeftShift", "ButtonL2" },
	Ability1 = { "Z", "DPadLeft" },
	Ability2 = { "X", "DPadUp" },
	Ability3 = { "C", "DPadRight" },
	StyleMenu = { "M" },
	Help = { "H" },
	ShiftLock = "LeftControl", -- Shift занят спринтом, блокировку камеры переносим сюда
}

-- Встроенные звуки Roblox. Можно заменить на свои rbxassetid://...
Config.Sounds = {
	Kick = { Id = "rbxasset://sounds/snap.wav", Volume = 0.9, Pitch = 0.75 },
	PowerKick = { Id = "rbxasset://sounds/Rocket shot.wav", Volume = 0.7, Pitch = 1.25 },
	Pass = { Id = "rbxasset://sounds/snap.wav", Volume = 0.55, Pitch = 1.1 },
	Bounce = { Id = "rbxasset://sounds/bass.wav", Volume = 0.25, Pitch = 1.6 },
	Dash = { Id = "rbxasset://sounds/swoosh.wav", Volume = 0.6, Pitch = 1.2 },
	Slide = { Id = "rbxasset://sounds/swordslash.wav", Volume = 0.45, Pitch = 0.7 },
	Steal = { Id = "rbxasset://sounds/swordlunge.wav", Volume = 0.6, Pitch = 1 },
	Block = { Id = "rbxasset://sounds/collide.wav", Volume = 0.7, Pitch = 0.9 },
	Whistle = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.6, Pitch = 1.9 },
	Tick = { Id = "rbxasset://sounds/switch.wav", Volume = 0.6, Pitch = 1 },
	Goal = { Id = "rbxasset://sounds/victory.wav", Volume = 0.8, Pitch = 1 },
	Ability = { Id = "rbxasset://sounds/unsheath.wav", Volume = 0.6, Pitch = 1 },
	Ultimate = { Id = "rbxasset://sounds/Rocket whoosh 01.wav", Volume = 0.8, Pitch = 0.8 },
	Click = { Id = "rbxasset://sounds/button.wav", Volume = 0.5, Pitch = 1 },
}

return Config
