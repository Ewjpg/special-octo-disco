-- Проигрывает анимации из Shared/Animations на любом персонаже R15.
-- Работает через Motor6D.Transform: каждый кадр (Stepped) мы подмешиваем свою позу
-- поверх того, что выставил стандартный Animator (бег, стойка).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Animations = require(Shared.Animations)
local AnimSampler = require(Shared.AnimSampler)

local ProcAnimator = {}

local JOINTS = {
	Root = true,
	Waist = true,
	Neck = true,
	RightShoulder = true,
	RightElbow = true,
	RightWrist = true,
	LeftShoulder = true,
	LeftElbow = true,
	LeftWrist = true,
	RightHip = true,
	RightKnee = true,
	RightAnkle = true,
	LeftHip = true,
	LeftKnee = true,
	LeftAnkle = true,
}

local rigs = {} -- [Model] = { motors, count, tracks, written }

local function findMotors(character: Model)
	local motors = {}
	local count = 0
	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("Motor6D") and JOINTS[descendant.Name] and not motors[descendant.Name] then
			motors[descendant.Name] = descendant
			count += 1
		end
	end
	return motors, count
end

local function getRig(character: Model)
	local rig = rigs[character]
	if not rig then
		rig = { motors = {}, count = 0, tracks = {}, written = {} }
		rigs[character] = rig
	end
	if rig.count < 12 then
		rig.motors, rig.count = findMotors(character)
	end
	return rig
end

-- options: speed, weight, fadeIn, fadeOut
function ProcAnimator.play(character: Model?, name: string, options: { [string]: number }?)
	local anim = Animations[name]
	if not anim or not character or not character.Parent then
		return nil
	end
	local rig = getRig(character)
	for i = #rig.tracks, 1, -1 do
		if rig.tracks[i].anim == anim then
			table.remove(rig.tracks, i)
		end
	end
	local opts = options or {}
	local track = {
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
	local anim = Animations[name]
	for _, track in ipairs(rig.tracks) do
		if track.anim == anim then
			track.stopping = true
		end
	end
end

function ProcAnimator.isPlaying(character: Model?, name: string): boolean
	local rig = character and rigs[character]
	if not rig then
		return false
	end
	local anim = Animations[name]
	for _, track in ipairs(rig.tracks) do
		if track.anim == anim and not track.stopping then
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
		for _, track in ipairs(rig.tracks) do
			local value = track.pose[name]
			if value and track.weight > 0 then
				result = result:Lerp(AnimSampler.toCFrame(value), track.weight)
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
