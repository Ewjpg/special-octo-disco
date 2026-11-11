-- Мяч. Сервер решает всё: у кого мяч, куда он летит, принят он или отбит, был ли гол.
--
-- Два состояния:
--   у игрока  — мяч приварен (Motor6D) к HumanoidRootPart и едет вместе с персонажем;
--   свободен  — обычная физика Roblox, владелец физики — сервер.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local F = require(Shared.FieldSpec)
local Signal = require(Shared.Signal)
local Util = require(Shared.Util)
local Actors = require(script.Parent.Actors)
local Net = require(script.Parent.Net)
local Physics = require(script.Parent.Physics)

local BALL = Config.Ball
local R = BALL.Radius
local UP = Vector3.new(0, 1, 0)

local Ball = {}

Ball.part = nil :: Part?
Ball.holder = nil -- актёр с мячом
Ball.active = false -- можно ли подбирать мяч и забивать
Ball.lastTouch = nil -- { actor, team, time, kind }
Ball.prevTouch = nil
Ball.shot = nil -- сведения о последнем ударе: { kicker, team, kind, time, untrappableUntil, speed, passTarget }
Ball.lockedUntil = 0 -- до этого времени мяч никто не может тронуть

Ball.Possessed = Signal.new() -- (actor, previousHolder, shotInfo)
Ball.Blocked = Signal.new() -- (actor, shotInfo)
Ball.Goal = Signal.new() -- (scoringTeam, scorer, assist, goalSide)

local joint: Motor6D? = nil
local lift: VectorForce = nil :: any
local ballMass = 1
local gravityScale = BALL.GravityScale
local gravityKickTime = 0 -- когда включили особую гравитацию удара
local gravityRestoreAt = 0 -- когда вернуть обычную
local forces = {} -- { fn = function(dt, part, t), expires = number }
local needOwner = false
local prevPos = Vector3.zero

local function createBall(): Part
	local part = Instance.new("Part")
	part.Name = "Ball"
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(R * 2, R * 2, R * 2)
	part.Material = Enum.Material.SmoothPlastic
	part.Color = Color3.fromRGB(246, 246, 250)
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CustomPhysicalProperties = PhysicalProperties.new(0.4, 0.45, 0.62, 1, 1)
	part.CollisionGroup = Physics.BALL
	part.RootPriority = -100 -- при ведении корнем сборки должен остаться персонаж
	part.CFrame = CFrame.new(F.Origin + Vector3.new(0, R + 0.05, 0))

	-- Тёмные «заплатки» по вершинам икосаэдра, чтобы было видно вращение.
	local phi = (1 + math.sqrt(5)) / 2
	local directions = {}
	for _, a in ipairs({ -1, 1 }) do
		for _, b in ipairs({ -phi, phi }) do
			table.insert(directions, Vector3.new(0, a, b).Unit)
			table.insert(directions, Vector3.new(a, b, 0).Unit)
			table.insert(directions, Vector3.new(b, 0, a).Unit)
		end
	end
	for _, dir in ipairs(directions) do
		local patch = Instance.new("Part")
		patch.Name = "Patch"
		patch.Shape = Enum.PartType.Cylinder
		patch.Size = Vector3.new(0.12, R * 0.82, R * 0.82)
		patch.Material = Enum.Material.SmoothPlastic
		patch.Color = Color3.fromRGB(28, 30, 40)
		patch.CanCollide = false
		patch.CanTouch = false
		patch.CanQuery = false
		patch.Massless = true
		patch.CastShadow = false
		patch.RootPriority = -127
		patch.CollisionGroup = Physics.BALL
		local position = part.Position + dir * (R - 0.03)
		patch.CFrame = CFrame.lookAt(position, position + dir) * CFrame.Angles(0, math.rad(90), 0)
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = part
		weld.Part1 = patch
		weld.Parent = patch
		patch.Parent = part
	end

	local center = Instance.new("Attachment")
	center.Name = "Center"
	center.Parent = part

	local force = Instance.new("VectorForce")
	force.Name = "Lift"
	force.Attachment0 = center
	force.RelativeTo = Enum.ActuatorRelativeTo.World
	force.ApplyAtCenterOfMass = true
	force.Force = Vector3.zero
	force.Enabled = false
	force.Parent = part
	lift = force

	part:SetAttribute("Held", false)
	part.Parent = Workspace
	ballMass = part.Mass
	return part
end

-- Подъёмная сила компенсирует часть гравитации: мяч летит дальше и «аниме-шнее».
local function refreshLift()
	local part = Ball.part :: Part
	if Ball.holder or part.Anchored then
		lift.Enabled = false
		return
	end
	lift.Force = Vector3.new(0, ballMass * Workspace.Gravity * (1 - gravityScale), 0)
	lift.Enabled = true
end

-- Физикой свободного мяча всегда владеет сервер.
local function claimOwnership()
	local part = Ball.part :: Part
	if part.Anchored then
		needOwner = false
		return
	end
	if part.AssemblyRootPart ~= part then
		needOwner = true
		return
	end
	local ok = pcall(function()
		part:SetNetworkOwner(nil)
	end)
	needOwner = not ok
end

local function releaseHolder()
	local actor = Ball.holder
	if joint then
		joint:Destroy()
		joint = nil
	end
	Ball.holder = nil
	if actor then
		actor.hasBall = false
		if actor.character.Parent then
			actor.character:SetAttribute("HasBall", false)
		end
	end
	local part = Ball.part :: Part
	part.Massless = false
	part.CanCollide = true
	part:SetAttribute("Held", false)
	claimOwnership()
	refreshLift()
end

function Ball.position(): Vector3
	return (Ball.part :: Part).Position
end

function Ball.velocity(): Vector3
	return (Ball.part :: Part).AssemblyLinearVelocity
end

function Ball.gravity(): number
	return Workspace.Gravity * gravityScale
end

function Ball.setGravityScale(scale: number)
	gravityScale = scale
	refreshLift()
end

-- Запомнить касание (нужно для авторства гола и передач).
function Ball.touch(actor, kind: string?)
	local last = Ball.lastTouch
	if last and last.actor ~= actor then
		Ball.prevTouch = last
	end
	Ball.lastTouch = { actor = actor, team = actor.team, time = Actors.now(), kind = kind or "hold" }
end

function Ball.lock(duration: number)
	Ball.lockedUntil = Actors.now() + duration
end

-- Дополнительная сила на мяч (подкрутка, притяжение...). fn(dt, part, t) вызывается каждый кадр.
function Ball.addForce(duration: number, fn)
	table.insert(forces, { fn = fn, expires = Actors.now() + duration })
end

-- Подсветка следа мяча на клиентах.
function Ball.setFx(color: Color3, duration: number)
	local part = Ball.part :: Part
	part:SetAttribute("FxColor", color)
	part:SetAttribute("FxUntil", Actors.now() + duration)
end

function Ball.attach(actor)
	local part = Ball.part :: Part
	if Ball.holder == actor then
		return
	end
	local previous = Ball.holder
	local shot = Ball.shot
	if previous then
		releaseHolder()
	end
	Ball.shot = nil
	table.clear(forces)

	part.Anchored = false
	part.AssemblyLinearVelocity = Vector3.zero
	part.AssemblyAngularVelocity = Vector3.zero
	part.CanCollide = false
	part.Massless = true
	lift.Enabled = false
	gravityScale = BALL.GravityScale

	local motor = Instance.new("Motor6D")
	motor.Name = "BallJoint"
	motor.Part0 = actor.root
	motor.Part1 = part
	motor.C0 = CFrame.new(0, -actor.groundOffset + R, -BALL.HoldDistance)
	motor.Parent = part
	joint = motor

	Ball.holder = actor
	actor.hasBall = true
	actor.character:SetAttribute("HasBall", true)
	part:SetAttribute("Held", true)
	part:SetAttribute("FxUntil", 0)
	Ball.touch(actor, "hold")
	Ball.Possessed:Fire(actor, previous, shot)
end

-- Удар по мячу. Работает и для игрока с мячом, и для свободного мяча (вторая фаза способностей).
-- opts: kind, noPickup, untrappable, gravityScale, gravityTime, passTarget, color, colorTime
-- gravityScale действует временно: до первого касания газона или gravityTime секунд (по умолчанию 1.2).
function Ball.kick(actor, velocity: Vector3, opts: { [string]: any }?)
	local options = opts or {}
	local part = Ball.part :: Part
	local t = Actors.now()

	if Ball.holder then
		local wasHolder = Ball.holder == actor
		releaseHolder()
		if wasHolder then
			local dir = Util.flatUnit(velocity, actor.root.CFrame.LookVector)
			local feet = actor.root.Position - Vector3.new(0, actor.groundOffset - R - 0.05, 0)
			local start = F.clampToArena(feet + dir * BALL.HoldDistance, R + 0.5)
			part.CFrame = CFrame.new(start)
		end
	end
	part.Anchored = false

	local speed = math.min(velocity.Magnitude, BALL.MaxSpeed)
	local direction = Util.unit(velocity, actor.root.CFrame.LookVector)
	part.AssemblyLinearVelocity = direction * speed
	part.AssemblyAngularVelocity = UP:Cross(Util.flatUnit(direction)) * (speed / R) * 0.35

	actor.noPickupUntil = t + (options.noPickup or BALL.KickNoPickup)
	Ball.touch(actor, "kick")
	Ball.shot = {
		kicker = actor,
		team = actor.team,
		kind = options.kind or "Shot",
		time = t,
		untrappableUntil = t + (options.untrappable or 0),
		speed = speed,
		passTarget = options.passTarget,
	}
	table.clear(forces)
	gravityScale = options.gravityScale or BALL.GravityScale
	gravityKickTime = t
	gravityRestoreAt = t + (options.gravityTime or 1.2)
	claimOwnership()
	refreshLift()
	if options.color then
		Ball.setFx(options.color, options.colorTime or 1.5)
	end
	prevPos = part.Position
end

-- Выбить мяч у владельца (подкат).
function Ball.knockLoose(velocity: Vector3, byActor)
	local part = Ball.part :: Part
	if Ball.holder then
		releaseHolder()
	end
	Ball.shot = nil
	table.clear(forces)
	part.AssemblyLinearVelocity = velocity
	if byActor then
		Ball.touch(byActor, "tackle")
	end
end

-- Поставить мяч в точку. frozen = true — закрепить (перед розыгрышем).
function Ball.reset(position: Vector3, frozen: boolean)
	local part = Ball.part :: Part
	if Ball.holder then
		releaseHolder()
	end
	Ball.shot = nil
	Ball.lastTouch = nil
	Ball.prevTouch = nil
	Ball.lockedUntil = 0
	table.clear(forces)
	gravityScale = BALL.GravityScale
	part.Anchored = frozen
	part.AssemblyLinearVelocity = Vector3.zero
	part.AssemblyAngularVelocity = Vector3.zero
	part.CFrame = CFrame.new(position)
	part:SetAttribute("FxUntil", 0)
	prevPos = position
	if not frozen then
		claimOwnership()
	end
	refreshLift()
end

function Ball.setFrozen(frozen: boolean)
	local part = Ball.part :: Part
	part.Anchored = frozen
	if not frozen then
		claimOwnership()
	end
	refreshLift()
end

---------------------------------------------------------------------------
-- Контакт мяча с игроками
---------------------------------------------------------------------------

-- Отбить мяч, который нельзя принять.
local function block(actor, pos: Vector3, vel: Vector3, speed: number, t: number)
	local toActor = Util.flat(actor.root.Position - pos)
	if vel:Dot(toActor) <= 0 then
		return -- мяч уже улетает от игрока
	end
	local part = Ball.part :: Part
	local normal = Util.flatUnit(pos - actor.root.Position, -Util.flatUnit(vel))
	local reflected = vel - normal * (2 * vel:Dot(normal))
	local out = reflected * BALL.BlockDamping + Vector3.new(0, 10 + speed * 0.05, 0)
	part.AssemblyLinearVelocity = out

	local shot = Ball.shot
	if shot then
		shot.untrappableUntil = 0
	end
	table.clear(forces)
	gravityScale = BALL.GravityScale
	refreshLift()
	part:SetAttribute("FxUntil", 0)
	actor.noPickupUntil = t + 0.35
	Ball.touch(actor, "block")
	Net.fx("Block", { character = actor.character, position = pos, speed = speed })
	Ball.Blocked:Fire(actor, shot)
end

local function resolveContact(actor, pos: Vector3, vel: Vector3, speed: number, t: number)
	if Actors.hasFlag(actor, "autoTrapUntil", t) then
		Ball.attach(actor)
		return
	end
	local shot = Ball.shot
	local sameTeam = shot ~= nil and shot.team == actor.team
	if shot and t < shot.untrappableUntil then
		if not sameTeam then
			block(actor, pos, vel, speed, t)
		end
		return
	end
	local limit = (actor.trapMaxSpeed or BALL.TrapMaxSpeed) * (actor.style.stats.trap or 1)
	if sameTeam then
		limit *= BALL.TeammateTrapBonus
	end
	if speed > limit then
		block(actor, pos, vel, speed, t)
		return
	end
	Ball.attach(actor)
end

local function checkContacts(pos: Vector3, vel: Vector3, t: number)
	local best, bestDist
	for _, actor in pairs(Actors.byCharacter) do
		if actor.alive and not actor.frozen and t >= actor.noPickupUntil and t >= actor.stunnedUntil then
			local rootPos = actor.root.Position
			local closest = Util.closestOnSegment(prevPos, pos, rootPos)
			local dist = Util.flat(closest - rootPos).Magnitude
			local height = closest.Y - (rootPos.Y - actor.groundOffset)
			local radius = actor.trapRadius or BALL.PickupRadius
			if actor.flags.reach and Actors.hasFlag(actor, "reachUntil", t) then
				radius = math.max(radius, actor.flags.reach)
			end
			if dist <= radius and height >= -1.5 and height <= BALL.PickupHeight then
				if not bestDist or dist < bestDist then
					best, bestDist = actor, dist
				end
			end
		end
	end
	if best then
		resolveContact(best, pos, vel, vel.Magnitude, t)
	end
end

local function checkGoal(pos: Vector3)
	local side = F.goalSideAt(pos, R)
	if not side then
		return
	end
	local holder = Ball.holder
	if holder and holder.isKeeper and holder.side == side then
		return -- вратарь с мячом зашёл в свои ворота: не гол
	end
	Ball.active = false

	local scoringTeam = side == Config.Teams.Home.Side and "Away" or "Home"
	local scorer, assist
	local last, prev = Ball.lastTouch, Ball.prevTouch
	if last then
		if last.team == scoringTeam then
			scorer = last.actor
			if prev and prev.team == scoringTeam and prev.actor ~= last.actor and last.time - prev.time < 12 then
				assist = prev.actor
			end
		elseif prev and prev.team == scoringTeam and last.time - prev.time < 4 then
			scorer = prev.actor -- рикошет от защитника: гол записываем бившему
		end
	end
	Ball.Goal:Fire(scoringTeam, scorer, assist, side)
end

-- Каждый кадр сервера.
function Ball.step(dt: number)
	local part = Ball.part
	if not part or not part.Parent then
		return
	end
	local t = Actors.now()

	local holder = Ball.holder
	if holder then
		local valid = holder.alive
			and holder.character.Parent ~= nil
			and joint ~= nil
			and joint.Parent == part
			and joint.Part0 == holder.root
		if not valid then
			releaseHolder()
		elseif Ball.active then
			checkGoal(part.Position)
		end
		prevPos = part.Position
		return
	end

	if needOwner then
		claimOwnership()
	end
	if part.Anchored then
		prevPos = part.Position
		return
	end

	local pos = part.Position
	local rel = pos - F.Origin

	-- Страховка: мяч как-то вылетел из арены.
	if
		rel.Y < -12
		or rel.Y > F.WallHeight + 30
		or math.abs(rel.X) > F.HalfLength + F.EndMargin + 12
		or math.abs(rel.Z) > F.HalfWidth + F.SideMargin + 12
	then
		local safe = F.clampToArena(pos, 8)
		Ball.reset(Vector3.new(safe.X, F.Origin.Y + 5, safe.Z), false)
		return
	end

	for i = #forces, 1, -1 do
		local force = forces[i]
		if t >= force.expires then
			table.remove(forces, i)
		else
			force.fn(dt, part, t)
		end
	end

	-- Сопротивление: по земле мяч тормозит сильнее, чем в воздухе.
	local vel = part.AssemblyLinearVelocity
	local grounded = rel.Y <= R + 0.35

	-- Особая гравитация спец-удара заканчивается по времени или при первом касании газона.
	if gravityScale ~= BALL.GravityScale then
		if t >= gravityRestoreAt or (grounded and t - gravityKickTime > 0.15) then
			Ball.setGravityScale(BALL.GravityScale)
		end
	end
	local factor = math.max(0, 1 - (grounded and BALL.GroundDrag or BALL.AirDrag) * dt)
	local horizontal = Vector3.new(vel.X * factor, 0, vel.Z * factor)
	if grounded and horizontal.Magnitude < 0.6 then
		horizontal = Vector3.zero
	end
	vel = Vector3.new(horizontal.X, vel.Y, horizontal.Z)
	if vel.Magnitude > BALL.MaxSpeed then
		vel = vel.Unit * BALL.MaxSpeed
	end
	part.AssemblyLinearVelocity = vel
	if grounded then
		part.AssemblyAngularVelocity *= math.max(0, 1 - 0.9 * dt)
	end

	if Ball.active then
		if t >= Ball.lockedUntil then
			checkContacts(pos, vel, t)
		end
		if Ball.active and not Ball.holder then
			checkGoal(pos)
		end
	end
	prevPos = pos
end

function Ball.init()
	Ball.part = createBall()
	prevPos = Ball.part.Position
	Ball.reset(F.Origin + Vector3.new(0, R + 0.05, 0), true)
end

return Ball
