-- Звуки. Список и громкость — в Config.Sounds.

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)

local Sfx = {}

-- where: Vector3 (точка в мире), BasePart (звук едет с деталью) или nil (обычный 2D-звук).
function Sfx.play(name: string, where: any, options: { [string]: number }?)
	local def = Config.Sounds[name]
	if not def then
		return
	end
	local opts = options or {}

	local sound = Instance.new("Sound")
	sound.SoundId = def.Id
	sound.Volume = def.Volume * (opts.volume or 1)
	sound.PlaybackSpeed = def.Pitch * (opts.pitch or 1) * (0.96 + math.random() * 0.08)
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = 20
	sound.RollOffMaxDistance = 260

	if typeof(where) == "Vector3" then
		local holder = Instance.new("Part")
		holder.Name = "SoundPoint"
		holder.Anchored = true
		holder.CanCollide = false
		holder.CanQuery = false
		holder.CanTouch = false
		holder.Transparency = 1
		holder.Size = Vector3.new(0.2, 0.2, 0.2)
		holder.CFrame = CFrame.new(where)
		holder.Parent = Workspace
		sound.Parent = holder
		Debris:AddItem(holder, 4)
	elseif typeof(where) == "Instance" then
		sound.Parent = where
		Debris:AddItem(sound, 4)
	else
		sound.Parent = SoundService
		Debris:AddItem(sound, 4)
	end
	sound:Play()
end

return Sfx
