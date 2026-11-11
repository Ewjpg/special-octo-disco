-- Точка входа сервера: строит стадион и запускает все системы.

local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")

local Server = script.Parent

local Physics = require(Server.Physics)
local Net = require(Server.Net)
local FieldBuilder = require(Server.FieldBuilder)
local Actors = require(Server.Actors)
local Ball = require(Server.BallService)
local Match = require(Server.MatchService)
local PlayerService = require(Server.PlayerService)
local Actions = require(Server.ActionService)
local Bots = require(Server.BotService)

-- Камера и прыжок.
StarterPlayer.CameraMaxZoomDistance = 40
StarterPlayer.CameraMinZoomDistance = 6
StarterPlayer.EnableMouseLockOption = true

Physics.init()
FieldBuilder.ensureTeams()
FieldBuilder.build()
Ball.init()
PlayerService.init()
Actions.init()
Bots.init()
Match.init()

-- Одна ошибка в кадре не должна останавливать игру; повторяющиеся сообщения не спамим.
local lastWarning = {}
local function guarded(name: string, fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok then
		local now = os.clock()
		if not lastWarning[name] or now - lastWarning[name] > 5 then
			lastWarning[name] = now
			warn(string.format("[%s] %s", name, tostring(err)))
		end
	end
end

RunService.Heartbeat:Connect(function(dt)
	guarded("Actors", Actors.step, dt)
	guarded("Bots", Bots.step, dt)
	guarded("Actions", Actions.step)
	guarded("Ball", Ball.step, dt)
end)

print(string.format("[%s] сервер запущен, RemoteEvents: %s", "Resonance", Net.Action:GetFullName()))
