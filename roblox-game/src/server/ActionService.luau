-- Принимает действия игроков (RemoteEvent "Action"), проверяет их и выполняет:
-- удар, пас, навес, подкат, рывок, способности стиля, выбор стиля.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local F = require(Shared.FieldSpec)
local Styles = require(Shared.Styles)
local Util = require(Shared.Util)
local Actors = require(script.Parent.Actors)
local Ball = require(script.Parent.BallService)
local Match = require(script.Parent.MatchService)
local Net = require(script.Parent.Net)
local PlayerService = require(script.Parent.PlayerService)

local SHOT, PASS, LOB = Config.Shot, Config.Pass, Config.Lob
local TACKLE, DASH, DRIBBLE, RES = Config.Tackle, Config.Dash, Config.Dribble, Config.Resonance

local Actions = {}

local handlers = {}
local budgets = {} -- [Player] = { tokens, time } — защита от спама событиями

local function ready(actor, t: number): boolean
	return Match.isLive() and Actors.canAct(actor, t)
end

-- Направление от клиента -> безопасное горизонтальное направление (или nil).
local function flatDir(value: any, fallback: Vector3): Vector3?
	if value == nil then
		return fallback
	end
	if not Util.isVector(value) then
		return nil
	end
	return Util.flatUnit(value, fallback)
end

local function setCharging(actor, on: boolean)
	if actor.charging == on then
		return
	end
	actor.charging = on
	if actor.character.Parent then
		actor.character:SetAttribute("Charging", on)
	end
	Net.fx("Charge", { character = actor.character, on = on })
end

-- Лучший партнёр для паса в конусе по направлению dir.
function Actions.findPassTarget(actor, dir: Vector3, maxAngle: number, maxRange: number)
	local origin = actor.root.Position
	local best, bestScore
	for _, other in pairs(Actors.byCharacter) do
		if other ~= actor and other.alive and other.team == actor.team then
			local to = Util.flat(other.root.Position - origin)
			local distance = to.Magnitude
			if distance > 6 and distance <= maxRange then
				local angle = Util.angleBetween(dir, to)
				if angle <= maxAngle then
					local score = angle * 1.5 + distance * 0.08
					if not bestScore or score < bestScore then
						best, bestScore = other, score
					end
				end
			end
		end
	end
	return best
end

local function kickFx(actor, kind: string, power: number)
	Net.fx("Kick", { character = actor.character, kind = kind, power = power, position = Ball.position() })
end

---------------------------------------------------------------------------
-- Базовые действия
---------------------------------------------------------------------------

function handlers.Sprint(actor, on)
	actor.sprinting = on == true
end

function handlers.Charge(actor, on)
	local t = Actors.now()
	setCharging(actor, on == true and actor.hasBall and ready(actor, t))
end

-- Spin on a curved shot: every frame the ball's horizontal velocity turns a little to one side
-- (curve > 0 = right, < 0 = left), so the flight bends into an arc instead of a straight line.
local function addCurve(curve: number)
	local rate = SHOT.CurveTurnRate * curve
	Ball.addForce(SHOT.CurveTime, function(dt, part)
		local v = part.AssemblyLinearVelocity
		local flat = Vector3.new(v.X, 0, v.Z)
		local speed = flat.Magnitude
		if speed < 25 then
			return
		end
		local push = Util.rightOf(flat) * (speed * rate * dt)
		local turned = (flat + push).Unit * speed
		part.AssemblyLinearVelocity = Vector3.new(turned.X, v.Y, turned.Z)
	end)
end

function handlers.Shoot(actor, direction, charge, curve)
	local t = Actors.now()
	setCharging(actor, false)
	if not ready(actor, t) or not actor.hasBall or not Util.isVector(direction) then
		return
	end
	local power01 = math.clamp(tonumber(charge) or 0, 0, 1)
	local spin = math.clamp(tonumber(curve) or 0, -1, 1)
	if spin ~= spin then -- NaN from a bad client
		spin = 0
	end
	local flat = Util.flatUnit(direction, actor.root.CFrame.LookVector)
	if math.abs(spin) > 0.1 then
		-- Start off to the opposite side so the bend brings the ball back across the aim line.
		flat = Util.rotateY(flat, SHOT.CurveStartAngle * spin)
	end
	local elevation = math.clamp(Util.elevationOf(direction), SHOT.MinElevation, SHOT.MaxElevation)
	local power = Util.lerp(SHOT.MinPower, SHOT.MaxPower, power01) * (actor.style.stats.shot or 1)
	Ball.kick(actor, Util.withElevation(flat, elevation) * power, { kind = "Shot" })
	if math.abs(spin) > 0.1 then
		addCurve(spin)
	end
	kickFx(actor, "Shot", power01)
end

function handlers.Pass(actor, direction)
	local t = Actors.now()
	setCharging(actor, false)
	if not ready(actor, t) or not actor.hasBall then
		return
	end
	local dir = flatDir(direction, actor.root.CFrame.LookVector)
	if not dir then
		return
	end
	local target = Actions.findPassTarget(actor, dir, PASS.AssistAngle, PASS.MaxRange)
	local speed = PASS.MinSpeed + 14
	if target then
		local origin = actor.root.Position
		local to = Util.flat(target.root.Position - origin)
		speed = math.clamp(PASS.MinSpeed + to.Magnitude * 0.5, PASS.MinSpeed, PASS.MaxSpeed)
		-- Упреждение: бьём туда, где партнёр будет, когда мяч долетит.
		local lead = Util.flat(target.root.AssemblyLinearVelocity) * (to.Magnitude / speed) * 0.85
		dir = Util.flatUnit(to + lead, dir)
	end
	speed *= actor.style.stats.pass or 1
	Ball.kick(actor, Util.withElevation(dir, PASS.Elevation) * speed, {
		kind = "Pass",
		noPickup = 0.5,
		passTarget = target,
	})
	kickFx(actor, "Pass", 0.3)
end

function handlers.Lob(actor, direction)
	local t = Actors.now()
	setCharging(actor, false)
	if not ready(actor, t) or not actor.hasBall then
		return
	end
	local dir = flatDir(direction, actor.root.CFrame.LookVector)
	if not dir then
		return
	end
	local speed = LOB.DefaultSpeed
	local target = Actions.findPassTarget(actor, dir, PASS.AssistAngle, PASS.MaxRange)
	if target then
		local to = Util.flat(target.root.Position - actor.root.Position)
		local flightGuess = to.Magnitude / (LOB.DefaultSpeed * math.cos(math.rad(LOB.Elevation)))
		local aimAt = to + Util.flat(target.root.AssemblyLinearVelocity) * flightGuess * 0.8
		dir = Util.flatUnit(aimAt, dir)
		-- Скорость, при которой мяч упадёт на нужной дистанции.
		local gravity = Ball.gravity()
		local needed = math.sqrt(aimAt.Magnitude * gravity / math.sin(math.rad(LOB.Elevation * 2)))
		speed = math.clamp(needed, LOB.MinSpeed, LOB.MaxSpeed)
	end
	Ball.kick(actor, Util.withElevation(dir, LOB.Elevation) * speed, {
		kind = "Pass",
		noPickup = 0.6,
		passTarget = target,
	})
	kickFx(actor, "Lob", 0.5)
end

function handlers.Tackle(actor, direction)
	local t = Actors.now()
	if not ready(actor, t) or actor.hasBall or not Actors.cooldownReady(actor, "Tackle", t) then
		return
	end
	local dir = flatDir(direction, actor.root.CFrame.LookVector)
	if not dir or not Actors.spendStamina(actor, TACKLE.Stamina) then
		return
	end
	Actors.setCooldown(actor, "Tackle", TACKLE.Cooldown)
	actor.slide = {
		expires = t + TACKLE.Duration,
		radius = TACKLE.Radius * (actor.style.stats.tackle or 1),
		dir = dir,
		take = false,
		stun = TACKLE.StunTime,
		done = false,
	}
	Net.fx("Slide", { character = actor.character, duration = TACKLE.Duration })
end

function handlers.Dash(actor, direction)
	local t = Actors.now()
	if not ready(actor, t) or not Actors.cooldownReady(actor, "Dash", t) then
		return
	end
	local dir = flatDir(direction, actor.root.CFrame.LookVector)
	if not dir or not Actors.spendStamina(actor, DASH.Stamina) then
		return
	end
	Actors.setCooldown(actor, "Dash", DASH.Cooldown)
	Net.fx("Dash", { character = actor.character, hasBall = actor.hasBall })
end

-- Дриблинг: финт с мячом. На короткое время игрока нельзя обокрасть подкатом.
function handlers.Dribble(actor, direction)
	local t = Actors.now()
	if not ready(actor, t) or not actor.hasBall or not Actors.cooldownReady(actor, "Dribble", t) then
		return
	end
	local dir = flatDir(direction, actor.root.CFrame.LookVector)
	if not dir or not Actors.spendStamina(actor, DRIBBLE.Stamina) then
		return
	end
	setCharging(actor, false)
	Actors.setCooldown(actor, "Dribble", DRIBBLE.Cooldown)
	Actors.setImmune(actor, DRIBBLE.ImmuneTime)
	Net.fx("Dribble", { character = actor.character })
end

---------------------------------------------------------------------------
-- Способности стиля
---------------------------------------------------------------------------

local function makeContext(actor, slot: number, aimLook: Vector3, move: Vector3, t: number)
	local ctx = {
		actor = actor,
		character = actor.character,
		root = actor.root,
		humanoid = actor.humanoid,
		player = actor.player,
		slot = slot,
		aim = Util.flatUnit(aimLook, actor.root.CFrame.LookVector),
		aimLook = aimLook,
		move = move,
		hasBall = actor.hasBall,
		now = t,
		enemyGoal = F.goalCenter(-actor.side),
		ownGoal = F.goalCenter(actor.side),
		Ball = Ball,
		Actors = Actors,
		Config = Config,
		Field = F,
		Util = Util,
	}

	function ctx.fx(stage: string, data: { [string]: any }?)
		local payload = data or {}
		payload.character = actor.character
		payload.style = actor.style.id
		payload.slot = slot
		payload.stage = stage
		Net.fx("Ability", payload)
	end

	function ctx.after(delay: number, fn: () -> ())
		task.delay(delay, function()
			if actor.alive and Match.isLive() then
				local ok, err = pcall(fn)
				if not ok then
					warn("[Ability] " .. tostring(err))
				end
			end
		end)
	end

	function ctx.loop(duration: number, interval: number, fn: (number) -> ())
		task.spawn(function()
			local elapsed = 0
			while elapsed < duration and actor.alive and Match.isLive() do
				local ok, err = pcall(fn, elapsed)
				if not ok then
					warn("[Ability] " .. tostring(err))
					return
				end
				elapsed += task.wait(interval)
			end
		end)
	end

	function ctx.slide(options: { [string]: any })
		actor.slide = {
			expires = Actors.now() + (options.duration or TACKLE.Duration),
			radius = options.radius or TACKLE.Radius,
			dir = Util.flatUnit(options.dir or ctx.aim, ctx.aim),
			take = options.take == true,
			stun = options.stun or TACKLE.StunTime,
			done = false,
		}
	end

	return ctx
end

function handlers.Ability(actor, slotValue, aimValue, moveValue)
	local t = Actors.now()
	local slot = tonumber(slotValue)
	if not slot or not ready(actor, t) then
		return
	end
	local ability = actor.style.abilities[slot]
	if not ability then
		return
	end
	local key = "A" .. slot
	if not Actors.cooldownReady(actor, key, t) then
		return
	end
	if ability.needsBall and not actor.hasBall then
		return
	end
	if ability.needsNoBall and actor.hasBall then
		return
	end
	if ability.ultimate and actor.data.resonance < RES.Max then
		return
	end

	local look = actor.root.CFrame.LookVector
	local aimLook = Util.isVector(aimValue) and Util.unit(aimValue, look) or look
	local move = Vector3.zero
	if Util.isVector(moveValue) and Util.flat(moveValue).Magnitude > 0.1 then
		move = Util.flatUnit(moveValue)
	end

	setCharging(actor, false)
	local ctx = makeContext(actor, slot, aimLook, move, t)
	local ok, result = pcall(ability.server, ctx)
	if not ok then
		warn(string.format("[Ability] %s.%s: %s", actor.style.id, tostring(ability.id), tostring(result)))
		return
	end
	if result == false then
		return
	end
	Actors.setCooldown(actor, key, ability.cooldown or 8)
	if ability.ultimate then
		actor.data.resonance = 0
	end
end

function handlers.SelectStyle(actor, styleId)
	if type(styleId) ~= "string" then
		return
	end
	local style = Styles.byId[styleId]
	if not style or style.selectable == false or style.id == actor.style.id then
		return
	end
	Actors.applyStyle(actor, style.id)
	-- Чтобы сменой стиля нельзя было обнулять перезарядки.
	for slot = 1, 3 do
		Actors.setCooldown(actor, "A" .. slot, 4)
	end
	actor.data.resonance = 0
	if actor.player then
		actor.player:SetAttribute("Style", style.id)
	end
	Net.fx("StyleChanged", { character = actor.character, style = style.id })
end

---------------------------------------------------------------------------
-- Отбор мяча
---------------------------------------------------------------------------

local function steal(actor, holder, slide, t: number)
	if slide.take then
		Ball.attach(actor)
	else
		Ball.knockLoose(slide.dir * TACKLE.KnockSpeed + Vector3.new(0, 14, 0), actor)
		actor.noPickupUntil = t + 0.15
	end
	holder.noPickupUntil = t + 1
	Actors.stun(holder, slide.stun)
	Actors.addResonance(actor, RES.Steal)
	Net.fx("Steal", { character = actor.character, victim = holder.character, position = Ball.position() })
end

-- Каждый кадр: проверяем активные подкаты/тараны.
function Actions.step()
	if not Match.isLive() then
		return
	end
	local t = Actors.now()
	local holder = Ball.holder
	if holder and not holder.alive then
		holder = nil -- владелец только что вышел или погиб: мяч освободит BallService
	end
	for _, actor in pairs(Actors.byCharacter) do
		local slide = actor.slide
		if slide then
			if t >= slide.expires or not actor.alive then
				actor.slide = nil
			elseif not slide.done and holder and holder ~= actor and holder.team ~= actor.team then
				local origin = actor.root.Position
				local toBall = Util.flat(Ball.position() - origin).Magnitude
				local toHolder = Util.flat(holder.root.Position - origin).Magnitude
				if math.min(toBall, toHolder) <= slide.radius then
					slide.done = true
					if Actors.isImmune(holder, t) then
						Actors.addResonance(holder, RES.Dodge)
						Net.fx("Dodge", { character = holder.character, by = actor.character })
					else
						steal(actor, holder, slide, t)
						holder = Ball.holder
					end
				end
			end
		end
	end
end

---------------------------------------------------------------------------

local function allow(player: Player): boolean
	local now = os.clock()
	local budget = budgets[player]
	if not budget then
		budget = { tokens = 40, time = now }
		budgets[player] = budget
	end
	budget.tokens = math.min(40, budget.tokens + (now - budget.time) * 30)
	budget.time = now
	if budget.tokens < 1 then
		return false
	end
	budget.tokens -= 1
	return true
end

function Actions.init()
	Net.Action.OnServerEvent:Connect(function(player: Player, name: any, ...)
		if type(name) ~= "string" or not allow(player) then
			return
		end
		-- Lobby requests come from players who are not on the pitch yet.
		if name == "Play" then
			local problem = PlayerService.requestPlay(player, ...)
			if problem then
				player:SetAttribute("LobbyError", problem .. "#" .. os.clock())
			end
			return
		elseif name == "ToLobby" then
			PlayerService.toLobby(player)
			return
		elseif name == "LobbyStyle" then
			PlayerService.lobbyStyle(player, ...)
			return
		end
		local handler = handlers[name]
		local actor = Actors.ofPlayer(player)
		if handler and actor and actor.alive then
			handler(actor, ...)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		budgets[player] = nil
	end)

	-- Резонанс за удачные действия.
	Ball.Possessed:Connect(function(actor, _previous, shot)
		if shot and shot.kind == "Pass" and shot.kicker ~= actor and shot.team == actor.team then
			Actors.addResonance(actor, RES.PassDone)
			Actors.addResonance(shot.kicker, RES.PassDone)
		end
	end)
	Ball.Blocked:Connect(function(actor, shot)
		if shot and shot.team ~= actor.team then
			Actors.addResonance(actor, RES.Block)
		end
	end)
end

return Actions
