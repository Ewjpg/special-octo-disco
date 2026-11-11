-- Мини-эмулятор Roblox для проверки кода игры без Studio (запускается через Lune).
--
-- Что настоящее: дерево Instance и проверка имён/типов свойств (база рефлексии Roblox из Lune),
--                типы данных (Vector3, CFrame, Enum...), сам код игры из собранного .rbxlx.
-- Что упрощено: планировщик (виртуальное время), сигналы, сеть (RemoteEvent без задержки),
--               физика (мяч — баллистика с отскоком, персонажи — точки со скоростью).
-- Это дымовой тест: он ловит ошибки выполнения и грубые логические сбои, но не заменяет запуск в Studio.

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")

local Instance = roblox.Instance
local Vector3, Vector2, CFrame = roblox.Vector3, roblox.Vector2, roblox.CFrame
local Enum = roblox.Enum

local Emu = {}

Emu.now = 0
Emu.errors = {}
Emu.warnings = {}
Emu.prints = {}
Emu.verbose = false
Emu.game = nil
Emu.bound = {} -- ContextActionService: [name] = handler
Emu.renderSteps = {}
Emu.characters = {} -- [Model] = controller
Emu.remoteLog = {} -- счётчики отправленных событий

---------------------------------------------------------------------------
-- Ошибки
---------------------------------------------------------------------------

function Emu.recordError(message: string)
	table.insert(Emu.errors, string.format("[t=%.2f] %s", Emu.now, message))
	if Emu.verbose then
		print("ERROR " .. message)
	end
end

---------------------------------------------------------------------------
-- Планировщик с виртуальным временем
---------------------------------------------------------------------------

local queue = {}
local sequence = 0

local function resume(thread: thread, ...)
	local ok, err = coroutine.resume(thread, ...)
	if not ok then
		Emu.recordError(tostring(err) .. "\n" .. debug.traceback(thread))
	end
end

local function schedule(time: number, thread: thread, args)
	sequence += 1
	table.insert(queue, { time = time, seq = sequence, thread = thread, args = args })
end

local task = {}

function task.spawn(f, ...)
	local thread = type(f) == "thread" and f or coroutine.create(f)
	resume(thread, ...)
	return thread
end

function task.defer(f, ...)
	local thread = type(f) == "thread" and f or coroutine.create(f)
	schedule(Emu.now, thread, table.pack(...))
	return thread
end

function task.delay(delay, f, ...)
	local thread = type(f) == "thread" and f or coroutine.create(f)
	schedule(Emu.now + math.max(delay or 0, 0), thread, table.pack(...))
	return thread
end

function task.wait(duration)
	local start = Emu.now
	schedule(Emu.now + math.max(duration or 0, 1 / 60), coroutine.running(), nil)
	coroutine.yield()
	return Emu.now - start
end

function task.cancel(thread)
	for i = #queue, 1, -1 do
		if queue[i].thread == thread then
			table.remove(queue, i)
		end
	end
end

local function runDue(untilTime: number)
	while true do
		local bestIndex, best
		for i, entry in ipairs(queue) do
			if entry.time <= untilTime then
				if not best or entry.time < best.time or (entry.time == best.time and entry.seq < best.seq) then
					bestIndex, best = i, entry
				end
			end
		end
		if not best then
			break
		end
		table.remove(queue, bestIndex)
		Emu.now = math.max(Emu.now, best.time)
		if best.args then
			resume(best.thread, table.unpack(best.args, 1, best.args.n))
		else
			resume(best.thread)
		end
	end
	Emu.now = untilTime
end

---------------------------------------------------------------------------
-- Сигналы
---------------------------------------------------------------------------

local Signal = {}
Signal.__index = Signal

function Signal.new(name: string)
	return setmetatable({ name = name, handlers = {}, waiting = {} }, Signal)
end

function Signal:Connect(fn)
	local connection = { Connected = true }
	local entry = { fn = fn, connection = connection }
	local handlers = self.handlers
	table.insert(handlers, entry)
	function connection.Disconnect()
		connection.Connected = false
		local index = table.find(handlers, entry)
		if index then
			table.remove(handlers, index)
		end
	end
	return connection
end

function Signal:Once(fn)
	local connection
	connection = self:Connect(function(...)
		connection.Disconnect()
		fn(...)
	end)
	return connection
end

function Signal:Wait()
	table.insert(self.waiting, coroutine.running())
	return coroutine.yield()
end

function Signal:Fire(...)
	for _, entry in ipairs(table.clone(self.handlers)) do
		if entry.connection.Connected then
			task.spawn(entry.fn, ...)
		end
	end
	local waiting = self.waiting
	self.waiting = {}
	for _, thread in ipairs(waiting) do
		resume(thread, ...)
	end
end

Emu.Signal = Signal

local store = {} -- [Instance] = { [key] = value } — данные заглушек

local function data(instance)
	local entry = store[instance]
	if not entry then
		entry = {}
		store[instance] = entry
	end
	return entry
end

local function signalOf(instance, name: string)
	local entry = data(instance)
	local key = "signal:" .. name
	local signal = entry[key]
	if not signal then
		signal = Signal.new(name)
		entry[key] = signal
	end
	return signal
end

Emu.signalOf = signalOf

---------------------------------------------------------------------------
-- Заглушки свойств и методов, которых нет в Lune
---------------------------------------------------------------------------

local EVENTS = {
	Instance = { "ChildAdded", "ChildRemoved", "DescendantAdded", "DescendantRemoving", "AncestryChanged", "Destroying", "AttributeChanged", "Changed" },
	RunService = { "Heartbeat", "Stepped", "RenderStepped", "PreSimulation", "PostSimulation", "PreRender" },
	Players = { "PlayerAdded", "PlayerRemoving" },
	Player = { "CharacterAdded", "CharacterRemoving" },
	Humanoid = { "Died", "Running", "StateChanged", "MoveToFinished", "HealthChanged" },
	RemoteEvent = { "OnServerEvent", "OnClientEvent" },
	GuiButton = { "Activated", "MouseButton1Click" },
	GuiObject = { "MouseEnter", "MouseLeave", "InputBegan", "InputEnded" },
	BasePart = { "Touched", "TouchEnded" },
	UserInputService = { "InputBegan", "InputEnded", "InputChanged" },
}

local BALL_DENSITY = 0.4

local function partMass(part): number
	local size = part.Size
	local density = 0.7
	local custom = part.CustomPhysicalProperties
	if custom then
		density = custom.Density
	end
	if part.Shape == Enum.PartType.Ball then
		local r = size.X / 2
		return density * (4 / 3) * math.pi * r * r * r
	end
	return density * size.X * size.Y * size.Z
end

local function modelPivot(model): any
	local primary = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")
	if primary then
		return primary.CFrame
	end
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			return descendant.CFrame
		end
	end
	return CFrame.new()
end

local function movePivot(instance, target)
	if instance:IsA("BasePart") then
		instance.CFrame = target
		return
	end
	local delta = target * modelPivot(instance):Inverse()
	for _, descendant in ipairs(instance:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.CFrame = delta * descendant.CFrame
		end
	end
end

local function fakeTrack()
	local track = { Looped = false, IsPlaying = false, Stopped = Signal.new("Stopped") }
	function track.Play()
		track.IsPlaying = true
	end
	function track.Stop()
		track.IsPlaying = false
	end
	function track.AdjustSpeed() end
	function track.AdjustWeight() end
	return track
end

local buildRig -- объявлена ниже

local function installMocks()
	for className, names in pairs(EVENTS) do
		for _, name in ipairs(names) do
			roblox.implementProperty(className, name, function(self)
				return signalOf(self, name)
			end)
		end
	end

	-- Instance
	roblox.implementMethod("Instance", "WaitForChild", function(self, name, timeout)
		local limit = Emu.now + (timeout or 5)
		while true do
			local child = self:FindFirstChild(name)
			if child then
				return child
			end
			if Emu.now >= limit then
				if not timeout then
					Emu.recordError(string.format("WaitForChild: бесконечное ожидание %s.%s", self:GetFullName(), tostring(name)))
				end
				return nil
			end
			task.wait(0.05)
		end
	end)
	roblox.implementMethod("Instance", "GetAttributeChangedSignal", function(self, name)
		return signalOf(self, "attribute:" .. tostring(name))
	end)
	roblox.implementMethod("Instance", "GetPropertyChangedSignal", function(self, name)
		return signalOf(self, "property:" .. tostring(name))
	end)

	-- Свойства «только для чтения», которые Lune не вычисляет: в коде игры они заменяются на вызовы __x().
	roblox.implementMethod("BasePart", "__pos", function(self)
		return self.CFrame.Position
	end)
	roblox.implementMethod("BasePart", "__assemblyRoot", function(self)
		local joint = self:FindFirstChild("BallJoint")
		if joint and joint.Part0 then
			return joint.Part0
		end
		return self
	end)
	roblox.implementMethod("BasePart", "GetMass", partMass)
	roblox.implementMethod("BasePart", "SetNetworkOwner", function(self, owner)
		if self.Anchored then
			error("SetNetworkOwner: деталь закреплена")
		end
		data(self).networkOwner = owner
	end)
	roblox.implementMethod("BasePart", "GetNetworkOwner", function(self)
		return data(self).networkOwner
	end)
	roblox.implementMethod("PVInstance", "PivotTo", movePivot)
	roblox.implementMethod("PVInstance", "GetPivot", function(self)
		if self:IsA("BasePart") then
			return self.CFrame
		end
		return modelPivot(self)
	end)

	-- Humanoid / Animator
	roblox.implementMethod("Humanoid", "MoveTo", function(self, position)
		local controller = Emu.characters[self.Parent]
		if controller then
			controller.moveTarget = position
		end
	end)
	roblox.implementMethod("Humanoid", "ChangeState", function() end)
	roblox.implementMethod("Humanoid", "SetStateEnabled", function() end)
	roblox.implementMethod("Animator", "LoadAnimation", fakeTrack)
	roblox.implementMethod("Humanoid", "LoadAnimation", fakeTrack)

	-- Players
	roblox.implementMethod("Players", "GetPlayers", function(self)
		local list = {}
		for _, child in ipairs(self:GetChildren()) do
			if child:IsA("Player") then
				table.insert(list, child)
			end
		end
		return list
	end)
	roblox.implementMethod("Players", "GetPlayerFromCharacter", function(self, character)
		for _, child in ipairs(self:GetChildren()) do
			if child:IsA("Player") and child.Character == character then
				return child
			end
		end
		return nil
	end)
	roblox.implementMethod("Players", "CreateHumanoidModelFromDescription", function(_, description, rigType)
		assert(description and description:IsA("HumanoidDescription"), "нужен HumanoidDescription")
		assert(rigType == Enum.HumanoidRigType.R15, "ожидается R15")
		task.wait(0.1) -- в Roblox этот вызов тоже занимает время
		return buildRig("Rig", description.TorsoColor)
	end)

	-- Workspace / время
	roblox.implementMethod("Workspace", "GetServerTimeNow", function()
		return 1000 + Emu.now
	end)

	-- RunService
	roblox.implementMethod("RunService", "BindToRenderStep", function(_, name, priority, fn)
		assert(type(name) == "string" and type(priority) == "number" and type(fn) == "function", "BindToRenderStep: неверные аргументы")
		table.insert(Emu.renderSteps, { name = name, priority = priority, fn = fn })
		table.sort(Emu.renderSteps, function(a, b)
			return a.priority < b.priority
		end)
	end)
	roblox.implementMethod("RunService", "UnbindFromRenderStep", function(_, name)
		for i = #Emu.renderSteps, 1, -1 do
			if Emu.renderSteps[i].name == name then
				table.remove(Emu.renderSteps, i)
			end
		end
	end)
	roblox.implementMethod("RunService", "IsStudio", function()
		return true
	end)
	roblox.implementMethod("RunService", "IsServer", function()
		return true
	end)
	roblox.implementMethod("RunService", "IsClient", function()
		return true
	end)

	-- TweenService: цель применяется сразу — заодно проверяются имена и типы свойств.
	roblox.implementMethod("TweenService", "Create", function(_, instance, info, goals)
		assert(typeof(instance) == "Instance", "TweenService:Create — нужен Instance")
		assert(type(info) == "table" and info.__tweenInfo, "TweenService:Create — нужен TweenInfo")
		local tween = { Completed = Signal.new("Completed") }
		function tween.Play()
			for property, value in pairs(goals) do
				instance[property] = value
			end
			tween.Completed:Fire(Enum.PlaybackState.Completed)
		end
		function tween.Cancel() end
		function tween.Pause() end
		return tween
	end)

	roblox.implementMethod("Debris", "AddItem", function(_, instance, lifetime)
		task.delay(lifetime or 10, function()
			instance:Destroy()
		end)
	end)

	roblox.implementMethod("PhysicsService", "RegisterCollisionGroup", function(self, name)
		data(self)[name] = true
	end)
	roblox.implementMethod("PhysicsService", "CollisionGroupSetCollidable", function(self, a, b, collidable)
		local groups = data(self)
		assert(a == "Default" or groups[a], "неизвестная группа столкновений " .. tostring(a))
		assert(b == "Default" or groups[b], "неизвестная группа столкновений " .. tostring(b))
		assert(type(collidable) == "boolean")
	end)

	roblox.implementMethod("ContextActionService", "BindAction", function(_, name, handler, touchButton, ...)
		assert(type(name) == "string" and type(handler) == "function" and type(touchButton) == "boolean", "BindAction: неверные аргументы")
		local inputs = table.pack(...)
		assert(inputs.n > 0, "BindAction " .. name .. ": нет ни одной клавиши")
		for i = 1, inputs.n do
			local kind = typeof(inputs[i])
			assert(kind == "EnumItem", "BindAction " .. name .. ": клавиша должна быть EnumItem, а не " .. kind)
		end
		Emu.bound[name] = handler
	end)
	roblox.implementMethod("ContextActionService", "UnbindAction", function(_, name)
		Emu.bound[name] = nil
	end)
	roblox.implementMethod("ContextActionService", "SetTitle", function() end)
	roblox.implementMethod("ContextActionService", "SetPosition", function() end)

	roblox.implementMethod("StarterGui", "SetCoreGuiEnabled", function(_, coreGui, enabled)
		assert(typeof(coreGui) == "EnumItem" and type(enabled) == "boolean")
	end)
	roblox.implementMethod("StarterGui", "SetCore", function() end)

	roblox.implementMethod("Sound", "Play", function() end)
	roblox.implementMethod("Sound", "Stop", function() end)
	roblox.implementMethod("ParticleEmitter", "Emit", function(_, count)
		assert(type(count) == "number")
	end)

	-- RemoteEvent: доставка без задержки, но через планировщик (как отдельное событие).
	roblox.implementMethod("RemoteEvent", "FireServer", function(self, ...)
		local player = Emu.game:GetService("Players").LocalPlayer
		Emu.remoteLog["->" .. tostring((...))] = (Emu.remoteLog["->" .. tostring((...))] or 0) + 1
		local signal = signalOf(self, "OnServerEvent")
		local args = table.pack(...)
		task.defer(function()
			signal:Fire(player, table.unpack(args, 1, args.n))
		end)
	end)
	roblox.implementMethod("RemoteEvent", "FireAllClients", function(self, ...)
		Emu.remoteLog["<-" .. tostring((...))] = (Emu.remoteLog["<-" .. tostring((...))] or 0) + 1
		local signal = signalOf(self, "OnClientEvent")
		local args = table.pack(...)
		task.defer(function()
			signal:Fire(table.unpack(args, 1, args.n))
		end)
	end)
	roblox.implementMethod("RemoteEvent", "FireClient", function(self, player, ...)
		assert(typeof(player) == "Instance" and player:IsA("Player"), "FireClient: первый аргумент — игрок")
		local signal = signalOf(self, "OnClientEvent")
		local args = table.pack(...)
		task.defer(function()
			signal:Fire(table.unpack(args, 1, args.n))
		end)
	end)
end

---------------------------------------------------------------------------
-- Упрощённый персонаж R15 (блочный)
---------------------------------------------------------------------------

local RIG_PARTS = {
	-- имя, размер, сустав, родитель, C0 (в родителе), C1 (в детали)
	{ "LowerTorso", Vector3.new(2, 0.4, 1), "Root", "HumanoidRootPart", Vector3.new(0, -1, 0), Vector3.new(0, -0.2, 0) },
	{ "UpperTorso", Vector3.new(2, 1.6, 1), "Waist", "LowerTorso", Vector3.new(0, 0.2, 0), Vector3.new(0, -0.8, 0) },
	{ "Head", Vector3.new(1.2, 1.2, 1.2), "Neck", "UpperTorso", Vector3.new(0, 0.8, 0), Vector3.new(0, -0.6, 0) },
	{ "RightUpperArm", Vector3.new(1, 1.2, 1), "RightShoulder", "UpperTorso", Vector3.new(1, 0.56, 0), Vector3.new(-0.5, 0.4, 0) },
	{ "RightLowerArm", Vector3.new(1, 1.1, 1), "RightElbow", "RightUpperArm", Vector3.new(0, -0.35, 0), Vector3.new(0, 0.3, 0) },
	{ "RightHand", Vector3.new(1, 0.3, 1), "RightWrist", "RightLowerArm", Vector3.new(0, -0.55, 0), Vector3.new(0, 0.15, 0) },
	{ "LeftUpperArm", Vector3.new(1, 1.2, 1), "LeftShoulder", "UpperTorso", Vector3.new(-1, 0.56, 0), Vector3.new(0.5, 0.4, 0) },
	{ "LeftLowerArm", Vector3.new(1, 1.1, 1), "LeftElbow", "LeftUpperArm", Vector3.new(0, -0.35, 0), Vector3.new(0, 0.3, 0) },
	{ "LeftHand", Vector3.new(1, 0.3, 1), "LeftWrist", "LeftLowerArm", Vector3.new(0, -0.55, 0), Vector3.new(0, 0.15, 0) },
	{ "RightUpperLeg", Vector3.new(1, 1.2, 1), "RightHip", "LowerTorso", Vector3.new(0.5, -0.2, 0), Vector3.new(0, 0.42, 0) },
	{ "RightLowerLeg", Vector3.new(1, 1.2, 1), "RightKnee", "RightUpperLeg", Vector3.new(0, -0.4, 0), Vector3.new(0, 0.38, 0) },
	{ "RightFoot", Vector3.new(1, 0.3, 1), "RightAnkle", "RightLowerLeg", Vector3.new(0, -0.55, 0), Vector3.new(0, 0.1, 0) },
	{ "LeftUpperLeg", Vector3.new(1, 1.2, 1), "LeftHip", "LowerTorso", Vector3.new(-0.5, -0.2, 0), Vector3.new(0, 0.42, 0) },
	{ "LeftLowerLeg", Vector3.new(1, 1.2, 1), "LeftKnee", "LeftUpperLeg", Vector3.new(0, -0.4, 0), Vector3.new(0, 0.38, 0) },
	{ "LeftFoot", Vector3.new(1, 0.3, 1), "LeftAnkle", "LeftLowerLeg", Vector3.new(0, -0.55, 0), Vector3.new(0, 0.1, 0) },
}

Emu.RIG_PARTS = RIG_PARTS
Emu.HIP_HEIGHT = 2

function buildRig(name: string, color)
	local model = Instance.new("Model")
	model.Name = name

	local parts = {}
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	root.Transparency = 1
	root.CFrame = CFrame.new(0, Emu.HIP_HEIGHT + 1, 0)
	root.Parent = model
	parts.HumanoidRootPart = root
	model.PrimaryPart = root

	for _, spec in ipairs(RIG_PARTS) do
		local partName, size, jointName, parentName, c0, c1 = spec[1], spec[2], spec[3], spec[4], spec[5], spec[6]
		local parent = parts[parentName]
		local part = Instance.new("MeshPart")
		part.Name = partName
		part.Size = size
		if color then
			part.Color = color
		end
		local motor = Instance.new("Motor6D")
		motor.Name = jointName
		motor.Part0 = parent
		motor.Part1 = part
		motor.C0 = CFrame.new(c0)
		motor.C1 = CFrame.new(c1)
		motor.Transform = CFrame.new() -- в Lune у Transform нет значения по умолчанию
		part.CFrame = parent.CFrame * motor.C0 * motor.C1:Inverse()
		motor.Parent = part
		part.Parent = model
		parts[partName] = part
	end

	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R15
	humanoid.HipHeight = Emu.HIP_HEIGHT
	humanoid.Health = 100
	humanoid.Jump = false
	humanoid.MoveDirection = Vector3.zero
	humanoid.Parent = model
	local animator = Instance.new("Animator")
	animator.Parent = humanoid

	local animate = Instance.new("LocalScript")
	animate.Name = "Animate"
	animate.Parent = model
	return model
end

Emu.buildRig = buildRig

---------------------------------------------------------------------------
-- Загрузка и запуск скриптов игры
---------------------------------------------------------------------------

-- Свойства, которые Lune хранит отдельно или не вычисляет, заменяем на вызовы заглушек.
local function transformSource(source: string): string
	local lines = string.split(source, "\n")
	for index, line in ipairs(lines) do
		local out = {}
		local position = 1
		while true do
			local from, to = string.find(line, ".Position", position, true)
			if not from then
				table.insert(out, string.sub(line, position))
				break
			end
			local before = string.sub(line, position, from - 1)
			local after = string.sub(line, to + 1)
			local isWrite = string.match(after, "^%s*=[^=]") ~= nil
			local isCFrame = string.match(before, "CFrame$") ~= nil
			local continues = string.match(after, "^[%w_]") ~= nil
			table.insert(out, before)
			if isWrite or isCFrame or continues then
				table.insert(out, ".Position")
			else
				table.insert(out, ":__pos()")
			end
			position = to + 1
		end
		line = table.concat(out)
		line = string.gsub(line, "%.AssemblyRootPart", ":__assemblyRoot()")
		line = string.gsub(line, "%.Mass%f[^%w_]", ":GetMass()")
		lines[index] = line
	end
	return table.concat(lines, "\n")
end

local function makeRandom(seed: number?)
	local state = (seed or 12345) % 2147483647
	local random = {}
	local function nextFloat(): number
		state = (state * 48271) % 2147483647
		return state / 2147483647
	end
	function random.NextNumber(_, min: number?, max: number?): number
		local value = nextFloat()
		if min and max then
			return min + (max - min) * value
		end
		return value
	end
	function random.NextInteger(_, min: number, max: number): number
		return min + math.floor(nextFloat() * (max - min + 1))
	end
	return random
end

local function makeSide(sideName: string)
	local cache = {}
	local loading = {}
	local base = {}

	local function log(kind: string, ...)
		local parts = {}
		for i = 1, select("#", ...) do
			parts[i] = tostring((select(i, ...)))
		end
		local message = table.concat(parts, " ")
		table.insert(kind == "warn" and Emu.warnings or Emu.prints, string.format("[%s t=%.2f] %s", sideName, Emu.now, message))
		if Emu.verbose then
			print(string.format("%s[%s] %s", kind == "warn" and "WARN " or "", sideName, message))
		end
	end

	local function run(scriptInstance)
		local source = transformSource(scriptInstance.Source)
		-- luau.load берёт только собственные поля таблицы окружения, поэтому копируем её целиком.
		local env = table.clone(base)
		env.script = scriptInstance
		local chunk = luau.load(source, { debugName = scriptInstance:GetFullName(), environment = env })
		return chunk
	end

	local function requireModule(target)
		if typeof(target) ~= "Instance" or not target:IsA("ModuleScript") then
			error("require: ожидался ModuleScript, получено " .. typeof(target) .. " " .. tostring(target), 2)
		end
		if cache[target] ~= nil then
			return cache[target]
		end
		if loading[target] then
			error("require: циклическая зависимость через " .. target:GetFullName(), 2)
		end
		loading[target] = true
		local result = run(target)()
		loading[target] = nil
		if result == nil then
			error("модуль " .. target:GetFullName() .. " ничего не вернул", 2)
		end
		cache[target] = result
		return result
	end

	for key, value in pairs({
		game = Emu.game,
		workspace = Emu.game:GetService("Workspace"),
		Instance = Instance,
		Vector3 = Vector3,
		Vector2 = Vector2,
		CFrame = CFrame,
		Color3 = roblox.Color3,
		UDim = roblox.UDim,
		UDim2 = roblox.UDim2,
		Enum = Enum,
		BrickColor = roblox.BrickColor,
		NumberSequence = roblox.NumberSequence,
		NumberSequenceKeypoint = roblox.NumberSequenceKeypoint,
		ColorSequence = roblox.ColorSequence,
		ColorSequenceKeypoint = roblox.ColorSequenceKeypoint,
		NumberRange = roblox.NumberRange,
		PhysicalProperties = roblox.PhysicalProperties,
		Ray = roblox.Ray,
		Rect = roblox.Rect,
		Font = roblox.Font,
		TweenInfo = {
			new = function(time, style, direction)
				assert(time == nil or type(time) == "number", "TweenInfo.new: время должно быть числом")
				assert(style == nil or typeof(style) == "EnumItem", "TweenInfo.new: стиль должен быть Enum.EasingStyle")
				assert(direction == nil or typeof(direction) == "EnumItem", "TweenInfo.new: направление должно быть Enum.EasingDirection")
				return { __tweenInfo = true, Time = time or 1 }
			end,
		},
		Random = { new = makeRandom },
		task = task,
		wait = task.wait,
		require = requireModule,
		print = function(...)
			log("print", ...)
		end,
		warn = function(...)
			log("warn", ...)
		end,
		os = { clock = function()
			return Emu.now
		end, time = os.time, date = os.date },
		tick = function()
			return Emu.now
		end,
		time = function()
			return Emu.now
		end,
		typeof = typeof,
		type = type,
		error = error,
		assert = assert,
		pcall = pcall,
		xpcall = xpcall,
		select = select,
		ipairs = ipairs,
		pairs = pairs,
		next = next,
		tostring = tostring,
		tonumber = tonumber,
		unpack = table.unpack,
		rawget = rawget,
		rawset = rawset,
		rawequal = rawequal,
		rawlen = rawlen,
		setmetatable = setmetatable,
		getmetatable = getmetatable,
		table = table,
		string = string,
		math = math,
		coroutine = coroutine,
		debug = debug,
		bit32 = bit32,
		utf8 = utf8,
		buffer = buffer,
		_G = {},
		shared = {},
	}) do
		base[key] = value
	end

	return {
		name = sideName,
		require = requireModule,
		-- Запустить Script/LocalScript как отдельный поток.
		start = function(scriptInstance)
			local chunk = run(scriptInstance)
			task.spawn(chunk)
		end,
	}
end

---------------------------------------------------------------------------
-- Мир
---------------------------------------------------------------------------

function Emu.load(placePath: string)
	installMocks()
	Emu.game = roblox.deserializePlace(fs.readFile(placePath))
	local game = Emu.game
	local workspace = game:GetService("Workspace")

	local camera = workspace.CurrentCamera
	if not camera then
		camera = Instance.new("Camera")
		camera.Parent = workspace
		workspace.CurrentCamera = camera
	end
	camera.CFrame = CFrame.lookAt(Vector3.new(0, 30, 60), Vector3.new(0, 0, 0))
	camera.ViewportSize = Vector2.new(1280, 720)

	game:GetService("UserInputService").TouchEnabled = false
	Emu.server = makeSide("server")
	return game
end

function Emu.startServer()
	local main = Emu.game:GetService("ServerScriptService").Server.Main
	Emu.server.start(main)
end

-- Создать игрока с персонажем. Возвращает Player.
function Emu.addPlayer(name: string, userId: number)
	local game = Emu.game
	local players = game:GetService("Players")
	local player = Instance.new("Player")
	player.Name = name
	player.DisplayName = name
	player.UserId = userId
	player.Neutral = true
	local gui = Instance.new("PlayerGui")
	gui.Parent = player
	local scripts = Instance.new("PlayerScripts")
	scripts.Parent = player
	player.Parent = players
	signalOf(players, "PlayerAdded"):Fire(player)
	Emu.spawnCharacter(player)
	return player
end

function Emu.spawnCharacter(player)
	local workspace = Emu.game:GetService("Workspace")
	local old = player.Character
	if old then
		Emu.characters[old] = nil
		old:Destroy()
	end
	local character = buildRig(player.Name, nil)
	character.Parent = workspace
	player.Character = character
	Emu.characters[character] = { model = character, moveDir = Vector3.zero, moveTarget = nil, isPlayer = true }
	signalOf(player, "CharacterAdded"):Fire(character)
	return character
end

-- Запустить клиент от имени игрока (один клиент на эмулятор).
function Emu.startClient(player)
	local game = Emu.game
	game:GetService("Players").LocalPlayer = player
	local source = game:GetService("StarterPlayer").StarterPlayerScripts.Client
	local copy = source:Clone()
	copy.Parent = player:FindFirstChildOfClass("PlayerScripts")
	Emu.client = makeSide("client")
	Emu.client.start(copy.Main)
	return Emu.client
end

-- «Нажатие клавиши»: вызывает обработчик, привязанный через ContextActionService.
function Emu.input(action: string, state, inputType)
	local handler = Emu.bound[action]
	if not handler then
		Emu.recordError("нет привязки для действия " .. action)
		return
	end
	local inputObject = { UserInputType = inputType or Enum.UserInputType.Keyboard, UserInputState = state }
	task.spawn(handler, action, state, inputObject)
end

function Emu.tap(action: string)
	Emu.input(action, Enum.UserInputState.Begin)
	Emu.input(action, Enum.UserInputState.End)
end

---------------------------------------------------------------------------
-- Физика
---------------------------------------------------------------------------

local FIELD = {
	HalfLength = 130,
	HalfWidth = 75,
	EndMargin = 14,
	SideMargin = 9,
	GoalWidth = 32,
	GoalHeight = 12.5,
	GoalDepth = 9,
	WallHeight = 50,
}
Emu.FIELD = FIELD

local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

local function stepCharacters(dt: number)
	local workspace = Emu.game:GetService("Workspace")
	for model, controller in pairs(Emu.characters) do
		if not model.Parent then
			Emu.characters[model] = nil
			continue
		end
		local root = model:FindFirstChild("HumanoidRootPart")
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		if not root or not humanoid then
			continue
		end
		local position = root.CFrame.Position
		local direction = controller.moveDir
		if controller.moveTarget then
			local to = flat(controller.moveTarget - position)
			if to.Magnitude > 0.6 then
				direction = to.Unit
			else
				direction = Vector3.zero
			end
		end
		local velocity = direction * humanoid.WalkSpeed
		local dash = root:FindFirstChild("DashVelocity")
		if dash then
			local plane = dash.PlaneVelocity
			velocity = Vector3.new(plane.X, 0, plane.Y)
		end
		humanoid.MoveDirection = direction
		root.AssemblyLinearVelocity = velocity

		local target = position + velocity * dt
		local maxX = FIELD.HalfLength + FIELD.EndMargin - 2
		local maxZ = FIELD.HalfWidth + FIELD.SideMargin - 2
		target = Vector3.new(math.clamp(target.X, -maxX, maxX), Emu.HIP_HEIGHT + 1, math.clamp(target.Z, -maxZ, maxZ))

		local rotation = root.CFrame.Rotation
		if humanoid.AutoRotate and direction.Magnitude > 0.1 then
			rotation = CFrame.lookAt(Vector3.zero, direction)
		end
		local goal = CFrame.new(target) * rotation
		if (target - position).Magnitude > 1e-4 or rotation ~= root.CFrame.Rotation then
			movePivot(model, goal)
		end
	end
	local _ = workspace
end

Emu.ballTrace = {}

local function stepBall(dt: number)
	local workspace = Emu.game:GetService("Workspace")
	local ball = workspace:FindFirstChild("Ball")
	if not ball or ball.Anchored then
		return
	end
	local radius = ball.Size.X / 2
	local joint = ball:FindFirstChild("BallJoint")
	if joint and joint.Part0 then
		ball.CFrame = joint.Part0.CFrame * joint.C0
		ball.AssemblyLinearVelocity = joint.Part0.AssemblyLinearVelocity
		return
	end

	local velocity = ball.AssemblyLinearVelocity
	local acceleration = -workspace.Gravity
	local lift = ball:FindFirstChild("Lift")
	if lift and lift.Enabled then
		acceleration += lift.Force.Y / partMass(ball)
	end
	velocity += Vector3.new(0, acceleration * dt, 0)
	local previous = ball.CFrame.Position
	local position = previous + velocity * dt

	-- Газон.
	if position.Y < radius then
		position = Vector3.new(position.X, radius, position.Z)
		if velocity.Y < -6 then
			velocity = Vector3.new(velocity.X, -velocity.Y * 0.55, velocity.Z)
		else
			velocity = Vector3.new(velocity.X, 0, velocity.Z)
		end
	end
	if position.Y > FIELD.WallHeight - radius then
		position = Vector3.new(position.X, FIELD.WallHeight - radius, position.Z)
		velocity = Vector3.new(velocity.X, -math.abs(velocity.Y) * 0.5, velocity.Z)
	end

	local halfGoal = FIELD.GoalWidth / 2
	local inGoal = math.abs(previous.X) > FIELD.HalfLength and math.abs(previous.Z) < halfGoal and previous.Y < FIELD.GoalHeight
	if inGoal then
		-- Внутри ворот: сетка со всех сторон.
		local back = FIELD.HalfLength + FIELD.GoalDepth - radius
		if math.abs(position.X) > back then
			position = Vector3.new(math.sign(position.X) * back, position.Y, position.Z)
			velocity = Vector3.new(-velocity.X * 0.2, velocity.Y, velocity.Z)
		end
		if math.abs(position.Z) > halfGoal - radius then
			position = Vector3.new(position.X, position.Y, math.sign(position.Z) * (halfGoal - radius))
			velocity = Vector3.new(velocity.X, velocity.Y, -velocity.Z * 0.2)
		end
	else
		local maxX = FIELD.HalfLength + FIELD.EndMargin - radius
		local maxZ = FIELD.HalfWidth + FIELD.SideMargin - radius
		if math.abs(position.X) > maxX then
			position = Vector3.new(math.sign(position.X) * maxX, position.Y, position.Z)
			velocity = Vector3.new(-velocity.X * 0.6, velocity.Y, velocity.Z)
		end
		if math.abs(position.Z) > maxZ then
			position = Vector3.new(position.X, position.Y, math.sign(position.Z) * maxZ)
			velocity = Vector3.new(velocity.X, velocity.Y, -velocity.Z * 0.6)
		end
	end

	ball.CFrame = CFrame.new(position)
	ball.AssemblyLinearVelocity = velocity
end

-- Один кадр: таймеры -> Stepped -> физика -> Heartbeat -> RenderStepped.
function Emu.step(dt: number)
	local runService = Emu.game:GetService("RunService")
	runDue(Emu.now + dt)
	signalOf(runService, "Stepped"):Fire(Emu.now, dt)
	stepCharacters(dt)
	stepBall(dt)
	signalOf(runService, "Heartbeat"):Fire(dt)
	for _, entry in ipairs(table.clone(Emu.renderSteps)) do
		task.spawn(entry.fn, dt)
	end
	signalOf(runService, "RenderStepped"):Fire(dt)
	runDue(Emu.now)
end

function Emu.run(seconds: number, eachFrame: ((number) -> ())?)
	local dt = 1 / 60
	local frames = math.floor(seconds / dt + 0.5)
	for _ = 1, frames do
		Emu.step(dt)
		if eachFrame then
			eachFrame(dt)
		end
	end
end

-- Крутить мир, пока условие не выполнится (или не выйдет время).
function Emu.runUntil(timeout: number, condition: () -> boolean): boolean
	local dt = 1 / 60
	local frames = math.floor(timeout / dt + 0.5)
	for _ = 1, frames do
		if condition() then
			return true
		end
		Emu.step(dt)
	end
	return condition()
end

function Emu.controller(character)
	return Emu.characters[character]
end

-- Зарегистрировать персонажа, созданного кодом игры (бот), в физике эмулятора.
function Emu.adoptCharacters()
	local workspace = Emu.game:GetService("Workspace")
	for _, child in ipairs(workspace:GetChildren()) do
		if child:IsA("Model") and child:FindFirstChildOfClass("Humanoid") and not Emu.characters[child] then
			Emu.characters[child] = { model = child, moveDir = Vector3.zero, moveTarget = nil, isPlayer = false }
		end
	end
end

Emu.transformSource = transformSource

return Emu
