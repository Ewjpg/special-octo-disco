-- Всё, что делает мяч красивым на клиенте: шлейф, вращение при ведении, вспышки при отскоках, метка над мячом.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Fx = require(script.Parent.Fx)
local State = require(script.Parent.State)

local BallVisuals = {}

local R = Config.Ball.Radius
local WHITE = Color3.fromRGB(245, 247, 255)

local ball: BasePart? = nil
local anchor: Part? = nil -- невращающаяся точка в центре мяча: на ней висят шлейф и свет
local trail: Trail? = nil
local glow: PointLight? = nil
local marker: BillboardGui? = nil

local trailMode: any = nil -- false = обычный шлейф, Color3 = цветной шлейф способности
local rollAngle = 0
local dribblePhase = 0
local previousVelocity = Vector3.zero
local lastBounce = 0

local function build(part: BasePart)
	ball = part

	local holder = Instance.new("Part")
	holder.Name = "BallAnchor"
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanTouch = false
	holder.CanQuery = false
	holder.Transparency = 1
	holder.Size = Vector3.new(0.2, 0.2, 0.2)
	holder.CFrame = CFrame.new(part.Position)
	holder.Parent = Workspace
	anchor = holder

	local top = Instance.new("Attachment")
	top.Position = Vector3.new(0, R * 0.85, 0)
	top.Parent = holder
	local bottom = Instance.new("Attachment")
	bottom.Position = Vector3.new(0, -R * 0.85, 0)
	bottom.Parent = holder

	local ribbon = Instance.new("Trail")
	ribbon.Attachment0 = top
	ribbon.Attachment1 = bottom
	ribbon.FaceCamera = true
	ribbon.Lifetime = 0.3
	ribbon.MinLength = 0.05
	ribbon.LightEmission = 0.7
	ribbon.Color = ColorSequence.new(WHITE)
	ribbon.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) })
	ribbon.Enabled = false
	ribbon.Parent = holder
	trail = ribbon

	local light = Instance.new("PointLight")
	light.Range = 18
	light.Brightness = 0
	light.Shadows = false
	light.Parent = holder
	glow = light

	-- Метка над мячом, чтобы не терять его на большом поле.
	local gui = Instance.new("BillboardGui")
	gui.Name = "BallMarker"
	gui.Size = UDim2.fromOffset(22, 22)
	gui.StudsOffset = Vector3.new(0, 4.5, 0)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.Adornee = holder
	local diamond = Instance.new("Frame")
	diamond.AnchorPoint = Vector2.new(0.5, 0.5)
	diamond.Position = UDim2.fromScale(0.5, 0.5)
	diamond.Size = UDim2.fromScale(0.62, 0.62)
	diamond.Rotation = 45
	diamond.BackgroundColor3 = Color3.fromRGB(255, 232, 110)
	diamond.BorderSizePixel = 0
	diamond.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = Color3.fromRGB(20, 20, 26)
	stroke.Parent = diamond
	gui.Parent = holder
	marker = gui
end

local function updateTrail(part: BasePart, held: boolean, speed: number)
	local ribbon, light = trail, glow
	if not ribbon or not light then
		return
	end
	local fxUntil = part:GetAttribute("FxUntil")
	local fxColor = part:GetAttribute("FxColor")
	local special = type(fxUntil) == "number" and State.now() < fxUntil and typeof(fxColor) == "Color3"

	ribbon.Enabled = not held and (special or speed > 45)

	-- Свойства шлейфа меняем только при смене режима, а не каждый кадр.
	local mode = special and fxColor or false
	if mode == trailMode then
		return
	end
	trailMode = mode
	if special then
		ribbon.Color = ColorSequence.new(fxColor, WHITE)
		ribbon.Lifetime = 0.55
		ribbon.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.7), NumberSequenceKeypoint.new(1, 0.3) })
		light.Color = fxColor
		light.Brightness = 3
	else
		ribbon.Color = ColorSequence.new(WHITE)
		ribbon.Lifetime = 0.28
		ribbon.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.2) })
		light.Brightness = 0
	end
end

local function onRender()
	local part = ball
	local holder = anchor
	if not part or not part.Parent or not holder then
		return
	end
	local position = part.Position
	holder.CFrame = CFrame.new(position)

	local held = part:GetAttribute("Held") == true
	local velocity = part.AssemblyLinearVelocity
	local speed = velocity.Magnitude
	updateTrail(part, held, speed)

	-- Метка видна, когда мяч далеко и ни у кого.
	local gui = marker
	local camera = Workspace.CurrentCamera
	if gui and camera then
		gui.Enabled = not held and (camera.CFrame.Position - position).Magnitude > 55
	end

	-- Вспышка при резком отскоке (штанга, борт, газон).
	if not held then
		local change = (velocity - previousVelocity).Magnitude
		local now = os.clock()
		if change > 45 and previousVelocity.Magnitude > 40 and now - lastBounce > 0.12 then
			lastBounce = now
			Fx.sound("Bounce", position, { volume = math.clamp(change / 120, 0.4, 1.5) })
			Fx.disc(Fx.ground(position), WHITE, { from = 1, to = 3 + change * 0.04, time = 0.22, transparency = 0.55 })
		end
	end
	previousVelocity = velocity
end

-- При ведении мяч катится и чуть «убегает» от ноги. Меняем только локальный Transform шва.
local function onStepped(dt: number)
	local part = ball
	if not part or not part.Parent then
		return
	end
	local joint = part:FindFirstChild("BallJoint")
	if not joint or not joint:IsA("Motor6D") then
		rollAngle = 0
		return
	end
	local carrier = joint.Part0
	if not carrier then
		return
	end
	local velocity = carrier.AssemblyLinearVelocity
	local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	rollAngle = (rollAngle + speed / R * dt) % (math.pi * 2)
	local push = 0
	if speed > 2 then
		dribblePhase += dt * (6 + speed * 0.22)
		push = (0.5 + 0.5 * math.sin(dribblePhase)) * math.clamp(speed / 28, 0.2, 1) * 0.9
	end
	joint.Transform = CFrame.new(0, 0, -push) * CFrame.Angles(-rollAngle, 0, 0)
end

function BallVisuals.start()
	task.spawn(function()
		local part = Workspace:WaitForChild("Ball") :: BasePart
		build(part)
		RunService.RenderStepped:Connect(onRender)
		RunService.Stepped:Connect(function(_, dt)
			onStepped(dt)
		end)
	end)
end

return BallVisuals
