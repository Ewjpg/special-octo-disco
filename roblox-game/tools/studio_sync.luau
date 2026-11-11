-- Studio side of tools/studio_sync.py: run in the edit DataModel while src is served on 127.0.0.1:48902.
-- Creates or updates every script from src/_manifest.json; folders without an init become Folders.
local Http = game:GetService("HttpService")
local BASE = "http://127.0.0.1:48902/"
local manifest = Http:JSONDecode(Http:GetAsync(BASE .. "_manifest.json", true))
local changed, created = 0, 0

local function ensure(path, lastClass)
	local node = game:GetService(path[1])
	for i = 2, #path do
		local child = node:FindFirstChild(path[i])
		local wanted = i == #path and lastClass or nil
		if child and wanted and child.ClassName ~= wanted then
			-- a folder that became a module (init.luau), or the other way round: keep the children
			local replacement = Instance.new(wanted)
			replacement.Name = child.Name
			for _, c in ipairs(child:GetChildren()) do
				c.Parent = replacement
			end
			child:Destroy()
			replacement.Parent = node
			child = replacement
		end
		if not child then
			child = Instance.new(wanted or "Folder")
			child.Name = path[i]
			child.Parent = node
			created += 1
		end
		node = child
	end
	return node
end

for _, entry in ipairs(manifest) do
	local script = ensure(entry.path, entry.class)
	local source = Http:GetAsync(BASE .. entry.file, true)
	if script.Source ~= source then
		script.Source = source
		changed += 1
	end
end
return string.format("%d scripts, %d changed, %d created", #manifest, changed, created)
