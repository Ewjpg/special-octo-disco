-- Игроки: распределение по командам, регистрация персонажа как «актёра», командные метки.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Styles = require(Shared.Styles)
local Util = require(Shared.Util)
local Actors = require(script.Parent.Actors)
local FieldBuilder = require(script.Parent.FieldBuilder)
local Match = require(script.Parent.MatchService)
local Physics = require(script.Parent.Physics)

local PlayerService = {}

local teams = {} -- { Home = Team, Away = Team }
local dataByPlayer = {} -- то, что переживает респаун: стиль, резонанс, перезарядки

local function countTeam(key: string): number
	local count = 0
	for _, data in pairs(dataByPlayer) do
		if data.team == key then
			count += 1
		end
	end
	return count
end

-- Диск под ногами и табличка с именем в цвет команды.
local function addKit(actor, displayName: string)
	local team = Config.Teams[actor.team]
	local character = actor.character

	local ring = Instance.new("Part")
	ring.Name = "TeamRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.12, 5.2, 5.2)
	ring.Material = Enum.Material.Neon
	ring.Color = team.Color
	ring.Transparency = 0.55
	ring.CanCollide = false
	ring.CanTouch = false
	ring.CanQuery = false
	ring.Massless = true
	ring.CastShadow = false
	ring.CFrame = actor.root.CFrame * CFrame.new(0, -actor.groundOffset + 0.12, 0) * CFrame.Angles(0, 0, math.rad(90))
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = actor.root
	weld.Part1 = ring
	weld.Parent = ring
	ring.Parent = character

	local head = character:FindFirstChild("Head") :: BasePart?
	local tag = Instance.new("BillboardGui")
	tag.Name = "NameTag"
	tag.Size = UDim2.fromOffset(220, 44)
	tag.StudsOffset = Vector3.new(0, 2.7, 0)
	tag.MaxDistance = 240
	tag.LightInfluence = 0
	tag.Adornee = head or actor.root

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "PlayerName"
	nameLabel.BackgroundTransparency = 1
	nameLabel.Size = UDim2.new(1, 0, 0, 24)
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 18
	nameLabel.TextColor3 = team.Color:Lerp(Color3.new(1, 1, 1), 0.25)
	nameLabel.TextStrokeTransparency = 0.35
	nameLabel.Text = displayName
	nameLabel.Parent = tag

	local styleLabel = Instance.new("TextLabel")
	styleLabel.Name = "StyleName"
	styleLabel.BackgroundTransparency = 1
	styleLabel.Position = UDim2.fromOffset(0, 24)
	styleLabel.Size = UDim2.new(1, 0, 0, 18)
	styleLabel.Font = Enum.Font.GothamMedium
	styleLabel.TextSize = 13
	styleLabel.TextStrokeTransparency = 0.5
	styleLabel.Parent = tag

	local function refreshStyle()
		local style = Styles.get(character:GetAttribute("Style"))
		styleLabel.Text = Util.upper(style.name)
		styleLabel.TextColor3 = style.color
	end
	refreshStyle()
	character:GetAttributeChangedSignal("Style"):Connect(refreshStyle)

	tag.Parent = head or actor.root
end

PlayerService.addKit = addKit

local function onCharacter(player: Player, character: Model)
	local data = dataByPlayer[player]
	if not data then
		return
	end
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not humanoid or not root then
		return
	end
	if not character.Parent then
		character.AncestryChanged:Wait()
	end
	task.wait(0.2) -- персонаж должен полностью собраться (HipHeight, аксессуары)
	if player.Character ~= character or not character.Parent then
		return
	end

	Physics.tagCharacter(character)
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None

	local actor = Actors.register(character, { team = data.team, player = player, data = data })
	if not actor then
		return
	end
	addKit(actor, player.DisplayName)

	humanoid.Died:Connect(function()
		Actors.unregister(character)
	end)
	character.AncestryChanged:Connect(function(_, parent)
		if not parent then
			Actors.unregister(character)
		end
	end)

	Match.placeLate(actor)
end

local function onPlayer(player: Player)
	local key = countTeam("Home") <= countTeam("Away") and "Home" or "Away"
	local data = {
		team = key,
		styleId = Styles.default,
		resonance = 0,
		cooldowns = {},
	}
	dataByPlayer[player] = data

	player.Neutral = false
	player.Team = teams[key]
	player:SetAttribute("TeamKey", key)
	player:SetAttribute("Style", data.styleId)
	player:SetAttribute("Stamina", Config.Player.MaxStamina)
	player:SetAttribute("MaxStamina", Config.Player.MaxStamina)
	player:SetAttribute("Resonance", 0)

	player.CharacterAdded:Connect(function(character)
		onCharacter(player, character)
	end)
	if player.Character then
		task.spawn(onCharacter, player, player.Character)
	end
end

function PlayerService.init()
	teams = FieldBuilder.ensureTeams()
	Players.RespawnTime = 2

	Players.PlayerAdded:Connect(onPlayer)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(onPlayer, player)
	end

	Players.PlayerRemoving:Connect(function(player)
		if player.Character then
			Actors.unregister(player.Character)
		end
		dataByPlayer[player] = nil
	end)
end

return PlayerService
