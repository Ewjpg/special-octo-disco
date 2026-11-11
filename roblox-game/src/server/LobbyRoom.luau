-- The lobby room: a closed players' lounge high above the stadium (Config.Lobby.Origin).
-- Players stand on lit pedestals in a row and face the camera; the client frames its own character.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)

local LobbyRoom = {}

local ORIGIN = Config.Lobby.Origin
local SPACING = Config.Lobby.PedestalSpacing
local PEDESTALS = 9
local WIDTH, DEPTH, HEIGHT = 110, 46, 24
local CRIMSON = Color3.fromRGB(112, 12, 40)
local STEEL = Color3.fromRGB(46, 50, 58)

local model: Model? = nil

local function part(props: { [string]: any }, parent: Instance): BasePart
	local p = Instance.new(props.ClassName or "Part")
	props.ClassName = nil
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props) do
		(p :: any)[k] = v
	end
	p.Parent = parent
	return p :: BasePart
end

-- x offset of pedestal i (1 = middle, then alternating right/left)
local function slotX(i: number): number
	local n = (i - 1) % PEDESTALS
	local k = math.ceil(n / 2)
	return (n % 2 == 1 and 1 or -1) * k * SPACING
end

-- Where player number i stands, facing the camera (+Z).
function LobbyRoom.slot(i: number): CFrame
	local p = ORIGIN + Vector3.new(slotX(i), 1.6 + 3, 0)
	return CFrame.lookAt(p, p + Vector3.new(0, 0, 1))
end

function LobbyRoom.build(): Model
	if model and model.Parent then
		return model
	end
	local m = Instance.new("Model")
	m.Name = "Lobby"

	-- Floor: dark polished stone that reflects the lights.
	part({
		Name = "Floor",
		Size = Vector3.new(WIDTH, 1, DEPTH),
		CFrame = CFrame.new(ORIGIN + Vector3.new(0, -0.5, 0)),
		Material = Enum.Material.Marble,
		Color = Color3.fromRGB(28, 30, 36),
		Reflectance = 0.08,
	}, m)
	part({
		Name = "Ceiling",
		Size = Vector3.new(WIDTH, 1, DEPTH),
		CFrame = CFrame.new(ORIGIN + Vector3.new(0, HEIGHT + 0.5, 0)),
		Material = Enum.Material.Concrete,
		Color = Color3.fromRGB(36, 38, 44),
	}, m)
	-- Walls: concrete, back wall a little warmer.
	local walls = {
		{ Vector3.new(WIDTH, HEIGHT, 1), Vector3.new(0, HEIGHT / 2, -DEPTH / 2) },
		{ Vector3.new(WIDTH, HEIGHT, 1), Vector3.new(0, HEIGHT / 2, DEPTH / 2) },
		{ Vector3.new(1, HEIGHT, DEPTH), Vector3.new(-WIDTH / 2, HEIGHT / 2, 0) },
		{ Vector3.new(1, HEIGHT, DEPTH), Vector3.new(WIDTH / 2, HEIGHT / 2, 0) },
	}
	for i, w in ipairs(walls) do
		part({
			Name = "Wall" .. i,
			Size = w[1],
			CFrame = CFrame.new(ORIGIN + w[2]),
			Material = Enum.Material.Concrete,
			Color = i == 1 and Color3.fromRGB(58, 56, 60) or Color3.fromRGB(44, 46, 52),
		}, m)
	end

	-- Back wall: vertical wooden slats and a crimson light line along the floor.
	for x = -WIDTH / 2 + 3, WIDTH / 2 - 3, 3 do
		part({
			Name = "Slat",
			Size = Vector3.new(1.4, HEIGHT - 6, 0.5),
			CFrame = CFrame.new(ORIGIN + Vector3.new(x, HEIGHT / 2 + 1, -DEPTH / 2 + 0.8)),
			Material = Enum.Material.WoodPlanks,
			Color = Color3.fromRGB(96, 66, 44),
		}, m)
	end
	for _, z in ipairs({ -DEPTH / 2 + 1.2, DEPTH / 2 - 1.2 }) do
		local strip = part({
			Name = "FloorLight",
			Size = Vector3.new(WIDTH - 2, 0.1, 0.25),
			CFrame = CFrame.new(ORIGIN + Vector3.new(0, 0.1, z)),
			Material = Enum.Material.Neon,
			Color = CRIMSON,
			CanCollide = false,
		}, m)
		local glow = Instance.new("SurfaceLight")
		glow.Face = Enum.NormalId.Top
		glow.Color = CRIMSON
		glow.Brightness = 1.4
		glow.Range = 10
		glow.Angle = 120
		glow.Parent = strip
	end

	-- Big screen on the back wall.
	local screen = part({
		Name = "Screen",
		Size = Vector3.new(44, 12, 0.6),
		CFrame = CFrame.new(ORIGIN + Vector3.new(0, 14.5, -DEPTH / 2 + 1.4)),
		Material = Enum.Material.SmoothPlastic,
		Color = Color3.fromRGB(10, 10, 14),
	}, m)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Back -- the screen faces +Z, into the room
	gui.PixelsPerStud = 24
	gui.LightInfluence = 0
	gui.Brightness = 1.6
	gui.Parent = screen
	local bg = Instance.new("Frame")
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = Color3.new(1, 1, 1)
	bg.Parent = gui
	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(52, 120, 255)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(16, 16, 24)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(240, 62, 72)),
	})
	grad.Rotation = 0
	grad.Parent = bg
	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.fromScale(1, 0.62)
	title.Position = UDim2.fromScale(0, 0.1)
	title.Font = Enum.Font.GothamBlack
	title.TextScaled = true
	title.TextColor3 = Color3.new(1, 1, 1)
	title.Text = "HOME  vs  AWAY"
	title.Parent = bg
	local sub = Instance.new("TextLabel")
	sub.BackgroundTransparency = 1
	sub.Size = UDim2.fromScale(1, 0.18)
	sub.Position = UDim2.fromScale(0, 0.72)
	sub.Font = Enum.Font.GothamMedium
	sub.TextScaled = true
	sub.TextColor3 = Color3.fromRGB(220, 224, 236)
	sub.Text = "PICK A ROLE  ·  PRESS PLAY"
	sub.Parent = bg

	-- Ceiling: rows of light panels that actually light the room.
	for x = -WIDTH / 2 + 12, WIDTH / 2 - 12, 16 do
		for _, z in ipairs({ -8, 8 }) do
			local panel = part({
				Name = "CeilingPanel",
				Size = Vector3.new(10, 0.3, 3),
				CFrame = CFrame.new(ORIGIN + Vector3.new(x, HEIGHT - 0.15, z)),
				Material = Enum.Material.Neon,
				Color = Color3.fromRGB(255, 244, 228),
				CanCollide = false,
			}, m)
			local light = Instance.new("SurfaceLight")
			light.Face = Enum.NormalId.Bottom
			light.Color = Color3.fromRGB(255, 238, 220)
			light.Brightness = 2.2
			light.Range = 30
			light.Angle = 100
			light.Shadows = true
			light.Parent = panel
		end
	end

	-- Pedestals: brushed steel discs with a light ring and a spotlight from above.
	for i = 1, PEDESTALS do
		local base = ORIGIN + Vector3.new(slotX(i), 0, 0)
		part({
			Name = "Pedestal",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(1.6, 6.5, 6.5),
			CFrame = CFrame.new(base + Vector3.new(0, 0.8, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			Material = Enum.Material.Metal,
			Color = STEEL,
			Reflectance = 0.05,
		}, m)
		local ring = part({
			Name = "PedestalRing",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.12, 6.7, 6.7),
			CFrame = CFrame.new(base + Vector3.new(0, 1.2, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			Material = Enum.Material.Neon,
			Color = CRIMSON,
			CanCollide = false,
		}, m)
		ring.Transparency = 0.35
		local spotHolder = part({
			Name = "SpotHolder",
			Size = Vector3.new(1, 1, 1),
			CFrame = CFrame.new(base + Vector3.new(0, HEIGHT - 2, 6)),
			Transparency = 1,
			CanCollide = false,
		}, m)
		local spot = Instance.new("SpotLight")
		spot.Face = Enum.NormalId.Bottom
		spot.Angle = 40
		spot.Range = 30
		spot.Brightness = 3
		spot.Color = Color3.fromRGB(255, 246, 236)
		spot.Shadows = true
		spot.Parent = spotHolder
	end

	m.Parent = Workspace
	model = m
	return m
end

return LobbyRoom
