-- Резкие перемещения персонажа: рывок и телепорт на короткую дистанцию.
-- Персонажем игрока управляет его клиент, поэтому игрок вызывает это у себя, а сервер — только для ботов.

local FieldSpec = require(script.Parent.FieldSpec)
local Util = require(script.Parent.Util)

local Mover = {}

-- Рывок по горизонтали с постоянной скоростью. Гравитация и прыжок не затрагиваются.
function Mover.dash(root: BasePart, direction: Vector3, speed: number, duration: number)
	local dir = Util.flatUnit(direction, root.CFrame.LookVector)

	for _, name in ipairs({ "DashVelocity", "DashAttachment" }) do
		local old = root:FindFirstChild(name)
		if old then
			old:Destroy()
		end
	end

	local attachment = Instance.new("Attachment")
	attachment.Name = "DashAttachment"
	attachment.Parent = root

	local velocity = Instance.new("LinearVelocity")
	velocity.Name = "DashVelocity"
	velocity.Attachment0 = attachment
	velocity.RelativeTo = Enum.ActuatorRelativeTo.World
	velocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	velocity.PrimaryTangentAxis = Vector3.new(1, 0, 0)
	velocity.SecondaryTangentAxis = Vector3.new(0, 0, 1)
	velocity.PlaneVelocity = Vector2.new(dir.X, dir.Z) * speed
	velocity.MaxForce = 400000
	velocity.Parent = root

	task.delay(duration, function()
		velocity:Destroy()
		attachment:Destroy()
	end)
end

-- Мгновенный перенос вперёд, но не дальше бортов арены.
function Mover.blink(root: BasePart, direction: Vector3, distance: number)
	local dir = Util.flatUnit(direction, root.CFrame.LookVector)
	local target = FieldSpec.clampToArena(root.Position + dir * distance, 3)
	root.CFrame = CFrame.lookAt(target, target + dir)
end

return Mover
