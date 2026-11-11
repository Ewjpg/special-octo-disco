-- БАСТИОН — защитник. Таран с отбором мяча, энергобарьер, ульта «Цитадель».

local Workspace = game:GetService("Workspace")

local COLOR = Color3.fromRGB(64, 232, 150)
local COLOR2 = Color3.fromRGB(210, 255, 232)

return {
	id = "Bastion",
	order = 4,
	name = "Бастион",
	role = "Защитник",
	tagline = "Дальше ты не пройдёшь.",
	description = "Отбирает мяч дальше всех, ставит барьеры и принимает даже те удары, которые принять нельзя.",
	color = COLOR,
	color2 = COLOR2,
	stats = { speed = 0.97, shot = 1.0, stamina = 1.15, tackle = 1.25, trap = 1.3 },

	abilities = {
		{
			id = "Ram",
			name = "Таран",
			desc = "Длинный рывок плечом. Если задел соперника с мячом — мяч сразу твой, а он оглушён.",
			cooldown = 9,
			needsNoBall = true,

			predict = function(me, input)
				local dir = input.move.Magnitude > 0.1 and input.move or input.aim
				me.dash(dir, 72, 0.4)
				me.anim("Ram")
			end,

			server = function(ctx)
				local dir = ctx.move.Magnitude > 0.1 and ctx.move or ctx.aim
				ctx.slide({ duration = 0.46, radius = 6.2, take = true, stun = 1, dir = dir })
				ctx.fx("ram")
			end,

			client = function(fx, data)
				local character = data.character
				if not fx.isLocal(character) then
					fx.anim(character, "Ram")
				end
				fx.charTrail(character, COLOR, 0.6)
				local root = fx.rootOf(character)
				if root then
					fx.disc(fx.ground(root.Position), COLOR, { from = 2, to = 14, time = 0.3 })
					fx.sound("Dash", root)
				end
			end,
		},

		{
			id = "Barrier",
			name = "Барьер",
			desc = "Ставит перед собой энергостену на 3.5 секунды. Игроки проходят сквозь неё, мяч — нет.",
			cooldown = 13,

			predict = function(me)
				me.anim("Cast")
			end,

			server = function(ctx)
				local F = ctx.Field
				local width, height, thickness, duration = 22, 11, 2.5, 3.5
				local flat = F.clampToArena(ctx.root.Position + ctx.aim * 9, 3)
				local center = Vector3.new(flat.X, F.Origin.Y + height / 2, flat.Z)
				local cframe = CFrame.lookAt(center, center + ctx.aim)

				local wall = Instance.new("Part")
				wall.Name = "Barrier"
				wall.Anchored = true
				wall.Size = Vector3.new(width, height, thickness)
				wall.CFrame = cframe
				wall.Material = Enum.Material.ForceField
				wall.Color = COLOR
				wall.CollisionGroup = "BallOnly"
				wall.CanQuery = false
				wall.CastShadow = false

				-- Светящаяся рамка, чтобы стену было хорошо видно.
				local edges = {
					{ Vector3.new(width, 0.4, 0.4), CFrame.new(0, height / 2, 0) },
					{ Vector3.new(width, 0.4, 0.4), CFrame.new(0, -height / 2 + 0.2, 0) },
					{ Vector3.new(0.4, height, 0.4), CFrame.new(width / 2, 0, 0) },
					{ Vector3.new(0.4, height, 0.4), CFrame.new(-width / 2, 0, 0) },
				}
				for _, edge in ipairs(edges) do
					local bar = Instance.new("Part")
					bar.Name = "Edge"
					bar.Anchored = true
					bar.CanCollide = false
					bar.CanQuery = false
					bar.CanTouch = false
					bar.CastShadow = false
					bar.Material = Enum.Material.Neon
					bar.Color = COLOR
					bar.Size = edge[1]
					bar.CFrame = cframe * edge[2]
					bar.Parent = wall
				end

				wall.Parent = Workspace
				task.delay(duration, function()
					wall:Destroy()
				end)
				ctx.fx("barrier", { position = center })
			end,

			client = function(fx, data)
				if not fx.isLocal(data.character) then
					fx.anim(data.character, "Cast")
				end
				fx.sphere(data.position, COLOR, { from = 3, to = 20, time = 0.35 })
				fx.burst(data.position, COLOR2, { count = 30, speed = 26, life = 0.5 })
				fx.sound("Ability", data.position)
			end,
		},

		{
			id = "Citadel",
			name = "Цитадель",
			desc = "УЛЬТА. 9 секунд ты принимаешь любой мяч в большом радиусе, и тебя нельзя ни оглушить, ни обокрасть.",
			cooldown = 6,
			ultimate = true,

			predict = function(me)
				me.anim("PowerStance")
			end,

			server = function(ctx)
				local actor, Actors = ctx.actor, ctx.Actors
				local duration, radius = 9, 9.5
				Actors.setFlag(actor, "autoTrapUntil", duration)
				Actors.setFlag(actor, "unstoppableUntil", duration)
				Actors.setFlag(actor, "reachUntil", duration)
				actor.flags.reach = radius
				Actors.addSpeedMod(actor, "Citadel", 1.1, duration)
				ctx.fx("start", { duration = duration, radius = radius })
			end,

			client = function(fx, data)
				local character = data.character
				if not fx.isLocal(character) then
					fx.anim(character, "PowerStance")
				end
				local root = fx.rootOf(character)
				if root then
					fx.sphere(root.Position, COLOR, { from = 2, to = 30, time = 0.5 })
					fx.disc(fx.ground(root.Position), COLOR2, { from = 3, to = 34, time = 0.6 })
					fx.sound("Ultimate", root)
				end
				fx.aura(character, COLOR, { radius = data.radius, time = data.duration })
			end,
		},
	},
}
