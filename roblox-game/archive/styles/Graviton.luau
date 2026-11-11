-- ГРАВИТОН — контроль поля. Притягивает мяч, бьёт самонаводящимся ударом, ульта «Сингулярность».

local COLOR = Color3.fromRGB(72, 212, 255)
local COLOR2 = Color3.fromRGB(40, 70, 190)

-- Цель удара «Орбита»: точка в воротах, куда смотрит игрок, либо точка впереди.
local function orbitTarget(ctx): Vector3
	local F = ctx.Field
	local goal = ctx.enemyGoal
	local origin = ctx.root.Position
	local toGoal = ctx.Util.flat(goal - origin)
	local aim = ctx.aim
	if toGoal.Magnitude < 130 and ctx.Util.angleBetween(aim, toGoal) < 70 and math.abs(aim.X) > 0.05 then
		local travel = (goal.X - origin.X) / aim.X
		local z = origin.Z + aim.Z * travel
		local limit = F.GoalWidth / 2 - 3.5
		z = math.clamp(z, goal.Z - limit, goal.Z + limit)
		return Vector3.new(goal.X, F.Origin.Y + 4.5, z) + ctx.Util.flatUnit(toGoal) * 3
	end
	local point = F.clampToArena(origin + aim * 90, 6)
	return Vector3.new(point.X, F.Origin.Y + 3, point.Z)
end

return {
	id = "Graviton",
	order = 3,
	name = "Гравитон",
	role = "Плеймейкер",
	tagline = "Мяч сам знает, к кому лететь.",
	description = "Управляет мячом на расстоянии: притягивает его к себе и доводит удар до цели.",
	color = COLOR,
	color2 = COLOR2,
	stats = { speed = 1.0, shot = 1.0, stamina = 1.1, tackle = 1.0, trap = 1.25 },

	abilities = {
		{
			id = "Pull",
			name = "Притяжение",
			desc = "Свободный мяч в радиусе 70 летит к тебе. Вблизи вырывает мяч у соперника.",
			cooldown = 10,
			needsNoBall = true,

			predict = function(me)
				me.anim("Cast")
			end,

			server = function(ctx)
				local actor, Ball = ctx.actor, ctx.Ball
				local ballPos = Ball.position()
				local distance = (ballPos - ctx.root.Position).Magnitude
				local holder = Ball.holder

				if holder then
					if holder.team == actor.team or distance > 18 or ctx.Actors.isImmune(holder) then
						return false -- не сработало: перезарядка не тратится
					end
					local dir = ctx.Util.flatUnit(ctx.root.Position - ballPos)
					Ball.knockLoose(dir * 26 + Vector3.new(0, 16, 0), actor)
					holder.noPickupUntil = ctx.now + 0.9
				elseif distance > 70 then
					return false
				end

				local duration = 1
				Ball.addForce(duration, function(dt, part)
					if not actor.alive then
						return
					end
					local chest = actor.root.Position - Vector3.new(0, actor.groundOffset - 1.5, 0)
					local to = chest - part.Position
					local desired = ctx.Util.unit(to) * math.clamp(to.Magnitude * 3, 30, 95)
					part.AssemblyLinearVelocity = part.AssemblyLinearVelocity:Lerp(desired, math.min(1, dt * 7))
				end)
				Ball.setFx(COLOR, duration + 0.3)
				ctx.fx("pull", { duration = duration })
				return true
			end,

			client = function(fx, data)
				local character = data.character
				if not fx.isLocal(character) then
					fx.anim(character, "Cast")
				end
				local root = fx.rootOf(character)
				local ball = fx.ball()
				if root and ball then
					fx.beam(root, ball, COLOR, { width = 1.1, time = data.duration })
					fx.sphere(ball.Position, COLOR, { from = 14, to = 2, time = 0.35 })
					fx.sound("Ability", root)
				end
			end,
		},

		{
			id = "Orbit",
			name = "Орбита",
			desc = "Удар, который сам доворачивает к цели: в угол ворот или в точку, куда ты смотришь.",
			cooldown = 11,
			needsBall = true,

			predict = function(me)
				me.anim("Shoot")
			end,

			server = function(ctx)
				local actor, Ball, Util = ctx.actor, ctx.Ball, ctx.Util
				local target = orbitTarget(ctx)
				local speed = 132 * (actor.style.stats.shot or 1)
				local duration = 1.15
				Ball.kick(actor, Util.withElevation(ctx.aim, 12) * speed, {
					kind = "Shot",
					untrappable = 0.3,
					gravityScale = 0.3,
					color = COLOR,
					colorTime = 1.7,
				})
				Ball.addForce(duration, function(dt, part)
					local velocity = part.AssemblyLinearVelocity
					local current = velocity.Magnitude
					if current < 20 then
						return
					end
					local want = Util.unit(target - part.Position)
					local dir = Util.unit(velocity.Unit:Lerp(want, math.min(1, dt * 3.2)))
					part.AssemblyLinearVelocity = dir * current
				end)
				ctx.fx("shot", { position = Ball.position(), duration = duration })
			end,

			client = function(fx, data)
				if not fx.isLocal(data.character) then
					fx.anim(data.character, "Shoot")
				end
				fx.sphere(data.position, COLOR, { from = 2, to = 13, time = 0.3 })
				fx.sound("Kick", data.position)
				local ball = fx.ball()
				if ball then
					fx.orbit(ball, COLOR, { count = 3, radius = 3.2, time = data.duration })
				end
			end,
		},

		{
			id = "Singularity",
			name = "Сингулярность",
			desc = "УЛЬТА. Гравитационная воронка: соперники в ней вдвое медленнее, а мяч летит к тебе.",
			cooldown = 6,
			ultimate = true,

			predict = function(me)
				me.anim("PowerStance")
			end,

			server = function(ctx)
				local actor, Ball, Actors, F = ctx.actor, ctx.Ball, ctx.Actors, ctx.Field
				local radius, duration = 34, 4.5
				local flat = F.clampToArena(ctx.root.Position + ctx.aim * 16, 6)
				local center = Vector3.new(flat.X, F.Origin.Y + 5, flat.Z)

				-- Соперник с мячом рядом с центром сразу теряет мяч.
				local holder = Ball.holder
				if holder and holder.team ~= actor.team and not Actors.isImmune(holder) then
					if ctx.Util.flat(holder.root.Position - center).Magnitude < 16 then
						Ball.knockLoose(Vector3.new(0, 22, 0), actor)
						holder.noPickupUntil = ctx.now + 1.2
					end
				end

				ctx.fx("open", { position = center, radius = radius, duration = duration })
				ctx.loop(duration, 0.05, function()
					for _, other in ipairs(Actors.inRadius(center, radius)) do
						if other.team ~= actor.team then
							Actors.addSpeedMod(other, "Singularity", 0.5, 0.3)
						end
					end
					if not Ball.holder and Ball.active then
						local part = Ball.part
						local ballPos = part.Position
						if ctx.Util.flat(ballPos - center).Magnitude < radius then
							local to = actor.root.Position - ballPos
							local desired = ctx.Util.unit(to) * math.clamp(to.Magnitude * 2.5, 20, 70)
							part.AssemblyLinearVelocity = part.AssemblyLinearVelocity:Lerp(desired, 0.2)
						end
					end
				end)
			end,

			client = function(fx, data)
				local character = data.character
				if not fx.isLocal(character) then
					fx.anim(character, "PowerStance")
				end
				local position, radius, duration = data.position, data.radius, data.duration
				fx.sound("Ultimate", position)
				fx.shake(position, 1.2, 0.5)
				fx.zone(position, COLOR, { radius = radius, time = duration, core = COLOR2 })
				fx.every(duration, 0.3, function()
					fx.sphere(position, COLOR, { from = radius * 1.6, to = 4, time = 0.45, transparency = 0.6 })
				end)
			end,
		},
	},
}
