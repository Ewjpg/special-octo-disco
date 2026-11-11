-- Компилирует каждый .luau файл из src и сообщает о синтаксических ошибках.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")

local failed = 0
local count = 0
local function walk(dir)
	for _, name in ipairs(fs.readDir(dir)) do
		local path = dir .. "/" .. name
		if fs.isDir(path) then
			walk(path)
		elseif string.sub(name, -5) == ".luau" then
			count += 1
			local ok, err = pcall(luau.compile, fs.readFile(path))
			if not ok then
				failed += 1
				print("SYNTAX " .. path .. ": " .. tostring(err))
			end
		end
	end
end
walk(process.args[1] or "src")
print(string.format("%d files, %d with syntax errors", count, failed))
if failed > 0 then
	process.exit(1)
end
