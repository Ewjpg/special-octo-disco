-- Интерфейс: табло, баннеры, полоски сил/резонанса/удара, слоты способностей, подсказка, меню стилей.
-- Всё создаётся кодом.

local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Styles = require(Shared.Styles)
local Util = require(Shared.Util)
local Controls = require(script.Parent.Controls)
local FxEvents = require(script.Parent.FxEvents)
local Sfx = require(script.Parent.Sfx)
local State = require(script.Parent.State)

local Hud = {}

local PANEL = Color3.fromRGB(14, 16, 24)
local WHITE = Color3.fromRGB(245, 247, 255)
local MUTED = Color3.fromRGB(158, 164, 184)
local GOLD = Color3.fromRGB(255, 224, 120)
local RED = Color3.fromRGB(255, 92, 92)
local HOME, AWAY = Config.Teams.Home, Config.Teams.Away
local RES_MAX = Config.Resonance.Max
-- Пока в игре нет выбираемых стилей, меню стилей, способности и Резонанс не показываем.
local STYLES_ON = Styles.enabled
-- Без шкалы Резонанса полоски внизу на одну строку ниже.
local BARS_SHIFT = STYLES_ON and 0 or 22

local root: Frame
local rootScale: UIScale
local cache = {} -- последние выставленные тексты, чтобы не трогать интерфейс без нужды

---------------------------------------------------------------------------
-- Помощники
---------------------------------------------------------------------------

local function make(className: string, props: { [string]: any }, parent: Instance?): any
	local instance = Instance.new(className)
	for key, value in pairs(props) do
		(instance :: any)[key] = value
	end
	if parent then
		instance.Parent = parent
	end
	return instance
end

local function corner(parent: Instance, radius: number)
	make("UICorner", { CornerRadius = UDim.new(0, radius) }, parent)
end

local function border(parent: Instance, color: Color3, thickness: number, transparency: number?): UIStroke
	return make("UIStroke", {
		Color = color,
		Thickness = thickness,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, parent)
end

local function text(props: { [string]: any }, parent: Instance?): TextLabel
	local label = make("TextLabel", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Font = Enum.Font.GothamBold,
		TextColor3 = WHITE,
		TextSize = 14,
		Text = "",
	}, nil)
	for key, value in pairs(props) do
		(label :: any)[key] = value
	end
	label.Parent = parent
	return label
end

local function tween(instance: Instance, time: number, goal: { [string]: any }, style: Enum.EasingStyle?)
	local t = TweenService:Create(instance, TweenInfo.new(time, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), goal)
	t:Play()
	return t
end

local function setText(label: TextLabel, value: string)
	if cache[label] ~= value then
		cache[label] = value
		label.Text = value
	end
end

local KEY_NAMES = {
	MouseButton1 = "LMB",
	MouseButton2 = "RMB",
	LeftShift = "Shift",
	LeftControl = "Ctrl",
	Space = "Space",
}

local function keyName(names: { string }): string
	local first = names[1] or "?"
	return KEY_NAMES[first] or first
end

local function formatTime(seconds: number): string
	local whole = math.max(0, math.floor(seconds + 0.5))
	return string.format("%d:%02d", whole // 60, whole % 60)
end

---------------------------------------------------------------------------
-- Табло
---------------------------------------------------------------------------

local homeScore: TextLabel, awayScore: TextLabel, clock: TextLabel, phaseLabel: TextLabel

-- Счёт сверху по центру без плашки: «HOME : 0   4:17   0 : AWAY».
local SCORE_FONT = Enum.Font.FredokaOne
local OUTLINE = Color3.fromRGB(10, 14, 32)

local function buildScoreboard()
	local board = make("Frame", {
		Name = "Scoreboard",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 10),
		Size = UDim2.fromOffset(520, 40),
		BackgroundTransparency = 1,
	}, root)

	local function label(props: { [string]: any }): TextLabel
		props.Font = SCORE_FONT
		props.TextStrokeTransparency = 0.15
		props.TextStrokeColor3 = OUTLINE
		props.Size = props.Size or UDim2.fromOffset(120, 40)
		return text(props, board)
	end

	label({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(0.5, -84, 0, 0),
		Size = UDim2.fromOffset(160, 40),
		Text = HOME.Name .. " :",
		TextColor3 = HOME.Color:Lerp(WHITE, 0.25),
		TextSize = 26,
		TextXAlignment = Enum.TextXAlignment.Right,
	})
	homeScore = label({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(0.5, -50, 0, 0),
		Size = UDim2.fromOffset(30, 40),
		Text = "0",
		TextSize = 28,
		TextXAlignment = Enum.TextXAlignment.Right,
	})
	clock = label({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 0),
		Size = UDim2.fromOffset(90, 40),
		Text = "5:00",
		TextSize = 26,
	})
	awayScore = label({
		Position = UDim2.new(0.5, 50, 0, 0),
		Size = UDim2.fromOffset(30, 40),
		Text = "0",
		TextSize = 28,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	label({
		Position = UDim2.new(0.5, 84, 0, 0),
		Size = UDim2.fromOffset(160, 40),
		Text = ": " .. AWAY.Name,
		TextColor3 = AWAY.Color:Lerp(WHITE, 0.25),
		TextSize = 26,
		TextXAlignment = Enum.TextXAlignment.Left,
	})

	phaseLabel = text({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 50),
		Size = UDim2.fromOffset(420, 20),
		Font = SCORE_FONT,
		TextColor3 = WHITE,
		TextSize = 15,
		TextStrokeTransparency = 0.3,
		TextStrokeColor3 = OUTLINE,
	}, root)
end

---------------------------------------------------------------------------
-- Баннер по центру
---------------------------------------------------------------------------

local bannerTitle: TextLabel, bannerSub: TextLabel, bannerScale: UIScale
local bannerToken = 0

local function buildBanner()
	local frame = make("Frame", {
		Name = "Banner",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.3),
		Size = UDim2.fromOffset(1000, 150),
		BackgroundTransparency = 1,
	}, root)
	bannerScale = make("UIScale", { Scale = 1 }, frame)
	bannerTitle = text({
		Size = UDim2.new(1, 0, 0, 96),
		Font = Enum.Font.GothamBlack,
		TextSize = 84,
		TextTransparency = 1,
		TextStrokeTransparency = 1,
		TextStrokeColor3 = Color3.fromRGB(8, 9, 14),
	}, frame)
	bannerSub = text({
		Position = UDim2.fromOffset(0, 100),
		Size = UDim2.new(1, 0, 0, 36),
		TextSize = 26,
		TextTransparency = 1,
		TextStrokeTransparency = 1,
		TextStrokeColor3 = Color3.fromRGB(8, 9, 14),
	}, frame)
end

function Hud.banner(title: string, subtitle: string?, color: Color3?, duration: number?)
	bannerToken += 1
	local token = bannerToken
	bannerTitle.Text = title
	bannerTitle.TextColor3 = color or WHITE
	bannerSub.Text = subtitle or ""
	bannerTitle.TextTransparency = 0
	bannerTitle.TextStrokeTransparency = 0.2
	bannerSub.TextTransparency = 0
	bannerSub.TextStrokeTransparency = 0.3
	bannerScale.Scale = 1.5
	tween(bannerScale, 0.28, { Scale = 1 }, Enum.EasingStyle.Back)
	task.delay(duration or 1.5, function()
		if token ~= bannerToken then
			return
		end
		tween(bannerTitle, 0.35, { TextTransparency = 1, TextStrokeTransparency = 1 })
		tween(bannerSub, 0.35, { TextTransparency = 1, TextStrokeTransparency = 1 })
	end)
end

---------------------------------------------------------------------------
-- Полоски: удар, силы, резонанс
---------------------------------------------------------------------------

local chargeHolder: Frame, chargeFill: Frame
local staminaFill: Frame, resonanceFill: Frame, resonanceGlow: UIStroke
local ballLabel: TextLabel, hintLabel: TextLabel
local hintToken = 0

local function bar(parent: Instance, y: number, height: number, caption: string, color: Color3)
	local holder = make("Frame", {
		Position = UDim2.fromOffset(0, y),
		Size = UDim2.new(1, 0, 0, height),
		BackgroundColor3 = Color3.fromRGB(6, 7, 12),
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
	}, parent)
	corner(holder, height / 2)
	local fill = make("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
	}, holder)
	corner(fill, height / 2)
	text({
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(0, -10, 0.5, 0),
		Size = UDim2.fromOffset(90, 14),
		Text = caption,
		TextColor3 = MUTED,
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextStrokeTransparency = 0.6,
	}, holder)
	return holder, fill
end

local function buildBars()
	local cluster = make("Frame", {
		Name = "Bars",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UserInputService.TouchEnabled and UDim2.new(0.5, 0, 1, -24) or UDim2.new(0.5, 0, 1, -112 + BARS_SHIFT),
		Size = UDim2.fromOffset(340, 66),
		BackgroundTransparency = 1,
	}, root)

	chargeHolder, chargeFill = bar(cluster, 0, 12, "SHOT", GOLD)
	chargeHolder.Visible = false
	local _, stamina = bar(cluster, 26, 10, "STAMINA", WHITE)
	staminaFill = stamina
	local resonanceHolder, resonance = bar(cluster, 48, 12, "RESONANCE", WHITE)
	resonanceFill = resonance
	resonanceGlow = border(resonanceHolder, WHITE, 2, 1)
	resonanceHolder.Visible = STYLES_ON

	ballLabel = text({
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UserInputService.TouchEnabled and UDim2.new(0.5, 0, 1, -104) or UDim2.new(0.5, 0, 1, -184 + BARS_SHIFT),
		Size = UDim2.fromOffset(300, 22),
		Text = "YOU HAVE THE BALL",
		TextColor3 = GOLD,
		TextSize = 15,
		TextStrokeTransparency = 0.4,
		Visible = false,
	}, root)

	hintLabel = text({
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UserInputService.TouchEnabled and UDim2.new(0.5, 0, 1, -132) or UDim2.new(0.5, 0, 1, -212 + BARS_SHIFT),
		Size = UDim2.fromOffset(420, 24),
		TextColor3 = RED,
		TextSize = 17,
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	}, root)
end

function Hud.hint(message: string)
	hintToken += 1
	local token = hintToken
	hintLabel.Text = message
	hintLabel.TextTransparency = 0
	hintLabel.TextStrokeTransparency = 0.4
	task.delay(1.1, function()
		if token == hintToken then
			tween(hintLabel, 0.3, { TextTransparency = 1, TextStrokeTransparency = 1 })
		end
	end)
end

---------------------------------------------------------------------------
-- Слоты способностей
---------------------------------------------------------------------------

local slots = {} -- [key] = { frame, stroke, name, overlay, time, total }
-- "Action" — контекстная клавиша: без мяча подкат, с мячом дриблинг.
local slotOrder = STYLES_ON and { "Action", "Dash", "A1", "A2", "A3" } or { "Action", "Dash" }

local function buildSlots()
	local touch = UserInputService.TouchEnabled
	local holder = make("Frame", {
		Name = "Slots",
		-- На ПК — по центру внизу, под полоской сил; на телефоне — справа сверху, чтобы не мешать кнопкам.
		AnchorPoint = touch and Vector2.new(1, 0) or Vector2.new(0.5, 1),
		Position = touch and UDim2.new(1, -18, 0, 86) or UDim2.new(0.5, 0, 1, -10),
		Size = UDim2.fromOffset(#slotOrder * 78, 92),
		BackgroundTransparency = 1,
	}, root)
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = touch and Enum.HorizontalAlignment.Right or Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, holder)

	local keys = {
		Action = keyName(Config.Controls.Action),
		Dash = keyName(Config.Controls.Dash),
		A1 = keyName(Config.Controls.Ability1),
		A2 = keyName(Config.Controls.Ability2),
		A3 = keyName(Config.Controls.Ability3),
	}

	for index, key in ipairs(slotOrder) do
		local cell = make("Frame", {
			Name = key,
			LayoutOrder = index,
			Size = UDim2.fromOffset(68, 92),
			BackgroundTransparency = 1,
		}, holder)
		local frame = make("Frame", {
			Size = UDim2.fromOffset(68, 68),
			BackgroundColor3 = PANEL,
			BackgroundTransparency = 0.15,
			BorderSizePixel = 0,
			ClipsDescendants = true,
		}, cell)
		corner(frame, 12)
		local stroke = border(frame, WHITE, 2, 0.5)
		text({
			Position = UDim2.fromOffset(8, 5),
			Size = UDim2.fromOffset(52, 18),
			Text = keys[key],
			TextSize = 15,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 3,
		}, frame)
		local overlay = make("Frame", {
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			Size = UDim2.fromScale(1, 0),
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 0.4,
			BorderSizePixel = 0,
			ZIndex = 2,
		}, frame)
		local timeLabel = text({
			Position = UDim2.fromOffset(0, 22),
			Size = UDim2.new(1, 0, 0, 30),
			Font = Enum.Font.GothamBlack,
			TextSize = 22,
			ZIndex = 3,
		}, frame)
		local nameLabel = text({
			Position = UDim2.fromOffset(-6, 70),
			Size = UDim2.fromOffset(80, 22),
			Font = Enum.Font.GothamMedium,
			TextColor3 = MUTED,
			TextSize = 10,
			TextWrapped = true,
			TextYAlignment = Enum.TextYAlignment.Top,
			TextStrokeTransparency = 0.6,
		}, cell)
		slots[key] = { frame = frame, stroke = stroke, name = nameLabel, overlay = overlay, time = timeLabel, total = 1 }
	end

	slots.Dash.name.Text = "DASH"
	slots.Dash.total = Config.Dash.Cooldown
	slots.Action.name.Text = "TACKLE"
	slots.Action.total = Config.Tackle.Cooldown
end

-- Подписи и цвета слотов под текущий стиль.
local shownStyle: string? = nil

local function refreshStyle()
	local style = State.style()
	if shownStyle == style.id then
		return
	end
	shownStyle = style.id
	for index = 1, STYLES_ON and 3 or 0 do
		local slot = slots["A" .. index]
		local ability = style.abilities[index]
		slot.name.Text = ability and Util.upper(ability.name) or "—"
		slot.total = ability and ability.cooldown or 1
		slot.stroke.Color = style.color
	end
	resonanceFill.BackgroundColor3 = style.color
	resonanceGlow.Color = style.color
end

local function flashSlot(key: string)
	local slot = slots[key]
	if not slot then
		return
	end
	local original = slot.stroke.Color
	slot.stroke.Color = RED
	slot.stroke.Transparency = 0
	task.delay(0.25, function()
		slot.stroke.Color = original
	end)
end

local function updateSlots(hasBall: boolean, resonance: number)
	local style = State.style()
	for _, key in ipairs(slotOrder) do
		local slot = slots[key]
		local cooldownKey = key
		if key == "Action" then
			-- Слот показывает то действие, которое сейчас сработает по этой клавише.
			cooldownKey = hasBall and "Dribble" or "Tackle"
			slot.total = hasBall and Config.Dribble.Cooldown or Config.Tackle.Cooldown
			setText(slot.name, hasBall and "DRIBBLE" or "TACKLE")
		end
		local remaining = State.cooldown(cooldownKey)
		local fraction = math.clamp(remaining / math.max(slot.total, 0.01), 0, 1)
		local label = ""
		if remaining >= 10 then
			label = tostring(math.floor(remaining))
		elseif remaining > 0 then
			label = string.format("%.1f", remaining)
		end
		local usable = remaining <= 0

		if key ~= "Action" and key ~= "Dash" then
			local ability = style.abilities[tonumber(string.sub(key, 2)) :: number]
			if not ability then
				usable = false
			else
				if ability.needsBall and not hasBall then
					usable = false
				end
				if ability.needsNoBall and hasBall then
					usable = false
				end
				if ability.ultimate and remaining <= 0 and resonance < RES_MAX then
					-- Ульта: слот заполняется по мере накопления резонанса.
					usable = false
					fraction = 1 - resonance / RES_MAX
					label = string.format("%d%%", math.floor(resonance / RES_MAX * 100))
				end
			end
		end

		slot.overlay.Size = UDim2.fromScale(1, fraction)
		setText(slot.time, label)
		slot.stroke.Transparency = usable and 0 or 0.65
		slot.frame.BackgroundTransparency = usable and 0.1 or 0.3
	end
end

---------------------------------------------------------------------------
-- Подсказка по управлению
---------------------------------------------------------------------------

local helpPanel: Frame, helpChip: TextLabel

local function buildHelp()
	local c = Config.Controls
	local lines = {
		{ "WASD / Space", "move, jump" },
		{ keyName(c.Sprint), "sprint (uses stamina)" },
		{ keyName(c.Shoot) .. " (hold)", "shoot: hold longer, kick harder" },
		{ keyName(c.Action), "tackle; with the ball: dribble" },
		{ keyName(c.Pass), "pass to a teammate" },
		{ keyName(c.Lob), "lob" },
		{ keyName(c.Dash), "dash" },
	}
	if STYLES_ON then
		table.insert(lines, { keyName(c.Ability1) .. "  " .. keyName(c.Ability2), "style abilities" })
		table.insert(lines, { keyName(c.Ability3), "ultimate (full Resonance)" })
		table.insert(lines, { keyName(c.StyleMenu), "change style" })
	end
	table.insert(lines, { c.ShiftLock == "LeftControl" and "Ctrl" or c.ShiftLock, "lock camera" })

	helpPanel = make("Frame", {
		Name = "Help",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 18, 1, -24),
		Size = UDim2.fromOffset(340, 46 + #lines * 20),
		BackgroundColor3 = PANEL,
		BackgroundTransparency = 0.18,
		BorderSizePixel = 0,
	}, root)
	corner(helpPanel, 12)
	border(helpPanel, WHITE, 1, 0.88)
	text({
		Position = UDim2.fromOffset(14, 10),
		Size = UDim2.new(1, -28, 0, 18),
		Text = "CONTROLS   [" .. keyName(c.Help) .. " to hide]",
		TextColor3 = GOLD,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, helpPanel)
	for index, line in ipairs(lines) do
		local y = 34 + (index - 1) * 20
		text({
			Position = UDim2.fromOffset(14, y),
			Size = UDim2.fromOffset(110, 18),
			Text = line[1],
			TextSize = 13,
			TextXAlignment = Enum.TextXAlignment.Left,
		}, helpPanel)
		text({
			Position = UDim2.fromOffset(128, y),
			Size = UDim2.new(1, -140, 0, 18),
			Font = Enum.Font.GothamMedium,
			Text = line[2],
			TextColor3 = MUTED,
			TextSize = 13,
			TextXAlignment = Enum.TextXAlignment.Left,
		}, helpPanel)
	end

	helpChip = text({
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 18, 1, -24),
		Size = UDim2.fromOffset(190, 26),
		BackgroundColor3 = PANEL,
		BackgroundTransparency = 0.25,
		Text = keyName(c.Help) .. ": controls",
		TextColor3 = MUTED,
		TextSize = 12,
		Visible = false,
	}, root)
	corner(helpChip, 8)
end

local function setHelp(visible: boolean)
	helpPanel.Visible = visible
	helpChip.Visible = not visible
end

---------------------------------------------------------------------------
-- Меню стилей
---------------------------------------------------------------------------

local menu: TextButton, styleButton: TextButton
local cards = {} -- [styleId] = { stroke, button }

local function setMenu(open: boolean)
	menu.Visible = open
	Controls.menuOpen = open
	if open then
		local current = State.style().id
		for id, card in pairs(cards) do
			local selected = id == current
			card.stroke.Transparency = selected and 0 or 0.7
			card.stroke.Thickness = selected and 3 or 1
			card.button.Text = selected and "SELECTED" or "SELECT"
		end
	end
end

local function chooseStyle(style)
	Sfx.play("Click", nil)
	if style.id ~= State.style().id then
		State.send("SelectStyle", style.id)
		Hud.banner(Util.upper(style.name), style.tagline, style.color, 1.6)
	end
	setMenu(false)
end

local function buildStyleCard(style, parent: Instance, order: number)
	local card = make("Frame", {
		Name = style.id,
		LayoutOrder = order,
		Size = UDim2.fromOffset(214, 396),
		BackgroundColor3 = Color3.fromRGB(22, 25, 36),
		BorderSizePixel = 0,
	}, parent)
	corner(card, 14)
	local stroke = border(card, style.color, 1, 0.7)

	local header = make("Frame", {
		Size = UDim2.new(1, 0, 0, 8),
		BackgroundColor3 = style.color,
		BorderSizePixel = 0,
	}, card)
	corner(header, 4)

	text({
		Position = UDim2.fromOffset(14, 18),
		Size = UDim2.new(1, -28, 0, 28),
		Font = Enum.Font.GothamBlack,
		Text = Util.upper(style.name),
		TextColor3 = style.color,
		TextSize = 24,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, card)
	text({
		Position = UDim2.fromOffset(14, 46),
		Size = UDim2.new(1, -28, 0, 16),
		Text = Util.upper(style.role or ""),
		TextColor3 = MUTED,
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, card)
	text({
		Position = UDim2.fromOffset(14, 66),
		Size = UDim2.new(1, -28, 0, 30),
		Font = Enum.Font.GothamMedium,
		Text = '"' .. (style.tagline or "") .. '"',
		TextSize = 12,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
	}, card)
	text({
		Position = UDim2.fromOffset(14, 98),
		Size = UDim2.new(1, -28, 0, 58),
		Font = Enum.Font.Gotham,
		Text = style.description or "",
		TextColor3 = MUTED,
		TextSize = 11,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
	}, card)

	local keys = {
		keyName(Config.Controls.Ability1),
		keyName(Config.Controls.Ability2),
		keyName(Config.Controls.Ability3),
	}
	for index = 1, 3 do
		local ability = style.abilities[index]
		if ability then
			local y = 160 + (index - 1) * 62
			text({
				Position = UDim2.fromOffset(14, y),
				Size = UDim2.new(1, -28, 0, 16),
				Text = string.format("[%s] %s", keys[index], ability.name),
				TextColor3 = ability.ultimate and GOLD or WHITE,
				TextSize = 13,
				TextXAlignment = Enum.TextXAlignment.Left,
			}, card)
			text({
				Position = UDim2.fromOffset(14, y + 17),
				Size = UDim2.new(1, -28, 0, 42),
				Font = Enum.Font.Gotham,
				Text = ability.desc or "",
				TextColor3 = MUTED,
				TextSize = 10,
				TextWrapped = true,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Top,
			}, card)
		end
	end

	local button = make("TextButton", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -12),
		Size = UDim2.new(1, -28, 0, 34),
		BackgroundColor3 = style.color,
		BorderSizePixel = 0,
		Font = Enum.Font.GothamBlack,
		Text = "SELECT",
		TextColor3 = Color3.fromRGB(14, 16, 24),
		TextSize = 14,
		AutoButtonColor = true,
	}, card)
	corner(button, 9)
	button.Activated:Connect(function()
		chooseStyle(style)
	end)

	cards[style.id] = { stroke = stroke, button = button }
end

local function buildStyleMenu()
	styleButton = make("TextButton", {
		Name = "StyleButton",
		Position = UDim2.fromOffset(18, 62),
		Size = UDim2.fromOffset(190, 34),
		BackgroundColor3 = PANEL,
		BackgroundTransparency = 0.15,
		BorderSizePixel = 0,
		Font = Enum.Font.GothamBold,
		Text = "STYLE",
		TextColor3 = WHITE,
		TextSize = 13,
	}, root)
	corner(styleButton, 10)
	border(styleButton, WHITE, 1, 0.8)

	-- Modal = true освобождает курсор, даже если камера закреплена.
	menu = make("TextButton", {
		Name = "StyleMenu",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
		Text = "",
		AutoButtonColor = false,
		Modal = true,
		Visible = false,
		ZIndex = 10,
	}, root)

	local count = #Styles.list
	local width = math.min(980, count * 228 + 40)
	local panel = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.fromOffset(width, 500),
		BackgroundColor3 = PANEL,
		BorderSizePixel = 0,
		ZIndex = 10,
	}, menu)
	corner(panel, 18)
	border(panel, WHITE, 1, 0.85)

	text({
		Position = UDim2.fromOffset(24, 16),
		Size = UDim2.new(1, -100, 0, 30),
		Font = Enum.Font.GothamBlack,
		Text = "CHOOSE YOUR STYLE",
		TextSize = 24,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 10,
	}, panel)

	local close = make("TextButton", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 14),
		Size = UDim2.fromOffset(34, 34),
		BackgroundColor3 = Color3.fromRGB(34, 38, 52),
		BorderSizePixel = 0,
		Font = Enum.Font.GothamBold,
		Text = "X",
		TextColor3 = WHITE,
		TextSize = 16,
		ZIndex = 10,
	}, panel)
	corner(close, 9)
	close.Activated:Connect(function()
		setMenu(false)
	end)

	local list = make("ScrollingFrame", {
		Position = UDim2.fromOffset(20, 60),
		Size = UDim2.new(1, -40, 1, -76),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		ScrollingDirection = Enum.ScrollingDirection.X,
		ScrollBarThickness = 6,
		ZIndex = 10,
	}, panel)
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 14),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, list)
	make("UIPadding", { PaddingLeft = UDim.new(0, 2), PaddingTop = UDim.new(0, 4) }, list)

	for index, style in ipairs(Styles.list) do
		buildStyleCard(style, list, index)
	end
	-- Всё внутри меню должно рисоваться поверх остального HUD.
	for _, descendant in ipairs(list:GetDescendants()) do
		if descendant:IsA("GuiObject") then
			descendant.ZIndex = 11
		end
	end

	styleButton.Activated:Connect(function()
		setMenu(not menu.Visible)
	end)
end

---------------------------------------------------------------------------
-- Обновление
---------------------------------------------------------------------------

local PHASE_TEXT = {
	Waiting = "WAITING FOR PLAYERS",
	Kickoff = "KICKOFF",
	Playing = "",
	Goal = "GOAL",
	FullTime = "FULL TIME: NEXT MATCH SOON",
}

local function updateScale()
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local size = camera.ViewportSize
	local scale = math.clamp(math.min(size.X / 1280, size.Y / 720), 0.55, 1.3)
	if math.abs(rootScale.Scale - scale) > 0.01 then
		rootScale.Scale = scale
		-- Корневой кадр «растягиваем обратно», чтобы после масштаба он снова занимал весь экран.
		root.Size = UDim2.fromScale(1 / scale, 1 / scale)
	end
end

local function onRender()
	updateScale()
	refreshStyle()

	local match = State.match
	setText(homeScore, tostring(match:GetAttribute("Home") or 0))
	setText(awayScore, tostring(match:GetAttribute("Away") or 0))
	setText(clock, formatTime(match:GetAttribute("TimeLeft") or 0))
	setText(phaseLabel, PHASE_TEXT[State.phase()] or "")

	if STYLES_ON then
		local style = State.style()
		setText(styleButton, string.format("STYLE: %s  [%s]", Util.upper(style.name), keyName(Config.Controls.StyleMenu)))
	end

	-- Силы.
	local maxStamina = State.player:GetAttribute("MaxStamina") or Config.Player.MaxStamina
	local stamina = math.clamp(State.stamina() / math.max(maxStamina, 1), 0, 1)
	staminaFill.Size = staminaFill.Size:Lerp(UDim2.fromScale(stamina, 1), 0.3)
	staminaFill.BackgroundColor3 = stamina < 0.15 and RED or WHITE

	-- Резонанс.
	local resonance = State.resonance()
	local full = resonance >= RES_MAX
	resonanceFill.Size = resonanceFill.Size:Lerp(UDim2.fromScale(math.clamp(resonance / RES_MAX, 0, 1), 1), 0.3)
	resonanceGlow.Transparency = full and (0.25 + 0.35 * math.sin(os.clock() * 7)) or 1

	-- Заряд удара.
	chargeHolder.Visible = Controls.charging
	if Controls.charging then
		chargeFill.Size = UDim2.fromScale(Controls.charge, 1)
		chargeFill.BackgroundColor3 = Controls.charge >= 1 and RED or GOLD
	end

	local hasBall = State.hasBall()
	ballLabel.Visible = hasBall
	updateSlots(hasBall, resonance)
end

local function hookEvents()
	FxEvents.on("Countdown", function(data)
		local team = Config.Teams[data.team]
		local subtitle = team and (team.Name .. " KICKS OFF") or ""
		Hud.banner(tostring(data.n), subtitle, WHITE, 0.8)
	end)

	FxEvents.on("Whistle", function()
		Hud.banner("PLAY!", "", GOLD, 0.9)
	end)

	FxEvents.on("Goal", function(data)
		local team = Config.Teams[data.team]
		local subtitle = ""
		if data.scorerName and data.scorerName ~= "" then
			subtitle = data.scorerName
			local style = data.styleId and Styles.byId[data.styleId]
			if style and style.selectable ~= false then
				subtitle ..= "  ·  " .. style.name
			end
			if data.assistName and data.assistName ~= "" then
				subtitle ..= "   (assist: " .. data.assistName .. ")"
			end
		end
		Hud.banner("GOAL!", subtitle, team and team.Color or WHITE, 3.2)
	end)

	FxEvents.on("FullTime", function(data)
		local title = "DRAW"
		local color = WHITE
		local winner = Config.Teams[data.winner]
		if winner then
			title = winner.Name .. " WINS"
			color = winner.Color
		end
		Hud.banner(title, string.format("%d : %d", data.home or 0, data.away or 0), color, 6)
	end)

	Controls.onDenied = function(key, reason)
		flashSlot(key)
		Hud.hint(reason)
	end
end

function Hud.start()
	local playerGui = State.player:WaitForChild("PlayerGui")
	local gui = make("ScreenGui", {
		Name = "ResonanceHud",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 5,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, playerGui)

	root = make("Frame", {
		Name = "Root",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	}, gui)
	rootScale = make("UIScale", { Scale = 1 }, root)

	buildScoreboard()
	buildBanner()
	buildBars()
	buildSlots()
	buildHelp()
	if STYLES_ON then
		buildStyleMenu()
	end
	hookEvents()

	local function press(fn: () -> ())
		return function(_, inputState: Enum.UserInputState)
			if inputState == Enum.UserInputState.Begin then
				fn()
			end
			return Enum.ContextActionResult.Pass
		end
	end
	local function keys(names: { string })
		local list = {}
		for _, name in ipairs(names) do
			local ok, key = pcall(function()
				return (Enum.KeyCode :: any)[name]
			end)
			if ok and key then
				table.insert(list, key)
			end
		end
		return list
	end
	if STYLES_ON then
		ContextActionService:BindAction(
			"RS_StyleMenu",
			press(function()
				setMenu(not menu.Visible)
			end),
			false,
			table.unpack(keys(Config.Controls.StyleMenu))
		)
	end
	ContextActionService:BindAction(
		"RS_Help",
		press(function()
			setHelp(not helpPanel.Visible)
		end),
		false,
		table.unpack(keys(Config.Controls.Help))
	)

	-- На телефоне подсказка по клавишам не нужна.
	setHelp(not UserInputService.TouchEnabled)
	if UserInputService.TouchEnabled then
		helpChip.Visible = false
	end

	RunService.RenderStepped:Connect(onRender)

	-- При первом входе сразу предлагаем выбрать стиль.
	if STYLES_ON then
		task.delay(1.5, function()
			setMenu(true)
		end)
	end
end

return Hud
