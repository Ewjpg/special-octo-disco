-- Мелкая математика, общая для сервера и клиента.

local Util = {}

local FORWARD = Vector3.new(0, 0, -1)

function Util.flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

function Util.unit(v: Vector3, fallback: Vector3?): Vector3
	if v.Magnitude > 1e-4 then
		return v.Unit
	end
	return fallback or FORWARD
end

function Util.flatUnit(v: Vector3, fallback: Vector3?): Vector3
	return Util.unit(Util.flat(v), fallback)
end

function Util.lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- Проверка вектора, пришедшего от клиента.
function Util.isVector(v: any): boolean
	if typeof(v) ~= "Vector3" then
		return false
	end
	local m = v.Magnitude
	return m == m and m < 1e6
end

-- Горизонтальное направление + подъём в градусах.
function Util.withElevation(flatDir: Vector3, degrees: number): Vector3
	local rad = math.rad(degrees)
	local dir = Util.flatUnit(flatDir)
	return (dir * math.cos(rad) + Vector3.new(0, math.sin(rad), 0)).Unit
end

function Util.elevationOf(dir: Vector3): number
	return math.deg(math.asin(math.clamp(Util.unit(dir).Y, -1, 1)))
end

-- Угол между двумя направлениями в градусах.
function Util.angleBetween(a: Vector3, b: Vector3): number
	return math.deg(math.acos(math.clamp(Util.unit(a):Dot(Util.unit(b)), -1, 1)))
end

-- Ближайшая к p точка на отрезке a-b.
function Util.closestOnSegment(a: Vector3, b: Vector3, p: Vector3): Vector3
	local ab = b - a
	local len2 = ab:Dot(ab)
	if len2 < 1e-6 then
		return a
	end
	local t = math.clamp((p - a):Dot(ab) / len2, 0, 1)
	return a + ab * t
end

-- Повернуть горизонтальный вектор вокруг вертикали (градусы, + = влево).
function Util.rotateY(v: Vector3, degrees: number): Vector3
	local rad = math.rad(degrees)
	local c, s = math.cos(rad), math.sin(rad)
	return Vector3.new(v.X * c + v.Z * s, v.Y, -v.X * s + v.Z * c)
end

-- Вектор вправо от направления движения (на плоскости).
function Util.rightOf(dir: Vector3): Vector3
	local d = Util.flatUnit(dir)
	return Vector3.new(-d.Z, 0, d.X)
end

-- Расстояние от центра HumanoidRootPart до земли. У R6 HipHeight равен 0, а ноги — 2 студа.
function Util.groundOffset(root: BasePart, humanoid: Humanoid): number
	local legs = humanoid.RigType == Enum.HumanoidRigType.R6 and 2 or humanoid.HipHeight
	return root.Size.Y / 2 + legs
end

-- Верхний регистр с поддержкой кириллицы (string.upper понимает только латиницу).
function Util.upper(text: string): string
	local out = {}
	for _, code in utf8.codes(text) do
		if code >= 0x430 and code <= 0x44F then
			code -= 0x20
		elseif code == 0x451 then
			code = 0x401 -- ё -> Ё
		elseif code >= 97 and code <= 122 then
			code -= 32
		end
		table.insert(out, utf8.char(code))
	end
	return table.concat(out)
end

function Util.easeOutQuad(t: number): number
	return 1 - (1 - t) * (1 - t)
end

return Util
