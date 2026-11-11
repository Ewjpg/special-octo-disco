-- ШАБЛОН СТИЛЯ (твой OC).
-- 1. Скопируй этот файл, назови без подчёркивания в начале (например Phoenix.luau).
-- 2. Поменяй id, name, цвета, характеристики и способности.
-- 3. Стиль сам появится в меню выбора. Модули с "_" в начале имени игра не загружает.
-- Готовые примеры стилей лежат в папке archive/styles (сейчас отключены).
--
-- У каждой способности три функции:
--   predict(me, input) — выполняется СРАЗУ на клиенте игрока (рывок, анимация). Необязательна.
--   server(ctx)        — настоящая логика на сервере. Вернёт false — способность не сработала, перезарядки нет.
--   client(fx, data)   — эффекты у всех игроков. data.stage — то, что сервер передал в ctx.fx("stage", {...}).
--
-- Что есть в ctx (сервер):
--   ctx.actor, ctx.root, ctx.character, ctx.player
--   ctx.aim       — куда смотрит камера (по горизонтали), ctx.aimLook — то же с наклоном
--   ctx.move      — куда игрок идёт (или нулевой вектор)
--   ctx.now       — серверное время
--   ctx.enemyGoal / ctx.ownGoal — центры ворот
--   ctx.Ball      — kick(actor, velocity, opts), addForce(time, fn), knockLoose(v, actor), attach(actor),
--                   position(), velocity(), holder, lock(time), setFx(color, time)
--   ctx.Actors    — setImmune, addSpeedMod, setFlag, stun, inRadius, isImmune...
--   ctx.fx(stage, data)      — запустить client(...) у всех
--   ctx.after(sec, fn)       — выполнить позже (если игрок жив и матч идёт)
--   ctx.loop(sec, step, fn)  — повторять fn каждые step секунд
--   ctx.slide{ duration, radius, take, stun, dir } — «окно отбора», как у подката
--
-- Что есть в fx (клиент): sphere, disc, pillar, burst, light, beam, zone, aura, orbit, afterimage,
--   charTrail, ghostBall, shake, flash, sound, anim, every, ground, ball, rootOf, isLocal.
-- Что есть в me (predict): me.dash(dir, speed, time), me.blink(dir, distance), me.anim(name).
-- Имена анимаций — в Shared/Animations.

local COLOR = Color3.fromRGB(255, 255, 255)
local COLOR2 = Color3.fromRGB(200, 200, 200)

return {
	id = "Template",
	order = 50,
	name = "Название",
	role = "Роль",
	tagline = "Коронная фраза.",
	description = "Пара предложений о стиле.",
	color = COLOR,
	color2 = COLOR2,

	-- 1.0 = обычное значение. speed — бег, shot — сила удара, stamina — запас выносливости,
	-- tackle — дальность отбора, trap — насколько быстрый мяч можно принять, dribble — скорость с мячом (по умолчанию 0.94).
	stats = { speed = 1.0, shot = 1.0, stamina = 1.0, tackle = 1.0, trap = 1.0 },

	abilities = {
		{
			id = "ExampleShot",
			name = "Пример удара",
			desc = "Быстрый удар туда, куда смотрит камера.",
			cooldown = 8,
			needsBall = true, -- needsNoBall = true — наоборот, только без мяча

			predict = function(me)
				me.anim("Shoot")
			end,

			server = function(ctx)
				local dir = ctx.Util.withElevation(ctx.aim, 10)
				ctx.Ball.kick(ctx.actor, dir * 170, { kind = "Shot", untrappable = 0.4, color = COLOR, colorTime = 1.5 })
				ctx.fx("shot", { position = ctx.Ball.position() })
			end,

			client = function(fx, data)
				if not fx.isLocal(data.character) then
					fx.anim(data.character, "Shoot")
				end
				fx.sphere(data.position, COLOR, { from = 2, to = 14, time = 0.3 })
				fx.sound("PowerKick", data.position)
			end,
		},
		-- вторая способность...
		-- третья — ульта: добавь ultimate = true, она требует полный Резонанс.
	},
}
