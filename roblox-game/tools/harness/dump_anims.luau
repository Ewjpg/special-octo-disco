-- Выгружает кадры всех анимаций как набор «коробок» (части блочного R15) для отрисовки картинки.
-- Запуск из папки roblox-game:  lune run tools/harness/dump_anims.luau <папка>

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local Emu = require("./emu")

local CFrame = roblox.CFrame

local outDir = process.args[1] or "."
local game = Emu.load("build/Resonance.rbxlx")
local Shared = game:GetService("ReplicatedStorage").Shared
local Animations = Emu.server.require(Shared.Animations)
local Sampler = Emu.server.require(Shared.AnimSampler)

local FRAMES = 7
local rig = Emu.buildRig("Preview", nil)
local root = rig.HumanoidRootPart
local motors = {}
for _, d in ipairs(rig:GetDescendants()) do
	if d:IsA("Motor6D") then
		motors[d.Name] = d
	end
end

local names = {}
for name in pairs(Animations) do
	table.insert(names, name)
end
table.sort(names)

local out = {}
for _, name in ipairs(names) do
	local anim = Animations[name]
	local frames = {}
	for i = 0, FRAMES - 1 do
		local t = anim.length * i / (FRAMES - 1)
		if anim.loop then
			t = anim.length * i / FRAMES
		end
		local pose = Sampler.sample(anim, t, {})
		for jointName, motor in pairs(motors) do
			local value = pose[jointName]
			motor.Transform = value and Sampler.toCFrame(value) or CFrame.new()
		end
		-- Прямая кинематика: Part1 = Part0 * C0 * Transform * C1^-1 (порядок — от корня к конечностям).
		local boxes = {}
		for _, spec in ipairs(Emu.RIG_PARTS) do
			local part = rig[spec[1]]
			local motor = motors[spec[3]]
			part.CFrame = motor.Part0.CFrame * motor.C0 * motor.Transform * motor.C1:Inverse()
			local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = part.CFrame:GetComponents()
			table.insert(boxes, {
				n = spec[1],
				s = { part.Size.X, part.Size.Y, part.Size.Z },
				p = { x, y, z },
				r = { r00, r01, r02, r10, r11, r12, r20, r21, r22 },
			})
		end
		table.insert(frames, { t = t, boxes = boxes })
	end
	table.insert(out, { name = name, length = anim.length, loop = anim.loop == true, frames = frames })
end
local _ = root

fs.writeFile(outDir .. "/anims.json", serde.encode("json", out))
print(string.format("анимаций: %d, кадров на каждую: %d -> %s/anims.json", #out, FRAMES, outDir))
