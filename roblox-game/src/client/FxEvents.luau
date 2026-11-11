-- Принимает события Fx от сервера и превращает их в анимации, эффекты и звуки.
-- Другие модули (HUD) могут подписаться через FxEvents.on(name, fn).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local FieldSpec = require(Shared.FieldSpec)
local Styles = require(Shared.Styles)
local Fx = require(script.Parent.Fx)
local ProcAnimator = require(script.Parent.ProcAnimator)
local State = require(script.Parent.State)

local FxEvents = {}

local listeners = {} -- [name] = { fn, ... }
local WHITE = Color3.fromRGB(245, 247, 255)

function FxEvents.on(name: string, fn: ({ [string]: any }) -> ())
	local list = listeners[name]
	if not list then
		list = {}
		listeners[name] = list
	end
	table.insert(list, fn)
end

local function styleColor(character: Model?): Color3
	if character then
		return Styles.get(character:GetAttribute("Style")).color
	end
	return WHITE
end

local function teamColor(teamKey: string?): Color3
	local team = teamKey and Config.Teams[teamKey]
	return team and team.Color or WHITE
end

---------------------------------------------------------------------------
-- Удары и борьба
---------------------------------------------------------------------------

-- Свою анимацию локальный игрок запускает сам в момент нажатия (Controls), поэтому здесь её пропускаем.

FxEvents.on("Charge", function(data)
	local character = data.character
	if not character or Fx.isLocal(character) then
		return
	end
	if data.on then
		ProcAnimator.play(character, "ChargeHold")
	else
		ProcAnimator.stop(character, "ChargeHold")
	end
end)

FxEvents.on("Kick", function(data)
	local character = data.character
	local position = data.position
	local power = data.power or 0
	if character and not Fx.isLocal(character) then
		ProcAnimator.stop(character, "ChargeHold")
		local name = data.kind == "Pass" and "Pass" or (data.kind == "Lob" and "Lob" or "Shoot")
		ProcAnimator.play(character, name)
	end
	if typeof(position) ~= "Vector3" then
		return
	end
	if data.kind == "Shot" then
		Fx.sound(power > 0.75 and "PowerKick" or "Kick", position, { pitch = 0.9 + power * 0.25 })
		Fx.disc(Fx.ground(position), WHITE, { from = 1.5, to = 5 + power * 9, time = 0.25 })
		if power > 0.75 then
			Fx.sphere(position, styleColor(character), { from = 1.5, to = 9, time = 0.25 })
			Fx.shake(position, 0.4, 0.2)
		end
	else
		Fx.sound("Pass", position)
		Fx.disc(Fx.ground(position), WHITE, { from = 1, to = 4, time = 0.2 })
	end
end)

FxEvents.on("Slide", function(data)
	local character = data.character
	local root = Fx.rootOf(character)
	if not root then
		return
	end
	if not Fx.isLocal(character) then
		ProcAnimator.play(character, "Slide")
	end
	Fx.sound("Slide", root)
	Fx.burst(Fx.ground(root.Position), Color3.fromRGB(190, 220, 170), { count = 14, speed = 14, life = 0.4, size = 0.9 })
end)

FxEvents.on("Dash", function(data)
	local character = data.character
	local root = Fx.rootOf(character)
	if not root then
		return
	end
	if not Fx.isLocal(character) then
		ProcAnimator.play(character, "Dash")
	end
	Fx.sound("Dash", root)
	Fx.burst(Fx.ground(root.Position), Color3.fromRGB(200, 226, 190), { count = 12, speed = 16, life = 0.35, size = 0.9 })
	Fx.charTrail(character, styleColor(character), 0.3)
end)

FxEvents.on("Dribble", function(data)
	local character = data.character
	local root = Fx.rootOf(character)
	if not root then
		return
	end
	if not Fx.isLocal(character) then
		ProcAnimator.play(character, "Dribble")
	end
	-- Послеобраз показывает, что в этот момент игрока не отобрать.
	local color = styleColor(character)
	Fx.sound("Dash", root, { pitch = 1.3, volume = 0.8 })
	Fx.afterimage(character, color, { time = 0.35 })
	task.delay(0.1, function()
		Fx.afterimage(character, color, { time = 0.35 })
	end)
end)

FxEvents.on("Stun", function(data)
	local character = data.character
	local root = Fx.rootOf(character)
	if not root then
		return
	end
	ProcAnimator.stop(character, "ChargeHold")
	ProcAnimator.play(character, "Stun")
	Fx.burst(root.Position + Vector3.new(0, 2, 0), Color3.fromRGB(255, 232, 120), { count = 12, speed = 12, life = 0.5 })
end)

FxEvents.on("Steal", function(data)
	if typeof(data.position) ~= "Vector3" then
		return
	end
	Fx.sound("Steal", data.position)
	Fx.sphere(data.position, styleColor(data.character), { from = 1.5, to = 9, time = 0.3 })
	Fx.burst(data.position, WHITE, { count = 26, speed = 30, life = 0.45 })
	Fx.shake(data.position, 0.6, 0.25)
end)

FxEvents.on("Dodge", function(data)
	local character = data.character
	local root = Fx.rootOf(character)
	if not root then
		return
	end
	Fx.afterimage(character, styleColor(character), { time = 0.45 })
	Fx.sound("Dash", root, { pitch = 1.4 })
end)

FxEvents.on("Block", function(data)
	if typeof(data.position) ~= "Vector3" then
		return
	end
	local strength = math.clamp((data.speed or 100) / 200, 0.3, 1.2)
	Fx.sound("Block", data.position)
	Fx.sphere(data.position, WHITE, { from = 1.5, to = 6 + strength * 8, time = 0.3 })
	Fx.burst(data.position, WHITE, { count = 20, speed = 26, life = 0.4 })
	Fx.shake(data.position, strength, 0.25)
end)

FxEvents.on("Save", function(data)
	if typeof(data.position) ~= "Vector3" then
		return
	end
	Fx.sound("Block", data.position, { pitch = 1.2 })
	Fx.sphere(data.position, styleColor(data.character), { from = 2, to = 10, time = 0.35 })
end)

FxEvents.on("KeeperDive", function(data)
	ProcAnimator.play(data.character, data.right and "DiveRight" or "DiveLeft")
end)

FxEvents.on("StyleChanged", function(data)
	local root = Fx.rootOf(data.character)
	if root then
		local style = Styles.get(data.style)
		Fx.sphere(root.Position, style.color, { from = 2, to = 12, time = 0.4 })
		Fx.burst(root.Position, style.color2 or style.color, { count = 30, speed = 22, life = 0.5 })
	end
end)

---------------------------------------------------------------------------
-- Матч
---------------------------------------------------------------------------

FxEvents.on("Countdown", function()
	Fx.sound("Tick", nil)
end)

FxEvents.on("Whistle", function()
	Fx.sound("Whistle", nil)
end)

FxEvents.on("FullTime", function()
	Fx.sound("Whistle", nil, { pitch = 0.8 })
	task.delay(0.35, function()
		Fx.sound("Whistle", nil, { pitch = 0.8 })
	end)
end)

FxEvents.on("Goal", function(data)
	local color = teamColor(data.team)
	Fx.sound("Goal", nil)
	Fx.flash(color, 0.3, 0.6)

	-- Салют за воротами, в которые забили.
	local side = data.side or 1
	local goal = FieldSpec.goalCenter(side)
	Fx.shake(goal, 1.4, 0.6)
	for i = 0, 5 do
		task.delay(i * 0.22, function()
			local z = (math.random() * 2 - 1) * FieldSpec.GoalWidth * 0.7
			local point = goal + Vector3.new(side * 6, 10 + math.random() * 14, z)
			Fx.burst(point, i % 2 == 0 and color or WHITE, { count = 46, speed = 46, life = 0.9, size = 1.5 })
			Fx.sphere(point, color, { from = 2, to = 16, time = 0.5 })
			Fx.light(point, color, { range = 40, time = 0.5 })
		end)
	end
	Fx.pillar(goal + Vector3.new(side * 4, 0, 0), color, { radius = 4, height = 70, time = 0.9 })

	local scorer = data.character
	if scorer and scorer.Parent then
		ProcAnimator.play(scorer, "Celebrate")
		local root = Fx.rootOf(scorer)
		if root then
			Fx.disc(Fx.ground(root.Position), color, { from = 2, to = 18, time = 0.6 })
		end
	end
end)

---------------------------------------------------------------------------
-- Способности стилей
---------------------------------------------------------------------------

FxEvents.on("Ability", function(data)
	local style = Styles.byId[data.style]
	local ability = style and style.abilities[data.slot]
	if not ability or not ability.client then
		return
	end
	local ok, err = pcall(ability.client, Fx, data)
	if not ok then
		warn(string.format("[Fx] %s.%s: %s", tostring(data.style), tostring(ability.id), tostring(err)))
	end
end)

function FxEvents.start()
	State.fx.OnClientEvent:Connect(function(name: string, data: any)
		local list = listeners[name]
		if not list then
			return
		end
		local payload = type(data) == "table" and data or {}
		for _, fn in ipairs(list) do
			local ok, err = pcall(fn, payload)
			if not ok then
				warn(string.format("[Fx] %s: %s", tostring(name), tostring(err)))
			end
		end
	end)
end

return FxEvents
