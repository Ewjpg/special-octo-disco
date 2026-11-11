-- «Обезьяний» тест: три игрока несколько минут жмут случайные кнопки, бегают за мячом,
-- меняют стили, перерождаются и выходят из игры. Цель — поймать редкие ошибки выполнения.
-- Запуск из папки roblox-game:  lune run tools/harness/monkey.luau [seed] [секунд]

local process = require("@lune/process")
local roblox = require("@lune/roblox")

local Emu = require("./emu")

local Vector3, CFrame, Enum = roblox.Vector3, roblox.CFrame, roblox.Enum

local seed = tonumber(process.args[1]) or 1
local duration = tonumber(process.args[2]) or 180

-- Свой генератор, чтобы прогон с тем же seed всегда был одинаковым.
local state = (seed * 7919 + 17) % 2147483647
local function rand(): number
	state = (state * 48271) % 2147483647
	return state / 2147483647
end
local function pick(list)
	return list[1 + math.floor(rand() * #list)]
end
local function randomDir()
	local angle = rand() * math.pi * 2
	return Vector3.new(math.cos(angle), rand() * 0.6 - 0.1, math.sin(angle))
end

local game = Emu.load("build/Resonance.rbxlx")
local workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Server = game:GetService("ServerScriptService").Server

local Config = Emu.server.require(ReplicatedStorage.Shared.Config)
Config.Match.Duration = 45 -- короткие матчи: чаще проходим свисток и перезапуск
Config.Match.FullTimePause = 3

Emu.startServer()
Emu.run(1)

local Actors = Emu.server.require(Server.Actors)
local Ball = Emu.server.require(Server.BallService)
local Styles = Emu.server.require(ReplicatedStorage.Shared.Styles)
local action = ReplicatedStorage.Remotes.Action
local matchState = ReplicatedStorage.MatchState

local alice = Emu.addPlayer("Alice", 101)
Emu.startClient(alice)
local others = { Emu.addPlayer("Bob", 202), Emu.addPlayer("Carol", 303) }
Emu.run(2)
Emu.input("RS_StyleMenu", Enum.UserInputState.Begin)

local CLIENT_ACTIONS =
	{ "RS_Pass", "RS_Lob", "RS_Tackle", "RS_Dash", "RS_Ability1", "RS_Ability2", "RS_Ability3", "RS_StyleMenu", "RS_Help" }
local SERVER_ACTIONS = { "Shoot", "Pass", "Lob", "Tackle", "Dash", "Ability", "Charge", "Sprint", "SelectStyle" }
local styleIds = {}
for _, style in ipairs(Styles.list) do
	table.insert(styleIds, style.id)
end
table.insert(styleIds, "Keeper")
table.insert(styleIds, "Nope")

-- Действие «чужого» клиента: событие приходит на сервер от имени игрока.
local function serverAction(player)
	local name = pick(SERVER_ACTIONS)
	local signal = Emu.signalOf(action, "OnServerEvent")
	if name == "Shoot" then
		signal:Fire(player, name, randomDir(), rand())
	elseif name == "Ability" then
		signal:Fire(player, name, math.floor(rand() * 4), randomDir(), rand() < 0.5 and randomDir() or nil)
	elseif name == "Charge" or name == "Sprint" then
		signal:Fire(player, name, rand() < 0.5)
	elseif name == "SelectStyle" then
		signal:Fire(player, name, pick(styleIds))
	else
		signal:Fire(player, name, randomDir())
	end
end

local stats = { goals = 0, kickoffs = 0, respawns = 0, leaves = 0, cheats = 0 }
local lastPhase = ""
local nextEvent = 0
local shooting = false

local function everyone()
	local list = { alice }
	for _, player in ipairs(others) do
		table.insert(list, player)
	end
	return list
end

Emu.run(duration, function()
	local phase = matchState:GetAttribute("Phase")
	if phase ~= lastPhase then
		if phase == "Goal" then
			stats.goals += 1
		elseif phase == "Kickoff" then
			stats.kickoffs += 1
		end
		lastPhase = phase
	end
	Emu.adoptCharacters()

	if Emu.now < nextEvent then
		return
	end
	nextEvent = Emu.now + 0.05 + rand() * 0.25
	local ball = workspace:FindFirstChild("Ball")
	local ballPosition = ball and ball.CFrame.Position or Vector3.zero

	-- Все бегут то к мячу, то в случайную точку.
	for _, player in ipairs(everyone()) do
		local controller = player.Character and Emu.controller(player.Character)
		if controller then
			if rand() < 0.6 then
				controller.moveTarget = ballPosition
			elseif rand() < 0.5 then
				controller.moveTarget = Vector3.new((rand() * 2 - 1) * 140, 0, (rand() * 2 - 1) * 80)
			end
		end
	end

	-- Камера локального игрока смотрит в случайную сторону.
	local root = alice.Character and alice.Character:FindFirstChild("HumanoidRootPart")
	if root then
		local eye = root.CFrame.Position + Vector3.new(0, 8, 0)
		workspace.CurrentCamera.CFrame = CFrame.lookAt(eye, eye + randomDir() * 20)
	end

	local roll = rand()
	if roll < 0.3 then
		Emu.tap(pick(CLIENT_ACTIONS))
	elseif roll < 0.42 then
		shooting = not shooting
		Emu.input("RS_Shoot", shooting and Enum.UserInputState.Begin or Enum.UserInputState.End, Enum.UserInputType.MouseButton1)
	elseif roll < 0.5 then
		Emu.input("RS_Sprint", rand() < 0.5 and Enum.UserInputState.Begin or Enum.UserInputState.End)
	elseif roll < 0.85 then
		serverAction(pick(others))
	elseif roll < 0.9 then
		-- Подыгрываем: резонанс до максимума и мяч случайному игроку, чтобы чаще срабатывали ульты и удары.
		stats.cheats += 1
		local player = pick(everyone())
		local actor = Actors.ofPlayer(player)
		if actor and matchState:GetAttribute("Phase") == "Playing" then
			actor.data.resonance = 100
			actor.noPickupUntil = 0
			if rand() < 0.5 then
				Ball.attach(actor)
			end
		end
	elseif roll < 0.93 then
		stats.respawns += 1
		Emu.spawnCharacter(pick(everyone()))
	elseif roll < 0.95 and #others > 1 then
		-- Игрок выходит (возможно, прямо с мячом).
		stats.leaves += 1
		local player = table.remove(others, 1 + math.floor(rand() * #others))
		Emu.signalOf(game:GetService("Players"), "PlayerRemoving"):Fire(player)
		if player.Character then
			Emu.characters[player.Character] = nil
			player.Character:Destroy()
		end
		player:Destroy()
	elseif roll < 0.97 and #others < 3 then
		table.insert(others, Emu.addPlayer("Guest" .. math.floor(rand() * 1000), 1000 + math.floor(rand() * 1000)))
	end
end)

print(
	string.format(
		"seed %d: %.0f c игры, голов %d, розыгрышей %d, респаунов %d, выходов %d | ошибок %d, предупреждений %d",
		seed,
		duration,
		stats.goals,
		stats.kickoffs,
		stats.respawns,
		stats.leaves,
		#Emu.errors,
		#Emu.warnings
	)
)

local function summarize(title: string, list)
	if #list == 0 then
		return
	end
	local groups, order = {}, {}
	for _, message in ipairs(list) do
		local lines = string.split(message, "\n")
		local head = string.gsub(lines[1], "^%[[^%]]*%] ", "")
		local where = ""
		for _, line in ipairs(lines) do
			local found = string.match(line, '%[string "[^"]+"%]:%d+')
			if found then
				where = found
				break
			end
		end
		local key = head .. " @ " .. where
		if not groups[key] then
			groups[key] = 0
			table.insert(order, key)
		end
		groups[key] += 1
	end
	print(title)
	for i = 1, math.min(#order, 15) do
		print(string.format("   ×%d  %s", groups[order[i]], order[i]))
	end
end
summarize("ошибки:", Emu.errors)
summarize("предупреждения:", Emu.warnings)

if #Emu.errors > 0 or #Emu.warnings > 0 then
	process.exit(1)
end
