-- Строит весь стадион из деталей при запуске сервера: газон, разметку, ворота, борта, трибуны, крышу, небо и свет.
-- Размеры берутся из Shared/FieldSpec, цвета команд — из Shared/Config.
-- Вид — дневной: яркий газон в полоску, светлая чаша стадиона с двумя ярусами и крышей, облачное небо.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Teams = game:GetService("Teams")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local F = require(Shared.FieldSpec)

local FieldBuilder = {}

-- Надписи табло, которые обновляет MatchService.
FieldBuilder.scoreLabels = {}
FieldBuilder.timeLabels = {}

local O = F.Origin
local HL, HW = F.HalfLength, F.HalfWidth
local ARENA_X = HL + F.EndMargin
local ARENA_Z = HW + F.SideMargin

local WHITE = Color3.fromRGB(244, 246, 250)
local STEEL = Color3.fromRGB(74, 80, 94)
local WALKWAY = Color3.fromRGB(152, 158, 170)

local HOME = Config.Teams.Home
local AWAY = Config.Teams.Away

local function newPart(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Material = material or Enum.Material.SmoothPlastic
	part.Color = color
	part.Size = size
	part.CFrame = cframe
	part.Parent = parent
	return part
end

local function decor(part: Part): Part
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	return part
end

local function invisible(part: Part): Part
	part.Transparency = 1
	part.CastShadow = false
	part.CanQuery = false
	return part
end

local function at(x: number, y: number, z: number): CFrame
	return CFrame.new(O + Vector3.new(x, y, z))
end

local function folder(parent: Instance, name: string): Folder
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

-- Плоская линия разметки между двумя точками поля.
local LINE_Y = 0.04
local function line(parent: Instance, x1: number, z1: number, x2: number, z2: number, width: number?)
	local dx, dz = x2 - x1, z2 - z1
	local length = math.sqrt(dx * dx + dz * dz)
	if length < 0.01 then
		return
	end
	local yaw = math.atan2(-dz, dx)
	local cf = at((x1 + x2) / 2, LINE_Y, (z1 + z2) / 2) * CFrame.Angles(0, yaw, 0)
	local p = newPart(parent, "Line", Vector3.new(length + 0.05, 0.08, width or F.LineWidth), cf, WHITE)
	decor(p)
end

-- Дуга окружности из коротких отрезков. Углы в градусах, 0 = +X, 90 = +Z.
local function arc(parent: Instance, cx: number, cz: number, radius: number, fromDeg: number, toDeg: number, segments: number)
	local prevX, prevZ
	for i = 0, segments do
		local a = math.rad(fromDeg + (toDeg - fromDeg) * i / segments)
		local x, z = cx + math.cos(a) * radius, cz + math.sin(a) * radius
		if prevX then
			line(parent, prevX, prevZ, x, z)
		end
		prevX, prevZ = x, z
	end
end

local function spot(parent: Instance, x: number, z: number, radius: number)
	local cf = at(x, LINE_Y, z) * CFrame.Angles(0, 0, math.rad(90))
	local p = newPart(parent, "Spot", Vector3.new(0.08, radius * 2, radius * 2), cf, WHITE)
	p.Shape = Enum.PartType.Cylinder
	decor(p)
end

local function buildPitch(root: Instance)
	local pitch = folder(root, "Pitch")

	-- Площадь вокруг стадиона.
	local ground = newPart(
		pitch,
		"Ground",
		Vector3.new(F.Length + 900, 6, F.Width + 900),
		at(0, -3.06, 0),
		Color3.fromRGB(176, 180, 188),
		Enum.Material.Concrete
	)
	ground.CastShadow = false

	-- Газон: тёмный, насыщенный, с еле заметными полосами покоса.
	local stripes = 19
	local stripeWidth = F.Length / stripes
	for i = 0, stripes - 1 do
		local x = -HL + stripeWidth * (i + 0.5)
		local color = i % 2 == 0 and Color3.fromRGB(76, 116, 64) or Color3.fromRGB(70, 108, 59)
		local stripe = newPart(pitch, "Grass", Vector3.new(stripeWidth, 1, F.Width), at(x, -0.5, 0), color, Enum.Material.Grass)
		stripe.CastShadow = false
	end

	-- Газон за линиями до бортов.
	local apronColor = Color3.fromRGB(64, 98, 56)
	for _, s in ipairs({ -1, 1 }) do
		local endApron = newPart(
			pitch,
			"Apron",
			Vector3.new(F.EndMargin, 1, ARENA_Z * 2),
			at(s * (HL + F.EndMargin / 2), -0.5, 0),
			apronColor,
			Enum.Material.Grass
		)
		endApron.CastShadow = false
		local sideApron = newPart(
			pitch,
			"Apron",
			Vector3.new(F.Length, 1, F.SideMargin),
			at(0, -0.5, s * (HW + F.SideMargin / 2)),
			apronColor,
			Enum.Material.Grass
		)
		sideApron.CastShadow = false
	end
end

local function buildLines(root: Instance)
	local lines = folder(root, "Lines")

	line(lines, -HL, -HW, HL, -HW)
	line(lines, -HL, HW, HL, HW)
	line(lines, -HL, -HW, -HL, HW)
	line(lines, HL, -HW, HL, HW)
	line(lines, 0, -HW, 0, HW)

	arc(lines, 0, 0, F.CenterRadius, 0, 360, 72)
	spot(lines, 0, 0, 1.4)

	for _, s in ipairs({ -1, 1 }) do
		local goalX = s * HL
		local boxX = s * (HL - F.PenaltyDepth)
		local halfBox = F.PenaltyWidth / 2
		line(lines, goalX, -halfBox, boxX, -halfBox)
		line(lines, goalX, halfBox, boxX, halfBox)
		line(lines, boxX, -halfBox, boxX, halfBox)

		local areaX = s * (HL - F.GoalAreaDepth)
		local halfArea = F.GoalAreaWidth / 2
		line(lines, goalX, -halfArea, areaX, -halfArea)
		line(lines, goalX, halfArea, areaX, halfArea)
		line(lines, areaX, -halfArea, areaX, halfArea)

		local spotX = s * (HL - F.PenaltySpot)
		spot(lines, spotX, 0, 1.1)

		-- Дуга у штрафной: только та часть, что снаружи площади.
		local half = math.deg(math.acos((F.PenaltyDepth - F.PenaltySpot) / F.PenaltyArc))
		local centerAngle = s == 1 and 180 or 0
		arc(lines, spotX, 0, F.PenaltyArc, centerAngle - half, centerAngle + half, 20)

		-- Угловые дуги.
		for _, zs in ipairs({ -1, 1 }) do
			local from
			if s == 1 then
				from = zs == 1 and 180 or 90
			else
				from = zs == 1 and 270 or 0
			end
			arc(lines, goalX, zs * HW, 5, from, from + 90, 6)
		end
	end
end

local function cylinder(parent: Instance, name: string, length: number, radius: number, cframe: CFrame, color: Color3): Part
	local p = newPart(parent, name, Vector3.new(length, radius * 2, radius * 2), cframe, color, Enum.Material.Metal)
	p.Shape = Enum.PartType.Cylinder
	return p
end

local function buildGoal(root: Instance, side: number)
	local goal = folder(root, side == HOME.Side and "GoalHome" or "GoalAway")
	local gx = side * HL
	local backX = side * (HL + F.GoalDepth)
	local midX = side * (HL + F.GoalDepth / 2)
	local halfW = F.GoalWidth / 2
	local h = F.GoalHeight
	local r = F.PostRadius
	local vertical = CFrame.Angles(0, 0, math.rad(90))
	local alongZ = CFrame.Angles(0, math.rad(90), 0)

	-- Каркас.
	for _, zs in ipairs({ -1, 1 }) do
		cylinder(goal, "Post", h, r, at(gx, h / 2, zs * halfW) * vertical, WHITE)
		decor(cylinder(goal, "BackPost", h, r * 0.5, at(backX, h / 2, zs * halfW) * vertical, WHITE))
		decor(cylinder(goal, "TopRail", F.GoalDepth, r * 0.5, at(midX, h, zs * halfW), WHITE))
	end
	cylinder(goal, "Crossbar", F.GoalWidth + r * 2, r, at(gx, h, 0) * alongZ, WHITE)
	decor(cylinder(goal, "BackBar", F.GoalWidth, r * 0.5, at(backX, h, 0) * alongZ, WHITE))

	-- Сетка: тонкие нити без столкновений.
	local netColor = Color3.fromRGB(236, 240, 246)
	local function strand(size: Vector3, cf: CFrame)
		local p = newPart(goal, "Net", size, cf, netColor)
		p.Transparency = 0.3
		decor(p)
	end
	local t = 0.12
	local step = 2
	for z = -halfW + step, halfW - step, step do
		strand(Vector3.new(t, h, t), at(backX, h / 2, z))
		strand(Vector3.new(F.GoalDepth, t, t), at(midX, h, z))
	end
	for y = step, h - 1, step do
		strand(Vector3.new(t, t, F.GoalWidth), at(backX, y, 0))
		for _, zs in ipairs({ -1, 1 }) do
			strand(Vector3.new(F.GoalDepth, t, t), at(midX, y, zs * halfW))
		end
	end
	for d = step, F.GoalDepth - 1, step do
		local x = side * (HL + d)
		strand(Vector3.new(t, t, F.GoalWidth), at(x, h, 0))
		for _, zs in ipairs({ -1, 1 }) do
			strand(Vector3.new(t, h, t), at(x, h / 2, zs * halfW))
		end
	end

	-- Невидимые стенки сетки: останавливают мяч.
	local thick = 3
	invisible(
		newPart(
			goal,
			"NetBack",
			Vector3.new(thick, h + thick, F.GoalWidth + thick * 2),
			at(backX + side * thick / 2, (h + thick) / 2, 0),
			WHITE
		)
	)
	invisible(newPart(goal, "NetTop", Vector3.new(F.GoalDepth, thick, F.GoalWidth + thick * 2), at(midX, h + thick / 2 + r, 0), WHITE))
	for _, zs in ipairs({ -1, 1 }) do
		invisible(
			newPart(
				goal,
				"NetSide",
				Vector3.new(F.GoalDepth - r * 2, h, thick),
				at(midX + side * r, h / 2, zs * (halfW + thick / 2)),
				WHITE
			)
		)
	end
end

-- Борта вокруг поля (мяч от них отскакивает) и невидимые стены до потолка арены.
local function buildWalls(root: Instance)
	local walls = folder(root, "Walls")
	local boardH = 4.5
	local boardT = 2
	local wallT = 6
	local wallH = F.WallHeight

	-- Борт: тёмно-синий корпус и светодиодная панель в цвет команды той половины поля, где он стоит.
	local function board(length: number, cf: CFrame, color: Color3)
		newPart(walls, "Board", Vector3.new(length, boardH, boardT), cf, Color3.fromRGB(24, 44, 104), Enum.Material.Metal)
		local faceCf = cf * CFrame.new(0, -0.2, -boardT / 2 - 0.08)
		local face = newPart(
			walls,
			"BoardFace",
			Vector3.new(length - 0.6, boardH - 1.4, 0.2),
			faceCf,
			color:Lerp(Color3.fromRGB(40, 44, 56), 0.4),
			Enum.Material.SmoothPlastic
		)
		decor(face)
	end

	local segment = 24
	-- Боковые борта. Лицевая сторона смотрит на поле (локальная -Z детали).
	for _, zs in ipairs({ -1, 1 }) do
		local z = zs * (ARENA_Z + boardT / 2)
		local count = math.floor((ARENA_X * 2 - 32) / segment)
		local span = (ARENA_X * 2 - 32) / count
		for i = 0, count - 1 do
			local x = -ARENA_X + 16 + span * (i + 0.5)
			local cf = CFrame.lookAt(O + Vector3.new(x, boardH / 2, z), O + Vector3.new(x, boardH / 2, 0))
			board(span - 0.4, cf, x < 0 and HOME.Color or AWAY.Color)
		end
		invisible(
			newPart(walls, "Wall", Vector3.new(ARENA_X * 2 + wallT * 2, wallH, wallT), at(0, wallH / 2, zs * (ARENA_Z + wallT / 2)), WHITE)
		)
	end

	-- Торцевые борта.
	for _, team in ipairs({ HOME, AWAY }) do
		local s = team.Side
		local x = s * (ARENA_X + boardT / 2)
		local count = math.floor((ARENA_Z * 2 - 32) / segment)
		local span = (ARENA_Z * 2 - 32) / count
		for i = 0, count - 1 do
			local z = -ARENA_Z + 16 + span * (i + 0.5)
			local cf = CFrame.lookAt(O + Vector3.new(x, boardH / 2, z), O + Vector3.new(0, boardH / 2, z))
			board(span - 0.4, cf, team.Color)
		end
		invisible(
			newPart(walls, "Wall", Vector3.new(wallT, wallH, ARENA_Z * 2 + wallT * 2), at(s * (ARENA_X + wallT / 2), wallH / 2, 0), WHITE)
		)
	end

	-- Скошенные углы, чтобы мяч не застревал.
	local cut = 16
	for _, xs in ipairs({ -1, 1 }) do
		for _, zs in ipairs({ -1, 1 }) do
			local length = cut * math.sqrt(2) + 2
			local cf = at(xs * (ARENA_X - cut / 2), 0, zs * (ARENA_Z - cut / 2)) * CFrame.Angles(0, math.rad(xs * zs * 45), 0)
			newPart(walls, "CornerBoard", Vector3.new(length, boardH, boardT), cf * CFrame.new(0, boardH / 2, 0), WHITE)
			invisible(newPart(walls, "CornerWall", Vector3.new(length, wallH, 4), cf * CFrame.new(0, wallH / 2, 0), WHITE))
		end
	end

	invisible(newPart(walls, "Ceiling", Vector3.new(ARENA_X * 2 + 20, 6, ARENA_Z * 2 + 20), at(0, wallH + 3, 0), WHITE))
end

---------------------------------------------------------------------------
-- Трибуны: высокая закрытая чаша — два крутых яруса, плотная мозаика зрителей,
-- синие светящиеся линии по ярусам и крыша-кольцо с открытым небом над полем.
---------------------------------------------------------------------------

local STAND_GAP = 7 -- проход между бортом и первым рядом
local LOWER_ROWS, LOWER_RISE = 12, 2.8
local UPPER_ROWS, UPPER_RISE = 14, 3.8
local ROW_DEPTH = 4.5
local LOWER_BASE = 4.5
local LOWER_TOP = LOWER_BASE + LOWER_ROWS * LOWER_RISE
local UPPER_BASE = LOWER_TOP + 8
local UPPER_TOP = UPPER_BASE + UPPER_ROWS * UPPER_RISE
local FASCIA_DEPTH = 4
local UPPER_FRONT = LOWER_ROWS * ROW_DEPTH + FASCIA_DEPTH
local BACK = UPPER_FRONT + UPPER_ROWS * ROW_DEPTH
local STAND_DEPTH = BACK + 3
local ROOF_Y = UPPER_TOP + 14
local ROOF_INNER = -12 -- крыша нависает над проходом перед трибуной

local LED_BLUE = Color3.fromRGB(46, 118, 255)
local STRUCTURE_BLUE = Color3.fromRGB(34, 66, 156)
local STRUCTURE_DARK = Color3.fromRGB(24, 44, 104)
local TIER_LIGHT = Color3.fromRGB(198, 206, 224)
local TIER_SHADE = Color3.fromRGB(182, 191, 212)

-- Зрители: каждый ряд — цепочка коротких цветных отрезков. Издалека это читается как плотная толпа.
local CROWD_SEGMENT_MIN, CROWD_SEGMENT_MAX = 3, 8
local CROWD_NEUTRAL = {
	{ Color3.fromRGB(246, 247, 252), 30 },
	{ Color3.fromRGB(30, 40, 86), 12 },
	{ Color3.fromRGB(150, 160, 186), 8 },
}

local function rival(team)
	return team == HOME and AWAY or HOME
end

local function crowdColor(rng: Random, team): Color3
	-- Почти половина мест — цвет команды этой трибуны, примерно каждое восьмое — цвет соперника.
	local roll = rng:NextNumber() * 100
	if roll < 46 then
		return team.Color:Lerp(Color3.new(1, 1, 1), rng:NextNumber() * 0.25)
	elseif roll < 58 then
		return rival(team).Color:Lerp(Color3.new(1, 1, 1), rng:NextNumber() * 0.25)
	end
	roll = rng:NextNumber() * 50
	for _, entry in ipairs(CROWD_NEUTRAL) do
		roll -= entry[2]
		if roll <= 0 then
			return entry[1]
		end
	end
	return CROWD_NEUTRAL[1][1]
end

-- Одна сторона чаши. frame — система координат стороны: X вдоль трибуны, Z — от поля наружу,
-- начало — у переднего края первого ряда на уровне газона.
local function buildStandSide(parent: Instance, frame: CFrame, length: number, team, rng: Random, withTunnel: boolean)
	local stands = folder(parent, "Stand")
	local crowd = folder(stands, "Crowd")

	local function local_(x: number, y: number, z: number): CFrame
		return frame * CFrame.new(x, y, z)
	end

	local function crowdRow(top: number, z: number, gap: number?)
		local x = -length / 2 + 1
		while x < length / 2 - 1 do
			local segment = math.min(CROWD_SEGMENT_MIN + rng:NextNumber() * (CROWD_SEGMENT_MAX - CROWD_SEGMENT_MIN), length / 2 - 1 - x)
			local mid = x + segment / 2
			if not (gap and math.abs(mid) < gap) then
				local height = 2 + rng:NextNumber() * 0.5
				local size = Vector3.new(segment - 0.15, height, 1.8)
				decor(newPart(crowd, "Fans", size, local_(mid, top + height / 2, z - 0.6), crowdColor(rng, team)))
			end
			x += segment
		end
	end

	local function tier(rows: number, rise: number, base: number, front: number, gapRows: number?, gap: number?)
		for row = 0, rows - 1 do
			local top = base + row * rise
			local z = front + ROW_DEPTH * (row + 0.5)
			local shade = row % 2 == 0 and TIER_LIGHT or TIER_SHADE
			newPart(stands, "Tier", Vector3.new(length, top, ROW_DEPTH), local_(0, top / 2, z), shade, Enum.Material.Concrete)
			crowdRow(top, z, (gapRows and row < gapRows) and gap or nil)
		end
	end

	-- Проход перед трибуной и низкая стенка с синей светящейся линией.
	local walkway = newPart(
		stands,
		"Walkway",
		Vector3.new(length, 0.4, STAND_GAP + 1),
		local_(0, 0.2, -STAND_GAP / 2 - 0.5),
		WALKWAY,
		Enum.Material.Concrete
	)
	decor(walkway)
	newPart(stands, "FrontWall", Vector3.new(length, LOWER_BASE, 1.2), local_(0, LOWER_BASE / 2, 0.6), STRUCTURE_DARK)
	decor(newPart(stands, "FrontLed", Vector3.new(length, 0.5, 0.3), local_(0, LOWER_BASE - 0.6, -0.1), LED_BLUE, Enum.Material.Neon))

	-- Туннель выхода игроков в середине нижнего яруса.
	local tunnelRows, tunnelHalf = 5, 14
	if withTunnel then
		tier(LOWER_ROWS, LOWER_RISE, LOWER_BASE, 0, tunnelRows, tunnelHalf)
		local depth = tunnelRows * ROW_DEPTH
		local height = LOWER_BASE + tunnelRows * LOWER_RISE + 1
		decor(
			newPart(
				stands,
				"Tunnel",
				Vector3.new(tunnelHalf * 2, height, depth),
				local_(0, height / 2, depth / 2 - 0.4),
				Color3.fromRGB(14, 20, 44)
			)
		)
		for _, xs in ipairs({ -1, 1 }) do
			decor(
				newPart(
					stands,
					"TunnelLed",
					Vector3.new(0.5, height, 0.5),
					local_(xs * tunnelHalf, height / 2, -0.7),
					LED_BLUE,
					Enum.Material.Neon
				)
			)
		end
		decor(
			newPart(stands, "TunnelLed", Vector3.new(tunnelHalf * 2 + 0.5, 0.5, 0.5), local_(0, height, -0.7), LED_BLUE, Enum.Material.Neon)
		)
	else
		tier(LOWER_ROWS, LOWER_RISE, LOWER_BASE, 0)
	end

	-- Пояс между ярусами: синий, со светящимися линиями.
	local fasciaZ = LOWER_ROWS * ROW_DEPTH + FASCIA_DEPTH / 2
	local fasciaFace = fasciaZ - FASCIA_DEPTH / 2 - 0.15
	newPart(stands, "Fascia", Vector3.new(length, UPPER_BASE, FASCIA_DEPTH), local_(0, UPPER_BASE / 2, fasciaZ), STRUCTURE_BLUE)
	decor(
		newPart(stands, "FasciaLed", Vector3.new(length, 0.9, 0.3), local_(0, UPPER_BASE - 1.6, fasciaFace), LED_BLUE, Enum.Material.Neon)
	)
	decor(newPart(stands, "FasciaLed", Vector3.new(length, 0.5, 0.3), local_(0, LOWER_TOP + 1.2, fasciaFace), WHITE, Enum.Material.Neon))

	tier(UPPER_ROWS, UPPER_RISE, UPPER_BASE, UPPER_FRONT)

	-- Растяжки болельщиков на верхнем ярусе: полотна в цвет команды, лежат по склону трибуны.
	local slope = math.atan2(UPPER_RISE, ROW_DEPTH)
	local banners = math.max(2, math.floor(length / 70))
	for i = 1, banners do
		local x = -length / 2 + length * (i - 0.5) / banners + (rng:NextNumber() - 0.5) * 20
		local row = rng:NextInteger(3, UPPER_ROWS - 4)
		local y = UPPER_BASE + row * UPPER_RISE + 3.2
		local z = UPPER_FRONT + ROW_DEPTH * (row + 0.5)
		local cf = local_(x, y, z) * CFrame.Angles(-slope, 0, 0)
		local color = rng:NextNumber() < 0.75 and team.Color or rival(team).Color
		decor(newPart(stands, "Banner", Vector3.new(16, 0.3, 11), cf, color))
		decor(newPart(stands, "Banner", Vector3.new(16, 0.32, 2.4), cf, WHITE))
	end

	-- Задняя стена до крыши.
	newPart(stands, "BackWall", Vector3.new(length, ROOF_Y, 3), local_(0, ROOF_Y / 2, BACK + 1.5), STRUCTURE_BLUE, Enum.Material.Metal)

	-- Крыша: панели (белые и голубые, как стекло) на синих фермах, по краю — светящаяся линия.
	local roofDepth = STAND_DEPTH - ROOF_INNER + 2
	local roofZ = ROOF_INNER + roofDepth / 2
	local panels = math.max(2, math.floor(length / 14))
	for i = 0, panels - 1 do
		local x = -length / 2 + length * (i + 0.5) / panels
		local color = i % 2 == 0 and Color3.fromRGB(236, 242, 252) or Color3.fromRGB(196, 220, 252)
		local panel = newPart(stands, "RoofPanel", Vector3.new(length / panels - 0.3, 1.2, roofDepth), local_(x, ROOF_Y, roofZ), color)
		panel.CanCollide = false
	end
	for i = 0, panels do
		local x = -length / 2 + length * i / panels
		decor(
			newPart(
				stands,
				"RoofTruss",
				Vector3.new(1.2, 3.4, roofDepth),
				local_(x, ROOF_Y - 2.2, roofZ),
				STRUCTURE_BLUE,
				Enum.Material.Metal
			)
		)
	end
	decor(
		newPart(
			stands,
			"RoofEdge",
			Vector3.new(length + 2, 4.5, 1.6),
			local_(0, ROOF_Y - 1.4, ROOF_INNER),
			STRUCTURE_BLUE,
			Enum.Material.Metal
		)
	)
	decor(
		newPart(
			stands,
			"RoofLed",
			Vector3.new(length + 2, 0.7, 0.3),
			local_(0, ROOF_Y - 2.6, ROOF_INNER - 0.9),
			LED_BLUE,
			Enum.Material.Neon
		)
	)
	local lights = newPart(
		stands,
		"RoofLights",
		Vector3.new(length * 0.94, 0.7, 1),
		local_(0, ROOF_Y - 4.2, ROOF_INNER + 2),
		Color3.fromRGB(255, 250, 236),
		Enum.Material.Neon
	)
	decor(lights)
end

local function buildStands(root: Instance)
	local stands = folder(root, "Stands")
	local rng = Random.new(20241)
	local sideFront = ARENA_Z + STAND_GAP
	local endFront = ARENA_X + STAND_GAP
	-- Боковые трибуны тянутся через углы до задних стен торцов — чаша получается сплошной, без пустых углов.
	local sideLength = (endFront + STAND_DEPTH) * 2
	local endLength = sideFront * 2

	-- Боковые трибуны: одна болеет за HOME, другая за AWAY. Туннель — на трибуне HOME.
	for _, zs in ipairs({ -1, 1 }) do
		local origin = O + Vector3.new(0, 0, zs * sideFront)
		local out = Vector3.new(0, 0, zs)
		local frame = CFrame.lookAt(origin, origin - out)
		buildStandSide(stands, frame, sideLength, zs == 1 and HOME or AWAY, rng, zs == 1)
	end
	-- Торцевые трибуны: за воротами каждой команды — её болельщики.
	for _, team in ipairs({ HOME, AWAY }) do
		local origin = O + Vector3.new(team.Side * endFront, 0, 0)
		local out = Vector3.new(team.Side, 0, 0)
		local frame = CFrame.lookAt(origin, origin - out)
		buildStandSide(stands, frame, endLength, team, rng, false)
	end
end

-- Большие экраны под крышей за каждыми воротами: HOME — счёт — AWAY и время.
local function buildScoreboard(root: Instance, side: number)
	local screens = folder(root, side == HOME.Side and "ScreenHome" or "ScreenAway")
	local x = side * (ARENA_X + STAND_GAP + UPPER_FRONT - 8)
	local y = ROOF_Y - 19
	local width, height = 78, 26
	local frame = newPart(screens, "Frame", Vector3.new(2.4, height + 3, width + 3), at(x + side * 0.6, y, 0), STEEL, Enum.Material.Metal)
	frame.CanCollide = false
	for _, zs in ipairs({ -1, 1 }) do
		local cable = newPart(
			screens,
			"Cable",
			Vector3.new(0.5, ROOF_Y - y - height / 2, 0.5),
			at(x, (ROOF_Y + y + height / 2) / 2, zs * width * 0.4),
			STEEL
		)
		decor(cable)
	end
	local screen = newPart(screens, "Screen", Vector3.new(0.4, height, width), at(x - side * 1, y, 0), Color3.fromRGB(12, 14, 22))
	decor(screen)

	local gui = Instance.new("SurfaceGui")
	gui.Face = side == 1 and Enum.NormalId.Left or Enum.NormalId.Right
	gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	gui.CanvasSize = Vector2.new(1200, 400)
	gui.LightInfluence = 0
	gui.Parent = screen

	local function label(text: string, position: UDim2, size: UDim2, color: Color3): TextLabel
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Font = Enum.Font.GothamBlack
		l.Text = text
		l.TextColor3 = color
		l.TextScaled = true
		l.Position = position
		l.Size = size
		l.Parent = gui
		return l
	end

	local function band(team, position: UDim2)
		local block = Instance.new("Frame")
		block.BackgroundColor3 = team.Color
		block.BorderSizePixel = 0
		block.Position = position
		block.Size = UDim2.fromScale(0.26, 0.42)
		block.Parent = gui
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Font = Enum.Font.GothamBlack
		l.Text = team.Name
		l.TextColor3 = Color3.new(1, 1, 1)
		l.TextScaled = true
		l.Size = UDim2.fromScale(1, 1)
		l.Parent = block
	end

	band(HOME, UDim2.fromScale(0.04, 0.12))
	band(AWAY, UDim2.fromScale(0.7, 0.12))
	local score = label("0 : 0", UDim2.fromScale(0.32, 0.08), UDim2.fromScale(0.36, 0.5), WHITE)
	local clock = label("5:00", UDim2.fromScale(0.36, 0.64), UDim2.fromScale(0.28, 0.26), Color3.fromRGB(255, 221, 120))
	table.insert(FieldBuilder.scoreLabels, score)
	table.insert(FieldBuilder.timeLabels, clock)
end

local function buildSpawns(root: Instance)
	local spawns = folder(root, "Spawns")
	for key, team in pairs(Config.Teams) do
		local spawn = Instance.new("SpawnLocation")
		spawn.Name = "Spawn" .. key
		spawn.Anchored = true
		spawn.CanCollide = false
		spawn.CanTouch = false
		spawn.Transparency = 1
		spawn.Size = Vector3.new(18, 1, 18)
		spawn.CFrame = CFrame.new(F.fromOwnGoal(team.Side, 80, 0) + Vector3.new(0, -0.5, 0))
		spawn.Neutral = false
		spawn.TeamColor = BrickColor.new(team.Color)
		spawn.AllowTeamChangeOnTouch = false
		spawn.Duration = 0
		spawn.Parent = spawns
	end
end

-- Дневной свет: высокое солнце, мягкие тени, яркие чуть голубоватые тона, облака над открытой крышей.
local function setupLighting()
	Lighting.ClockTime = 14.4
	Lighting.GeographicLatitude = 32
	Lighting.Brightness = 2.3
	Lighting.Ambient = Color3.fromRGB(128, 136, 162)
	Lighting.OutdoorAmbient = Color3.fromRGB(166, 178, 208)
	Lighting.ColorShift_Top = Color3.fromRGB(236, 243, 255)
	Lighting.ColorShift_Bottom = Color3.fromRGB(0, 0, 0)
	Lighting.EnvironmentDiffuseScale = 1
	Lighting.EnvironmentSpecularScale = 0.7
	Lighting.ExposureCompensation = 0.1
	Lighting.ShadowSoftness = 0.3
	Lighting.GlobalShadows = true
	Lighting.FogEnd = 100000

	for _, child in ipairs(Lighting:GetChildren()) do
		if child:IsA("PostEffect") or child:IsA("Atmosphere") or child:IsA("Sky") then
			child:Destroy()
		end
	end

	local sky = Instance.new("Sky")
	sky.SunAngularSize = 14
	sky.Parent = Lighting

	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Density = 0.08
	atmosphere.Offset = 0
	atmosphere.Color = Color3.fromRGB(184, 196, 214)
	atmosphere.Decay = Color3.fromRGB(104, 118, 146)
	atmosphere.Glare = 0.2
	atmosphere.Haze = 0.3
	atmosphere.Parent = Lighting

	local bloom = Instance.new("BloomEffect")
	bloom.Intensity = 0.25
	bloom.Size = 24
	bloom.Threshold = 1.7
	bloom.Parent = Lighting

	local rays = Instance.new("SunRaysEffect")
	rays.Intensity = 0.05
	rays.Spread = 0.6
	rays.Parent = Lighting

	local grade = Instance.new("ColorCorrectionEffect")
	grade.Brightness = 0.03
	grade.Contrast = 0.14
	grade.Saturation = -0.06
	grade.TintColor = Color3.fromRGB(240, 242, 248)
	grade.Parent = Lighting

	-- Облака живут в Terrain.
	local terrain = Workspace:FindFirstChildOfClass("Terrain")
	if terrain then
		local old = terrain:FindFirstChildOfClass("Clouds")
		if old then
			old:Destroy()
		end
		local clouds = Instance.new("Clouds")
		clouds.Cover = 0.55
		clouds.Density = 0.6
		clouds.Color = Color3.fromRGB(255, 255, 255)
		clouds.Parent = terrain
	end
end

-- Создаёт две команды в сервисе Teams (если их ещё нет).
function FieldBuilder.ensureTeams()
	local result = {}
	for key, info in pairs(Config.Teams) do
		local team = Teams:FindFirstChild(info.Name) :: Team?
		if not team then
			local created = Instance.new("Team")
			created.Name = info.Name
			created.TeamColor = BrickColor.new(info.Color)
			created.AutoAssignable = false
			created.Parent = Teams
			team = created
		end
		result[key] = team
	end
	return result
end

function FieldBuilder.build()
	local old = Workspace:FindFirstChild("Stadium")
	if old then
		old:Destroy()
	end
	table.clear(FieldBuilder.scoreLabels)
	table.clear(FieldBuilder.timeLabels)

	local root = Instance.new("Model")
	root.Name = "Stadium"

	buildPitch(root)
	buildLines(root)
	buildGoal(root, -1)
	buildGoal(root, 1)
	buildWalls(root)
	-- A stadium mesh made in Blender (tools/stadium), imported into Workspace as StadiumMesh,
	-- replaces the part-built stands and their hanging screens.
	if not Workspace:FindFirstChild("StadiumMesh") then
		buildStands(root)
		buildScoreboard(root, -1)
		buildScoreboard(root, 1)
	end
	buildSpawns(root)
	setupLighting()

	root.Parent = Workspace
	return root
end

return FieldBuilder
