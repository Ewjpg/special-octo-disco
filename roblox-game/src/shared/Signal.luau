-- Простейший сигнал: Connect / Fire. Нужен, чтобы серверные модули не зависели друг от друга напрямую.

local Signal = {}
Signal.__index = Signal

function Signal.new()
	return setmetatable({ _handlers = {} }, Signal)
end

function Signal:Connect(fn)
	table.insert(self._handlers, fn)
	local handlers = self._handlers
	return {
		Disconnect = function()
			local index = table.find(handlers, fn)
			if index then
				table.remove(handlers, index)
			end
		end,
	}
end

function Signal:Fire(...)
	for _, fn in ipairs(table.clone(self._handlers)) do
		task.spawn(fn, ...)
	end
end

return Signal
