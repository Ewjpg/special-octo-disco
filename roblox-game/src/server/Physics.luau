-- Группы столкновений.
--   Ball       — мяч. Сквозь игроков проходит: приём и блок считает BallService.
--   Characters — все части персонажей.
--   BallOnly   — преграды способностей: останавливают только мяч.

local PhysicsService = game:GetService("PhysicsService")

local Config = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared").Config)

local Physics = {}

Physics.BALL = "Ball"
Physics.CHARACTERS = "Characters"
Physics.BALL_ONLY = "BallOnly"

function Physics.init()
	for _, name in ipairs({ Physics.BALL, Physics.CHARACTERS, Physics.BALL_ONLY }) do
		pcall(function()
			PhysicsService:RegisterCollisionGroup(name)
		end)
	end
	PhysicsService:CollisionGroupSetCollidable(Physics.BALL, Physics.CHARACTERS, false)
	PhysicsService:CollisionGroupSetCollidable(Physics.BALL_ONLY, Physics.CHARACTERS, false)
	PhysicsService:CollisionGroupSetCollidable(Physics.BALL_ONLY, "Default", false)
	PhysicsService:CollisionGroupSetCollidable(Physics.BALL_ONLY, Physics.BALL_ONLY, false)
	PhysicsService:CollisionGroupSetCollidable(Physics.BALL_ONLY, Physics.BALL, true)
	if Config.Player.PlayersCollide == false then
		PhysicsService:CollisionGroupSetCollidable(Physics.CHARACTERS, Physics.CHARACTERS, false)
	end
end

-- Переводит все части модели в группу персонажей (и новые тоже — аксессуары догружаются позже).
function Physics.tagCharacter(character: Model)
	local function apply(instance: Instance)
		if instance:IsA("BasePart") then
			(instance :: BasePart).CollisionGroup = Physics.CHARACTERS
		end
	end
	for _, descendant in ipairs(character:GetDescendants()) do
		apply(descendant)
	end
	character.DescendantAdded:Connect(apply)
end

return Physics
