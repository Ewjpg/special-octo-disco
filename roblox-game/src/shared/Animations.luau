-- Все анимации игры заданы кодом: ключевые позы суставов в градусах.
-- Их проигрывает клиентский ProcAnimator поверх стандартных анимаций ходьбы/бега.
--
-- Позы описаны для R15 (15 суставов). Для R6 (6 суставов) они пересчитываются автоматически,
-- см. retarget ниже; если авто-поза не нравится, анимации можно дать поле r6 с позами вручную.
--
-- Формат сустава: { rx, ry, rz, px, py, pz } — поворот в градусах и (необязательно) смещение в студах.
-- Оси одинаковы для обоих типов аватара (персонаж смотрит вдоль -Z):
--   +rx  нога/рука вперёд, корпус — назад      -rx  нога/рука назад, корпус — наклон вперёд
--   +ry  поворот влево                          -ry  поворот вправо
--   +rz  конечность вправо, корпус — влево      -rz  конечность влево, корпус — вправо
--   Колено сгибается через -rx, локоть — через +rx (только R15).
-- Сустав, не указанный ни в одном ключе анимации, остаётся под обычной анимацией Roblox.

local R15 = {}

local function mirrorPose(pose)
	local result = {}
	for joint, v in pairs(pose) do
		local name = joint
		if string.sub(joint, 1, 5) == "Right" then
			name = "Left" .. string.sub(joint, 6)
		elseif string.sub(joint, 1, 4) == "Left" then
			name = "Right" .. string.sub(joint, 5)
		end
		result[name] = { v[1] or 0, -(v[2] or 0), -(v[3] or 0), -(v[4] or 0), v[5] or 0, v[6] or 0 }
	end
	return result
end

local function mirror(anim)
	local copy = table.clone(anim)
	copy.keys = {}
	for i, key in ipairs(anim.keys) do
		copy.keys[i] = { t = key.t, ease = key.ease, pose = mirrorPose(key.pose) }
	end
	return copy
end

local REST = {}

---------------------------------------------------------------------------
-- Удары
---------------------------------------------------------------------------

local WINDUP = {
	Root = { -6, -18, 0 },
	Waist = { -8, -14, 0 },
	Neck = { 4, 26, 0 },
	RightHip = { -48, 0, 6 },
	RightKnee = { -62, 0, 0 },
	RightAnkle = { 0, 0, 0 },
	LeftHip = { 14, 0, -4 },
	LeftKnee = { -18, 0, 0 },
	LeftShoulder = { 38, 0, -42 },
	LeftElbow = { 22, 0, 0 },
	RightShoulder = { -46, 0, 26 },
	RightElbow = { 34, 0, 0 },
}

-- Замах, пока игрок держит кнопку удара.
R15.ChargeHold = {
	loop = true,
	length = 0.7,
	fadeIn = 0.14,
	fadeOut = 0.12,
	priority = 2,
	keys = {
		{ t = 0, pose = WINDUP },
		{
			t = 0.35,
			ease = "sine",
			pose = {
				Root = { -8, -22, 0 },
				Waist = { -10, -16, 0 },
				Neck = { 6, 32, 0 },
				RightHip = { -56, 0, 6 },
				RightKnee = { -70, 0, 0 },
				RightAnkle = { 0, 0, 0 },
				LeftHip = { 16, 0, -4 },
				LeftKnee = { -22, 0, 0 },
				LeftShoulder = { 44, 0, -46 },
				LeftElbow = { 22, 0, 0 },
				RightShoulder = { -52, 0, 28 },
				RightElbow = { 34, 0, 0 },
			},
		},
		{ t = 0.7, ease = "sine", pose = WINDUP },
	},
}

-- Удар: начинается из замаха, нога выстреливает вперёд.
R15.Shoot = {
	length = 0.52,
	fadeIn = 0.04,
	fadeOut = 0.2,
	priority = 3,
	keys = {
		{ t = 0, pose = WINDUP },
		{
			t = 0.09,
			ease = "quadIn",
			pose = {
				Root = { -4, 10, 0 },
				Waist = { 4, 14, 0 },
				Neck = { -4, -18, 0 },
				RightHip = { 72, 0, -6 },
				RightKnee = { -8, 0, 0 },
				RightAnkle = { -22, 0, 0 },
				LeftHip = { -10, 0, -4 },
				LeftKnee = { -12, 0, 0 },
				LeftShoulder = { -30, 0, -30 },
				LeftElbow = { 20, 0, 0 },
				RightShoulder = { 40, 0, 30 },
				RightElbow = { 30, 0, 0 },
			},
		},
		{
			t = 0.21,
			ease = "quadOut",
			pose = {
				Root = { 6, 16, 0 },
				Waist = { 8, 18, 0 },
				Neck = { -8, -26, 0 },
				RightHip = { 98, 0, -10 },
				RightKnee = { -24, 0, 0 },
				RightAnkle = { -22, 0, 0 },
				LeftHip = { -16, 0, -4 },
				LeftKnee = { -8, 0, 0 },
				LeftShoulder = { -44, 0, -36 },
				LeftElbow = { 20, 0, 0 },
				RightShoulder = { 58, 0, 24 },
				RightElbow = { 30, 0, 0 },
			},
		},
		{ t = 0.52, ease = "quadInOut", pose = REST },
	},
}

-- Усиленный удар для способностей: замах 0.2 с, затем выстрел.
R15.PowerShot = {
	length = 0.7,
	fadeIn = 0.06,
	fadeOut = 0.22,
	priority = 4,
	keys = {
		{
			t = 0,
			pose = {
				Root = { -6, -18, 0 },
				Waist = { -8, -14, 0 },
				Neck = { 4, 26, 0 },
				RightHip = { -40, 0, 6 },
				RightKnee = { -50, 0, 0 },
				RightAnkle = { 0, 0, 0 },
				LeftHip = { 14, 0, -4 },
				LeftKnee = { -18, 0, 0 },
				LeftShoulder = { 30, 0, -40 },
				LeftElbow = { 22, 0, 0 },
				RightShoulder = { -40, 0, 26 },
				RightElbow = { 34, 0, 0 },
			},
		},
		{
			t = 0.17,
			ease = "quadOut",
			pose = {
				Root = { -12, -32, 0 },
				Waist = { -12, -24, 0 },
				Neck = { 8, 48, 0 },
				RightHip = { -74, 0, 10 },
				RightKnee = { -98, 0, 0 },
				RightAnkle = { 0, 0, 0 },
				LeftHip = { 20, 0, -4 },
				LeftKnee = { -28, 0, 0 },
				LeftShoulder = { 62, 0, -52 },
				LeftElbow = { 24, 0, 0 },
				RightShoulder = { -72, 0, 34 },
				RightElbow = { 30, 0, 0 },
			},
		},
		{
			t = 0.26,
			ease = "quadIn",
			pose = {
				Root = { -2, 18, 0 },
				Waist = { 6, 22, 0 },
				Neck = { -6, -34, 0 },
				RightHip = { 84, 0, -8 },
				RightKnee = { -6, 0, 0 },
				RightAnkle = { -25, 0, 0 },
				LeftHip = { -14, 0, -4 },
				LeftKnee = { -14, 0, 0 },
				LeftShoulder = { -50, 0, -40 },
				LeftElbow = { 20, 0, 0 },
				RightShoulder = { 50, 0, 36 },
				RightElbow = { 30, 0, 0 },
			},
		},
		{
			t = 0.4,
			ease = "quadOut",
			pose = {
				Root = { 12, 26, 0, 0, 0.3, 0 },
				Waist = { 12, 26, 0 },
				Neck = { -10, -44, 0 },
				RightHip = { 114, 0, -14 },
				RightKnee = { -30, 0, 0 },
				RightAnkle = { -25, 0, 0 },
				LeftHip = { -22, 0, -4 },
				LeftKnee = { -10, 0, 0 },
				LeftShoulder = { -62, 0, -44 },
				LeftElbow = { 20, 0, 0 },
				RightShoulder = { 66, 0, 30 },
				RightElbow = { 30, 0, 0 },
			},
		},
		{ t = 0.7, ease = "quadInOut", pose = REST },
	},
}

-- Пас щёчкой.
R15.Pass = {
	length = 0.36,
	fadeIn = 0.04,
	fadeOut = 0.16,
	priority = 3,
	keys = {
		{
			t = 0,
			pose = {
				Waist = { -4, -8, 0 },
				RightHip = { -24, 0, 8 },
				RightKnee = { -32, 0, 0 },
				LeftHip = { 6, 0, 0 },
				LeftKnee = { -10, 0, 0 },
				RightShoulder = { -20, 0, 14 },
				LeftShoulder = { 20, 0, -16 },
			},
		},
		{
			t = 0.08,
			ease = "quadIn",
			pose = {
				Waist = { 2, 8, 0 },
				RightHip = { 46, -26, 0 },
				RightKnee = { -10, 0, 0 },
				LeftHip = { -6, 0, 0 },
				LeftKnee = { -14, 0, 0 },
				RightShoulder = { 24, 0, 14 },
				LeftShoulder = { -18, 0, -18 },
			},
		},
		{
			t = 0.2,
			ease = "quadOut",
			pose = {
				Waist = { 2, 6, 0 },
				RightHip = { 30, -16, 0 },
				RightKnee = { -14, 0, 0 },
				LeftHip = { -4, 0, 0 },
				LeftKnee = { -10, 0, 0 },
				RightShoulder = { 14, 0, 12 },
				LeftShoulder = { -10, 0, -14 },
			},
		},
		{ t = 0.36, ease = "quadInOut", pose = REST },
	},
}

-- Навес: подсечка мяча с отклонением назад.
R15.Lob = {
	length = 0.46,
	fadeIn = 0.04,
	fadeOut = 0.18,
	priority = 3,
	keys = {
		{
			t = 0,
			pose = {
				Root = { -6, 0, 0 },
				Waist = { -4, 0, 0 },
				RightHip = { -36, 0, 4 },
				RightKnee = { -52, 0, 0 },
				RightAnkle = { 0, 0, 0 },
				LeftHip = { 8, 0, 0 },
				LeftKnee = { -14, 0, 0 },
				RightShoulder = { -24, 0, 30 },
				LeftShoulder = { 24, 0, -36 },
			},
		},
		{
			t = 0.09,
			ease = "quadIn",
			pose = {
				Root = { 10, 0, 0 },
				Waist = { 8, 0, 0 },
				RightHip = { 50, 0, 0 },
				RightKnee = { -30, 0, 0 },
				RightAnkle = { 22, 0, 0 },
				LeftHip = { -8, 0, 0 },
				LeftKnee = { -12, 0, 0 },
				RightShoulder = { 10, 0, 52 },
				LeftShoulder = { 10, 0, -52 },
			},
		},
		{
			t = 0.24,
			ease = "quadOut",
			pose = {
				Root = { 14, 0, 0 },
				Waist = { 10, 0, 0 },
				RightHip = { 74, 0, 0 },
				RightKnee = { -42, 0, 0 },
				RightAnkle = { 22, 0, 0 },
				LeftHip = { -12, 0, 0 },
				LeftKnee = { -8, 0, 0 },
				RightShoulder = { 0, 0, 60 },
				LeftShoulder = { 0, 0, -60 },
			},
		},
		{ t = 0.46, ease = "quadInOut", pose = REST },
	},
}

---------------------------------------------------------------------------
-- Движение и борьба
---------------------------------------------------------------------------

local SLIDE = {
	Root = { 60, 0, 0, 0, -1.5, 0.5 },
	Waist = { -30, 0, 0 },
	Neck = { -22, 0, 0 },
	RightHip = { 26, 0, -4 },
	RightKnee = { -4, 0, 0 },
	RightAnkle = { -20, 0, 0 },
	LeftHip = { 50, 0, -12 },
	LeftKnee = { -60, 0, 0 },
	LeftAnkle = { 10, 0, 0 },
	RightShoulder = { -64, 0, 24 },
	RightElbow = { 20, 0, 0 },
	LeftShoulder = { -52, 0, -30 },
	LeftElbow = { 32, 0, 0 },
}

-- Подкат: корпус отклонён назад, правая нога вытянута вперёд, левая согнута коленом вверх.
R15.Slide = {
	length = 0.8,
	fadeIn = 0.07,
	fadeOut = 0.22,
	priority = 4,
	keys = {
		{ t = 0, pose = SLIDE },
		{ t = 0.55, pose = SLIDE },
		{ t = 0.8, ease = "quadInOut", pose = REST },
	},
}

local DASH_A = {
	Root = { -34, 0, 0 },
	Waist = { -10, 0, 0 },
	Neck = { 30, 0, 0 },
	RightShoulder = { -72, 0, 18 },
	RightElbow = { 10, 0, 0 },
	LeftShoulder = { -72, 0, -18 },
	LeftElbow = { 10, 0, 0 },
	RightHip = { 62, 0, 0 },
	RightKnee = { -74, 0, 0 },
	LeftHip = { -30, 0, 0 },
	LeftKnee = { -22, 0, 0 },
}

-- Рывок: корпус вперёд, руки отведены назад.
R15.Dash = {
	length = 0.38,
	fadeIn = 0.05,
	fadeOut = 0.16,
	priority = 3,
	keys = {
		{ t = 0, pose = DASH_A },
		{
			t = 0.2,
			pose = {
				Root = { -34, 0, 0 },
				Waist = { -10, 0, 0 },
				Neck = { 30, 0, 0 },
				RightShoulder = { -72, 0, 18 },
				RightElbow = { 10, 0, 0 },
				LeftShoulder = { -72, 0, -18 },
				LeftElbow = { 10, 0, 0 },
				RightHip = { -24, 0, 0 },
				RightKnee = { -30, 0, 0 },
				LeftHip = { 56, 0, 0 },
				LeftKnee = { -70, 0, 0 },
			},
		},
		{ t = 0.38, ease = "quadInOut", pose = REST },
	},
}

-- Таран плечом (Бастион).
R15.Ram = {
	length = 0.5,
	fadeIn = 0.05,
	fadeOut = 0.18,
	priority = 4,
	keys = {
		{
			t = 0,
			pose = {
				Root = { -30, 26, 0 },
				Waist = { -12, 18, 0 },
				Neck = { 22, -40, 0 },
				RightShoulder = { 34, 0, -8 },
				RightElbow = { 112, 0, 0 },
				LeftShoulder = { -54, 0, -20 },
				LeftElbow = { 30, 0, 0 },
				RightHip = { 56, 0, 0 },
				RightKnee = { -70, 0, 0 },
				LeftHip = { -32, 0, 0 },
				LeftKnee = { -18, 0, 0 },
			},
		},
		{
			t = 0.3,
			pose = {
				Root = { -30, 26, 0 },
				Waist = { -12, 18, 0 },
				Neck = { 22, -40, 0 },
				RightShoulder = { 34, 0, -8 },
				RightElbow = { 112, 0, 0 },
				LeftShoulder = { -54, 0, -20 },
				LeftElbow = { 30, 0, 0 },
				RightHip = { -26, 0, 0 },
				RightKnee = { -24, 0, 0 },
				LeftHip = { 54, 0, 0 },
				LeftKnee = { -66, 0, 0 },
			},
		},
		{ t = 0.5, ease = "quadInOut", pose = REST },
	},
}

-- Оглушение после отбора: шатается.
R15.Stun = {
	length = 0.8,
	fadeIn = 0.05,
	fadeOut = 0.25,
	priority = 5,
	keys = {
		{
			t = 0.08,
			ease = "quadOut",
			pose = {
				Root = { 22, 0, 8 },
				Waist = { 14, 0, 0 },
				Neck = { -20, 0, 0 },
				RightShoulder = { 40, 0, 70 },
				RightElbow = { 30, 0, 0 },
				LeftShoulder = { 30, 0, -80 },
				LeftElbow = { 30, 0, 0 },
				RightHip = { 30, 0, 6 },
				RightKnee = { -40, 0, 0 },
				LeftHip = { -20, 0, 0 },
				LeftKnee = { -30, 0, 0 },
			},
		},
		{
			t = 0.42,
			ease = "quadInOut",
			pose = {
				Root = { -18, 0, -6 },
				Waist = { -16, 0, 0 },
				Neck = { 14, 0, 0 },
				RightShoulder = { -20, 0, 40 },
				RightElbow = { 40, 0, 0 },
				LeftShoulder = { -30, 0, -36 },
				LeftElbow = { 40, 0, 0 },
				RightHip = { -10, 0, 4 },
				RightKnee = { -36, 0, 0 },
				LeftHip = { 24, 0, -4 },
				LeftKnee = { -44, 0, 0 },
			},
		},
		{ t = 0.8, ease = "quadInOut", pose = REST },
	},
}

-- Дриблинг (финт с мячом): качнулся в одну сторону — ушёл в другую.
R15.Dribble = {
	length = 0.4,
	fadeIn = 0.04,
	fadeOut = 0.16,
	priority = 3,
	keys = {
		{
			t = 0,
			pose = {
				Root = { -10, 0, -16 },
				Waist = { -6, -12, 0 },
				Neck = { 4, 14, 0 },
				RightShoulder = { -30, 0, 44 },
				RightElbow = { 30, 0, 0 },
				LeftShoulder = { 34, 0, -54 },
				LeftElbow = { 30, 0, 0 },
				RightHip = { 34, 0, 12 },
				RightKnee = { -44, 0, 0 },
				LeftHip = { -16, 0, -12 },
				LeftKnee = { -20, 0, 0 },
			},
		},
		{
			t = 0.16,
			ease = "quadInOut",
			pose = {
				Root = { -14, 0, 14 },
				Waist = { -8, 12, 0 },
				Neck = { 4, -14, 0 },
				RightShoulder = { 34, 0, 54 },
				RightElbow = { 30, 0, 0 },
				LeftShoulder = { -30, 0, -44 },
				LeftElbow = { 30, 0, 0 },
				RightHip = { -18, 0, 10 },
				RightKnee = { -24, 0, 0 },
				LeftHip = { 38, 0, -10 },
				LeftKnee = { -48, 0, 0 },
			},
		},
		{ t = 0.4, ease = "quadInOut", pose = REST },
	},
}

---------------------------------------------------------------------------
-- Способности и эмоции
---------------------------------------------------------------------------

-- Выброс руки вперёд (притяжение, барьер).
R15.Cast = {
	length = 0.55,
	fadeIn = 0.06,
	fadeOut = 0.18,
	priority = 4,
	keys = {
		{
			t = 0.1,
			ease = "quadOut",
			pose = {
				Root = { -6, 12, 0 },
				Waist = { -4, 16, 0 },
				Neck = { 0, -24, 0 },
				RightShoulder = { 92, 0, 8 },
				RightElbow = { 4, 0, 0 },
				LeftShoulder = { -30, 0, -24 },
				LeftElbow = { 50, 0, 0 },
				RightHip = { 16, 0, 10 },
				RightKnee = { -14, 0, 0 },
				LeftHip = { -18, 0, -10 },
				LeftKnee = { -16, 0, 0 },
			},
		},
		{
			t = 0.38,
			pose = {
				Root = { -6, 12, 0 },
				Waist = { -4, 16, 0 },
				Neck = { 0, -24, 0 },
				RightShoulder = { 88, 0, 8 },
				RightElbow = { 8, 0, 0 },
				LeftShoulder = { -30, 0, -24 },
				LeftElbow = { 50, 0, 0 },
				RightHip = { 16, 0, 10 },
				RightKnee = { -14, 0, 0 },
				LeftHip = { -18, 0, -10 },
				LeftKnee = { -16, 0, 0 },
			},
		},
		{ t = 0.55, ease = "quadInOut", pose = REST },
	},
}

-- Включение ульты: сжался — и раскрылся.
R15.PowerStance = {
	length = 0.95,
	fadeIn = 0.08,
	fadeOut = 0.22,
	priority = 5,
	keys = {
		{
			t = 0.12,
			ease = "quadOut",
			pose = {
				Root = { -16, 0, 0, 0, -0.5, 0 },
				Waist = { -12, 0, 0 },
				Neck = { -14, 0, 0 },
				RightShoulder = { 20, 0, 10 },
				RightElbow = { 110, 0, 0 },
				LeftShoulder = { 20, 0, -10 },
				LeftElbow = { 110, 0, 0 },
				RightHip = { 34, 0, 8 },
				RightKnee = { -64, 0, 0 },
				LeftHip = { 34, 0, -8 },
				LeftKnee = { -64, 0, 0 },
			},
		},
		{
			t = 0.32,
			ease = "backOut",
			pose = {
				Root = { 12, 0, 0 },
				Waist = { 14, 0, 0 },
				Neck = { 22, 0, 0 },
				RightShoulder = { -24, 0, 64 },
				RightElbow = { 40, 0, 0 },
				LeftShoulder = { -24, 0, -64 },
				LeftElbow = { 40, 0, 0 },
				RightHip = { 6, 0, 14 },
				RightKnee = { -10, 0, 0 },
				LeftHip = { 6, 0, -14 },
				LeftKnee = { -10, 0, 0 },
			},
		},
		{
			t = 0.72,
			pose = {
				Root = { 10, 0, 0 },
				Waist = { 12, 0, 0 },
				Neck = { 20, 0, 0 },
				RightShoulder = { -22, 0, 60 },
				RightElbow = { 44, 0, 0 },
				LeftShoulder = { -22, 0, -60 },
				LeftElbow = { 44, 0, 0 },
				RightHip = { 6, 0, 14 },
				RightKnee = { -10, 0, 0 },
				LeftHip = { 6, 0, -14 },
				LeftKnee = { -10, 0, 0 },
			},
		},
		{ t = 0.95, ease = "quadInOut", pose = REST },
	},
}

-- Празднование гола: присел и выпрыгнул с руками вверх.
R15.Celebrate = {
	length = 1.9,
	fadeIn = 0.1,
	fadeOut = 0.3,
	priority = 4,
	keys = {
		{
			t = 0.18,
			ease = "quadOut",
			pose = {
				Root = { -14, 0, 0, 0, -0.6, 0 },
				Waist = { -8, 0, 0 },
				Neck = { 6, 0, 0 },
				RightShoulder = { -20, 0, 20 },
				RightElbow = { 96, 0, 0 },
				LeftShoulder = { -20, 0, -20 },
				LeftElbow = { 96, 0, 0 },
				RightHip = { 40, 0, 4 },
				RightKnee = { -72, 0, 0 },
				LeftHip = { 40, 0, -4 },
				LeftKnee = { -72, 0, 0 },
			},
		},
		{
			t = 0.42,
			ease = "backOut",
			pose = {
				Root = { 8, 0, 0, 0, 0.5, 0 },
				Waist = { 10, 0, 0 },
				Neck = { 16, 0, 0 },
				RightShoulder = { 168, 0, 24 },
				RightElbow = { 6, 0, 0 },
				LeftShoulder = { 168, 0, -24 },
				LeftElbow = { 6, 0, 0 },
				RightHip = { -8, 0, 6 },
				RightKnee = { -6, 0, 0 },
				LeftHip = { -8, 0, -6 },
				LeftKnee = { -6, 0, 0 },
			},
		},
		{
			t = 0.9,
			ease = "sine",
			pose = {
				Root = { 6, 0, 4 },
				Waist = { 8, 0, 4 },
				Neck = { 14, 0, 0 },
				RightShoulder = { 160, 0, 42 },
				RightElbow = { 20, 0, 0 },
				LeftShoulder = { 172, 0, -18 },
				LeftElbow = { 4, 0, 0 },
				RightHip = { -4, 0, 8 },
				RightKnee = { -10, 0, 0 },
				LeftHip = { -4, 0, -8 },
				LeftKnee = { -10, 0, 0 },
			},
		},
		{
			t = 1.4,
			ease = "sine",
			pose = {
				Root = { 6, 0, -4 },
				Waist = { 8, 0, -4 },
				Neck = { 14, 0, 0 },
				RightShoulder = { 172, 0, 18 },
				RightElbow = { 4, 0, 0 },
				LeftShoulder = { 160, 0, -42 },
				LeftElbow = { 20, 0, 0 },
				RightHip = { -4, 0, 8 },
				RightKnee = { -10, 0, 0 },
				LeftHip = { -4, 0, -8 },
				LeftKnee = { -10, 0, 0 },
			},
		},
		{ t = 1.9, ease = "quadInOut", pose = REST },
	},
}

-- Прыжок вратаря вправо (влево — зеркально).
R15.DiveRight = {
	length = 0.75,
	fadeIn = 0.06,
	fadeOut = 0.25,
	priority = 4,
	keys = {
		{
			t = 0.12,
			ease = "quadOut",
			pose = {
				Root = { 0, 0, -68, 0, -0.4, 0 },
				Waist = { 0, 0, -12 },
				Neck = { 0, 0, 20 },
				RightShoulder = { 0, 0, 150 },
				RightElbow = { 6, 0, 0 },
				LeftShoulder = { 30, 0, 110 },
				LeftElbow = { 10, 0, 0 },
				RightHip = { 0, 0, 14 },
				RightKnee = { -10, 0, 0 },
				LeftHip = { 10, 0, -16 },
				LeftKnee = { -30, 0, 0 },
			},
		},
		{
			t = 0.5,
			pose = {
				Root = { 0, 0, -74, 0, -0.9, 0 },
				Waist = { 0, 0, -12 },
				Neck = { 0, 0, 20 },
				RightShoulder = { 0, 0, 156 },
				RightElbow = { 6, 0, 0 },
				LeftShoulder = { 30, 0, 116 },
				LeftElbow = { 10, 0, 0 },
				RightHip = { 0, 0, 14 },
				RightKnee = { -10, 0, 0 },
				LeftHip = { 10, 0, -16 },
				LeftKnee = { -30, 0, 0 },
			},
		},
		{ t = 0.75, ease = "quadInOut", pose = REST },
	},
}
R15.DiveLeft = mirror(R15.DiveRight)

---------------------------------------------------------------------------
-- Подготовка: в каждом ключе должны быть все суставы анимации.
---------------------------------------------------------------------------

local ZERO = { 0, 0, 0, 0, 0, 0 }

local function compile(name: string, anim)
	anim.name = name
	local joints = {}
	local seen = {}
	for _, key in ipairs(anim.keys) do
		for joint in pairs(key.pose) do
			if not seen[joint] then
				seen[joint] = true
				table.insert(joints, joint)
			end
		end
	end
	table.sort(joints)
	anim.joints = joints
	table.sort(anim.keys, function(a, b)
		return a.t < b.t
	end)
	for _, key in ipairs(anim.keys) do
		local full = {}
		for _, joint in ipairs(joints) do
			local v = key.pose[joint] or ZERO
			full[joint] = { v[1] or 0, v[2] or 0, v[3] or 0, v[4] or 0, v[5] or 0, v[6] or 0 }
		end
		key.pose = full
	end
end

---------------------------------------------------------------------------
-- R6: шесть суставов. Корпус цельный, локтей и коленей нет.
---------------------------------------------------------------------------

-- Корпус R6 вращаем вокруг линии бёдер (на 1 студ ниже центра), а не вокруг центра —
-- иначе при наклоне ноги «уезжали» бы назад.
local R6_PIVOTS = { RootJoint = { 0, -1, 0 } }

-- Поза R15 -> поза R6.
--   корпус   = таз + поясница
--   плечо    = плечо + половина сгиба локтя
--   бедро    = бедро + часть сгиба колена, минус поворот поясницы (в R6 ноги растут из цельного корпуса)
-- Ноги R6 не гнутся, поэтому замах ограничен, а приседать можно только настолько, насколько ноги наклонены.
local LEG_LENGTH = 2

local function retargetPose(pose)
	local function get(name: string)
		return pose[name] or ZERO
	end
	local root, waist = get("Root"), get("Waist")
	local torso = { root[1] + waist[1], root[2] + waist[2], root[3] + waist[3], root[4], root[5], root[6] }
	local out = {}
	if pose.Neck then
		out.Neck = table.clone(pose.Neck)
	end

	-- Насколько можно опустить корпус, чтобы самая «вертикальная» нога не ушла под газон.
	local straightest = 1
	local hasLegs = false
	for _, side in ipairs({ "Right", "Left" }) do
		local shoulder = pose[side .. "Shoulder"]
		if shoulder then
			local elbow = get(side .. "Elbow")
			out[side .. " Shoulder"] = { shoulder[1] + elbow[1] * 0.5, shoulder[2], shoulder[3], 0, 0, 0 }
		end
		local hip = pose[side .. "Hip"]
		if hip then
			local knee = get(side .. "Knee")
			local rx = math.clamp(hip[1] + knee[1] * 0.2 - waist[1], -62, 112)
			local ry, rz = hip[2] - waist[2], hip[3] - waist[3]
			out[side .. " Hip"] = { rx, ry, rz, 0, 0, 0 }
			local vertical = math.cos(math.rad(torso[1] + rx)) * math.cos(math.rad(torso[3] + rz))
			if not hasLegs then
				straightest = vertical
				hasLegs = true
			else
				straightest = math.max(straightest, vertical)
			end
		end
	end
	if pose.Root or pose.Waist then
		local lowest = LEG_LENGTH * math.max(straightest, 0) - LEG_LENGTH
		torso[5] = math.max(torso[5], lowest)
		out.RootJoint = torso
	end
	return out
end

local function retarget(anim)
	local copy = table.clone(anim)
	copy.r6 = nil
	copy.pivots = R6_PIVOTS
	copy.keys = {}
	local source = anim.r6 and anim.r6.keys or nil
	if source then
		-- Позы R6 заданы вручную.
		for i, key in ipairs(source) do
			copy.keys[i] = { t = key.t, ease = key.ease, pose = key.pose }
		end
	else
		for i, key in ipairs(anim.keys) do
			copy.keys[i] = { t = key.t, ease = key.ease, pose = retargetPose(key.pose) }
		end
	end
	return copy
end

local R6 = {}
for name, anim in pairs(R15) do
	compile(name, anim)
end
for name, anim in pairs(R15) do
	local converted = retarget(anim)
	compile(name, converted)
	R6[name] = converted
end

local Animations = { R15 = R15, R6 = R6 }

-- Анимация по имени для нужного типа аватара ("R6" или "R15").
function Animations.get(name: string, rig: string?)
	local set = rig == "R6" and R6 or R15
	return set[name]
end

return Animations
