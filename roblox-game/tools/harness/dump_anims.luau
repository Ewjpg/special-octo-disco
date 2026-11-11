-- Выгружает кадры всех анимаций как набор «коробок» (части блочного персонажа) для отрисовки картинки.
-- Поза считается той же формулой, что и в клиентском ProcAnimator, на скелетах R6 и R15.
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

local function dumpRig(kind: string)
	local rig = Emu.buildRig("Preview", nil, kind)
	local specs = kind == "R6" and Emu.R6_PARTS or Emu.RIG_PARTS
	local motors = {}
	for _, d in ipairs(rig:GetDescendants()) do
		if d:IsA("Motor6D") then
			motors[d.Name] = d
		end
	end

	local names = {}
	for name in pairs(Animations[kind]) do
		table.insert(names, name)
	end
	table.sort(names)

	local out = {}
	for _, name in ipairs(names) do
		local anim = Animations.get(name, kind)
		local frames = {}
		for i = 0, FRAMES - 1 do
			local t = anim.length * i / (FRAMES - 1)
			if anim.loop then
				t = anim.length * i / FRAMES
			end
			local pose = Sampler.sample(anim, t, {})
			for jointName, motor in pairs(motors) do
				local value = pose[jointName]
				if value then
					-- Как в ProcAnimator: поза в осях персонажа -> оси сустава.
					local desired = Sampler.toCFrame(value, anim.pivots and anim.pivots[jointName])
					local frame = motor.C0.Rotation
					motor.Transform = frame:Inverse() * desired * frame
				else
					motor.Transform = CFrame.new()
				end
			end
			-- Прямая кинематика: Part1 = Part0 * C0 * Transform * C1^-1 (порядок — от корня к конечностям).
			local boxes = {}
			for _, spec in ipairs(specs) do
				local part = rig[spec[1]]
				local motor = motors[spec[3]]
				part.CFrame = motor.Part0.CFrame * motor.C0 * motor.Transform * motor.C1:Inverse()
				local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = part.CFrame:GetComponents()
				local size = part.Size
				if kind == "R6" and spec[1] == "Head" then
					size = roblox.Vector3.new(1.25, 1.25, 1.25) -- у головы R6 видимая сетка меньше самой детали
				end
				table.insert(boxes, {
					n = spec[1],
					s = { size.X, size.Y, size.Z },
					p = { x, y, z },
					r = { r00, r01, r02, r10, r11, r12, r20, r21, r22 },
				})
			end
			table.insert(frames, { t = t, boxes = boxes })
		end
		table.insert(out, { name = name, length = anim.length, loop = anim.loop == true, frames = frames })
	end
	local file = string.format("%s/anims-%s.json", outDir, kind)
	fs.writeFile(file, serde.encode("json", out))
	print(string.format("%s: анимаций %d, кадров на каждую %d -> %s", kind, #out, FRAMES, file))
end

dumpRig("R6")
dumpRig("R15")
