-- Точка входа клиента.

local StarterGui = game:GetService("StarterGui")

local Client = script.Parent

local ProcAnimator = require(Client.ProcAnimator)
local Fx = require(Client.Fx)
local FxEvents = require(Client.FxEvents)
local BallVisuals = require(Client.BallVisuals)
local Controls = require(Client.Controls)
local Hud = require(Client.Hud)

-- Рюкзак и полоска здоровья в футболе не нужны.
for _, coreGui in ipairs({ Enum.CoreGuiType.Backpack, Enum.CoreGuiType.Health, Enum.CoreGuiType.EmotesMenu }) do
	pcall(function()
		StarterGui:SetCoreGuiEnabled(coreGui, false)
	end)
end

ProcAnimator.start()
Fx.start()
FxEvents.start()
BallVisuals.start()
Controls.start()
Hud.start()
