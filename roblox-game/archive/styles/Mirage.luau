-- МИРАЖ — дриблёр. Телепорт сквозь защиту, кручёный удар с ложными мячами, ульта «Зал зеркал».

local COLOR = Color3.fromRGB(186, 96, 255)
local COLOR2 = Color3.fromRGB(255, 150, 236)

return {
	id = "Mirage",
	order = 2,
	name = "Мираж",
	role = "Дриблёр",
	tagline = "Ты целишься туда, где меня уже нет.",
	description = "Проходит сквозь защиту и путает соперника ложными образами. Мяч в ногах почти не замедляет.",
	color = COLOR,
	color2 = COLOR2,
	stats = { speed = 1.04, shot = 0.95, stamina = 1.0, tackle = 0.95, trap = 1.0, dribble = 1.0 },

	abilities = {
		{
			id = "PhantomStep",
			name = "Фантомный шаг",
			desc = "Мгновенный перенос на 20 шагов по направлению движения. Мяч уходит вместе с тобой.",
			cooldown = 8,

			predict = function(me, input)
				local dir = input.move.Magnitude > 0.1 and input.move or input.aim
				me.blink(dir, 20)
			end,

			server = function(ctx)
				ctx.Actors.setImmune(ctx.actor, 0.55)
				ctx.fx("blink", { from = ctx.root.Position })
			end,

			client = function(fx, data)
				local character = data.character
				local root = fx.rootOf(character)
				if not root then
					return
				end
				-- Образ остаётся там, откуда игрок исчез.
				fx.afterimage(character, COLOR, { time = 0.6, offset = data.from - root.Position })
				fx.sphere(data.from, COLOR, { from = 7, to = 1, time = 0.25 })
				fx.sphere(root.Position, COLOR2, { from = 1, to = 9, time = 0.3 })
				fx.burst(root.Position, COLOR2, { count = 24, speed = 22, life = 0.4 })
				fx.sound("Dash", root)
			end,
		},

		{
			id = "MirrorCurve",
			name = "Кривое зеркало",
			desc = "Кручёный удар: мяч уходит в сторону и возвращается по дуге. Вместе с ним летят два ложных мяча.",
			cooldown = 10,
			needsBall = true,

			predict = function(me)
				me.anim("Shoot")
			end,

			server = function(ctx)
				local actor, Util = ctx.actor, ctx.Util
				-- Сторона закрутки: куда игрок смещается (A/D), по умолчанию вправо.
				local right = Util.rightOf(ctx.aim)
				local side = 1
				if ctx.move.Magnitude > 0.1 and math.abs(ctx.move:Dot(right)) > 0.3 then
					side = ctx.move:Dot(right) > 0 and 1 or -1
				end
				local speed = 150 * (actor.style.stats.shot or 1)
				local start = Util.rotateY(ctx.aim, 20 * side) -- сначала мяч уходит в противоположную сторону
				local velocity = Util.withElevation(start, 9) * speed
				local accel = right * (side * 190)

				ctx.Ball.kick(actor, velocity, {
					kind = "Shot",
					untrappable = 0.3,
					gravityScale = 0.4,
					color = COLOR,
					colorTime = 1.4,
				})
				ctx.Ball.addForce(0.55, function(dt, part)
					part.AssemblyLinearVelocity += accel * dt
				end)
				ctx.fx("shot", { position = ctx.Ball.position(), velocity = velocity, accel = accel })
			end,

			client = function(fx, data)
				if not fx.isLocal(data.character) then
					fx.anim(data.character, "Shoot")
				end
				local position, velocity, accel = data.position, data.velocity, data.accel
				fx.sphere(position, COLOR, { from = 2, to = 12, time = 0.3 })
				fx.sound("Kick", position)
				-- Ложные мячи: зеркальная дуга и прямая.
				local mirrored = Vector3.new(velocity.X, velocity.Y, velocity.Z) - accel.Unit * (2 * velocity:Dot(accel.Unit))
				fx.ghostBall(position, mirrored, COLOR2, { time = 0.6, accel = -accel })
				fx.ghostBall(position, (velocity + mirrored) / 2, COLOR2, { time = 0.5 })
			end,
		},

		{
			id = "HallOfMirrors",
			name = "Зал зеркал",
			desc = "УЛЬТА. 8 секунд ты быстрее, а подкаты и оглушения на тебя не действуют.",
			cooldown = 6,
			ultimate = true,

			predict = function(me)
				me.anim("PowerStance")
			end,

			server = function(ctx)
				local duration = 8
				ctx.Actors.setFlag(ctx.actor, "unstoppableUntil", duration)
				ctx.Actors.addSpeedMod(ctx.actor, "Mirrors", 1.2, duration)
				ctx.fx("start", { duration = duration })
			end,

			client = function(fx, data)
				local character = data.character
				if not fx.isLocal(character) then
					fx.anim(character, "PowerStance")
				end
				local root = fx.rootOf(character)
				if root then
					fx.sphere(root.Position, COLOR, { from = 2, to = 26, time = 0.5 })
					fx.burst(root.Position, COLOR2, { count = 50, speed = 34, life = 0.6 })
					fx.sound("Ultimate", root)
				end
				if fx.isLocal(character) then
					fx.flash(COLOR, 0.35, 0.5)
				end
				fx.charTrail(character, COLOR2, data.duration)
				fx.every(data.duration, 0.14, function()
					fx.afterimage(character, COLOR, { time = 0.4, transparency = 0.6 })
				end)
			end,
		},
	},
}
