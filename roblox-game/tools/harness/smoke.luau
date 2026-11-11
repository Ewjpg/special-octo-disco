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

local placePath = "build/Resonance.rbxlx"
for i, arg in ipairs(process.args) do
	if arg == "--place" then
		placePath = process.args[i + 1]
	end
end
local game = Emu.load(placePath)
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
local stadiumMesh = workspace:FindFirstChild("StadiumMesh")
if stadiumMesh then
	-- Imported Blender stadium: the part-built stands must be skipped and its lamps lit.
	local meshParts, lamps = 0, 0
	for _, d in ipairs(stadiumMesh:GetDescendants()) do
		if d:IsA("BasePart") then
			meshParts += 1
			if d.Material == Enum.Material.Neon then
				lamps += 1
			end
		end
	end
	check("стадион из Blender на месте", meshParts >= 40, meshParts)
	check("старые трибуны из деталей не строятся", stadium and stadium:FindFirstChild("Stands") == nil)
	check("прожекторы стадиона светятся", lamps >= 8, lamps)
	check("поле, ворота и борта построены", partCount > 500, partCount)
else
	check("деталей стадиона > 800", partCount > 800, partCount)
end
check("мяч создан", workspace:FindFirstChild("Ball") ~= nil)
check(
	"на стадионе нет старых названий",
	(function()
		for _, d in ipairs(workspace:GetDescendants()) do
			if
				d:IsA("TextLabel")
				and (string.find(d.Text, "RESONANCE") or string.find(d.Text, "СОЛАР") or string.find(d.Text, "НОКС"))
			then
				return false
			end
		end
		return true
	end)()
)
check("RemoteEvents созданы", ReplicatedStorage:FindFirstChild("Remotes") ~= nil)
local matchState = ReplicatedStorage:FindFirstChild("MatchState")
check("MatchState создан", matchState ~= nil)
check(
	"фаза Waiting без игроков",
	matchState and matchState:GetAttribute("Phase") == "Waiting",
	matchState and matchState:GetAttribute("Phase")
)
check("базовый стиль есть", Styles.byId[Styles.default] ~= nil, Styles.default)
print(
	string.format("       стилей в меню: %d (%s)", #Styles.list, Styles.enabled and "включены" or "отключены")
)

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

-- Lobby: a new player waits on a pedestal, not on the pitch, until PLAY.
Emu.run(0.6)
check("new player starts in the lobby", alice:GetAttribute("InMatch") == false and alice.Team == nil)
check("no actor in the lobby", Actors.ofPlayer(alice) == nil)
check("lobby screen shown", alice.PlayerGui:FindFirstChild("Lobby") ~= nil and alice.PlayerGui.Lobby.Bar.Visible == true)
check("character held on a lobby pedestal", rootOf(alice).Anchored == true)
ClientState.send("LobbyStyle", "MinamiShin")
ClientState.send("Play", "FW")
Emu.run(2)
check("Minami Shin picked in the lobby", alice:GetAttribute("Style") == "MinamiShin", alice:GetAttribute("Style"))
check("PLAY puts the player in the match", alice:GetAttribute("InMatch") == true and alice:GetAttribute("Role") == "FW")
check("lobby bar hidden in the match", alice.PlayerGui.Lobby.Bar.Visible == false)

check("игрок в команде", alice.Team ~= nil, alice.Team and alice.Team.Name)
check("стиль сохранился после входа", alice:GetAttribute("Style") == "MinamiShin", alice:GetAttribute("Style"))
check("персонаж зарегистрирован как актёр", Actors.ofPlayer(alice) ~= nil)
check("метка команды на персонаже", alice.Character:FindFirstChild("TeamRing") ~= nil)
local hud = alice.PlayerGui:FindFirstChild("ResonanceHud")
check("HUD создан", hud ~= nil)
check("клавиши привязаны", Emu.bound.RS_Shoot ~= nil and Emu.bound.RS_Action ~= nil and Emu.bound.RS_Pass ~= nil)
if Styles.enabled then
	check(
		"клавиши способностей и меню стилей",
		Emu.bound.RS_Ability3 ~= nil and Emu.bound.RS_StyleMenu ~= nil
	)
else
	check("без стилей Z/X/C и M свободны", Emu.bound.RS_Ability1 == nil and Emu.bound.RS_StyleMenu == nil)
	local slotCount = 0
	for _, child in ipairs(hud.Root.Slots:GetChildren()) do
		if child:IsA("Frame") then
			slotCount += 1
		end
	end
	check("без стилей в HUD только E и Q", slotCount == 2, slotCount)
	check("без стилей меню стилей не создано", hud.Root:FindFirstChild("StyleMenu") == nil)
end
check("персонаж игрока — R6", alice.Character.Humanoid.RigType == Enum.HumanoidRigType.R6)
do
	local root = alice.Character.HumanoidRootPart
	local leg = alice.Character:FindFirstChild("Right Leg")
	local want = 2 * Config.Player.Scale
	check(
		"персонаж уменьшен",
		math.abs(root.Size.Y - want) < 0.01 and leg and math.abs(leg.Size.Y - want) < 0.01,
		string.format("рост корня %.2f", root.Size.Y)
	)
	Emu.run(0.2)
	local feet = root.CFrame.Position.Y - Actors.ofPlayer(alice).groundOffset
	check(
		"уменьшенный персонаж стоит на газоне",
		math.abs(feet) < 0.15,
		string.format("ступни на %.2f", feet)
	)
	check("мяч маленький", math.abs(ballPart().Size.X - Config.Ball.Radius * 2) < 0.01, ballPart().Size.X)
	check("поле 600×380", F.Length == 600 and F.Width == 380, string.format("%d×%d", F.Length, F.Width))
end
do
	local r6Keepers = 0
	for _, actor in pairs(Actors.byCharacter) do
		if actor.isKeeper and actor.humanoid.RigType == Enum.HumanoidRigType.R6 then
			r6Keepers += 1
		end
	end
	check("вратари — R6", r6Keepers == 2, r6Keepers)
end

Emu.run(2)
if Styles.enabled then
	-- the style is picked in the lobby now; in a match M still opens the menu
	check("style menu closed when the match starts", ClientControls.menuOpen == false)
	Emu.input("RS_StyleMenu", Enum.UserInputState.Begin)
	Emu.run(0.1)
	check("M opens the style menu", ClientControls.menuOpen == true)
	Emu.input("RS_StyleMenu", Enum.UserInputState.Begin)
	Emu.run(0.1)
	check("меню стилей закрывается", ClientControls.menuOpen == false)
else
	check("без стилей меню не открывается", ClientControls.menuOpen == false)
end
check("команды называются HOME и AWAY", Config.Teams.Home.Name == "HOME" and Config.Teams.Away.Name == "AWAY")

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
Emu.run(0.1)
do
	local shown, near = 0, true
	local rootPos = rootOf(alice).CFrame.Position
	for _, child in ipairs(workspace:GetChildren()) do
		if child.Name == "BallRing" and child.Transparency < 1 then
			shown += 1
			local p = child.CFrame.Position
			near = near and math.abs(p.X - rootPos.X) < 1 and math.abs(p.Z - rootPos.Z) < 1 and p.Y < 0.5
		end
	end
	check("круги на газоне под игроком с мячом", shown == 3 and near, shown)
end

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
check(
	"скорость удара в разумных пределах",
	-- Between the weakest shot and the strongest one a style multiplier (up to x1.25) allows.
	shotSpeed > Config.Shot.MinPower * 0.9 and shotSpeed < Config.Shot.MaxPower * 1.25,
	string.format("%.1f", shotSpeed)
)

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

local function giveBall(player)
	local actor = Actors.ofPlayer(player)
	actor.noPickupUntil = 0
	Ball.attach(actor)
end

---------------------------------------------------------------------------
section("Curved shot (hold D)")
---------------------------------------------------------------------------

do
	waitLive(40)
	giveBall(alice)
	Emu.run(0.3)
	aimAt(goalCenter + Vector3.new(0, 4, 9))
	local aim = ClientControls.aimFlat()
	Emu.keysDown[Enum.KeyCode.D] = true
	Emu.input("RS_Shoot", Enum.UserInputState.Begin, Enum.UserInputType.MouseButton1)
	Emu.run(0.5)
	Emu.input("RS_Shoot", Enum.UserInputState.End, Enum.UserInputType.MouseButton1)
	Emu.keysDown[Enum.KeyCode.D] = nil
	Emu.run(0.05)
	local v0 = ballPart().AssemblyLinearVelocity
	local flat0 = Vector3.new(v0.X, 0, v0.Z).Unit
	local right = Vector3.new(-aim.Z, 0, aim.X)
	check("curved shot starts to the left of the aim", flat0:Dot(right) < -0.05, string.format("%.3f", flat0:Dot(right)))
	Emu.run(0.5)
	local v1 = ballPart().AssemblyLinearVelocity
	local flat1 = Vector3.new(v1.X, 0, v1.Z).Unit
	local turn = math.deg(math.asin(math.clamp(flat0:Cross(flat1).Y * -1, -1, 1)))
	check("curved shot bends to the right", turn > 8, string.format("%.1f°", turn))
	Emu.run(4)
end

---------------------------------------------------------------------------
section("Стили и способности")
---------------------------------------------------------------------------

-- Соперник и партнёр нужны для проверки способностей; пока стоят в стороне.
-- Бобу Roblox «выдаёт» R15: сервер должен пересобрать его в R6.
local bob = Emu.addPlayer("Bob", 202, "R15")
local carol = Emu.addPlayer("Carol", 303)
Emu.run(1)
-- they have no client in the emulator: press PLAY for them on the server
local PlayerService = Emu.server.require(Server.PlayerService)
PlayerService.requestPlay(bob, "DF")
PlayerService.requestPlay(carol, "MF")
Emu.run(1.5)
do
	local humanoid = bob.Character and bob.Character:FindFirstChildOfClass("Humanoid")
	check("R15 пересобран в R6", humanoid ~= nil and humanoid.RigType == Enum.HumanoidRigType.R6)
	local copies = 0
	for _, child in ipairs(workspace:GetChildren()) do
		if child.Name == "Bob" then
			copies += 1
		end
	end
	check("старый персонаж R15 удалён", copies == 1, copies)
end
local actorBob = Actors.ofPlayer(bob)
local actorCarol = Actors.ofPlayer(carol)
check(
	"второй игрок в другой команде",
	actorBob ~= nil and actorBob.team ~= actorAlice.team,
	actorBob and actorBob.team
)
check(
	"третий игрок — партнёр",
	actorCarol ~= nil and actorCarol.team == actorAlice.team,
	actorCarol and actorCarol.team
)

local function parkOthers()
	place(bob, Vector3.new(-70, 0, -70), Vector3.new(0, 0, -70))
	place(carol, Vector3.new(-90, 0, 70), Vector3.new(0, 0, 70))
end

local enemyGoal = F.goalCenter(-actorAlice.side)

-- Особая подготовка и проверка результата для каждой способности.
-- prepare() вызывается перед нажатием, verify() — сразу после (сама крутит время и возвращает ok, подробности).
local scenarios = {}

scenarios.CometShot = {
	verify = function()
		local top = 0
		Emu.run(0.7, function()
			if not hasBall(alice) then
				top = math.max(top, ballPart().AssemblyLinearVelocity.Magnitude)
			end
		end)
		return top > 180, string.format("макс. скорость мяча %.0f", top)
	end,
}

scenarios.Afterburner = {
	verify = function(from)
		Emu.run(0.5)
		local moved = (rootOf(alice).CFrame.Position - from).Magnitude
		return moved > 20 and hasBall(alice),
			string.format("рывок на %.1f, мяч при себе: %s", moved, tostring(hasBall(alice)))
	end,
}

scenarios.Meteor = {
	verify = function()
		local height, top = 0, 0
		local t0 = Emu.now
		Emu.run(1.6, function()
			height = math.max(height, ballPos().Y)
			top = math.max(top, ballPart().AssemblyLinearVelocity.Magnitude)
			if process.env.TRACE then
				local v = ballPart().AssemblyLinearVelocity
				print(
					string.format(
						"    t=%.2f y=%.1f z=%.1f vy=%.1f |v|=%.1f held=%s lift=%.1f",
						Emu.now - t0,
						ballPos().Y,
						ballPos().Z,
						v.Y,
						v.Magnitude,
						tostring(hasBall(alice)),
						ballPart().Lift.Force.Y
					)
				)
			end
		end)
		return height > 20 and top > 200, string.format("высота %.0f, скорость падения %.0f", height, top)
	end,
}

scenarios.PhantomStep = {
	verify = function(from)
		Emu.run(0.15)
		local moved = (rootOf(alice).CFrame.Position - from).Magnitude
		local immune = Actors.isImmune(Actors.ofPlayer(alice))
		return moved > 17 and moved < 23 and hasBall(alice) and immune,
			string.format("перенос на %.1f, неуязвим: %s", moved, tostring(immune))
	end,
}

scenarios.MirrorCurve = {
	verify = function()
		-- Игрок целится вдоль +Z из центра, значит боковое смещение мяча — это X.
		local minX, maxX = 0, 0
		Emu.run(1, function()
			local x = ballPos().X
			minX, maxX = math.min(minX, x), math.max(maxX, x)
		end)
		return (maxX - minX) > 6 and not hasBall(alice),
			string.format("мяч гулял по дуге на %.1f в ширину", maxX - minX)
	end,
}

scenarios.HallOfMirrors = {
	verify = function()
		Emu.run(0.4)
		local actor = Actors.ofPlayer(alice)
		local unstoppable = Actors.hasFlag(actor, "unstoppableUntil")
		local faster = actor.speedMods.Mirrors ~= nil
		local stunned = Actors.stun(actor, 1)
		return unstoppable and faster and not stunned,
			string.format(
				"неуязвимость %s, ускорение %s, оглушить нельзя %s",
				tostring(unstoppable),
				tostring(faster),
				tostring(not stunned)
			)
	end,
}

scenarios.Pull = {
	prepare = function()
		Ball.reset(Vector3.new(0, 1.3, 40), false)
		Ball.active = true
	end,
	verify = function()
		local got = Emu.runUntil(2, function()
			return hasBall(alice)
		end)
		return got, "мяч с 40 шагов притянут: " .. tostring(got)
	end,
}

scenarios.Orbit = {
	prepare = function()
		-- Целимся мимо ворот (на 9 шагов шире штанги): удар должен сам довернуть в створ.
		local from = Vector3.new(enemyGoal.X - attackX * 75, 0, 20)
		place(alice, from, Vector3.new(enemyGoal.X, 0, 25))
		local target = Vector3.new(enemyGoal.X, 3, 25)
		local back = (Vector3.new(from.X, 0, from.Z) - Vector3.new(target.X, 0, target.Z)).Unit
		aimCamera(Vector3.new(from.X, 9, from.Z) + back * 14, target)
		giveBall(alice)
	end,
	verify = function()
		local scored = Emu.runUntil(3, function()
			return phase() == "Goal"
		end)
		return scored, "удар мимо створа довернул в ворота: " .. tostring(scored)
	end,
}

scenarios.Singularity = {
	prepare = function()
		Ball.reset(Vector3.new(0, 1.3, 30), false)
		Ball.active = true
		Actors.ofPlayer(alice).noPickupUntil = 0
		place(bob, Vector3.new(6, 0, 18), Vector3.new(0, 0, 0))
	end,
	verify = function()
		Emu.run(0.5)
		local slowed = Actors.ofPlayer(bob).speedMods.Singularity ~= nil
		local got = Emu.runUntil(4, function()
			return hasBall(alice)
		end)
		return slowed and got,
			string.format("соперник замедлен %s, мяч притянут %s", tostring(slowed), tostring(got))
	end,
}

scenarios.Ram = {
	prepare = function()
		place(bob, Vector3.new(0, 0, 14), Vector3.new(0, 0, 60))
		giveBall(bob)
	end,
	verify = function()
		Emu.run(0.7)
		local took = hasBall(alice)
		local stunned = Actors.isStunned(Actors.ofPlayer(bob))
		return took and stunned,
			string.format("мяч отобран %s, соперник оглушён %s", tostring(took), tostring(stunned))
	end,
}

scenarios.Barrier = {
	verify = function()
		Emu.run(0.3)
		local wall = workspace:FindFirstChild("Barrier")
		local built = wall ~= nil and wall.CollisionGroup == "BallOnly" and #wall:GetChildren() == 4
		Emu.run(4)
		local gone = workspace:FindFirstChild("Barrier") == nil
		return built and gone,
			string.format("стена поставлена %s, исчезла через 3.5 с %s", tostring(built), tostring(gone))
	end,
}

scenarios.Citadel = {
	prepare = function()
		-- Соперник бьёт «неберущимся» ударом в игрока: под Цитаделью мяч всё равно должен прилипнуть.
		place(bob, Vector3.new(0, 0, 45), Vector3.new(0, 0, 0))
		Ball.reset(Vector3.new(0, 1.3, 30), false)
		Ball.active = true
	end,
	verify = function()
		Emu.run(0.5)
		giveBall(bob)
		Emu.run(0.1)
		Ball.kick(Actors.ofPlayer(bob), Vector3.new(0, 4, -215), { kind = "Shot", untrappable = 2 })
		local got = Emu.runUntil(1.5, function()
			return hasBall(alice)
		end)
		return got, "неберущийся удар принят: " .. tostring(got)
	end,
}

for _, style in ipairs(Styles.list) do
	check("матч идёт перед тестом стиля " .. style.id, waitLive(40), phase())
	if style.id ~= alice:GetAttribute("Style") then
		ClientState.send("SelectStyle", style.id)
		Emu.run(0.2)
	end
	check("стиль выбран: " .. style.id, alice:GetAttribute("Style") == style.id, alice:GetAttribute("Style"))
	check("характеристики стиля применены", Actors.ofPlayer(alice).style.id == style.id)
	Emu.run(4.3) -- перезарядка после смены стиля

	for slot = 1, #style.abilities do -- a style may not have all three yet (Minami Shin: none so far)
		waitLive(40)
		local ability = style.abilities[slot]
		local scenario = scenarios[ability.id] or {}
		local actor = Actors.ofPlayer(alice)
		actor.data.resonance = 100
		actor.stamina = actor.staminaMax
		actor.stunnedUntil = 0
		parkOthers()
		-- По умолчанию: в центре поля, взгляд вдоль боковой линии — чтобы удары не заканчивались голом.
		place(alice, Vector3.new(0, 0, 0), Vector3.new(0, 0, 60))
		aimCamera(Vector3.new(0, 9, -14), Vector3.new(0, 4, 60))
		setKeepersFrozen(true)
		if ability.needsNoBall then
			Ball.reset(Vector3.new(0, 1.3, 30), false)
			Ball.active = true
			actor.noPickupUntil = Actors.now() + 0.4
		else
			giveBall(alice)
		end
		if scenario.prepare then
			scenario.prepare()
		end
		Emu.run(0.25)

		local before = alice:GetAttribute("CD_A" .. slot) or 0
		local errorsBefore = #Emu.errors
		local warningsBefore = #Emu.warnings
		local label = string.format("%s / %s «%s»", style.id, ability.id, ability.name)
		local startPosition = rootOf(alice).CFrame.Position
		Emu.tap("RS_Ability" .. slot)
		Emu.run(0.1)
		local after = alice:GetAttribute("CD_A" .. slot) or 0
		check("сервер принял: " .. label, after > before and after > Actors.now())
		if scenario.verify then
			local ok, detail = scenario.verify(startPosition)
			check("эффект: " .. label, ok, detail)
		else
			Emu.run(1.6)
		end
		Emu.run(ability.ultimate and 2 or 1)
		check("без ошибок: " .. label, #Emu.errors == errorsBefore and #Emu.warnings == warningsBefore, #Emu.errors - errorsBefore)
		if ability.ultimate then
			check("ульта тратит резонанс: " .. ability.id, (Actors.ofPlayer(alice).data.resonance or 0) < 20)
		end
		setKeepersFrozen(false)
	end
	Emu.run(6) -- дать эффектам и длительным способностям закончиться
end

-- Условия применения проверяет и сервер.
waitLive(40)
parkOthers()
do
	local actor = Actors.ofPlayer(alice)
	actor.data.resonance = 10
	actor.data.cooldowns.A3 = 0
	alice:SetAttribute("CD_A3", 0)
	Emu.run(0.3)
	local before = alice:GetAttribute("CD_A3") or 0
	ClientState.send("Ability", 3, Vector3.new(0, 0, 1), Vector3.zero)
	Emu.run(0.3)
	check("ульта без резонанса отклоняется сервером", (alice:GetAttribute("CD_A3") or 0) == before)
	ClientState.send("Ability", 7, Vector3.new(0, 0, 1), Vector3.zero)
	ClientState.send("Ability", "x", "мусор", 5)
	ClientState.send("Shoot", "не вектор", 99)
	ClientState.send("SelectStyle", "Keeper")
	ClientState.send("SelectStyle", 42)
	ClientState.send("НетТакого", 1)
	Emu.run(0.3)
	check("служебный стиль выбрать нельзя", alice:GetAttribute("Style") ~= "Keeper", alice:GetAttribute("Style"))
end

---------------------------------------------------------------------------
section("Клавиша E: подкат и дриблинг")
---------------------------------------------------------------------------

waitLive(40)

local function resetDuel()
	waitLive(40)
	local a = Actors.ofPlayer(alice)
	a.stamina = a.staminaMax
	a.stunnedUntil = 0
	a.data.cooldowns.Tackle = 0
	alice:SetAttribute("CD_Tackle", 0)
	place(carol, Vector3.new(-90, 0, 70), Vector3.new(0, 0, 70))
	place(bob, Vector3.new(0, 0, -40), Vector3.new(-20, 0, -40))
	place(alice, Vector3.new(-7, 0, -40), Vector3.new(0, 0, -40))
	giveBall(bob)
	Emu.run(0.2)
end

resetDuel()
check("мяч у соперника", hasBall(bob))
Emu.tap("RS_Action")
Emu.run(0.8)
check("подкат выбил мяч", not hasBall(bob))
check("соперник оглушён", (bob.Character:GetAttribute("StunnedUntil") or 0) > Actors.now() - 0.8)
check("событие Steal отправлено", (Emu.remoteLog["<-Steal"] or 0) >= 1, Emu.remoteLog["<-Steal"])
Emu.run(3)

resetDuel()
Actors.setImmune(Actors.ofPlayer(bob), 3)
local dodgesBefore = Emu.remoteLog["<-Dodge"] or 0
Emu.tap("RS_Action")
Emu.run(0.8)
check("неуязвимый соперник: подкат не прошёл", hasBall(bob))
check("событие Dodge отправлено", (Emu.remoteLog["<-Dodge"] or 0) > dodgesBefore)
Emu.run(3)

-- Та же клавиша с мячом — дриблинг. Соперник в этот момент делает подкат и должен промахнуться.
local actionRemote = ReplicatedStorage.Remotes.Action
local function duelWithBall()
	waitLive(40)
	for _, player in ipairs({ alice, bob }) do
		local actor = Actors.ofPlayer(player)
		actor.stamina = actor.staminaMax
		actor.stunnedUntil = 0
		actor.immuneUntil = 0
		actor.data.cooldowns.Tackle = 0
		actor.data.cooldowns.Dribble = 0
		player:SetAttribute("CD_Tackle", 0)
		player:SetAttribute("CD_Dribble", 0)
	end
	place(carol, Vector3.new(-90, 0, 70), Vector3.new(0, 0, 70))
	place(bob, Vector3.new(0, 0, -40), Vector3.new(-20, 0, -40))
	place(alice, Vector3.new(-10, 0, -40), Vector3.new(0, 0, -40))
	giveBall(alice)
	Emu.run(0.2)
end

duelWithBall()
local dribbleFrom = rootOf(alice).CFrame.Position
local dribblesBefore = Emu.remoteLog["<-Dribble"] or 0
dodgesBefore = Emu.remoteLog["<-Dodge"] or 0
Emu.tap("RS_Action")
Emu.signalOf(actionRemote, "OnServerEvent"):Fire(bob, "Tackle", Vector3.new(-1, 0, 0))
Emu.run(0.8)
local dribbled = (rootOf(alice).CFrame.Position - dribbleFrom).Magnitude
check("E с мячом — дриблинг (событие Dribble)", (Emu.remoteLog["<-Dribble"] or 0) > dribblesBefore)
check("дриблинг сдвигает игрока", dribbled > 7 and dribbled < 14, string.format("%.1f", dribbled))
check(
	"дриблинг: подкат соперника не прошёл",
	hasBall(alice) and (Emu.remoteLog["<-Dodge"] or 0) > dodgesBefore
)
check("у дриблинга своя перезарядка", (alice:GetAttribute("CD_Dribble") or 0) > Actors.now())
Emu.run(3)

-- Контроль: без дриблинга тот же подкат мяч отбирает.
duelWithBall()
place(alice, Vector3.new(-5, 0, -40), Vector3.new(0, 0, -40))
Emu.run(0.1)
Emu.signalOf(actionRemote, "OnServerEvent"):Fire(bob, "Tackle", Vector3.new(-1, 0, 0))
Emu.run(0.6)
check("без дриблинга подкат отбирает мяч", not hasBall(alice))
Emu.run(3)

-- Пас партнёру.
waitLive(40)
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

-- Блок: быстрый удар соперника попадает в игрока — принять нельзя, мяч отлетает.
waitLive(40)
place(carol, Vector3.new(-90, 0, 70), Vector3.new(0, 0, 70))
place(alice, Vector3.new(0, 0, 0), Vector3.new(0, 0, 60))
place(bob, Vector3.new(0, 0, 40), Vector3.new(0, 0, 0))
Actors.ofPlayer(alice).noPickupUntil = 0
giveBall(bob)
Emu.run(0.1)
local blocksBefore = Emu.remoteLog["<-Block"] or 0
Ball.kick(Actors.ofPlayer(bob), Vector3.new(0, 3, -180), { kind = "Shot" })
Emu.run(0.6)
check("быстрый удар отбит, а не принят", (Emu.remoteLog["<-Block"] or 0) > blocksBefore and not hasBall(alice))
check(
	"отбитый мяч летит обратно",
	ballPart().AssemblyLinearVelocity.Z > 0 or ballPos().Z > 2,
	string.format("vz=%.1f", ballPart().AssemblyLinearVelocity.Z)
)
Emu.run(2)

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
place(bob, Vector3.new(-70, 0, -70), Vector3.new(0, 0, -70))
place(carol, Vector3.new(-90, 0, 70), Vector3.new(0, 0, 70))
place(alice, Vector3.new(enemyGoal.X - attackX * 10, 0, 8), enemyGoal + Vector3.new(0, 0, 8))
giveBall(alice)
Emu.run(0.1)
Ball.kick(Actors.ofPlayer(alice), Vector3.new(attackX * 150, 6, 0), { kind = "Shot" })
local scored = Emu.runUntil(2, function()
	return phase() == "Goal"
end)
check("гол засчитан", scored, phase())
local scoreKey = actorAlice.team
check(
	"счёт вырос",
	matchState:GetAttribute(scoreKey) == (scoreKey == "Home" and homeBefore or awayBefore) + 1,
	string.format("%s:%s", tostring(matchState:GetAttribute("Home")), tostring(matchState:GetAttribute("Away")))
)
check("событие Goal отправлено", (Emu.remoteLog["<-Goal"] or 0) >= 1)
check(
	"резонанс за гол",
	Actors.ofPlayer(alice).data.resonance >= Config.Resonance.Goal - 1,
	Actors.ofPlayer(alice).data.resonance
)
setKeepersFrozen(false)
check(
	"после гола новый розыгрыш",
	Emu.runUntil(15, function()
		return phase() == "Kickoff"
	end),
	phase()
)
local center = ballPos()
check(
	"мяч вернулся в центр",
	math.abs(center.X) < 1 and math.abs(center.Z) < 1 and ballPart().Anchored,
	string.format("%.1f %.1f", center.X, center.Z)
)
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
	check(
		"вратарь остаётся у своих ворот",
		kx > F.HalfLength - 30 and kx < F.HalfLength + 6,
		string.format("x=%.1f", kx)
	)
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
check(
	"после респауна новый актёр",
	Actors.ofPlayer(alice) ~= nil and Actors.ofPlayer(alice).character == alice.Character
)
check(
	"мяч освободился после смерти владельца",
	Ball.holder == nil and ballPart():FindFirstChild("BallJoint") == nil
)
check("мяч можно столкнуть (CanCollide)", ballPart().CanCollide == true)
check("респаун без ошибок", #Emu.errors == errorsBefore, #Emu.errors - errorsBefore)

-- Смерть персонажа: мяч освобождается, а если Roblox сам не возродил игрока — это делает сервер.
giveBall(alice)
Emu.run(0.2)
local deadCharacter = alice.Character
local loadsBefore = Emu.loadCharacterCalls
Emu.kill(deadCharacter)
Emu.run(0.3)
check("после смерти актёр снят, мяч свободен", Actors.get(deadCharacter) == nil and Ball.holder == nil)
Emu.run(4.5)
check("сервер сам возродил игрока", Emu.loadCharacterCalls == loadsBefore + 1 and alice.Character ~= deadCharacter)
check(
	"новый персонаж зарегистрирован",
	Actors.ofPlayer(alice) ~= nil and Actors.ofPlayer(alice).character == alice.Character
)

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
check(
	"финальный свисток",
	Emu.runUntil(6, function()
		return phase() == "FullTime"
	end),
	phase()
)
check("событие FullTime отправлено", (Emu.remoteLog["<-FullTime"] or 0) >= 1)
check(
	"новый матч начался",
	Emu.runUntil(30, function()
		return phase() == "Playing"
	end),
	phase()
)
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
print(
	string.format(
		"\nИТОГ: проверок %d, провалено %d, ошибок выполнения %d, предупреждений %d",
		#results,
		failed,
		#Emu.errors,
		#Emu.warnings
	)
)
if failed > 0 or #Emu.errors > 0 then
	process.exit(1)
end
