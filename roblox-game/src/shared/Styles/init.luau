-- Реестр стилей. Каждый модуль в этой папке — один стиль (один OC).
-- Чтобы добавить свой: скопируй _Template, переименуй, поменяй id/name/способности.
-- Модули, имя которых начинается с "_", не загружаются.

local Styles = {}

Styles.list = {} -- стили, доступные в меню выбора (по порядку order)
Styles.byId = {}

for _, child in ipairs(script:GetChildren()) do
	if child:IsA("ModuleScript") and string.sub(child.Name, 1, 1) ~= "_" then
		local style = require(child) :: any
		style.id = style.id or child.Name
		style.stats = style.stats or {}
		style.abilities = style.abilities or {}
		Styles.byId[style.id] = style
		if style.selectable ~= false then
			table.insert(Styles.list, style)
		end
	end
end

table.sort(Styles.list, function(a, b)
	return (a.order or 99) < (b.order or 99)
end)

Styles.default = Styles.list[1].id

function Styles.get(id: string?)
	return Styles.byId[id or Styles.default] or Styles.byId[Styles.default]
end

return Styles
