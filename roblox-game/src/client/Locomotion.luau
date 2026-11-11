-- Run and idle for every R6 character on the pitch (players and goalkeepers), on this client.
-- The clips come from Blender (R6Clips: Run, Idle) and replace Roblox's stock R6 walk, which is what
-- made movement look stiff. Run plays faster the faster the character moves.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ProcAnimator = require(script.Parent.ProcAnimator)

local Locomotion = {}

local RUN_FROM = 3 -- studs/s: below this the character stands
local RUN_BASE_SPEED = 24 -- studs/s at which the Run clip plays at normal speed

local tracked = {} -- [Model] = { humanoid, root, state = "Idle" | "Run" | "Air", track }

local function consider(model: Instance)
	if tracked[model] or not model.Parent or not model:IsA("Model") then
		return
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	if humanoid and root and humanoid.RigType == Enum.HumanoidRigType.R6 then
		tracked[model] = { humanoid = humanoid, root = root, state = "", track = nil }
	end
end

local function switch(model: Model, entry, state: string)
	if entry.state == state then
		return
	end
	if entry.state == "Run" or entry.state == "Idle" then
		ProcAnimator.stop(model, entry.state)
	end
	entry.state = state
	entry.track = nil
	if state == "Run" or state == "Idle" then
		entry.track = ProcAnimator.play(model, state)
	end
end

local function step()
	for model, entry in pairs(tracked) do
		if not model.Parent or entry.humanoid.Health <= 0 then
			tracked[model] = nil
			continue
		end
		local velocity = entry.root.AssemblyLinearVelocity
		local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
		-- clearly rising or falling: let Roblox's own jump/fall pose show
		local airborne = math.abs(velocity.Y) > 14
		if airborne then
			switch(model, entry, "Air")
		elseif speed > RUN_FROM then
			switch(model, entry, "Run")
			if entry.track and type(entry.track) == "table" then
				entry.track.speed = math.clamp(speed / RUN_BASE_SPEED, 0.55, 1.45)
			end
		else
			switch(model, entry, "Idle")
		end
	end
end

function Locomotion.start()
	for _, child in ipairs(Workspace:GetChildren()) do
		consider(child)
	end
	Workspace.ChildAdded:Connect(function(child)
		-- the character's parts arrive right after the model itself
		task.delay(0.5, consider, child)
	end)
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function(character)
			task.delay(0.5, consider, character)
		end)
	end)
	RunService.Heartbeat:Connect(step)
end

return Locomotion
