-- Размеры поля. Используется и сервером (постройка, голы), и клиентом (прицел, боты).
-- Поле лежит вдоль оси X: ворота HOME на -X, ворота AWAY на +X. Верх газона = Origin.Y.

local FieldSpec = {}

FieldSpec.Origin = Vector3.new(0, 0, 0)

FieldSpec.Length = 600
FieldSpec.Width = 380
FieldSpec.HalfLength = FieldSpec.Length / 2
FieldSpec.HalfWidth = FieldSpec.Width / 2

-- Зона за линиями до бортов: мяч не уходит в аут, а отскакивает от борта.
FieldSpec.EndMargin = 24
FieldSpec.SideMargin = 16
FieldSpec.WallHeight = 80

FieldSpec.GoalWidth = 40
FieldSpec.GoalHeight = 14
FieldSpec.GoalDepth = 10
FieldSpec.PostRadius = 0.6

FieldSpec.PenaltyDepth = 100
FieldSpec.PenaltyWidth = 210
FieldSpec.GoalAreaDepth = 36
FieldSpec.GoalAreaWidth = 108
FieldSpec.PenaltySpot = 66
FieldSpec.PenaltyArc = 45
FieldSpec.CenterRadius = 55
FieldSpec.LineWidth = 1.4

-- Центр линии ворот на уровне газона. side: -1 или 1.
function FieldSpec.goalCenter(side: number): Vector3
	return FieldSpec.Origin + Vector3.new(side * FieldSpec.HalfLength, 0, 0)
end

-- Куда атакует команда, которая защищает ворота side.
function FieldSpec.attackDir(side: number): Vector3
	return Vector3.new(-side, 0, 0)
end

-- Точка относительно своих ворот: forward — от ворот к центру, lateral — вбок.
function FieldSpec.fromOwnGoal(side: number, forward: number, lateral: number): Vector3
	return FieldSpec.Origin + Vector3.new(side * (FieldSpec.HalfLength - forward), 0, lateral)
end

-- Ограничить точку игровой зоной (внутри бортов).
function FieldSpec.clampToArena(pos: Vector3, pad: number?): Vector3
	local p = pad or 0
	local rel = pos - FieldSpec.Origin
	local maxX = FieldSpec.HalfLength + FieldSpec.EndMargin - p
	local maxZ = FieldSpec.HalfWidth + FieldSpec.SideMargin - p
	return FieldSpec.Origin + Vector3.new(math.clamp(rel.X, -maxX, maxX), rel.Y, math.clamp(rel.Z, -maxZ, maxZ))
end

-- Мяч в створе ворот? Возвращает сторону ворот (-1/1) или nil.
function FieldSpec.goalSideAt(pos: Vector3, ballRadius: number): number?
	local rel = pos - FieldSpec.Origin
	local ax = math.abs(rel.X)
	if ax < FieldSpec.HalfLength + ballRadius * 0.6 then
		return nil
	end
	if ax > FieldSpec.HalfLength + FieldSpec.GoalDepth + 4 then
		return nil
	end
	if math.abs(rel.Z) > FieldSpec.GoalWidth / 2 - FieldSpec.PostRadius then
		return nil
	end
	if rel.Y > FieldSpec.GoalHeight or rel.Y < -3 then
		return nil
	end
	return rel.X > 0 and 1 or -1
end

return FieldSpec
