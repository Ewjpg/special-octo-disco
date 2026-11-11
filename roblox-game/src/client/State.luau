-- Короткие функции «что сейчас с моим игроком и матчем». Используются всеми клиентскими модулями.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Styles = require(Shared.Styles)

local State = {}

State.player = Players.LocalPlayer
State.remotes = ReplicatedStorage:WaitForChild("Remotes")
State.action = State.remotes:WaitForChild("Action") :: RemoteEvent
State.fx = State.remotes:WaitForChild("Fx") :: RemoteEvent
State.match = ReplicatedStorage:WaitForChild("MatchState")

function State.now(): number
	return Workspace:GetServerTimeNow()
end

function State.character(): Model?
	return State.player.Character
end

function State.root(): BasePart?
	local character = State.player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

function State.humanoid(): Humanoid?
	local character = State.player.Character
	return character and character:FindFirstChildOfClass("Humanoid")
end

function State.hasBall(): boolean
	local character = State.player.Character
	return character ~= nil and character:GetAttribute("HasBall") == true
end

function State.isStunned(): boolean
	local character = State.player.Character
	if not character then
		return true
	end
	local untilTime = character:GetAttribute("StunnedUntil")
	return type(untilTime) == "number" and State.now() < untilTime
end

function State.phase(): string
	return State.match:GetAttribute("Phase") or "Waiting"
end

function State.isLive(): boolean
	return State.phase() == "Playing"
end

function State.style()
	return Styles.get(State.player:GetAttribute("Style"))
end

function State.stamina(): number
	return State.player:GetAttribute("Stamina") or 0
end

function State.resonance(): number
	return State.player:GetAttribute("Resonance") or 0
end

-- Сколько секунд осталось до конца перезарядки.
function State.cooldown(key: string): number
	local ready = State.player:GetAttribute("CD_" .. key)
	if type(ready) ~= "number" then
		return 0
	end
	return math.max(0, ready - State.now())
end

function State.send(name: string, ...)
	State.action:FireServer(name, ...)
end

return State
