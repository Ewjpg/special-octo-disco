-- КОМЕТА — нападающий. Самый сильный удар, рывок к воротам, ульта «Метеор».

local COLOR = Color3.fromRGB(255, 138, 40)
local COLOR2 = Color3.fromRGB(255, 228, 132)
local UP = Vector3.new(0, 1, 0)

-- Куда падает «Метеор»: в ворота, если игрок смотрит в их сторону, иначе — в точку впереди.
local function meteorTarget(ctx): Vector3
	local F = ctx.Field
	local goal = ctx.enemyGoal
	local toGoal = ctx.Util.flat(goal - ctx.root.Position)
	if toGoal.Magnitude < 170 and ctx.Util.angleBetween(ctx.aim, toGoal) < 60 then
		local lateral = (math.random() * 2 - 1) * F.GoalWidth * 0.32
		local behind = ctx.Util.flatUnit(toGoal) * 3
		return goal + behind + Vector3.new(0, 4, lateral)
	end
	local point = F.clampToArena(ctx.root.Position + ctx.aim * 90, 6)
	return Vector3.new(point.X, F.Origin.Y + 1.5, point.Z)
end

return {
	id = "Comet",
	order = 1,
	name = "Комета",
	role = "Нападающий",
	tagline = "Один удар — один гол.",
	description = "Самый мощный удар в игре. Врывается в штрафную и бьёт так, что мяч нельзя принять.",
	color = COLOR,
	color2 = COLOR2,
	stats = { speed = 1.0, shot = 1.12, stamina = 1.0, tackle = 0.9, trap = 1.0 },

	abilities = {
		{
			id = "CometShot",
			name = "Хвост кометы",
			desc = "Сверхбыстрый прямой удар. Соперник не может принять мяч — только отбить.",
			cooldown = 11,
			needsBall = true,

			predict = function(me)
				me.anim("PowerShot")
			end,

			server = function(ctx)
				local actor = ctx.actor
				ctx.Actors.addSpeedMod(actor, "Windup", 0.35, 0.24)
				ctx.fx("windup")
				ctx.after(0.22, function()
					if not actor.hasBall then
						return
					end
					local elevation = math.clamp(ctx.Util.elevationOf(ctx.aimLook), 3, 20)
					local dir = ctx.Util.withElevation(ctx.aim, elevation)
					local power = 205 * (actor.style.stats.shot or 1)
					ctx.Ball.kick(actor, dir * power, {
						kind = "Shot",
						untrappable = 0.75,
						gravityScale = 0.22,
						color = COLOR,
						colorTime = 1.8,
					})
					ctx.fx("fire", { position = ctx.Ball.position() })
				end)
			end,

			client = function(fx, data)
				if data.stage == "windup" then
					if not fx.isLocal(data.character) then
						fx.anim(data.character, "PowerShot")
					end
					local root = fx.rootOf(data.character)
					if root then
						fx.burst(root.Position - Vector3.new(0, 2.5, 0), COLOR, { count = 16, speed = 12, life = 0.35 })
						fx.sound("Ability", root)
					end
				elseif data.stage == "fire" then
					local position = data.position
					fx.sphere(position, COLOR, { from = 2, to = 17, time = 0.35 })
					fx.disc(position - Vector3.new(0, 1, 0), COLOR2, { from = 3, to = 24, time = 0.4 })
					fx.burst(position, COLOR2, { count = 40, speed = 40, life = 0.5 })
					fx.light(position, COLOR, { range = 32, time = 0.4 })
					fx.shake(position, 0.9, 0.3)
					fx.sound("PowerKick", position)
				end
			end,
		},

		{
			id = "Afterburner",
			name = "Форсаж",
			desc = "Рывок вперёд на огромной скорости. Мяч остаётся в ногах, подкаты не проходят.",
			cooldown = 9,

			predict = function(me, input)
				local dir = input.move.Magnitude > 0.1 and input.move or input.aim
				me.dash(dir, 78, 0.36)
				me.anim("Dash")
			end,

			server = function(ctx)
				ctx.Actors.setImmune(ctx.actor, 0.45)
				ctx.Actors.addSpeedMod(ctx.actor, "Afterburner", 1.22, 2.6)
				ctx.fx("go")
			end,

			client = function(fx, data)
				local character = data.character
				if not fx.isLocal(character) then
					fx.anim(character, "Dash")
				end
				fx.charTrail(character, COLOR, 0.8)
				local root = fx.rootOf(character)
				if root then
					fx.disc(root.Position - Vector3.new(0, 2.8, 0), COLOR, { from = 2, to = 15, time = 0.3 })
					fx.sound("Dash", root)
				end
				for i = 0, 2 do
					task.delay(i * 0.09, function()
						fx.afterimage(character, COLOR, { time = 0.35 })
					end)
				end
			end,
		},

		{
			id = "Meteor",
			name = "Метеор",
			desc = "УЛЬТА. Мяч взмывает в небо и падает на ворота огненным метеором.",
			cooldown = 6,
			ultimate = true,
			needsBall = true,

			predict = function(me)
				me.anim("PowerShot")
			end,

			server = function(ctx)
				local actor, Ball = ctx.actor, ctx.Ball
				ctx.Actors.setImmune(actor, 0.5)
				ctx.Actors.addSpeedMod(actor, "Windup", 0.3, 0.24)
				ctx.fx("windup")
				ctx.after(0.22, function()
					if not actor.hasBall then
						return
					end
					-- Фаза 1: мяч уходит вверх. В это время его никто не может тронуть.
					local launch = (ctx.aim * 0.35 + UP).Unit
					Ball.kick(actor, launch * 100, {
						kind = "Shot",
						untrappable = 2.4,
						gravityScale = 0.6,
						noPickup = 1.6,
						color = COLOR,
						colorTime = 3,
					})
					Ball.lock(0.66)
					ctx.fx("launch", { position = Ball.position() })

					ctx.after(0.6, function()
						local shot = Ball.shot
						if Ball.holder or not shot or shot.kicker ~= actor then
							return
						end
						-- Фаза 2: падение по прямой в цель.
						local from = Ball.position()
						local target = meteorTarget(ctx)
						local dir = ctx.Util.unit(target - from, -UP)
						Ball.kick(actor, dir * 265, {
							kind = "Shot",
							untrappable = 1.2,
							gravityScale = 0,
							noPickup = 0.8,
							color = COLOR2,
							colorTime = 2,
						})
						ctx.fx("fall", { position = from, target = target })
					end)
				end)
			end,

			client = function(fx, data)
				if data.stage == "windup" then
					if not fx.isLocal(data.character) then
						fx.anim(data.character, "PowerShot")
					end
					local root = fx.rootOf(data.character)
					if root then
						fx.sphere(root.Position, COLOR, { from = 14, to = 3, time = 0.22 })
						fx.sound("Ultimate", root)
					end
				elseif data.stage == "launch" then
					fx.pillar(data.position, COLOR, { radius = 3, height = 60, time = 0.6 })
					fx.disc(data.position - Vector3.new(0, 1, 0), COLOR2, { from = 4, to = 30, time = 0.5 })
					fx.burst(data.position, COLOR2, { count = 50, speed = 45, life = 0.6 })
					fx.shake(data.position, 1.2, 0.4)
					fx.sound("PowerKick", data.position)
				elseif data.stage == "fall" then
					local from, target = data.position, data.target
					fx.sphere(from, COLOR2, { from = 3, to = 26, time = 0.4 })
					fx.light(from, COLOR, { range = 50, time = 0.5 })
					fx.sound("Ultimate", from)
					local travel = (target - from).Magnitude / 265
					task.delay(travel, function()
						fx.sphere(target, COLOR, { from = 4, to = 34, time = 0.5 })
						fx.disc(fx.ground(target), COLOR2, { from = 4, to = 46, time = 0.6 })
						fx.burst(target, COLOR, { count = 70, speed = 60, life = 0.7 })
						fx.light(target, COLOR, { range = 60, time = 0.6 })
						fx.shake(target, 1.8, 0.5)
						fx.sound("Block", target)
					end)
				end
			end,
		},
	},
}
