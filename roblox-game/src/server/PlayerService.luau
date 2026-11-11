-- Игроки: распределение по командам, регистрация персонажа как «актёра», командные метки.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

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
	local ringSize = 5.2 * Config.Player.Scale
	ring.Size = Vector3.new(0.12, ringSize, ringSize)
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
		-- Служебные стили (базовый, вратарь) в табличке не пишем.
		styleLabel.Text = style.selectable == false and "" or Util.upper(style.name)
		styleLabel.TextColor3 = style.color
	end
	refreshStyle()
	character:GetAttributeChangedSignal("Style"):Connect(refreshStyle)

	tag.Parent = head or actor.root
end

PlayerService.addKit = addKit

local WANTED_RIG = Config.Avatar.RigType == "R15" and Enum.HumanoidRigType.R15 or Enum.HumanoidRigType.R6

-- Roblox создал персонажа не того типа (например R15, а игра рассчитана на R6):
-- собираем такого же персонажа — с вещами и цветами игрока — на нужном скелете и подменяем.
-- Возвращает true, если подмена удалась (тогда для нового персонажа сработает CharacterAdded).
local function replaceRig(player: Player, character: Model, humanoid: Humanoid): boolean
	local description: HumanoidDescription? = nil
	pcall(function()
		description = humanoid:GetAppliedDescription()
	end)
	local ok, result = pcall(function()
		return Players:CreateHumanoidModelFromDescription(description or Instance.new("HumanoidDescription"), WANTED_RIG)
	end)
	if not ok or typeof(result) ~= "Instance" then
		warn("[Players] could not rebuild the character as " .. Config.Avatar.RigType .. ": " .. tostring(result))
		return false
	end
	-- Создание модели занимает время: за это время игрок мог выйти или его персонаж мог смениться.
	if not dataByPlayer[player] or player.Character ~= character or not character.Parent then
		result:Destroy()
		return true
	end
	local model = result :: Model
	model.Name = player.Name
	model:PivotTo(character:GetPivot())
	player.Character = model
	model.Parent = Workspace
	character:Destroy()
	return true
end

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
	if not dataByPlayer[player] or player.Character ~= character or not character.Parent then
		return -- игрок вышел или персонаж уже сменился
	end

	if Config.Avatar.ForceRig and humanoid.RigType ~= WANTED_RIG then
		-- Страховка от зацикливания: если пересборка идёт слишком часто, перестаём её делать для этого игрока.
		local now = os.clock()
		if now - (data.lastRebuild or 0) > 15 then
			data.rebuilds = 0
		end
		data.lastRebuild = now
		data.rebuilds = (data.rebuilds or 0) + 1
		if data.rebuilds <= 4 then
			if replaceRig(player, character, humanoid) then
				return
			end
		elseif data.rebuilds == 5 then
			warn("[Players] character rebuild disabled for " .. player.Name .. ": too many retries")
		end
	end

	-- Все персонажи уменьшены (Config.Player.Scale): поле кажется больше, а путь до ворот дольше.
	if Config.Player.Scale ~= 1 then
		character:ScaleTo(Config.Player.Scale)
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
		-- Обычно Roblox возрождает игрока сам. Если этого не случилось (персонаж был собран нами вручную),
		-- загружаем нового персонажа сами.
		task.delay(Players.RespawnTime + 1.5, function()
			if dataByPlayer[player] and player.Character == character then
				pcall(function()
					player:LoadCharacter()
				end)
			end
		end)
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
