-- Строит весь стадион из деталей при запуске сервера: газон, разметку, ворота, борта, трибуны, свет.
-- Размеры берутся из Shared/FieldSpec, цвета команд — из Shared/Config.

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

local WHITE = Color3.fromRGB(238, 242, 248)
local DARK = Color3.fromRGB(26, 28, 36)
local CONCRETE = Color3.fromRGB(52, 55, 66)

local HOME = Config.Teams.Home
local AWAY = Config.Teams.Away

local function teamOfSide(side: number)
	return side == HOME.Side and HOME or AWAY
end

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

	local ground = newPart(
		pitch,
		"Ground",
		Vector3.new(F.Length + 520, 6, F.Width + 520),
		at(0, -3.06, 0),
		Color3.fromRGB(34, 36, 44),
		Enum.Material.Concrete
	)
	ground.CastShadow = false

	-- Полосы газона.
	local stripes = 13
	local stripeWidth = F.Length / stripes
	for i = 0, stripes - 1 do
		local x = -HL + stripeWidth * (i + 0.5)
		local color = i % 2 == 0 and Color3.fromRGB(58, 142, 68) or Color3.fromRGB(49, 126, 58)
		local stripe = newPart(pitch, "Grass", Vector3.new(stripeWidth, 1, F.Width), at(x, -0.5, 0), color, Enum.Material.Grass)
		stripe.CastShadow = false
	end

	-- Зона за линиями.
	local apronColor = Color3.fromRGB(38, 100, 50)
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

	arc(lines, 0, 0, F.CenterRadius, 0, 360, 56)
	spot(lines, 0, 0, 1.2)

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
		spot(lines, spotX, 0, 0.9)

		-- Дуга у штрафной: только та часть, что снаружи площади.
		local arcRadius = 22
		local half = math.deg(math.acos((F.PenaltyDepth - F.PenaltySpot) / arcRadius))
		local centerAngle = s == 1 and 180 or 0
		arc(lines, spotX, 0, arcRadius, centerAngle - half, centerAngle + half, 16)

		-- Угловые дуги.
		for _, zs in ipairs({ -1, 1 }) do
			local from
			if s == 1 then
				from = zs == 1 and 180 or 90
			else
				from = zs == 1 and 270 or 0
			end
			arc(lines, goalX, zs * HW, 4, from, from + 90, 6)
		end
	end
end

local function cylinder(parent: Instance, name: string, length: number, radius: number, cframe: CFrame, color: Color3): Part
	local p = newPart(parent, name, Vector3.new(length, radius * 2, radius * 2), cframe, color, Enum.Material.Metal)
	p.Shape = Enum.PartType.Cylinder
	return p
end

local function buildGoal(root: Instance, side: number)
	local team = teamOfSide(side)
	local goal = folder(root, side == -1 and "GoalHome" or "GoalAway")
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
	local netColor = Color3.fromRGB(225, 230, 240)
	local function strand(size: Vector3, cf: CFrame)
		local p = newPart(goal, "Net", size, cf, netColor)
		p.Transparency = 0.35
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

	-- Светящаяся полоса в цвет команды за линией ворот.
	local glow =
		newPart(goal, "GoalGlow", Vector3.new(1, 0.1, F.GoalWidth - 2), at(side * (HL + 1.6), 0.05, 0), team.Color, Enum.Material.Neon)
	decor(glow)
end

local function addBoardText(panel: Part, face: Enum.NormalId, text: string, color: Color3)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	gui.CanvasSize = Vector2.new(900, 70)
	gui.LightInfluence = 0
	gui.Parent = panel

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.Text = text
	label.TextColor3 = color
	label.TextScaled = true
	label.Parent = gui
end

local function buildWalls(root: Instance)
	local walls = folder(root, "Walls")
	local boardH = 4.5
	local boardT = 2
	local wallT = 6
	local wallH = F.WallHeight

	local function board(size: Vector3, cf: CFrame, ledColor: Color3)
		newPart(walls, "Board", size, cf, DARK, Enum.Material.Metal)
		local ledSize = Vector3.new(size.X + 0.02, 0.35, size.Z + 0.02)
		decor(newPart(walls, "BoardLed", ledSize, cf * CFrame.new(0, size.Y / 2 + 0.17, 0), ledColor, Enum.Material.Neon))
	end

	-- Боковые борта: половина в цвет каждой команды.
	for _, zs in ipairs({ -1, 1 }) do
		local z = zs * (ARENA_Z + boardT / 2)
		for _, team in ipairs({ HOME, AWAY }) do
			board(Vector3.new(ARENA_X, boardH, boardT), at(team.Side * ARENA_X / 2, boardH / 2, z), team.Color)
		end
		invisible(
			newPart(walls, "Wall", Vector3.new(ARENA_X * 2 + wallT * 2, wallH, wallT), at(0, wallH / 2, zs * (ARENA_Z + wallT / 2)), WHITE)
		)

		-- Рекламные панели с названием игры.
		local face = zs == 1 and Enum.NormalId.Front or Enum.NormalId.Back
		for i = -2, 2 do
			local panel = newPart(
				walls,
				"AdPanel",
				Vector3.new(44, 3.4, 0.2),
				at(i * 54, boardH / 2, zs * (ARENA_Z - 0.12)),
				Color3.fromRGB(14, 15, 20)
			)
			decor(panel)
			local color = i < 0 and HOME.Color or (i > 0 and AWAY.Color or WHITE)
			addBoardText(panel, face, Config.GameTitle, color)
		end
	end

	-- Торцевые борта.
	for _, team in ipairs({ HOME, AWAY }) do
		local s = team.Side
		board(Vector3.new(boardT, boardH, ARENA_Z * 2 + boardT * 2), at(s * (ARENA_X + boardT / 2), boardH / 2, 0), team.Color)
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
			local color = teamOfSide(xs).Color
			newPart(walls, "CornerBoard", Vector3.new(length, boardH, boardT), cf * CFrame.new(0, boardH / 2, 0), DARK, Enum.Material.Metal)
			decor(
				newPart(
					walls,
					"BoardLed",
					Vector3.new(length, 0.35, boardT + 0.02),
					cf * CFrame.new(0, boardH + 0.17, 0),
					color,
					Enum.Material.Neon
				)
			)
			invisible(newPart(walls, "CornerWall", Vector3.new(length, wallH, 4), cf * CFrame.new(0, wallH / 2, 0), WHITE))
		end
	end

	invisible(newPart(walls, "Ceiling", Vector3.new(ARENA_X * 2 + 20, 6, ARENA_Z * 2 + 20), at(0, wallH + 3, 0), WHITE))
end

local CROWD_NEUTRAL = {
	Color3.fromRGB(230, 230, 235),
	Color3.fromRGB(60, 62, 74),
	Color3.fromRGB(245, 205, 90),
	Color3.fromRGB(150, 155, 170),
}

local function buildStands(root: Instance)
	local stands = folder(root, "Stands")
	local crowd = folder(stands, "Crowd")
	local rng = Random.new(20241)
	local rowDepth = 5
	local rowRise = 3.2
	local baseTop = 6

	local function fan(x: number, y: number, z: number, team)
		local color
		if rng:NextNumber() < 0.6 then
			color = team.Color:Lerp(Color3.new(1, 1, 1), rng:NextNumber() * 0.35)
		else
			color = CROWD_NEUTRAL[rng:NextInteger(1, #CROWD_NEUTRAL)]
		end
		local body = newPart(crowd, "Fan", Vector3.new(1.5, 2.3 + rng:NextNumber() * 0.5, 1.2), at(x, y + 1.2, z), color)
		decor(body)
	end

	-- Боковые трибуны (вдоль длинных сторон).
	local sideRows = 8
	local sideLength = ARENA_X * 2
	for _, zs in ipairs({ -1, 1 }) do
		for row = 0, sideRows - 1 do
			local top = baseTop + row * rowRise
			local z = zs * (ARENA_Z + 8 + rowDepth * (row + 0.5))
			local shade = row % 2 == 0 and CONCRETE or Color3.fromRGB(44, 46, 56)
			newPart(stands, "Tier", Vector3.new(sideLength, top, rowDepth), at(0, top / 2, z), shade, Enum.Material.Concrete)
			for _, team in ipairs({ HOME, AWAY }) do
				local seat = newPart(
					stands,
					"Seats",
					Vector3.new(sideLength / 2 - 2, 0.5, rowDepth - 1.6),
					at(team.Side * sideLength / 4, top + 0.25, z),
					team.Color:Lerp(DARK, 0.55)
				)
				decor(seat)
			end
			for x = -ARENA_X + 3, ARENA_X - 3, 5 do
				if rng:NextNumber() < 0.55 then
					fan(x + rng:NextNumber() * 2, top + 0.5, z, x < 0 and HOME or AWAY)
				end
			end
		end
		-- Козырёк.
		local roofZ = zs * (ARENA_Z + 8 + rowDepth * sideRows - 14)
		local roofY = baseTop + sideRows * rowRise + 16
		local roofCf = at(0, roofY, roofZ) * CFrame.Angles(math.rad(zs * 10), 0, 0)
		local roof = newPart(stands, "Roof", Vector3.new(sideLength + 30, 1.5, 44), roofCf, DARK, Enum.Material.Metal)
		roof.CanCollide = false
		decor(
			newPart(
				stands,
				"RoofLed",
				Vector3.new(sideLength + 30, 0.6, 0.8),
				roofCf * CFrame.new(0, -0.8, -zs * 21.5),
				WHITE,
				Enum.Material.Neon
			)
		)
	end

	-- Торцевые трибуны (за воротами).
	local endRows = 6
	local endLength = ARENA_Z * 2
	for _, team in ipairs({ HOME, AWAY }) do
		local s = team.Side
		for row = 0, endRows - 1 do
			local top = baseTop + row * rowRise
			local x = s * (ARENA_X + 8 + rowDepth * (row + 0.5))
			local shade = row % 2 == 0 and CONCRETE or Color3.fromRGB(44, 46, 56)
			newPart(stands, "Tier", Vector3.new(rowDepth, top, endLength), at(x, top / 2, 0), shade, Enum.Material.Concrete)
			decor(
				newPart(stands, "Seats", Vector3.new(rowDepth - 1.6, 0.5, endLength - 2), at(x, top + 0.25, 0), team.Color:Lerp(DARK, 0.55))
			)
			for z = -ARENA_Z + 3, ARENA_Z - 3, 5 do
				if rng:NextNumber() < 0.55 then
					fan(x, top + 0.5, z + rng:NextNumber() * 2, team)
				end
			end
		end
	end
end

local function buildScoreboard(root: Instance, side: number)
	local screens = folder(root, side == -1 and "ScreenHome" or "ScreenAway")
	local x = side * (ARENA_X + 8 + 5 * 6 + 6)
	local y = 6 + 6 * 3.2 + 22
	local frame = newPart(screens, "Frame", Vector3.new(3, 30, 74), at(x + side * 0.6, y, 0), DARK, Enum.Material.Metal)
	frame.CanCollide = false
	for _, zs in ipairs({ -1, 1 }) do
		local pole = newPart(screens, "Pole", Vector3.new(3, y, 3), at(x + side * 0.6, y / 2, zs * 30), DARK, Enum.Material.Metal)
		pole.CanCollide = false
	end
	local screen = newPart(screens, "Screen", Vector3.new(0.4, 26, 70), at(x - side * 1.1, y, 0), Color3.fromRGB(10, 11, 16))
	decor(screen)

	local gui = Instance.new("SurfaceGui")
	gui.Face = side == 1 and Enum.NormalId.Left or Enum.NormalId.Right
	gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	gui.CanvasSize = Vector2.new(1050, 390)
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

	label(Config.GameTitle, UDim2.fromScale(0.2, 0.04), UDim2.fromScale(0.6, 0.16), WHITE)
	label(HOME.Name, UDim2.fromScale(0.03, 0.24), UDim2.fromScale(0.3, 0.2), HOME.Color)
	label(AWAY.Name, UDim2.fromScale(0.67, 0.24), UDim2.fromScale(0.3, 0.2), AWAY.Color)
	local score = label("0 : 0", UDim2.fromScale(0.25, 0.4), UDim2.fromScale(0.5, 0.4), WHITE)
	local clock = label("5:00", UDim2.fromScale(0.36, 0.8), UDim2.fromScale(0.28, 0.16), Color3.fromRGB(255, 221, 120))
	table.insert(FieldBuilder.scoreLabels, score)
	table.insert(FieldBuilder.timeLabels, clock)
end

local function buildLights(root: Instance)
	local lights = folder(root, "Lights")
	local towerX = ARENA_X + 58
	local towerZ = ARENA_Z + 66
	for _, xs in ipairs({ -1, 1 }) do
		for _, zs in ipairs({ -1, 1 }) do
			local height = 96
			local pole =
				newPart(lights, "Tower", Vector3.new(4, height, 4), at(xs * towerX, height / 2, zs * towerZ), DARK, Enum.Material.Metal)
			pole.CanCollide = false
			local headPosition = O + Vector3.new(xs * towerX, height + 4, zs * towerZ)
			local panelCf = CFrame.lookAt(headPosition, O)
			decor(newPart(lights, "LampFrame", Vector3.new(30, 16, 2), panelCf, DARK, Enum.Material.Metal))
			for row = -1, 1 do
				for col = -3, 3 do
					local lamp = newPart(
						lights,
						"Lamp",
						Vector3.new(3.2, 3.6, 0.6),
						panelCf * CFrame.new(col * 4, row * 4.8, -1.2),
						Color3.fromRGB(255, 249, 232),
						Enum.Material.Neon
					)
					decor(lamp)
				end
			end
		end
	end
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
		spawn.CFrame = CFrame.new(F.fromOwnGoal(team.Side, 60, 0) + Vector3.new(0, -0.5, 0))
		spawn.Neutral = false
		spawn.TeamColor = BrickColor.new(team.Color)
		spawn.AllowTeamChangeOnTouch = false
		spawn.Duration = 0
		spawn.Parent = spawns
	end
end

local function setupLighting()
	Lighting.ClockTime = 20.5
	Lighting.GeographicLatitude = 28
	Lighting.Brightness = 2.4
	Lighting.Ambient = Color3.fromRGB(118, 122, 150)
	Lighting.OutdoorAmbient = Color3.fromRGB(150, 156, 188)
	Lighting.ColorShift_Top = Color3.fromRGB(200, 215, 255)
	Lighting.EnvironmentDiffuseScale = 0.6
	Lighting.EnvironmentSpecularScale = 0.5
	Lighting.ExposureCompensation = 0.45
	Lighting.GlobalShadows = true
	Lighting.FogEnd = 100000

	for _, child in ipairs(Lighting:GetChildren()) do
		if child:IsA("PostEffect") or child:IsA("Atmosphere") then
			child:Destroy()
		end
	end

	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Density = 0.24
	atmosphere.Offset = 0.2
	atmosphere.Color = Color3.fromRGB(168, 182, 222)
	atmosphere.Decay = Color3.fromRGB(70, 82, 130)
	atmosphere.Glare = 0
	atmosphere.Haze = 1.4
	atmosphere.Parent = Lighting

	local bloom = Instance.new("BloomEffect")
	bloom.Intensity = 0.55
	bloom.Size = 26
	bloom.Threshold = 1.15
	bloom.Parent = Lighting

	local grade = Instance.new("ColorCorrectionEffect")
	grade.Contrast = 0.1
	grade.Saturation = 0.16
	grade.TintColor = Color3.fromRGB(246, 248, 255)
	grade.Parent = Lighting
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
	buildStands(root)
	buildScoreboard(root, -1)
	buildScoreboard(root, 1)
	buildLights(root)
	buildSpawns(root)
	setupLighting()

	root.Parent = Workspace
	return root
end

return FieldBuilder
