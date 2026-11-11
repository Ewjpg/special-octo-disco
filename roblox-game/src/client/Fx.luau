-- Набор визуальных эффектов. Всё собирается из обычных деталей, частиц и лучей — без загруженных ассетов.
-- Этот же набор получают способности стилей (аргумент fx в функции client).

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local FieldSpec = require(Shared.FieldSpec)
local ProcAnimator = require(script.Parent.ProcAnimator)
local Sfx = require(script.Parent.Sfx)

local Fx = {}

local localPlayer = Players.LocalPlayer
local folder: Folder? = nil
local overlay: Frame? = nil
local shakes = {} -- { magnitude, duration, elapsed }

local function effects(): Folder
	if folder and folder.Parent then
		return folder
	end
	local created = Instance.new("Folder")
	created.Name = "LocalEffects"
	created.Parent = Workspace
	folder = created
	return created
end

local function newPart(
	shape: Enum.PartType,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material,
	transparency: number
): Part
	local part = Instance.new("Part")
	part.Name = "Fx"
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Shape = shape
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material
	part.Transparency = transparency
	part.Parent = effects()
	return part
end

local function tween(instance: Instance, time: number, goal: { [string]: any }, style: Enum.EasingStyle?)
	local info = TweenInfo.new(time, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local t = TweenService:Create(instance, info, goal)
	t:Play()
	return t
end

Fx.tween = tween

local FLAT = CFrame.Angles(0, 0, math.rad(90)) -- цилиндр «лёжа» -> диск на земле

---------------------------------------------------------------------------
-- Справочные функции
---------------------------------------------------------------------------

function Fx.ball(): BasePart?
	return Workspace:FindFirstChild("Ball") :: BasePart?
end

function Fx.rootOf(character: Model?): BasePart?
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

function Fx.isLocal(character: Model?): boolean
	return character ~= nil and character == localPlayer.Character
end

-- Точка на газоне под заданной позицией.
function Fx.ground(position: Vector3): Vector3
	return Vector3.new(position.X, FieldSpec.Origin.Y + 0.15, position.Z)
end

function Fx.anim(character: Model?, name: string, options: { [string]: number }?)
	return ProcAnimator.play(character, name, options)
end

function Fx.sound(name: string, where: any, options: { [string]: number }?)
	Sfx.play(name, where, options)
end

-- Повторять fn каждые interval секунд в течение duration.
function Fx.every(duration: number, interval: number, fn: (number) -> ())
	task.spawn(function()
		local elapsed = 0
		while elapsed < duration do
			fn(elapsed)
			elapsed += task.wait(interval)
		end
	end)
end

-- Вызывать fn(dt, elapsed) каждый кадр в течение duration. fn может вернуть false, чтобы остановиться.
function Fx.loop(duration: number, fn: (number, number) -> any)
	local elapsed = 0
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function(dt)
		elapsed += dt
		if elapsed >= duration or fn(dt, elapsed) == false then
			connection:Disconnect()
		end
	end)
	return connection
end

---------------------------------------------------------------------------
-- Простые формы
---------------------------------------------------------------------------

-- Расширяющаяся (или сжимающаяся) энергосфера. from/to — радиусы.
function Fx.sphere(position: Vector3, color: Color3, options: { [string]: any }?)
	local o = options or {}
	local from, to, time = o.from or 2, o.to or 12, o.time or 0.35
	local part = newPart(
		Enum.PartType.Ball,
		Vector3.new(from * 2, from * 2, from * 2),
		CFrame.new(position),
		color,
		o.material or Enum.Material.ForceField,
		o.transparency or 0
	)
	tween(part, time, { Size = Vector3.new(to * 2, to * 2, to * 2), Transparency = 1 })
	Debris:AddItem(part, time + 0.1)
end

-- Светящийся диск на земле.
function Fx.disc(position: Vector3, color: Color3, options: { [string]: any }?)
	local o = options or {}
	local from, to, time = o.from or 2, o.to or 14, o.time or 0.35
	local part = newPart(
		Enum.PartType.Cylinder,
		Vector3.new(0.15, from * 2, from * 2),
		CFrame.new(position) * FLAT,
		color,
		Enum.Material.Neon,
		o.transparency or 0.4
	)
	tween(part, time, { Size = Vector3.new(0.15, to * 2, to * 2), Transparency = 1 })
	Debris:AddItem(part, time + 0.1)
end

-- Столб света вверх.
function Fx.pillar(position: Vector3, color: Color3, options: { [string]: any }?)
	local o = options or {}
	local radius, height, time = o.radius or 2, o.height or 40, o.time or 0.5
	local part = newPart(
		Enum.PartType.Cylinder,
		Vector3.new(height, radius * 2, radius * 2),
		CFrame.new(position + Vector3.new(0, height / 2, 0)) * FLAT,
		color,
		Enum.Material.Neon,
		0.3
	)
	tween(part, time, { Size = Vector3.new(height, 0.2, 0.2), Transparency = 1 })
	Debris:AddItem(part, time + 0.1)
end

-- Разлёт частиц.
function Fx.burst(position: Vector3, color: Color3, options: { [string]: any }?)
	local o = options or {}
	local count, speed, life, size = o.count or 20, o.speed or 20, o.life or 0.5, o.size or 1.1
	local holder = newPart(Enum.PartType.Block, Vector3.new(0.2, 0.2, 0.2), CFrame.new(position), color, Enum.Material.SmoothPlastic, 1)

	local emitter = Instance.new("ParticleEmitter")
	emitter.Rate = 0
	emitter.Color = ColorSequence.new(color, Color3.new(1, 1, 1))
	emitter.LightEmission = 0.8
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size), NumberSequenceKeypoint.new(1, 0) })
	emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
	emitter.Lifetime = NumberRange.new(life * 0.6, life)
	emitter.Speed = NumberRange.new(speed * 0.5, speed)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.Drag = 3
	emitter.Parent = holder

	task.delay(0.03, function()
		if emitter.Parent then
			emitter:Emit(count)
		end
	end)
	Debris:AddItem(holder, life + 0.4)
end

-- Короткая вспышка света.
function Fx.light(position: Vector3, color: Color3, options: { [string]: any }?)
	local o = options or {}
	local time = o.time or 0.4
	local holder = newPart(Enum.PartType.Block, Vector3.new(0.2, 0.2, 0.2), CFrame.new(position), color, Enum.Material.SmoothPlastic, 1)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = o.range or 30
	light.Brightness = o.brightness or 4
	light.Shadows = false
	light.Parent = holder
	tween(light, time, { Brightness = 0 })
	Debris:AddItem(holder, time + 0.1)
end

-- Луч между двумя точками. a и b — Vector3 или BasePart (тогда луч следует за деталью).
function Fx.beam(a: any, b: any, color: Color3, options: { [string]: any }?)
	local o = options or {}
	local width, time = o.width or 1, o.time or 0.5
	local cleanup = {}

	local function attachmentFor(target: any): Attachment
		local attachment = Instance.new("Attachment")
		if typeof(target) == "Vector3" then
			local holder =
				newPart(Enum.PartType.Block, Vector3.new(0.2, 0.2, 0.2), CFrame.new(target), color, Enum.Material.SmoothPlastic, 1)
			attachment.Parent = holder
			table.insert(cleanup, holder)
		else
			attachment.Parent = target
			table.insert(cleanup, attachment)
		end
		return attachment
	end

	local a0, a1 = attachmentFor(a), attachmentFor(b)
	local beam = Instance.new("Beam")
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	beam.Width0 = width
	beam.Width1 = width * 0.4
	beam.Color = ColorSequence.new(color)
	beam.Transparency = NumberSequence.new(0.15)
	beam.LightEmission = 1
	beam.FaceCamera = true
	beam.Segments = 1
	beam.Parent = a0
	table.insert(cleanup, beam)

	task.delay(time, function()
		for _, item in ipairs(cleanup) do
			item:Destroy()
		end
	end)
end

---------------------------------------------------------------------------
-- Эффекты на персонаже
---------------------------------------------------------------------------

-- Светящийся силуэт персонажа, который остаётся на месте и гаснет.
function Fx.afterimage(character: Model?, color: Color3, options: { [string]: any }?)
	if not character or not character.Parent then
		return
	end
	local o = options or {}
	local time = o.time or 0.4
	local offset = o.offset or Vector3.zero
	local parent = effects()

	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("BasePart") and descendant.Transparency < 0.95 then
			local source = descendant :: BasePart
			local name = source.Name
			local isBody = source.Parent == character
			if name ~= "HumanoidRootPart" and name ~= "TeamRing" and (source:IsA("MeshPart") or isBody) then
				local ghost: BasePart
				if source:IsA("MeshPart") then
					local clone = source:Clone()
					for _, child in ipairs(clone:GetChildren()) do
						child:Destroy()
					end
					clone.TextureID = ""
					ghost = clone
				else
					local block = Instance.new("Part")
					block.Size = source.Size
					ghost = block
				end
				ghost.Name = "Afterimage"
				ghost.Anchored = true
				ghost.CanCollide = false
				ghost.CanTouch = false
				ghost.CanQuery = false
				ghost.CastShadow = false
				ghost.Massless = true
				ghost.Material = Enum.Material.Neon
				ghost.Color = color
				ghost.Transparency = o.transparency or 0.45
				ghost.CFrame = source.CFrame + offset
				ghost.Parent = parent
				tween(ghost, time, { Transparency = 1 }, Enum.EasingStyle.Linear)
				Debris:AddItem(ghost, time + 0.1)
			end
		end
	end
end

-- Цветной шлейф за корпусом персонажа.
function Fx.charTrail(character: Model?, color: Color3, duration: number)
	if not character then
		return
	end
	local torso = character:FindFirstChild("UpperTorso")
		or character:FindFirstChild("Torso")
		or character:FindFirstChild("HumanoidRootPart")
	if not torso then
		return
	end
	local top = Instance.new("Attachment")
	top.Position = Vector3.new(0, 1, 0)
	top.Parent = torso
	local bottom = Instance.new("Attachment")
	bottom.Position = Vector3.new(0, -1.5, 0)
	bottom.Parent = torso

	local trail = Instance.new("Trail")
	trail.Attachment0 = top
	trail.Attachment1 = bottom
	trail.Color = ColorSequence.new(color)
	trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	trail.Lifetime = 0.35
	trail.LightEmission = 0.8
	trail.FaceCamera = true
	trail.MinLength = 0.05
	trail.Parent = torso

	task.delay(duration, function()
		trail.Enabled = false
		Debris:AddItem(trail, 0.5)
		Debris:AddItem(top, 0.5)
		Debris:AddItem(bottom, 0.5)
	end)
end

-- Энергокупол, который ходит вместе с персонажем.
function Fx.aura(character: Model?, color: Color3, options: { [string]: any }?)
	local root = Fx.rootOf(character)
	if not root then
		return
	end
	local o = options or {}
	local radius, time = o.radius or 8, o.time or 5
	local part = newPart(Enum.PartType.Ball, Vector3.new(1, 1, 1), CFrame.new(root.Position), color, Enum.Material.ForceField, 0)
	tween(part, 0.35, { Size = Vector3.new(radius * 2, radius * 2, radius * 2) }, Enum.EasingStyle.Back)
	Fx.loop(time, function(_, elapsed)
		if not root.Parent or not part.Parent then
			part:Destroy()
			return false
		end
		part.CFrame = CFrame.new(root.Position) * CFrame.Angles(0, elapsed * 1.5, 0)
		if time - elapsed < 0.4 then
			part.Transparency = 1 - (time - elapsed) / 0.4
		end
		return true
	end)
	Debris:AddItem(part, time + 0.1)
end

---------------------------------------------------------------------------
-- Эффекты в мире
---------------------------------------------------------------------------

-- Долгая зона (воронка): большая сфера с тёмным ядром.
function Fx.zone(position: Vector3, color: Color3, options: { [string]: any }?)
	local o = options or {}
	local radius, time = o.radius or 30, o.time or 4
	local shell = newPart(Enum.PartType.Ball, Vector3.new(2, 2, 2), CFrame.new(position), color, Enum.Material.ForceField, 0)
	local core =
		newPart(Enum.PartType.Ball, Vector3.new(1, 1, 1), CFrame.new(position), o.core or Color3.new(0, 0, 0), Enum.Material.Neon, 0.15)
	local floor =
		newPart(Enum.PartType.Cylinder, Vector3.new(0.12, 2, 2), CFrame.new(Fx.ground(position)) * FLAT, color, Enum.Material.Neon, 0.75)
	tween(shell, 0.4, { Size = Vector3.new(radius * 2, radius * 2, radius * 2) }, Enum.EasingStyle.Back)
	tween(core, 0.4, { Size = Vector3.new(7, 7, 7) }, Enum.EasingStyle.Back)
	tween(floor, 0.4, { Size = Vector3.new(0.12, radius * 2, radius * 2) })
	task.delay(math.max(0, time - 0.4), function()
		for _, part in ipairs({ shell, core, floor }) do
			if part.Parent then
				tween(part, 0.4, { Transparency = 1 })
			end
		end
	end)
	for _, part in ipairs({ shell, core, floor }) do
		Debris:AddItem(part, time + 0.1)
	end
end

-- Маленькие шарики, которые кружат вокруг детали (например, мяча).
function Fx.orbit(target: BasePart, color: Color3, options: { [string]: any }?)
	local o = options or {}
	local count, radius, time = o.count or 3, o.radius or 3, o.time or 1
	local orbs = {}
	for i = 1, count do
		orbs[i] = newPart(Enum.PartType.Ball, Vector3.new(0.9, 0.9, 0.9), target.CFrame, color, Enum.Material.Neon, 0.1)
		Debris:AddItem(orbs[i], time + 0.1)
	end
	Fx.loop(time, function(_, elapsed)
		if not target.Parent then
			return false
		end
		local center = target.Position
		for i, orb in ipairs(orbs) do
			local angle = elapsed * 14 + (i - 1) * (math.pi * 2 / count)
			local tilt = (i - 1) * 1.1
			local offset = CFrame.Angles(tilt, 0, tilt * 0.5) * Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
			orb.CFrame = CFrame.new(center + offset)
			orb.Transparency = 0.1 + 0.9 * math.clamp((elapsed - (time - 0.3)) / 0.3, 0, 1)
		end
		return true
	end)
end

-- Ложный мяч: летит по своей траектории и исчезает.
function Fx.ghostBall(position: Vector3, velocity: Vector3, color: Color3, options: { [string]: any }?)
	local o = options or {}
	local time = o.time or 0.5
	local accel = o.accel or Vector3.zero
	local size = Config.Ball.Radius * 2
	local part = newPart(Enum.PartType.Ball, Vector3.new(size, size, size), CFrame.new(position), color, Enum.Material.Neon, 0.25)
	local current, speed = position, velocity
	local floorY = FieldSpec.Origin.Y + Config.Ball.Radius
	Fx.loop(time, function(dt, elapsed)
		speed += accel * dt
		current += speed * dt
		if current.Y < floorY then
			current = Vector3.new(current.X, floorY, current.Z)
		end
		part.CFrame = CFrame.new(current)
		part.Transparency = 0.25 + 0.75 * math.clamp((elapsed - time * 0.6) / (time * 0.4), 0, 1)
		return true
	end)
	Debris:AddItem(part, time + 0.05)
end

---------------------------------------------------------------------------
-- Камера и экран
---------------------------------------------------------------------------

-- Тряска камеры; чем дальше источник, тем слабее.
function Fx.shake(position: Vector3?, magnitude: number, duration: number)
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local scale = 1
	if position then
		local distance = (camera.CFrame.Position - position).Magnitude
		scale = math.clamp(1 - distance / 170, 0, 1)
	end
	if scale <= 0 then
		return
	end
	table.insert(shakes, { magnitude = magnitude * scale, duration = duration, elapsed = 0 })
end

-- Цветная вспышка на весь экран.
function Fx.flash(color: Color3, alpha: number, time: number)
	if not overlay or not overlay.Parent then
		local gui = Instance.new("ScreenGui")
		gui.Name = "FxOverlay"
		gui.IgnoreGuiInset = true
		gui.ResetOnSpawn = false
		gui.DisplayOrder = 50
		local frame = Instance.new("Frame")
		frame.Size = UDim2.fromScale(1, 1)
		frame.BorderSizePixel = 0
		frame.BackgroundTransparency = 1
		frame.Active = false
		frame.Parent = gui
		gui.Parent = localPlayer:WaitForChild("PlayerGui")
		overlay = frame
	end
	local frame = overlay :: Frame
	frame.BackgroundColor3 = color
	frame.BackgroundTransparency = 1 - alpha
	tween(frame, time, { BackgroundTransparency = 1 })
end

function Fx.start()
	-- Тряска применяется после того, как стандартная камера посчитала свой кадр.
	RunService:BindToRenderStep("ResonanceShake", Enum.RenderPriority.Camera.Value + 1, function(dt)
		if #shakes == 0 then
			return
		end
		local camera = Workspace.CurrentCamera
		local total = 0
		for i = #shakes, 1, -1 do
			local shake = shakes[i]
			shake.elapsed += dt
			if shake.elapsed >= shake.duration then
				table.remove(shakes, i)
			else
				total += shake.magnitude * (1 - shake.elapsed / shake.duration)
			end
		end
		if camera and total > 0 then
			local amount = math.min(total, 3) * 0.012
			local rx = (math.random() * 2 - 1) * amount
			local ry = (math.random() * 2 - 1) * amount
			camera.CFrame *= CFrame.Angles(rx, ry, 0)
		end
	end)
end

return Fx
