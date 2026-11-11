-- Дымовой тест: запускает сервер и клиент игры в эмуляторе и проигрывает типичные ситуации.
-- Запуск из папки roblox-game:  lune run tools/harness/smoke.luau [-v]

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local Emu = require("./emu")

local Vector3, CFrame, Enum = roblox.Vector3, roblox.CFrame, roblox.Enum

Emu.verbose = table.find(process.args, "-v") ~= nil
local dumpDir = nil
for i, arg in ipairs(process.args) do
	if arg == "--dump" then
		dumpDir = process.args[i + 1]
	end
end

local results = {}
local function check(name: string, ok: any, detail: any?)
	table.insert(results, { name = name, ok = ok and true or false, detail = detail })
	print(string.format("%s %s%s", ok and "  ok  " or " FAIL ", name, detail ~= nil and ("  — " .. tostring(detail)) or ""))
end

local function section(title: string)
	print("\n== " .. title)
end

---------------------------------------------------------------------------
-- Запуск
---------------------------------------------------------------------------

local game = Emu.load("build/Resonance.rbxlx")
local workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Server = game:GetService("ServerScriptService").Server
local Shared = ReplicatedStorage.Shared

-- Длинный матч, чтобы финальный свисток не прервал сценарии.
local Config = Emu.server.require(Shared.Config)
Config.Match.Duration = 900

section("Запуск сервера")
Emu.startServer()
Emu.run(1)

local Actors = Emu.server.require(Server.Actors)
local Ball = Emu.server.require(Server.BallService)
local Match = Emu.server.require(Server.MatchService)
local Styles = Emu.server.require(Shared.Styles)
local F = Emu.server.require(Shared.FieldSpec)

local stadium = workspace:FindFirstChild("Stadium")
check("стадион построен", stadium ~= nil)
local partCount = 0
if stadium then
	for _, d in ipairs(stadium:GetDescendants()) do
		if d:IsA("BasePart") then
			partCount += 1
		end
	end
end
check("деталей стадиона > 800", partCount > 800, partCount)
check("мяч создан", workspace:FindFirstChild("Ball") ~= nil)
check("RemoteEvents созданы", ReplicatedStorage:FindFirstChild("Remotes") ~= nil)
local matchState = ReplicatedStorage:FindFirstChild("MatchState")
check("MatchState создан", matchState ~= nil)
check("фаза Waiting без игроков", matchState and matchState:GetAttribute("Phase") == "Waiting", matchState and matchState:GetAttribute("Phase"))
check("стилей в меню: 4", #Styles.list == 4, #Styles.list)

Emu.adoptCharacters()
local function keeperCount(): number
	local n = 0
	for _, actor in pairs(Actors.byCharacter) do
		if actor.isKeeper then
			n += 1
		end
	end
	return n
end
check("два бота-вратаря", keeperCount() == 2, keeperCount())

local function phase(): string
	return matchState:GetAttribute("Phase")
end

local function ballPart()
	return workspace:FindFirstChild("Ball")
end

local function ballPos()
	return ballPart().CFrame.Position
end

local function rootOf(player)
	return player.Character and player.Character:FindFirstChild("HumanoidRootPart")
end

local function hasBall(player): boolean
	return player.Character ~= nil and player.Character:GetAttribute("HasBall") == true
end

local function walkTo(player, target)
	local controller = Emu.controller(player.Character)
	controller.moveTarget = target
end

local function stop(player)
	local controller = Emu.controller(player.Character)
	controller.moveTarget = nil
	controller.moveDir = Vector3.zero
end

local function place(player, position, lookAt)
	local feet = Vector3.new(position.X, Emu.HIP_HEIGHT + 1, position.Z)
	local target = Vector3.new(lookAt.X, feet.Y, lookAt.Z)
	player.Character:PivotTo(CFrame.lookAt(feet, target))
	stop(player)
end

local function aimCamera(from, to)
	workspace.CurrentCamera.CFrame = CFrame.lookAt(from, to)
end

local function waitLive(timeout: number?): boolean
	return Emu.runUntil(timeout or 30, function()
		return phase() == "Playing"
	end)
end

local function setKeepersFrozen(frozen: boolean)
	for _, actor in pairs(Actors.byCharacter) do
		if actor.isKeeper then
			actor.frozen = frozen
		end
	end
end

---------------------------------------------------------------------------
section("Игрок входит, запускается клиент")
---------------------------------------------------------------------------

local alice = Emu.addPlayer("Alice", 101)
Emu.startClient(alice)
Emu.run(1)

local Client = alice:FindFirstChildOfClass("PlayerScripts").Client
local ClientState = Emu.client.require(Client.State)
local ClientControls = Emu.client.require(Client.Controls)

check("игрок в команде", alice.Team ~= nil, alice.Team and alice.Team.Name)
check("стиль по умолчанию — Comet", alice:GetAttribute("Style") == "Comet", alice:GetAttribute("Style"))
check("персонаж зарегистрирован как актёр", Actors.ofPlayer(alice) ~= nil)
check("метка команды на персонаже", alice.Character:FindFirstChild("TeamRing") ~= nil)
local hud = alice.PlayerGui:FindFirstChild("ResonanceHud")
check("HUD создан", hud ~= nil)
check("клавиши привязаны", Emu.bound.RS_Shoot ~= nil and Emu.bound.RS_Ability3 ~= nil and Emu.bound.RS_StyleMenu ~= nil)

Emu.run(2)
check("меню стилей открылось при входе", ClientControls.menuOpen == true)
-- Закрываем меню кнопкой M.
Emu.input("RS_StyleMenu", Enum.UserInputState.Begin)
Emu.run(0.1)
check("меню стилей закрывается", ClientControls.menuOpen == false)

---------------------------------------------------------------------------
section("Розыгрыш и владение мячом")
---------------------------------------------------------------------------

check("игра началась", waitLive(12), phase())
check("мяч не закреплён после свистка", ballPart().Anchored == false)

walkTo(alice, ballPos())
local got = Emu.runUntil(8, function()
	if not hasBall(alice) and ballPart():FindFirstChild("BallJoint") == nil then
		walkTo(alice, ballPos())
	end
	return hasBall(alice)
end)
check("игрок подобрал мяч", got)
check("мяч приварен к игроку", ballPart():FindFirstChild("BallJoint") ~= nil)
check("клиент видит мяч у себя", ClientState.hasBall() == true)

-- Ведение со спринтом в сторону чужих ворот (Home атакует +X).
local actorAlice = Actors.ofPlayer(alice)
local attackX = -actorAlice.side
local startX = rootOf(alice).CFrame.Position.X
Emu.input("RS_Sprint", Enum.UserInputState.Begin)
walkTo(alice, Vector3.new(attackX * 60, 0, 20))
Emu.run(2)
local movedX = (rootOf(alice).CFrame.Position.X - startX) * attackX
check("игрок бежит с мячом", movedX > 25 and hasBall(alice), string.format("прошёл %.1f", movedX))
check("спринт тратит силы", (alice:GetAttribute("Stamina") or 100) < 95, alice:GetAttribute("Stamina"))
check("мяч едет перед игроком", (ballPos() - rootOf(alice).CFrame.Position).Magnitude < 5)
Emu.input("RS_Sprint", Enum.UserInputState.End)
stop(alice)
Emu.run(0.3)

---------------------------------------------------------------------------
section("Удар с зарядом")
---------------------------------------------------------------------------

local goalCenter = F.goalCenter(-actorAlice.side)
local function aimAt(point)
	local origin = rootOf(alice).CFrame.Position
	local back = (Vector3.new(origin.X, 0, origin.Z) - Vector3.new(point.X, 0, point.Z)).Unit
	aimCamera(origin + back * 14 + Vector3.new(0, 6, 0), point)
end
aimAt(goalCenter + Vector3.new(0, 4, 9))

Emu.input("RS_Shoot", Enum.UserInputState.Begin, Enum.UserInputType.MouseButton1)
Emu.run(0.6)
check("клиент заряжает удар", ClientControls.charging == true and ClientControls.charge > 0.5, ClientControls.charge)
check("сервер знает о замахе", alice.Character:GetAttribute("Charging") == true)
Emu.input("RS_Shoot", Enum.UserInputState.End, Enum.UserInputType.MouseButton1)
Emu.run(0.1)
check("мяч выбит", not hasBall(alice))
local shotSpeed = ballPart().AssemblyLinearVelocity.Magnitude
check("скорость удара в разумных пределах", shotSpeed > 80 and shotSpeed < 170, string.format("%.1f", shotSpeed))

local outcome = "мяч в игре"
Emu.runUntil(5, function()
	if phase() == "Goal" then
		outcome = "ГОЛ"
		return true
	end
	for _, actor in pairs(Actors.byCharacter) do
		if actor.isKeeper and actor.hasBall then
			outcome = "вратарь поймал"
			return true
		end
	end
	return false
end)
print("       исход удара: " .. outcome)
Emu.run(3)

---------------------------------------------------------------------------
section("Стили и способности")
---------------------------------------------------------------------------

local function giveBall(player)
	local actor = Actors.ofPlayer(player)
	actor.noPickupUntil = 0
	Ball.attach(actor)
end

local function dropBallNear(player, distance: number)
	local origin = rootOf(player).CFrame.Position
	Ball.reset(Vector3.new(origin.X - attackX * distance, 1.3, origin.Z), false)
	Ball.active = true
end

for _, style in ipairs(Styles.list) do
	check("матч идёт перед тестом стиля " .. style.id, waitLive(40), phase())
	if style.id ~= alice:GetAttribute("Style") then
		ClientState.send("SelectStyle", style.id)
		Emu.run(0.2)
	end
	check("стиль выбран: " .. style.id, alice:GetAttribute("Style") == style.id, alice:GetAttribute("Style"))
	Emu.run(4.3) -- перезарядка после смены стиля

	for slot = 1, 3 do
		waitLive(40)
		local ability = style.abilities[slot]
		local actor = Actors.ofPlayer(alice)
		actor.data.resonance = 100
		actor.stamina = actor.staminaMax
		actor.stunnedUntil = 0
		-- Встаём в центре поля и смотрим вдоль боковой линии, чтобы удары не заканчивались голом.
		place(alice, Vector3.new(0, 0, 0), Vector3.new(0, 0, 60))
		aimCamera(Vector3.new(0, 9, -14), Vector3.new(0, 4, 60))
		setKeepersFrozen(true)
		if ability.needsNoBall then
			if hasBall(alice) then
				Ball.reset(Vector3.new(0, 1.3, 30), false)
			end
			dropBallNear(alice, 0)
			Ball.reset(Vector3.new(0, 1.3, 30), false)
			Ball.active = true
			actor.noPickupUntil = Actors.now() + 0.4
		else
			giveBall(alice)
		end
		Emu.run(0.25)

		local before = alice:GetAttribute("CD_A" .. slot) or 0
		local errorsBefore = #Emu.errors
		local warningsBefore = #Emu.warnings
		Emu.tap("RS_Ability" .. slot)
		Emu.run(0.3)
		local after = alice:GetAttribute("CD_A" .. slot) or 0
		local label = string.format("%s / %s (%s)", style.id, ability.id, ability.name)
		check("способность сработала: " .. label, after > before and after > Actors.now())
		Emu.run(ability.ultimate and 3 or 1.6)
		check("без ошибок: " .. label, #Emu.errors == errorsBefore and #Emu.warnings == warningsBefore, #Emu.errors - errorsBefore)
		if ability.ultimate then
			check("ульта тратит резонанс: " .. ability.id, (Actors.ofPlayer(alice).data.resonance or 0) < 20)
		end
		setKeepersFrozen(false)
	end
	Emu.run(6) -- дать эффектам и длительным способностям закончиться
end

---------------------------------------------------------------------------
section("Подкат, финт, пас")
---------------------------------------------------------------------------

waitLive(40)
local bob = Emu.addPlayer("Bob", 202)
Emu.run(0.6)
local actorBob = Actors.ofPlayer(bob)
check("второй игрок в другой команде", actorBob ~= nil and actorBob.team ~= actorAlice.team, actorBob and actorBob.team)

local function resetDuel()
	waitLive(40)
	local a = Actors.ofPlayer(alice)
	a.stamina = a.staminaMax
	a.stunnedUntil = 0
	a.data.cooldowns.Tackle = 0
	alice:SetAttribute("CD_Tackle", 0)
	place(bob, Vector3.new(0, 0, -40), Vector3.new(-20, 0, -40))
	place(alice, Vector3.new(-7, 0, -40), Vector3.new(0, 0, -40))
	giveBall(bob)
	Emu.run(0.2)
end

resetDuel()
check("мяч у соперника", hasBall(bob))
Emu.tap("RS_Tackle")
Emu.run(0.8)
check("подкат выбил мяч", not hasBall(bob))
check("соперник оглушён", (bob.Character:GetAttribute("StunnedUntil") or 0) > Actors.now() - 0.8)
check("событие Steal отправлено", (Emu.remoteLog["<-Steal"] or 0) >= 1, Emu.remoteLog["<-Steal"])
Emu.run(3)

resetDuel()
Actors.setImmune(Actors.ofPlayer(bob), 3)
local dodgesBefore = Emu.remoteLog["<-Dodge"] or 0
Emu.tap("RS_Tackle")
Emu.run(0.8)
check("финт: подкат не прошёл", hasBall(bob))
check("событие Dodge отправлено", (Emu.remoteLog["<-Dodge"] or 0) > dodgesBefore)
Emu.run(3)

-- Пас партнёру.
waitLive(40)
local carol = Emu.addPlayer("Carol", 303)
Emu.run(0.6)
local actorCarol = Actors.ofPlayer(carol)
check("третий игрок — партнёр", actorCarol ~= nil and actorCarol.team == actorAlice.team, actorCarol and actorCarol.team)
place(bob, Vector3.new(-60, 0, 60), Vector3.new(0, 0, 60))
place(alice, Vector3.new(0, 0, 0), Vector3.new(40, 0, 6))
place(carol, Vector3.new(40, 0, 6), Vector3.new(0, 0, 0))
giveBall(alice)
aimCamera(Vector3.new(-14, 8, 0), Vector3.new(40, 2, 0))
Emu.run(0.2)
Emu.tap("RS_Pass")
local received = Emu.runUntil(3, function()
	return hasBall(carol)
end)
check("пас дошёл до партнёра", received)

-- Навес.
place(alice, Vector3.new(0, 0, 0), Vector3.new(60, 0, 0))
place(carol, Vector3.new(70, 0, -8), Vector3.new(0, 0, 0))
giveBall(alice)
aimCamera(Vector3.new(-14, 8, 0), Vector3.new(70, 2, -4))
Emu.run(0.5)
Emu.tap("RS_Lob")
Emu.run(0.25)
local peak = 0
local lobbed = Emu.runUntil(4, function()
	peak = math.max(peak, ballPos().Y)
	return hasBall(carol)
end)
check("навес летит высоко", peak > 8, string.format("высота %.1f", peak))
check("навес дошёл до партнёра", lobbed)

-- Рывок.
waitLive(40)
place(alice, Vector3.new(-20, 0, 20), Vector3.new(20, 0, 20))
local a2 = Actors.ofPlayer(alice)
a2.stamina = a2.staminaMax
local dashFrom = rootOf(alice).CFrame.Position
Emu.tap("RS_Dash")
Emu.run(0.5)
local dashed = (rootOf(alice).CFrame.Position - dashFrom).Magnitude
check("рывок переносит игрока", dashed > 8, string.format("%.1f", dashed))

---------------------------------------------------------------------------
section("Гол и новый розыгрыш")
---------------------------------------------------------------------------

waitLive(40)
local homeBefore = matchState:GetAttribute("Home")
local awayBefore = matchState:GetAttribute("Away")
setKeepersFrozen(true)
local enemyGoal = F.goalCenter(-actorAlice.side)
place(alice, Vector3.new(enemyGoal.X - attackX * 10, 0, 8), enemyGoal + Vector3.new(0, 0, 8))
giveBall(alice)
Emu.run(0.1)
Ball.kick(Actors.ofPlayer(alice), Vector3.new(attackX * 150, 6, 0), { kind = "Shot" })
local scored = Emu.runUntil(2, function()
	return phase() == "Goal"
end)
check("гол засчитан", scored, phase())
local scoreKey = actorAlice.team
check("счёт вырос", matchState:GetAttribute(scoreKey) == (scoreKey == "Home" and homeBefore or awayBefore) + 1, string.format("%s:%s", tostring(matchState:GetAttribute("Home")), tostring(matchState:GetAttribute("Away"))))
check("событие Goal отправлено", (Emu.remoteLog["<-Goal"] or 0) >= 1)
check("резонанс за гол", Actors.ofPlayer(alice).data.resonance >= Config.Resonance.Goal - 1, Actors.ofPlayer(alice).data.resonance)
setKeepersFrozen(false)
check("после гола новый розыгрыш", Emu.runUntil(15, function()
	return phase() == "Kickoff"
end), phase())
local center = ballPos()
check("мяч вернулся в центр", math.abs(center.X) < 1 and math.abs(center.Z) < 1 and ballPart().Anchored, string.format("%.1f %.1f", center.X, center.Z))
check("игра продолжается", waitLive(10), phase())

---------------------------------------------------------------------------
section("Вратарь")
---------------------------------------------------------------------------

Emu.adoptCharacters()
waitLive(40)
-- Слабый удар прямо во вратаря соперника: он должен поймать и выбить мяч.
local keeper
for _, actor in pairs(Actors.byCharacter) do
	if actor.isKeeper and actor.team ~= actorAlice.team then
		keeper = actor
	end
end
check("вратарь соперника найден", keeper ~= nil)
if keeper then
	local keeperPos = keeper.root.CFrame.Position
	place(bob, Vector3.new(-60, 0, 60), Vector3.new(0, 0, 60))
	place(carol, Vector3.new(-40, 0, -60), Vector3.new(0, 0, 0))
	place(alice, Vector3.new(keeperPos.X - attackX * 40, 0, keeperPos.Z), keeperPos)
	giveBall(alice)
	Emu.run(0.1)
	Ball.kick(Actors.ofPlayer(alice), Vector3.new(attackX * 95, 8, 0), { kind = "Shot" })
	local caught = Emu.runUntil(3, function()
		return keeper.hasBall
	end)
	check("вратарь ловит несильный удар", caught)
	local released = Emu.runUntil(4, function()
		return not keeper.hasBall
	end)
	check("вратарь выбивает мяч", released)
	local kx = math.abs(keeper.root.CFrame.Position.X)
	check("вратарь остаётся у своих ворот", kx > 100 and kx < 136, string.format("x=%.1f", kx))
end
Emu.run(3)

---------------------------------------------------------------------------
section("Респаун и выход игрока")
---------------------------------------------------------------------------

waitLive(40)
giveBall(alice)
Emu.run(0.2)
local errorsBefore = #Emu.errors
Emu.spawnCharacter(alice)
Emu.run(1.5)
check("после респауна новый актёр", Actors.ofPlayer(alice) ~= nil and Actors.ofPlayer(alice).character == alice.Character)
check("мяч освободился после смерти владельца", Ball.holder == nil and ballPart():FindFirstChild("BallJoint") == nil)
check("мяч можно столкнуть (CanCollide)", ballPart().CanCollide == true)
check("респаун без ошибок", #Emu.errors == errorsBefore, #Emu.errors - errorsBefore)

Emu.signalOf(game:GetService("Players"), "PlayerRemoving"):Fire(bob)
Emu.characters[bob.Character] = nil
bob.Character:Destroy()
bob:Destroy()
Emu.run(1)
check("выход игрока без ошибок", #Emu.errors == errorsBefore, #Emu.errors - errorsBefore)

---------------------------------------------------------------------------
section("Финальный свисток и новый матч")
---------------------------------------------------------------------------

waitLive(40)
Match.timeLeft = 1
check("финальный свисток", Emu.runUntil(6, function()
	return phase() == "FullTime"
end), phase())
check("событие FullTime отправлено", (Emu.remoteLog["<-FullTime"] or 0) >= 1)
check("новый матч начался", Emu.runUntil(30, function()
	return phase() == "Playing"
end), phase())
check("счёт обнулён", matchState:GetAttribute("Home") == 0 and matchState:GetAttribute("Away") == 0)
Emu.run(5)

---------------------------------------------------------------------------
-- Выгрузка данных для картинок
---------------------------------------------------------------------------

if dumpDir then
	local parts = {}
	for _, d in ipairs(workspace:GetDescendants()) do
		if d:IsA("BasePart") and d.Transparency < 1 and d.Name ~= "Fx" then
			local cf = d.CFrame
			local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cf:GetComponents()
			table.insert(parts, {
				n = d.Name,
				s = { d.Size.X, d.Size.Y, d.Size.Z },
				p = { x, y, z },
				r = { r00, r01, r02, r10, r11, r12, r20, r21, r22 },
				c = { d.Color.R, d.Color.G, d.Color.B },
				t = d.Transparency,
				sh = d:IsA("Part") and d.Shape.Name or "Block",
				m = d.Material.Name,
			})
		end
	end
	fs.writeFile(dumpDir .. "/stadium.json", serde.encode("json", parts))
	print(string.format("\nвыгружено деталей: %d -> %s/stadium.json", #parts, dumpDir))
end

---------------------------------------------------------------------------
-- Итог
---------------------------------------------------------------------------

print("\n== События (сколько раз отправлены)")
local names = {}
for name in pairs(Emu.remoteLog) do
	table.insert(names, name)
end
table.sort(names)
local line = {}
for _, name in ipairs(names) do
	table.insert(line, string.format("%s×%d", name, Emu.remoteLog[name]))
end
print("   " .. table.concat(line, "  "))

if #Emu.warnings > 0 then
	print(string.format("\n== Предупреждения (%d)", #Emu.warnings))
	for i = 1, math.min(#Emu.warnings, 25) do
		print("   " .. Emu.warnings[i])
	end
end
if #Emu.errors > 0 then
	-- Одинаковые ошибки сворачиваем: первая строка + место в коде + сколько раз.
	local groups, order = {}, {}
	for _, message in ipairs(Emu.errors) do
		local lines = string.split(message, "\n")
		local head = string.gsub(lines[1], "^%[t=[%d%.]+%] ", "")
		local where = ""
		for _, l in ipairs(lines) do
			local found = string.match(l, '%[string "([^"]+)"%]:(%d+)')
			if found then
				where = string.match(l, '%[string "[^"]+"%]:%d+[^\n]*') or ""
				break
			end
		end
		local key = head .. " @ " .. where
		if not groups[key] then
			groups[key] = { count = 0, first = lines[1] }
			table.insert(order, key)
		end
		groups[key].count += 1
	end
	print(string.format("\n== Ошибки выполнения (%d, разных: %d)", #Emu.errors, #order))
	for i = 1, math.min(#order, 20) do
		print(string.format("   ×%d  %s\n        первая: %s", groups[order[i]].count, order[i], groups[order[i]].first))
	end
end

local failed = 0
for _, result in ipairs(results) do
	if not result.ok then
		failed += 1
	end
end
print(string.format("\nИТОГ: проверок %d, провалено %d, ошибок выполнения %d, предупреждений %d", #results, failed, #Emu.errors, #Emu.warnings))
if failed > 0 or #Emu.errors > 0 then
	process.exit(1)
end
