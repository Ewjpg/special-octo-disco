-- Создаёт RemoteEvent'ы и даёт короткие функции для отправки эффектов клиентам.
--   Action: клиент -> сервер (удар, пас, подкат, способность...)
--   Fx:     сервер -> клиенты (анимации, вспышки, баннеры)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = {}

local folder = Instance.new("Folder")
folder.Name = "Remotes"

local action = Instance.new("RemoteEvent")
action.Name = "Action"
action.Parent = folder

local fx = Instance.new("RemoteEvent")
fx.Name = "Fx"
fx.Parent = folder

folder.Parent = ReplicatedStorage

Net.Action = action
Net.Fx = fx

function Net.fx(name: string, payload: { [string]: any }?)
	fx:FireAllClients(name, payload or {})
end

function Net.fxTo(player: Player, name: string, payload: { [string]: any }?)
	fx:FireClient(player, name, payload or {})
end

return Net
