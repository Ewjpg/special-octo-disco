-- Выгружает дерево интерфейса (HUD) в трёх состояниях для отрисовки макета.
-- Запуск из папки roblox-game:  lune run tools/harness/dump_gui.luau <папка>

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local Emu = require("./emu")

local Vector3, CFrame, Enum = roblox.Vector3, roblox.CFrame, roblox.Enum
local outDir = process.args[1] or "."

local function get(instance, property)
	local ok, value = pcall(function()
		return instance[property]
	end)
	if ok then
		return value
	end
	return nil
end

local function udim2(value)
	if not value then
		return nil
	end
	return { value.X.Scale, value.X.Offset, value.Y.Scale, value.Y.Offset }
end

local function color(value)
	if not value then
		return nil
	end
	return { value.R, value.G, value.B }
end

local function enumName(value)
	return value and value.Name or nil
end

local function dump(instance)
	local node = { class = instance.ClassName, name = instance.Name, children = {} }
	if instance:IsA("GuiObject") then
		node.position = udim2(get(instance, "Position"))
		node.size = udim2(get(instance, "Size"))
		local anchor = get(instance, "AnchorPoint")
		node.anchor = anchor and { anchor.X, anchor.Y } or { 0, 0 }
		node.bg = color(get(instance, "BackgroundColor3"))
		node.bgT = get(instance, "BackgroundTransparency")
		node.visible = get(instance, "Visible")
		node.z = get(instance, "ZIndex")
		node.order = get(instance, "LayoutOrder")
		node.rotation = get(instance, "Rotation")
		node.clips = get(instance, "ClipsDescendants")
		if instance:IsA("TextLabel") or instance:IsA("TextButton") then
			node.text = get(instance, "Text")
			node.textColor = color(get(instance, "TextColor3"))
			node.textSize = get(instance, "TextSize")
			node.textT = get(instance, "TextTransparency")
			node.alignX = enumName(get(instance, "TextXAlignment"))
			node.alignY = enumName(get(instance, "TextYAlignment"))
			node.wrapped = get(instance, "TextWrapped")
			node.font = enumName(get(instance, "Font"))
		end
	elseif instance:IsA("UICorner") then
		node.radius = get(instance, "CornerRadius").Offset
	elseif instance:IsA("UIStroke") then
		node.color = color(get(instance, "Color"))
		node.thickness = get(instance, "Thickness")
		node.transparency = get(instance, "Transparency")
	elseif instance:IsA("UIListLayout") then
		node.fill = enumName(get(instance, "FillDirection"))
		node.padding = get(instance, "Padding").Offset
		node.alignH = enumName(get(instance, "HorizontalAlignment"))
	elseif instance:IsA("UIPadding") then
		node.left = get(instance, "PaddingLeft").Offset
		node.top = get(instance, "PaddingTop").Offset
	elseif instance:IsA("UIScale") then
		node.scale = get(instance, "Scale")
	end
	for _, child in ipairs(instance:GetChildren()) do
		table.insert(node.children, dump(child))
	end
	return node
end

local game = Emu.load("build/Resonance.rbxlx")
local workspace = game:GetService("Workspace")
local Server = game:GetService("ServerScriptService").Server
Emu.startServer()
Emu.run(1)
local Actors = Emu.server.require(Server.Actors)
local Ball = Emu.server.require(Server.BallService)
local matchState = game:GetService("ReplicatedStorage").MatchState

local alice = Emu.addPlayer("Alice", 101)
Emu.startClient(alice)
Emu.run(3)

local hud = alice.PlayerGui.ResonanceHud
local function save(name)
	fs.writeFile(outDir .. "/" .. name .. ".json", serde.encode("json", dump(hud)))
	print("сохранено: " .. name)
end

save("gui-menu")

-- Игра: мяч у игрока, спринт, замах.
Emu.input("RS_StyleMenu", Enum.UserInputState.Begin)
Emu.runUntil(12, function()
	return matchState:GetAttribute("Phase") == "Playing"
end)
Emu.run(1.2)
local actor = Actors.ofPlayer(alice)
actor.noPickupUntil = 0
Ball.attach(actor)
Emu.input("RS_Sprint", Enum.UserInputState.Begin)
Emu.controller(alice.Character).moveTarget = Vector3.new(60, 0, 20)
Emu.run(3)
Emu.input("RS_Dash", Enum.UserInputState.Begin)
Emu.run(0.4)
workspace.CurrentCamera.CFrame = CFrame.lookAt(Vector3.new(40, 9, 20), Vector3.new(130, 4, 5))
Emu.input("RS_Shoot", Enum.UserInputState.Begin, Enum.UserInputType.MouseButton1)
Emu.run(0.55)
save("gui-play")

-- Гол: баннер.
Emu.input("RS_Shoot", Enum.UserInputState.End, Enum.UserInputType.MouseButton1)
Emu.run(0.2)
for _, other in pairs(Actors.byCharacter) do
	if other.isKeeper then
		other.frozen = true
	end
end
alice.Character:PivotTo(CFrame.new(-actor.side * 120, 3, 6))
actor.noPickupUntil = 0
Ball.attach(actor)
Emu.run(0.1)
Ball.kick(actor, Vector3.new(-actor.side * 150, 5, 0), { kind = "Shot" })
Emu.runUntil(2, function()
	return matchState:GetAttribute("Phase") == "Goal"
end)
Emu.run(0.5)
save("gui-goal")

if #Emu.errors > 0 then
	print("ошибок: " .. #Emu.errors)
	print(Emu.errors[1])
end
