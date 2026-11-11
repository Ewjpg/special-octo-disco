-- Dynamic presentation: slanted splash banners (KICK OFF! / GOAL!), radial speed lines,
-- a cinematic goal camera with depth of field, and a wider field of view while sprinting.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)
local Controls = require(script.Parent.Controls)
local FxEvents = require(script.Parent.FxEvents)
local State = require(script.Parent.State)

local Cinematics = {}

local player = Players.LocalPlayer
local gui: ScreenGui
local lines: Frame
local BASE_FOV = 70
local SPRINT_FOV = 82
local cinematicUntil = 0

local function tween(instance: Instance, time: number, goal: { [string]: any }, style: Enum.EasingStyle?, direction: Enum.EasingDirection?)
	local t =
		TweenService:Create(instance, TweenInfo.new(time, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out), goal)
	t:Play()
	return t
end

---------------------------------------------------------------------------
-- Slanted splash banner
---------------------------------------------------------------------------

-- A tilted colour band sweeps in from the left with big italic text, holds, then sweeps out.
function Cinematics.splash(text: string, color: Color3, hold: number?)
	local band = Instance.new("Frame")
	band.Name = "Splash"
	band.AnchorPoint = Vector2.new(0.5, 0.5)
	band.Position = UDim2.fromScale(-0.6, 0.62)
	band.Size = UDim2.new(1.4, 0, 0, 120)
	band.Rotation = -7
	band.BackgroundColor3 = color
	band.BackgroundTransparency = 0.05
	band.BorderSizePixel = 0
	band.ZIndex = 20
	band.Parent = gui

	local edge = Instance.new("Frame")
	edge.AnchorPoint = Vector2.new(0, 1)
	edge.Position = UDim2.fromScale(0, 0)
	edge.Size = UDim2.new(1, 0, 0, 10)
	edge.BackgroundColor3 = Color3.new(1, 1, 1)
	edge.BorderSizePixel = 0
	edge.ZIndex = 20
	edge.Parent = band

	local label = Instance.new("TextLabel")
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.Size = UDim2.new(0.6, 0, 1.3, 0)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.Text = text
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeColor3 = Color3.fromRGB(10, 14, 32)
	label.TextStrokeTransparency = 0
	label.Rotation = 0
	label.ZIndex = 21
	label.Parent = band

	tween(band, 0.22, { Position = UDim2.fromScale(0.5, 0.62) }, Enum.EasingStyle.Back)
	task.delay(0.22 + (hold or 1.1), function()
		tween(band, 0.25, { Position = UDim2.fromScale(1.7, 0.62) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		task.delay(0.3, function()
			band:Destroy()
		end)
	end)
end

---------------------------------------------------------------------------
-- Radial speed lines
---------------------------------------------------------------------------

local LINE_COUNT = 36

local function buildLines()
	lines = Instance.new("Frame")
	lines.Name = "SpeedLines"
	lines.Size = UDim2.fromScale(1, 1)
	lines.BackgroundTransparency = 1
	lines.Visible = false
	lines.ZIndex = 15
	lines.Parent = gui
	for i = 1, LINE_COUNT do
		local angle = (i / LINE_COUNT) * 360
		local holder = Instance.new("Frame")
		holder.AnchorPoint = Vector2.new(0.5, 0.5)
		holder.Position = UDim2.fromScale(0.5, 0.5)
		holder.Size = UDim2.fromScale(2, 2)
		holder.Rotation = angle
		holder.BackgroundTransparency = 1
		holder.ZIndex = 15
		holder.Parent = lines
		local streak = Instance.new("Frame")
		streak.Name = "Streak"
		streak.AnchorPoint = Vector2.new(0, 0.5)
		streak.Position = UDim2.fromScale(0.62, 0.5)
		streak.Size = UDim2.new(0.4, 0, 0, 3)
		streak.BackgroundColor3 = Color3.new(1, 1, 1)
		streak.BackgroundTransparency = 0.35
		streak.BorderSizePixel = 0
		streak.ZIndex = 15
		streak.Parent = holder
	end
end

-- Show flickering speed lines around the screen edge for `duration` seconds.
function Cinematics.speedLines(duration: number)
	lines.Visible = true
	local started = os.clock()
	local connection
	connection = RunService.RenderStepped:Connect(function()
		local elapsed = os.clock() - started
		if elapsed >= duration then
			lines.Visible = false
			connection:Disconnect()
			return
		end
		local fade = math.clamp((duration - elapsed) / 0.3, 0, 1)
		for _, holder in ipairs(lines:GetChildren()) do
			local streak = holder:FindFirstChild("Streak") :: Frame?
			if streak then
				streak.Position = UDim2.fromScale(0.55 + math.random() * 0.12, 0.5)
				streak.BackgroundTransparency = 1 - (0.35 + math.random() * 0.45) * fade
			end
		end
	end)
end

---------------------------------------------------------------------------
-- Goal camera
---------------------------------------------------------------------------

local dof: DepthOfFieldEffect

-- Orbit the camera around the scorer with a shallow depth of field, then hand control back.
function Cinematics.goalCamera(character: Model?, duration: number)
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local camera = Workspace.CurrentCamera
	if not root or not camera then
		return
	end
	cinematicUntil = os.clock() + duration
	local previousType = camera.CameraType
	camera.CameraType = Enum.CameraType.Scriptable
	dof.Enabled = true
	local started = os.clock()
	local startAngle = math.random() * math.pi * 2
	local connection
	connection = RunService.RenderStepped:Connect(function()
		local t = os.clock() - started
		if t >= duration or not root.Parent then
			connection:Disconnect()
			dof.Enabled = false
			camera.CameraType = previousType
			camera.FieldOfView = BASE_FOV
			return
		end
		local angle = startAngle + t * 0.9
		local radius = 11 - t * 1.2
		local focus = root.Position + Vector3.new(0, 1.5, 0)
		local eye = focus + Vector3.new(math.cos(angle) * radius, 2.5 + t * 0.6, math.sin(angle) * radius)
		camera.CFrame = CFrame.lookAt(eye, focus)
		camera.FieldOfView = 55 + t * 4
		dof.FocusDistance = (eye - focus).Magnitude
	end)
end

---------------------------------------------------------------------------

function Cinematics.start()
	gui = Instance.new("ScreenGui")
	gui.Name = "Cinematics"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 20
	gui.Parent = player:WaitForChild("PlayerGui")
	buildLines()

	dof = Instance.new("DepthOfFieldEffect")
	dof.Name = "CinematicDOF"
	dof.FarIntensity = 0.6
	dof.NearIntensity = 0.3
	dof.InFocusRadius = 6
	dof.Enabled = false
	dof.Parent = Lighting

	local home, away = Config.Teams.Home, Config.Teams.Away

	FxEvents.on("Whistle", function()
		Cinematics.splash("KICK OFF!", Color3.fromRGB(32, 92, 220), 1.0)
	end)

	FxEvents.on("Goal", function(data)
		local team = Config.Teams[data.team]
		Cinematics.splash("GOAL!", team and team.Color or home.Color, 1.6)
		Cinematics.speedLines(1.8)
		Cinematics.goalCamera(data.character, 3.2)
	end)

	FxEvents.on("Kick", function(data)
		if data.kind == "Shot" and (data.power or 0) > 0.75 and data.character == player.Character then
			Cinematics.speedLines(0.35)
		end
	end)

	FxEvents.on("FullTime", function(data)
		local winner = Config.Teams[data.winner]
		Cinematics.splash("FULL TIME", winner and winner.Color or away.Color:Lerp(home.Color, 0.5), 2.5)
	end)

	-- Wider field of view while sprinting: the pitch rushes past.
	RunService.RenderStepped:Connect(function(dt)
		local camera = Workspace.CurrentCamera
		if not camera or os.clock() < cinematicUntil then
			return
		end
		local humanoid = State.humanoid()
		local moving = humanoid ~= nil and humanoid.MoveDirection.Magnitude > 0.1
		local target = (Controls.sprintHeld and moving) and SPRINT_FOV or BASE_FOV
		camera.FieldOfView += (target - camera.FieldOfView) * math.min(1, dt * 6)
	end)
end

return Cinematics
