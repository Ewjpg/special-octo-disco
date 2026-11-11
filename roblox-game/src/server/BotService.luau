-- Боты-вратари. По одному на команду: держат позицию, прыгают за ударами, выбивают мяч партнёрам.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local F = require(Shared.FieldSpec)
local Mover = require(Shared.Mover)
local Util = require(Shared.Util)
local Actions = require(script.Parent.ActionService)
local Actors = require(script.Parent.Actors)
local Ball = require(script.Parent.BallService)
local Match = require(script.Parent.MatchService)
local Net = require(script.Parent.Net)
local Physics = require(script.Parent.Physics)
local PlayerService = require(script.Parent.PlayerService)

local BOTS = Config.Bots

local Bots = {}

local keepers = {} -- [teamKey] = { actor, tracks, running, releaseAt, diveReadyAt, reactAt, lastShot }
local spawning = {} -- [teamKey] = true, пока бот создаётся
local thinkTimer = 0

-- Стандартные анимации R15 от Roblox (доступны в любой игре).
local ANIMATION_IDS = {
	idle = "rbxassetid://507766666",
	run = "rbxassetid://507767714",
}

local function createRig(teamKey: string): Model?
	local team = Config.Teams[teamKey]
	local kit = team.Color:Lerp(Color3.fromRGB(255, 236, 90), 0.6)
	local dark = Color3.fromRGB(30, 32, 42)

	local description = Instance.new("HumanoidDescription")
	description.HeadColor = Color3.fromRGB(234, 196, 160)
	description.TorsoColor = kit
	description.LeftArmColor = kit
	description.RightArmColor = kit
	description.LeftLegColor = dark
	description.RightLegColor = dark

	local ok, result = pcall(function()
		return Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
	end)
	if not ok or typeof(result) ~= "Instance" then
		warn("[Bots] не удалось создать вратаря: " .. tostring(result))
		return nil
	end
	return result :: Model
end

local function spawnKeeper(teamKey: string)
	if spawning[teamKey] then
		return
	end
	spawning[teamKey] = true

	local model = createRig(teamKey)
	local humanoid = model and model:FindFirstChildOfClass("Humanoid") :: Humanoid?
	local root = model and model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not model or not humanoid or not root then
		if model then
			model:Destroy()
		end
		spawning[teamKey] = nil
		return
	end

	local team = Config.Teams[teamKey]
	model.Name = "Вратарь " .. team.Name
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.AutoRotate = false
	local animate = model:FindFirstChild("Animate")
	if animate then
		animate:Destroy()
	end

	local spot = F.fromOwnGoal(team.Side, 5, 0) + Vector3.new(0, 4, 0)
	model:PivotTo(CFrame.lookAt(spot, spot + F.attackDir(team.Side)))
	model.Parent = Workspace
	Physics.tagCharacter(model)
	pcall(function()
		root:SetNetworkOwner(nil)
	end)
	task.wait(0.2)

	local actor = Actors.register(model, { team = teamKey, isBot = true, isKeeper = true, styleId = "Keeper" })
	if not actor then
		model:Destroy()
		spawning[teamKey] = nil
		return
	end
	actor.baseSpeed = BOTS.KeeperSpeed
	actor.trapRadius = BOTS.KeeperReach
	actor.trapMaxSpeed = BOTS.KeeperCatchSpeed
	PlayerService.addKit(actor, "ВРАТАРЬ")

	local animator = humanoid:FindFirstChildOfClass("Animator") :: Animator?
	if not animator then
		local created = Instance.new("Animator")
		created.Parent = humanoid
		animator = created
	end
	local tracks = {}
	for name, id in pairs(ANIMATION_IDS) do
		local animation = Instance.new("Animation")
		animation.AnimationId = id
		local ok, track = pcall(function()
			return (animator :: Animator):LoadAnimation(animation)
		end)
		if ok and track then
			track.Looped = true
			tracks[name] = track
		end
	end
	if tracks.idle then
		tracks.idle:Play()
	end

	keepers[teamKey] = {
		actor = actor,
		tracks = tracks,
		running = false,
		releaseAt = 0,
		diveReadyAt = 0,
		reactAt = 0,
		lastShot = nil,
	}
	Match.placeLate(actor)
	spawning[teamKey] = nil
end

local function dive(keeper, lateral: number, heightAtLine: number, t: number)
	local actor = keeper.actor
	keeper.diveReadyAt = t + BOTS.KeeperDiveCooldown
	local dir = Vector3.new(0, 0, lateral > 0 and 1 or -1)
	actor.flags.reach = BOTS.KeeperDiveReach
	Actors.setFlag(actor, "reachUntil", 0.6)
	Mover.dash(actor.root, dir, BOTS.KeeperDiveSpeed, 0.3)
	if heightAtLine > 5.5 then
		actor.humanoid.Jump = true
	end
	Net.fx("KeeperDive", { character = actor.character, right = dir:Dot(actor.root.CFrame.RightVector) > 0 })
end

-- Вратарь с мячом выбивает его: партнёру, если тот открыт, иначе просто вперёд.
local function distribute(keeper)
	local actor = keeper.actor
	if not Match.isLive() then
		return
	end
	local forward = F.attackDir(actor.side)
	local target = Actions.findPassTarget(actor, forward, 85, 170)
	local elevation = 34
	local velocity
	if target then
		local to = Util.flat(target.root.Position - actor.root.Position)
		local needed = math.sqrt(to.Magnitude * Ball.gravity() / math.sin(math.rad(elevation * 2)))
		velocity = Util.withElevation(to, elevation) * math.clamp(needed, 50, 125)
	else
		local dir = Util.rotateY(forward, (math.random() * 2 - 1) * 28)
		velocity = Util.withElevation(dir, elevation) * 108
	end
	Ball.kick(actor, velocity, { kind = "Pass", noPickup = 0.8, passTarget = target })
	Net.fx("Kick", { character = actor.character, kind = "Lob", power = 0.6, position = Ball.position() })
end

local function think(keeper, t: number)
	local actor = keeper.actor
	local humanoid, root = actor.humanoid, actor.root
	local goal = F.goalCenter(actor.side)
	local inward = -actor.side -- направление от ворот в поле по оси X
	local half = F.GoalWidth / 2
	local rootPos = root.Position
	local ballPos, ballVel = Ball.position(), Ball.velocity()

	if actor.frozen or Actors.isStunned(actor, t) then
		return
	end

	-- Всегда лицом к мячу.
	local face = Util.flatUnit(ballPos - rootPos, Vector3.new(inward, 0, 0))
	root.CFrame = CFrame.lookAt(rootPos, rootPos + face)

	if actor.hasBall then
		if t >= keeper.releaseAt then
			distribute(keeper)
		else
			humanoid:MoveTo(Vector3.new(goal.X + inward * 9, rootPos.Y, goal.Z))
		end
		return
	end
	if not Match.isLive() then
		return
	end

	local shot = Ball.shot
	if shot and shot ~= keeper.lastShot then
		keeper.lastShot = shot
		keeper.reactAt = t + BOTS.KeeperReaction
	end

	local holder = Ball.holder
	local ahead = (ballPos.X - goal.X) * inward -- насколько мяч впереди линии ворот
	local approach = -ballVel.X * inward -- скорость мяча к линии ворот
	local target: Vector3? = nil

	-- Удар в створ: идём в точку, где мяч пересечёт линию, и при необходимости прыгаем.
	if not holder and approach > 12 and ahead > 0 and t >= keeper.reactAt then
		local eta = ahead / approach
		if eta < 1.6 then
			local zAtLine = ballPos.Z + ballVel.Z * eta
			local yAtLine = ballPos.Y + ballVel.Y * eta - 0.5 * Ball.gravity() * eta * eta
			if math.abs(zAtLine - goal.Z) < half + 5 and yAtLine < F.GoalHeight + 5 then
				local z = math.clamp(zAtLine, goal.Z - half + 1.5, goal.Z + half - 1.5)
				target = Vector3.new(goal.X + inward * 2.5, rootPos.Y, z)
				local lateral = zAtLine - rootPos.Z
				if eta < 0.6 and math.abs(lateral) > 3.2 and math.abs(lateral) < 17 and t >= keeper.diveReadyAt then
					dive(keeper, lateral, yAtLine, t)
				end
			end
		end
	end

	if not target then
		local loose = not holder
			and ahead < 30
			and ahead > -8
			and math.abs(ballPos.Z - goal.Z) < F.PenaltyWidth * 0.35
			and ballVel.Magnitude < 45
		if loose then
			-- Ничейный мяч рядом с воротами: забираем.
			target = Vector3.new(ballPos.X, rootPos.Y, ballPos.Z)
		else
			-- Обычная позиция: на линии «мяч — центр ворот», чуть выходя вперёд, когда мяч близко.
			local out = 4 + math.clamp(1 - ahead / 120, 0, 1) * 5
			local toBall = Util.flatUnit(ballPos - goal, Vector3.new(inward, 0, 0))
			local point = goal + toBall * out
			local x = goal.X + inward * math.max(2.5, (point.X - goal.X) * inward)
			target = Vector3.new(x, rootPos.Y, math.clamp(point.Z, goal.Z - half + 2, goal.Z + half - 2))
		end
	end
	humanoid:MoveTo(target :: Vector3)
end

local function updateAnimation(keeper)
	local tracks = keeper.tracks
	if not tracks.run then
		return
	end
	local moving = Util.flat(keeper.actor.root.AssemblyLinearVelocity).Magnitude > 2
	if moving ~= keeper.running then
		keeper.running = moving
		if moving then
			tracks.run:Play(0.15)
		else
			tracks.run:Stop(0.15)
		end
	end
end

function Bots.step(dt: number)
	thinkTimer += dt
	if thinkTimer < 0.05 then
		return
	end
	thinkTimer = 0
	local t = Actors.now()
	for teamKey, keeper in pairs(keepers) do
		local actor = keeper.actor
		if not actor.alive or not actor.character.Parent then
			-- Вратарь пропал (например, упал за карту) — создаём нового.
			keepers[teamKey] = nil
			Actors.unregister(actor.character)
			if actor.character.Parent then
				actor.character:Destroy()
			end
			task.delay(2, spawnKeeper, teamKey)
		else
			think(keeper, t)
			updateAnimation(keeper)
		end
	end
end

function Bots.init()
	if not BOTS.Goalkeepers then
		return
	end

	Ball.Possessed:Connect(function(actor, _previous, shot)
		for _, keeper in pairs(keepers) do
			if keeper.actor == actor then
				keeper.releaseAt = Actors.now() + BOTS.KeeperHoldTime
				if shot and shot.team ~= actor.team and shot.kind == "Shot" then
					Net.fx("Save", { character = actor.character, position = Ball.position() })
				end
			end
		end
	end)

	for teamKey in pairs(Config.Teams) do
		task.spawn(spawnKeeper, teamKey)
	end
end

return Bots
