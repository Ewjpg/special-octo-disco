-- «Актёр» — любой персонаж на поле: игрок или бот.
-- Здесь живёт всё его игровое состояние: выносливость, оглушение, бафы скорости, перезарядки.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Signal = require(Shared.Signal)
local Styles = require(Shared.Styles)
local Util = require(Shared.Util)
local Net = require(script.Parent.Net)

local P = Config.Player
local RES = Config.Resonance

local Actors = {}

Actors.byCharacter = {} -- [Model] = actor
Actors.live = false -- идёт ли игра (ставит MatchService)
Actors.Added = Signal.new()
Actors.Removed = Signal.new()

function Actors.now(): number
	return Workspace:GetServerTimeNow()
end

function Actors.get(character: Model?)
	if character then
		return Actors.byCharacter[character]
	end
	return nil
end

function Actors.ofPlayer(player: Player)
	return Actors.get(player.Character)
end

-- info: { team = "Home"|"Away", player?, data?, isBot?, isKeeper?, styleId? }
function Actors.register(character: Model, info)
	local humanoid = character:FindFirstChildOfClass("Humanoid") :: Humanoid?
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or not root then
		return nil
	end

	local data = info.data or { styleId = info.styleId or Styles.default, resonance = 0, cooldowns = {} }
	local style = Styles.get(data.styleId)
	local staminaMax = P.MaxStamina * (style.stats.stamina or 1)

	local actor = {
		character = character,
		humanoid = humanoid,
		root = root,
		player = info.player,
		data = data,
		isBot = info.isBot == true,
		isKeeper = info.isKeeper == true,
		team = info.team,
		side = Config.Teams[info.team].Side,
		style = style,
		alive = true,
		groundOffset = Util.groundOffset(root, humanoid),

		stamina = staminaMax,
		staminaMax = staminaMax,
		lastStaminaUse = 0,
		exhausted = false,

		hasBall = false,
		sprinting = false,
		isSprinting = false,
		charging = false,
		frozen = false,
		stunnedUntil = 0,
		immuneUntil = 0,
		noPickupUntil = 0,

		speedMods = {},
		flags = {},
		slide = nil,
		baseSpeed = nil, -- боты: фиксированная скорость
		trapRadius = nil,
		trapMaxSpeed = nil,

		jumpPower = humanoid.JumpPower,
		jumpHeight = humanoid.JumpHeight,
		jumpLocked = false,
		repStamina = -1,
		repResonance = -1,
	}

	Actors.byCharacter[character] = actor
	character:SetAttribute("Team", info.team)
	character:SetAttribute("Style", style.id)
	character:SetAttribute("HasBall", false)
	character:SetAttribute("Charging", false)
	character:SetAttribute("StunnedUntil", 0)
	if actor.player then
		actor.player:SetAttribute("MaxStamina", math.floor(staminaMax + 0.5))
	end

	Actors.Added:Fire(actor)
	return actor
end

function Actors.unregister(character: Model)
	local actor = Actors.byCharacter[character]
	if not actor then
		return
	end
	actor.alive = false
	Actors.byCharacter[character] = nil
	Actors.Removed:Fire(actor)
end

-- Сменить стиль на лету.
function Actors.applyStyle(actor, styleId: string)
	local style = Styles.get(styleId)
	actor.style = style
	actor.data.styleId = style.id
	actor.staminaMax = P.MaxStamina * (style.stats.stamina or 1)
	actor.stamina = math.min(actor.stamina, actor.staminaMax)
	table.clear(actor.speedMods)
	table.clear(actor.flags)
	if actor.character.Parent then
		actor.character:SetAttribute("Style", style.id)
	end
	if actor.player then
		actor.player:SetAttribute("MaxStamina", math.floor(actor.staminaMax + 0.5))
	end
end

---------------------------------------------------------------------------
-- Состояния
---------------------------------------------------------------------------

function Actors.isStunned(actor, t: number?): boolean
	return (t or Actors.now()) < actor.stunnedUntil
end

-- Нельзя отобрать мяч: рывок, ульта или вратарь с мячом в руках.
function Actors.isImmune(actor, t: number?): boolean
	local now = t or Actors.now()
	if now < actor.immuneUntil then
		return true
	end
	if actor.flags.unstoppableUntil and now < actor.flags.unstoppableUntil then
		return true
	end
	return actor.isKeeper and actor.hasBall
end

function Actors.setImmune(actor, duration: number)
	actor.immuneUntil = math.max(actor.immuneUntil, Actors.now() + duration)
end

function Actors.canAct(actor, t: number?): boolean
	local now = t or Actors.now()
	return actor.alive and not actor.frozen and now >= actor.stunnedUntil
end

function Actors.stun(actor, duration: number): boolean
	local t = Actors.now()
	if actor.flags.unstoppableUntil and t < actor.flags.unstoppableUntil then
		return false
	end
	actor.stunnedUntil = math.max(actor.stunnedUntil, t + duration)
	actor.noPickupUntil = math.max(actor.noPickupUntil, t + duration + 0.25)
	actor.charging = false
	actor.slide = nil
	if actor.character.Parent then
		actor.character:SetAttribute("Charging", false)
		actor.character:SetAttribute("StunnedUntil", actor.stunnedUntil)
	end
	Net.fx("Stun", { character = actor.character, duration = duration })
	return true
end

function Actors.setFrozen(actor, frozen: boolean)
	actor.frozen = frozen
	if frozen then
		actor.charging = false
		actor.slide = nil
		if actor.character.Parent then
			actor.character:SetAttribute("Charging", false)
		end
	end
end

function Actors.addSpeedMod(actor, key: string, mult: number, duration: number)
	actor.speedMods[key] = { mult = mult, expires = Actors.now() + duration }
end

function Actors.removeSpeedMod(actor, key: string)
	actor.speedMods[key] = nil
end

function Actors.setFlag(actor, key: string, duration: number)
	actor.flags[key] = Actors.now() + duration
end

function Actors.hasFlag(actor, key: string, t: number?): boolean
	local expires = actor.flags[key]
	return expires ~= nil and (t or Actors.now()) < expires
end

---------------------------------------------------------------------------
-- Ресурсы
---------------------------------------------------------------------------

function Actors.spendStamina(actor, amount: number): boolean
	if actor.stamina < amount then
		return false
	end
	actor.stamina -= amount
	actor.lastStaminaUse = Actors.now()
	return true
end

function Actors.addResonance(actor, amount: number)
	if not actor then
		return
	end
	local data = actor.data
	data.resonance = math.clamp(data.resonance + amount, 0, RES.Max)
end

function Actors.cooldownReady(actor, key: string, t: number?): boolean
	local ready = actor.data.cooldowns[key]
	return ready == nil or (t or Actors.now()) >= ready
end

function Actors.setCooldown(actor, key: string, seconds: number)
	local ready = Actors.now() + seconds
	actor.data.cooldowns[key] = ready
	if actor.player then
		actor.player:SetAttribute("CD_" .. key, ready)
	end
end

---------------------------------------------------------------------------
-- Перемещение
---------------------------------------------------------------------------

function Actors.teleport(actor, position: Vector3, lookDir: Vector3?)
	local feet = Vector3.new(position.X, position.Y + actor.groundOffset + 0.1, position.Z)
	local dir = Util.flatUnit(lookDir or Vector3.new(-actor.side, 0, 0))
	actor.character:PivotTo(CFrame.lookAt(feet, feet + dir))
	actor.root.AssemblyLinearVelocity = Vector3.zero
end

function Actors.feetPosition(actor): Vector3
	return actor.root.Position - Vector3.new(0, actor.groundOffset, 0)
end

-- Все живые актёры в радиусе. filter(actor) -> boolean (необязательно).
function Actors.inRadius(position: Vector3, radius: number, filter: ((any) -> boolean)?)
	local result = {}
	for _, actor in pairs(Actors.byCharacter) do
		if actor.alive and Util.flat(actor.root.Position - position).Magnitude <= radius then
			if not filter or filter(actor) then
				table.insert(result, actor)
			end
		end
	end
	return result
end

function Actors.teamList(team: string, includeKeepers: boolean?)
	local result = {}
	for _, actor in pairs(Actors.byCharacter) do
		if actor.alive and actor.team == team and (includeKeepers or not actor.isKeeper) then
			table.insert(result, actor)
		end
	end
	return result
end

local function computeSpeed(actor, t: number): number
	if actor.frozen or t < actor.stunnedUntil then
		return 0
	end
	local stats = actor.style.stats
	local speed
	if actor.baseSpeed then
		speed = actor.baseSpeed
	else
		speed = (actor.isSprinting and P.SprintSpeed or P.WalkSpeed) * (stats.speed or 1)
		if actor.hasBall then
			speed *= stats.dribble or P.DribbleMult
		end
		if actor.charging then
			speed *= Config.Shot.ChargeMoveMult
		end
	end
	for key, mod in pairs(actor.speedMods) do
		if t >= mod.expires then
			actor.speedMods[key] = nil
		else
			speed *= mod.mult
		end
	end
	return speed
end

-- Вызывается каждый кадр сервера.
function Actors.step(dt: number)
	local t = Actors.now()
	for character, actor in pairs(Actors.byCharacter) do
		if not character.Parent or actor.humanoid.Health <= 0 then
			actor.alive = false
			continue
		end

		-- Выносливость.
		local moving = Util.flat(actor.root.AssemblyLinearVelocity).Magnitude > 3
		local canMove = not actor.frozen and t >= actor.stunnedUntil
		local sprint = actor.sprinting and moving and canMove and not actor.charging and not actor.exhausted
		if sprint then
			actor.stamina = math.max(0, actor.stamina - P.SprintDrain * dt)
			actor.lastStaminaUse = t
			if actor.stamina <= 0 then
				actor.exhausted = true
			end
		elseif t - actor.lastStaminaUse >= P.StaminaRegenDelay then
			actor.stamina = math.min(actor.staminaMax, actor.stamina + P.StaminaRegen * dt)
			if actor.exhausted and actor.stamina >= P.ExhaustedThreshold then
				actor.exhausted = false
			end
		end
		actor.isSprinting = sprint

		-- Резонанс копится сам, пока идёт игра.
		if Actors.live and not actor.isBot then
			actor.data.resonance = math.min(RES.Max, actor.data.resonance + RES.Passive * dt)
		end

		-- Скорость и прыжок.
		local speed = computeSpeed(actor, t)
		if math.abs(actor.humanoid.WalkSpeed - speed) > 0.05 then
			actor.humanoid.WalkSpeed = speed
		end
		local lockJump = speed <= 0
		if lockJump ~= actor.jumpLocked then
			actor.jumpLocked = lockJump
			actor.humanoid.JumpPower = lockJump and 0 or actor.jumpPower
			actor.humanoid.JumpHeight = lockJump and 0 or actor.jumpHeight
		end

		-- Атрибуты для интерфейса.
		local player = actor.player
		if player then
			local stamina = math.floor(actor.stamina + 0.5)
			if stamina ~= actor.repStamina then
				actor.repStamina = stamina
				player:SetAttribute("Stamina", stamina)
			end
			local resonance = math.floor(actor.data.resonance + 0.5)
			if resonance ~= actor.repResonance then
				actor.repResonance = resonance
				player:SetAttribute("Resonance", resonance)
			end
		end
	end
end

return Actors
