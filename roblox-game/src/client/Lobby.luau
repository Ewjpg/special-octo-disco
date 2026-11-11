-- Lobby screen: the player's character on a lit pedestal, and a bar at the bottom:
--   [ FW | MF | DF | GK ]   [  PLAY  ]   [ STYLE: <name> ]
-- STYLE opens a row of style cards. PLAY sends the role to the server, which puts the player in a team.
-- In a match a small "LOBBY" button (top left) goes back.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Styles = require(Shared.Styles)
local Controls = require(script.Parent.Controls)
local State = require(script.Parent.State)

local Lobby = {}

local player = Players.LocalPlayer
local ROLES = Config.Roles
local INK = Color3.fromRGB(14, 15, 20)
local PANEL = Color3.fromRGB(22, 24, 31)
local WHITE = Color3.fromRGB(240, 242, 248)
local MUTED = Color3.fromRGB(150, 156, 172)

local gui: ScreenGui
local bar: Frame
local stylePanel: Frame
local errorLabel: TextLabel
local lobbyButton: TextButton
local roleButtons = {}
local styleButtonName: TextLabel
local styleButtonStripe: Frame
local selectedRole = ROLES.default
local inLobby = nil :: boolean?
local cameraConn: RBXScriptConnection? = nil

local function make(className: string, props: { [string]: any }, parent: Instance?): any
	local inst = Instance.new(className)
	for k, v in pairs(props) do
		(inst :: any)[k] = v
	end
	inst.Parent = parent
	return inst
end

local function corner(parent: Instance, r: number)
	make("UICorner", { CornerRadius = UDim.new(0, r) }, parent)
end

local function stroke(parent: Instance, color: Color3, t: number, transparency: number?)
	return make("UIStroke", {
		Color = color,
		Thickness = t,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, parent)
end

local function tween(inst: Instance, time: number, goal: { [string]: any })
	TweenService:Create(inst, TweenInfo.new(time, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), goal):Play()
end

local function hover(button: GuiButton, scale: UIScale)
	button.MouseEnter:Connect(function()
		tween(scale, 0.18, { Scale = 1.05 })
	end)
	button.MouseLeave:Connect(function()
		tween(scale, 0.18, { Scale = 1 })
	end)
end

---------------------------------------------------------------------------
-- Bar
---------------------------------------------------------------------------

local function refreshRoles()
	for role, button in pairs(roleButtons) do
		local on = role == selectedRole
		tween(button, 0.15, {
			BackgroundColor3 = on and WHITE or PANEL,
			TextColor3 = on and INK or MUTED,
		})
	end
end

local function refreshStyle()
	local style = Styles.get(player:GetAttribute("Style"))
	styleButtonName.Text = string.upper(style.name)
	styleButtonStripe.BackgroundColor3 = style.color
end

local function showError(message: string)
	errorLabel.Text = message
	errorLabel.TextTransparency = 0
	task.delay(2.5, function()
		if errorLabel.Text == message then
			tween(errorLabel, 0.4, { TextTransparency = 1 })
		end
	end)
end

local function buildBar()
	bar = make("Frame", {
		Name = "Bar",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -28),
		Size = UDim2.fromOffset(760, 86),
		BackgroundTransparency = 1,
	}, gui)
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 14),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, bar)

	-- Role selector
	local roles = make("Frame", {
		Name = "Roles",
		LayoutOrder = 1,
		Size = UDim2.fromOffset(236, 58),
		BackgroundColor3 = INK,
		BackgroundTransparency = 0.15,
	}, bar)
	corner(roles, 12)
	stroke(roles, WHITE, 1, 0.85)
	make("UIPadding", {
		PaddingLeft = UDim.new(0, 5),
		PaddingRight = UDim.new(0, 5),
		PaddingTop = UDim.new(0, 5),
		PaddingBottom = UDim.new(0, 5),
	}, roles)
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 4),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, roles)
	for i, role in ipairs(ROLES.order) do
		local button = make("TextButton", {
			Name = role,
			LayoutOrder = i,
			Size = UDim2.new(0.25, -3, 1, 0),
			BackgroundColor3 = PANEL,
			AutoButtonColor = false,
			Font = Enum.Font.GothamBlack,
			TextSize = 18,
			TextColor3 = MUTED,
			Text = role,
		}, roles)
		corner(button, 8)
		button.Activated:Connect(function()
			selectedRole = role
			refreshRoles()
		end)
		roleButtons[role] = button
	end

	-- PLAY
	local play = make("TextButton", {
		Name = "Play",
		LayoutOrder = 2,
		Size = UDim2.fromOffset(250, 72),
		BackgroundColor3 = WHITE,
		AutoButtonColor = false,
		Font = Enum.Font.GothamBlack,
		TextSize = 34,
		TextColor3 = INK,
		Text = "PLAY",
	}, bar)
	corner(play, 14)
	make("UIGradient", {
		Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(200, 206, 222)),
		Rotation = 90,
	}, play)
	local playScale = make("UIScale", {}, play)
	hover(play, playScale)
	play.Activated:Connect(function()
		tween(playScale, 0.08, { Scale = 0.94 })
		task.delay(0.08, function()
			tween(playScale, 0.2, { Scale = 1 })
		end)
		State.send("Play", selectedRole)
	end)

	-- STYLE
	local style = make("TextButton", {
		Name = "Style",
		LayoutOrder = 3,
		Size = UDim2.fromOffset(236, 58),
		BackgroundColor3 = INK,
		BackgroundTransparency = 0.15,
		AutoButtonColor = false,
		Text = "",
	}, bar)
	corner(style, 12)
	stroke(style, WHITE, 1, 0.85)
	local styleScale = make("UIScale", {}, style)
	hover(style, styleScale)
	styleButtonStripe = make("Frame", {
		Size = UDim2.new(0, 6, 1, -16),
		Position = UDim2.fromOffset(10, 8),
		BorderSizePixel = 0,
	}, style)
	corner(styleButtonStripe, 3)
	make("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(26, 8),
		Size = UDim2.new(1, -36, 0, 16),
		Font = Enum.Font.GothamBold,
		TextSize = 13,
		TextColor3 = MUTED,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "STYLE",
	}, style)
	styleButtonName = make("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(26, 24),
		Size = UDim2.new(1, -36, 0, 26),
		Font = Enum.Font.GothamBlack,
		TextSize = 20,
		TextColor3 = WHITE,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}, style)
	style.Activated:Connect(function()
		stylePanel.Visible = not stylePanel.Visible
	end)

	errorLabel = make("TextLabel", {
		Name = "Error",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -124),
		Size = UDim2.fromOffset(500, 28),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		TextSize = 18,
		TextColor3 = Color3.fromRGB(255, 120, 130),
		TextStrokeTransparency = 0.5,
		TextTransparency = 1,
		Text = "",
	}, gui)
end

---------------------------------------------------------------------------
-- Style cards
---------------------------------------------------------------------------

local function buildStylePanel()
	stylePanel = make("Frame", {
		Name = "StylePanel",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -132),
		Size = UDim2.fromOffset(760, 210),
		BackgroundColor3 = INK,
		BackgroundTransparency = 0.12,
		Visible = false,
	}, gui)
	corner(stylePanel, 16)
	stroke(stylePanel, WHITE, 1, 0.85)
	make("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(20, 12),
		Size = UDim2.new(1, -40, 0, 22),
		Font = Enum.Font.GothamBlack,
		TextSize = 18,
		TextColor3 = WHITE,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "CHOOSE YOUR STYLE",
	}, stylePanel)
	local list = make("ScrollingFrame", {
		Position = UDim2.fromOffset(16, 44),
		Size = UDim2.new(1, -32, 1, -58),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		ScrollingDirection = Enum.ScrollingDirection.X,
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		CanvasSize = UDim2.new(),
	}, stylePanel)
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 12),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, list)

	for i, style in ipairs(Styles.list) do
		local card = make("TextButton", {
			Name = style.id,
			LayoutOrder = i,
			Size = UDim2.fromOffset(170, 146),
			BackgroundColor3 = PANEL,
			AutoButtonColor = false,
			Text = "",
			ClipsDescendants = true,
		}, list)
		corner(card, 12)
		local cardStroke = stroke(card, style.color2 or style.color, 2, 0.6)
		-- colour panel with a soft gradient
		local art = make("Frame", {
			Size = UDim2.new(1, 0, 0, 92),
			BackgroundColor3 = style.color,
			BorderSizePixel = 0,
		}, card)
		make("UIGradient", {
			Color = ColorSequence.new(style.color2 or style.color, style.color),
			Rotation = 120,
		}, art)
		make("TextLabel", {
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			Font = Enum.Font.GothamBlack,
			TextSize = 46,
			TextColor3 = Color3.new(1, 1, 1),
			TextTransparency = 0.65,
			Text = string.upper(string.sub(style.name, 1, 1)),
		}, art)
		make("TextLabel", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(12, 98),
			Size = UDim2.new(1, -24, 0, 22),
			Font = Enum.Font.GothamBlack,
			TextSize = 17,
			TextColor3 = WHITE,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Text = string.upper(style.name),
		}, card)
		make("TextLabel", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(12, 120),
			Size = UDim2.new(1, -24, 0, 16),
			Font = Enum.Font.GothamMedium,
			TextSize = 12,
			TextColor3 = MUTED,
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = #style.abilities > 0 and (#style.abilities .. " ABILITIES") or "ABILITIES SOON",
		}, card)
		local cardScale = make("UIScale", {}, card)
		hover(card, cardScale)
		card.Activated:Connect(function()
			State.send("LobbyStyle", style.id)
			stylePanel.Visible = false
		end)
		player:GetAttributeChangedSignal("Style"):Connect(function()
			cardStroke.Transparency = player:GetAttribute("Style") == style.id and 0 or 0.6
		end)
		cardStroke.Transparency = player:GetAttribute("Style") == style.id and 0 or 0.6
	end
end

---------------------------------------------------------------------------
-- Camera and switching between lobby and match
---------------------------------------------------------------------------

local function lobbyCamera()
	local camera = Workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Scriptable
	local start = os.clock()
	if cameraConn then
		cameraConn:Disconnect()
	end
	cameraConn = RunService.RenderStepped:Connect(function()
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root then
			return
		end
		local t = os.clock() - start
		local focus = root.Position + Vector3.new(0, 0.6, 0)
		local sway = Vector3.new(math.sin(t * 0.35) * 1.2, math.sin(t * 0.5) * 0.25, 0)
		local eye = focus + root.CFrame.LookVector * 17 + root.CFrame.RightVector * -3.2 + Vector3.new(0, 2.4, 0) + sway
		local target = CFrame.lookAt(eye, focus + Vector3.new(0, -0.8, 0) + root.CFrame.RightVector * -1.4)
		camera.CFrame = camera.CFrame:Lerp(target, 0.12)
		camera.FieldOfView = 50
	end)
end

local function matchCamera()
	if cameraConn then
		cameraConn:Disconnect()
		cameraConn = nil
	end
	local camera = Workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Custom
	camera.FieldOfView = 70
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		camera.CameraSubject = humanoid
	end
end

local function setOtherGuis(visible: boolean)
	local playerGui = player:FindFirstChild("PlayerGui")
	if not playerGui then
		return
	end
	for _, name in ipairs({ "ResonanceHud", "Cinematics", "BallMarker", "FxOverlay" }) do
		local other = playerGui:FindFirstChild(name)
		if other and other:IsA("ScreenGui") then
			other.Enabled = visible
		end
	end
end

local function apply()
	local lobby = player:GetAttribute("InMatch") ~= true
	if lobby == inLobby then
		return
	end
	inLobby = lobby
	bar.Visible = lobby
	stylePanel.Visible = false
	lobbyButton.Visible = not lobby
	Controls.menuOpen = lobby -- no kicking from the lobby
	setOtherGuis(not lobby)
	if lobby then
		lobbyCamera()
	else
		matchCamera()
	end
end

function Lobby.start()
	gui = make("ScreenGui", {
		Name = "Lobby",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 20,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, player:WaitForChild("PlayerGui"))
	buildBar()
	buildStylePanel()
	refreshRoles()
	refreshStyle()

	lobbyButton = make("TextButton", {
		Name = "ToLobby",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 12),
		Size = UDim2.fromOffset(92, 32),
		BackgroundColor3 = INK,
		BackgroundTransparency = 0.25,
		AutoButtonColor = false,
		Font = Enum.Font.GothamBlack,
		TextSize = 14,
		TextColor3 = WHITE,
		Text = "LOBBY",
		Visible = false,
	}, gui)
	corner(lobbyButton, 8)
	lobbyButton.Activated:Connect(function()
		State.send("ToLobby")
	end)

	player:GetAttributeChangedSignal("Style"):Connect(refreshStyle)
	player:GetAttributeChangedSignal("InMatch"):Connect(apply)
	player:GetAttributeChangedSignal("LobbyError"):Connect(function()
		local message = tostring(player:GetAttribute("LobbyError") or "")
		showError((string.split(message, "#"))[1])
	end)
	player.CharacterAdded:Connect(function()
		-- a new character after PLAY / LOBBY: point the camera again
		task.defer(function()
			inLobby = nil
			apply()
		end)
	end)
	apply()
	-- other screens are created after this one; hide them once they exist
	task.delay(1, function()
		if inLobby then
			setOtherGuis(false)
		end
	end)
end

return Lobby
