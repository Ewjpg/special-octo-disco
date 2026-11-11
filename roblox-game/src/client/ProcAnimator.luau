-- Проигрывает анимации из Shared/Animations на персонажах R6 и R15.
-- Работает через Motor6D.Transform: каждый кадр (Stepped) мы подмешиваем свою позу
-- поверх того, что выставил стандартный Animator (бег, стойка).
--
-- Если в Config.AnimationIds для анимации указан ID (анимация, опубликованная в Roblox — например,
-- сделанная в Blender), вместо позы из кода играется она, через обычный Animator.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Animations = require(Shared.Animations)
local Config = require(Shared.Config)
local AnimSampler = require(Shared.AnimSampler)

local ProcAnimator = {}

local JOINTS = {
	R15 = {
		"Root",
		"Waist",
		"Neck",
		"RightShoulder",
		"RightElbow",
		"RightWrist",
		"LeftShoulder",
		"LeftElbow",
		"LeftWrist",
		"RightHip",
		"RightKnee",
		"RightAnkle",
		"LeftHip",
		"LeftKnee",
		"LeftAnkle",
	},
	R6 = { "RootJoint", "Neck", "Right Shoulder", "Left Shoulder", "Right Hip", "Left Hip" },
}

local rigs = {} -- [Model] = { kind, motors, frames, count, tracks, written }

-- Тип аватара определяем по Humanoid, а если его нет — по именам суставов.
local function detectKind(character: Model): string
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		return humanoid.RigType == Enum.HumanoidRigType.R6 and "R6" or "R15"
	end
	return character:FindFirstChild("Torso") and "R6" or "R15"
end

local function findMotors(character: Model, kind: string)
	local wanted = {}
	for _, name in ipairs(JOINTS[kind]) do
		wanted[name] = true
	end
	local motors, frames = {}, {}
	local count = 0
	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("Motor6D") and wanted[descendant.Name] and not motors[descendant.Name] then
			motors[descendant.Name] = descendant
			-- У суставов R6 оси повёрнуты (C0 с поворотом). Позы заданы в осях персонажа,
			-- поэтому перед записью в Transform переводим их в оси сустава.
			local rotation = descendant.C0.Rotation
			frames[descendant.Name] = { rotation = rotation, inverse = rotation:Inverse() }
			count += 1
		end
	end
	return motors, frames, count
end

local function getRig(character: Model)
	local rig = rigs[character]
	if not rig then
		rig = { kind = detectKind(character), motors = {}, frames = {}, count = 0, tracks = {}, written = {}, assets = {} }
		rigs[character] = rig
	end
	if rig.count < #JOINTS[rig.kind] - 3 then
		rig.kind = detectKind(character)
		rig.motors, rig.frames, rig.count = findMotors(character, rig.kind)
	end
	return rig
end

-- Анимация из Roblox по ID (Config.AnimationIds). Возвращает AnimationTrack или nil, если ID не задан
-- или анимацию не удалось загрузить — тогда играет встроенная поза.
local function assetTrack(rig, character: Model, name: string): AnimationTrack?
	local id = Config.AnimationIds[name]
	if type(id) ~= "string" or id == "" then
		return nil
	end
	local cached = rig.assets[name]
	if cached ~= nil then
		return cached or nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	local track = nil
	if animator then
		local animation = Instance.new("Animation")
		animation.AnimationId = id
		local ok, result = pcall(function()
			return animator:LoadAnimation(animation)
		end)
		if ok and result then
			track = result
			track.Priority = Enum.AnimationPriority.Action
		else
			warn(string.format("[Animations] could not load %s (%s): %s", name, id, tostring(result)))
		end
	end
	rig.assets[name] = track or false
	return track
end

-- options: speed, weight, fadeIn, fadeOut
function ProcAnimator.play(character: Model?, name: string, options: { [string]: number }?)
	if not character or not character.Parent then
		return nil
	end
	local rig = getRig(character)
	local anim = Animations.get(name, rig.kind)
	if not anim then
		return nil
	end
	local opts = options or {}

	local asset = assetTrack(rig, character, name)
	if asset then
		asset.Looped = anim.loop == true
		asset:Play(opts.fadeIn or anim.fadeIn or 0.08, opts.weight or 1, opts.speed or 1)
		return asset
	end

	for i = #rig.tracks, 1, -1 do
		if rig.tracks[i].name == name then
			table.remove(rig.tracks, i)
		end
	end
	local track = {
		name = name,
		anim = anim,
		time = 0,
		elapsed = 0,
		speed = opts.speed or 1,
		weight = 0,
		maxWeight = opts.weight or 1,
		fadeIn = math.max(0.001, opts.fadeIn or anim.fadeIn or 0.08),
		fadeOut = math.max(0.001, opts.fadeOut or anim.fadeOut or 0.15),
		priority = anim.priority or 1,
		loop = anim.loop == true,
		stopping = false,
		stopElapsed = 0,
		pose = {},
	}
	-- Вставляем по приоритету: более важные применяются последними.
	local index = #rig.tracks + 1
	for i, other in ipairs(rig.tracks) do
		if other.priority > track.priority then
			index = i
			break
		end
	end
	table.insert(rig.tracks, index, track)
	return track
end

function ProcAnimator.stop(character: Model?, name: string)
	local rig = character and rigs[character]
	if not rig then
		return
	end
	local asset = rig.assets[name]
	if asset then
		local anim = Animations.get(name, rig.kind)
		asset:Stop(anim and anim.fadeOut or 0.15)
	end
	for _, track in ipairs(rig.tracks) do
		if track.name == name then
			track.stopping = true
		end
	end
end

function ProcAnimator.isPlaying(character: Model?, name: string): boolean
	local rig = character and rigs[character]
	if not rig then
		return false
	end
	local asset = rig.assets[name]
	if asset and asset.IsPlaying then
		return true
	end
	for _, track in ipairs(rig.tracks) do
		if track.name == name and not track.stopping then
			return true
		end
	end
	return false
end

local function stepRig(rig, dt: number)
	-- Продвигаем дорожки и считаем их вес.
	for i = #rig.tracks, 1, -1 do
		local track = rig.tracks[i]
		local anim = track.anim
		track.elapsed += dt
		track.time += dt * track.speed
		local weight = math.min(1, track.elapsed / track.fadeIn)
		local done = false
		if track.loop then
			if track.time >= anim.length then
				track.time %= anim.length
			end
		else
			local remaining = anim.length - track.time
			if remaining <= 0 then
				done = true
			else
				weight *= math.clamp(remaining / track.fadeOut, 0, 1)
			end
		end
		if track.stopping then
			track.stopElapsed += dt
			local k = 1 - track.stopElapsed / track.fadeOut
			if k <= 0 then
				done = true
			else
				weight *= k
			end
		end
		if done then
			table.remove(rig.tracks, i)
		else
			track.weight = weight * track.maxWeight
			AnimSampler.sample(anim, track.time, track.pose)
		end
	end

	-- Смешиваем с тем, что выставил стандартный Animator.
	for name, motor in pairs(rig.motors) do
		local base = motor.Transform
		local last = rig.written[name]
		local driven = true
		if last and base == last then
			-- Animator в этом кадре сустав не трогал: исходим из нейтральной позы.
			base = CFrame.identity
			driven = false
		end
		local result = base
		local touched = false
		local frame = rig.frames[name]
		for _, track in ipairs(rig.tracks) do
			local value = track.pose[name]
			if value and track.weight > 0 then
				local pivots = track.anim.pivots
				local desired = AnimSampler.toCFrame(value, pivots and pivots[name])
				result = result:Lerp(frame.inverse * desired * frame.rotation, track.weight)
				touched = true
			end
		end
		if touched then
			motor.Transform = result
			rig.written[name] = result
		elseif last then
			if not driven then
				motor.Transform = CFrame.identity
			end
			rig.written[name] = nil
		end
	end
end

function ProcAnimator.start()
	RunService.Stepped:Connect(function(_, dt)
		for character, rig in pairs(rigs) do
			if not character.Parent then
				rigs[character] = nil
			elseif #rig.tracks > 0 or next(rig.written) ~= nil then
				stepRig(rig, dt)
			end
		end
	end)
end

return ProcAnimator
