-- Ход матча: розыгрыш с центра -> игра -> гол -> розыгрыш ... -> финальный свисток -> новый матч.
-- Состояние для интерфейса лежит в атрибутах ReplicatedStorage.MatchState.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local F = require(Shared.FieldSpec)
local Actors = require(script.Parent.Actors)
local Ball = require(script.Parent.BallService)
local FieldBuilder = require(script.Parent.FieldBuilder)
local Net = require(script.Parent.Net)

local MATCH = Config.Match
local RES = Config.Resonance

local Match = {}

Match.phase = "Waiting" -- Waiting | Kickoff | Playing | Goal | FullTime
Match.score = { Home = 0, Away = 0 }
Match.timeLeft = MATCH.Duration

local state = Instance.new("Folder")
state.Name = "MatchState"

local pendingGoal = nil

-- Расстановка: { доля половины поля от своих ворот, доля половины ширины }.
local SLOTS = {
	{ 0.8, 0 },
	{ 0.62, -0.4 },
	{ 0.62, 0.4 },
	{ 0.42, -0.2 },
	{ 0.42, 0.2 },
	{ 0.52, 0 },
	{ 0.3, -0.5 },
	{ 0.3, 0.5 },
	{ 0.2, 0 },
}

local function formatTime(seconds: number): string
	local whole = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", whole // 60, whole % 60)
end

local function replicate()
	state:SetAttribute("Home", Match.score.Home)
	state:SetAttribute("Away", Match.score.Away)
	state:SetAttribute("TimeLeft", math.max(0, math.ceil(Match.timeLeft)))
	local scoreText = string.format("%d : %d", Match.score.Home, Match.score.Away)
	local timeText = formatTime(Match.timeLeft)
	for _, label in ipairs(FieldBuilder.scoreLabels) do
		label.Text = scoreText
	end
	for _, label in ipairs(FieldBuilder.timeLabels) do
		label.Text = timeText
	end
end

local function setPhase(phase: string)
	Match.phase = phase
	Actors.live = phase == "Playing"
	state:SetAttribute("Phase", phase)
end

function Match.isLive(): boolean
	return Match.phase == "Playing"
end

local function actorName(actor): string
	if not actor then
		return ""
	end
	if actor.player then
		return actor.player.DisplayName
	end
	return actor.character.Name
end

local function ballSpot(): Vector3
	return F.Origin + Vector3.new(0, Config.Ball.Radius + 0.05, 0)
end

-- Поставить актёра на позицию. index — номер в команде, isKicker — разыгрывает мяч с центра.
function Match.place(actor, index: number, isKicker: boolean)
	local position
	if actor.isKeeper then
		position = F.fromOwnGoal(actor.side, 5, 0)
	elseif isKicker then
		position = F.fromOwnGoal(actor.side, F.HalfLength - 3.4, 0)
	else
		local slot = SLOTS[((index - 1) % #SLOTS) + 1]
		position = F.fromOwnGoal(actor.side, slot[1] * F.HalfLength, slot[2] * F.HalfWidth)
	end
	Actors.teleport(actor, position, F.attackDir(actor.side))
end

-- Игрок появился посреди матча.
function Match.placeLate(actor)
	local index = #Actors.teamList(actor.team, false) + 1
	Match.place(actor, index, false)
	Actors.setFrozen(actor, Match.phase == "Kickoff")
end

local function sortedTeam(team: string)
	local list = Actors.teamList(team, false)
	table.sort(list, function(a, b)
		return actorName(a) < actorName(b)
	end)
	return list
end

local function placeEveryone(kickoffTeam: string)
	for _, team in ipairs({ "Home", "Away" }) do
		for index, actor in ipairs(sortedTeam(team)) do
			-- У разыгрывающей команды первый игрок встаёт к мячу, остальные сдвигаются на слот назад.
			local isKicker = team == kickoffTeam and index == 1
			Match.place(actor, team == kickoffTeam and index - 1 or index, isKicker)
		end
	end
	for _, actor in pairs(Actors.byCharacter) do
		if actor.isKeeper and actor.alive then
			Match.place(actor, 1, false)
		end
		if actor.alive then
			Actors.setFrozen(actor, true)
		end
	end
end

local function unfreezeEveryone()
	for _, actor in pairs(Actors.byCharacter) do
		Actors.setFrozen(actor, false)
	end
end

local function kickoff(kickoffTeam: string)
	setPhase("Kickoff")
	Ball.active = false
	Ball.reset(ballSpot(), true)
	placeEveryone(kickoffTeam)
	replicate()

	for n = MATCH.KickoffCountdown, 1, -1 do
		state:SetAttribute("Countdown", n)
		Net.fx("Countdown", { n = n, team = kickoffTeam })
		task.wait(1)
	end
	state:SetAttribute("Countdown", 0)

	unfreezeEveryone()
	Ball.setFrozen(false)
	Ball.active = true
	setPhase("Playing")
	Net.fx("Whistle", { kind = "Kickoff" })
end

-- Игра идёт, пока не забьют или не кончится время.
local function playUntilStop()
	pendingGoal = nil
	while Match.timeLeft > 0 do
		local dt = task.wait(0.1)
		if pendingGoal then
			return pendingGoal
		end
		if #Players:GetPlayers() == 0 then
			return "empty"
		end
		Match.timeLeft = math.max(0, Match.timeLeft - dt)
		replicate()
	end
	return pendingGoal
end

local function goalSequence(goal)
	setPhase("Goal")
	Match.score[goal.team] += 1
	replicate()

	local scorer, assist = goal.scorer, goal.assist
	if scorer then
		Actors.addResonance(scorer, RES.Goal)
	end
	if assist then
		Actors.addResonance(assist, RES.Assist)
	end

	Net.fx("Goal", {
		team = goal.team,
		side = goal.side,
		character = scorer and scorer.character or nil,
		scorerName = actorName(scorer),
		assistName = actorName(assist),
		styleId = scorer and scorer.style.id or nil,
		home = Match.score.Home,
		away = Match.score.Away,
		position = Ball.position(),
	})
	task.wait(MATCH.GoalPause)
end

local function fullTime()
	setPhase("FullTime")
	Ball.active = false
	local home, away = Match.score.Home, Match.score.Away
	local winner = "Draw"
	if home > away then
		winner = "Home"
	elseif away > home then
		winner = "Away"
	end
	Net.fx("FullTime", { home = home, away = away, winner = winner })
	task.wait(MATCH.FullTimePause)
end

local function runForever()
	while true do
		setPhase("Waiting")
		Ball.active = false
		Ball.reset(ballSpot(), true)
		Match.score.Home, Match.score.Away = 0, 0
		Match.timeLeft = MATCH.Duration
		replicate()
		while #Players:GetPlayers() == 0 do
			task.wait(0.5)
		end
		task.wait(1.5) -- дать персонажу загрузиться

		local kickoffTeam = math.random() < 0.5 and "Home" or "Away"
		local abandoned = false
		while Match.timeLeft > 0 do
			kickoff(kickoffTeam)
			local result = playUntilStop()
			if result == "empty" then
				abandoned = true
				break
			elseif result then
				goalSequence(result)
				kickoffTeam = result.team == "Home" and "Away" or "Home"
			end
		end
		if not abandoned then
			fullTime()
		end
	end
end

function Match.init()
	state:SetAttribute("Phase", Match.phase)
	state:SetAttribute("Countdown", 0)
	replicate()
	state.Parent = ReplicatedStorage

	Ball.Goal:Connect(function(scoringTeam, scorer, assist, side)
		if Match.phase == "Playing" then
			pendingGoal = { team = scoringTeam, scorer = scorer, assist = assist, side = side }
		end
	end)

	task.spawn(runForever)
end

return Match
