-- Считает позу анимации в заданный момент времени. Чистая математика — без доступа к персонажу.

local AnimSampler = {}

local EASE = {}

function EASE.linear(a: number): number
	return a
end

function EASE.quadIn(a: number): number
	return a * a
end

function EASE.quadOut(a: number): number
	return 1 - (1 - a) * (1 - a)
end

function EASE.quadInOut(a: number): number
	if a < 0.5 then
		return 2 * a * a
	end
	return 1 - (-2 * a + 2) ^ 2 / 2
end

function EASE.sine(a: number): number
	return 0.5 - math.cos(a * math.pi) / 2
end

function EASE.backOut(a: number): number
	local c1 = 1.70158
	local c3 = c1 + 1
	return 1 + c3 * (a - 1) ^ 3 + c1 * (a - 1) ^ 2
end

-- Заполняет out позой: out[joint] = { rx, ry, rz, px, py, pz }.
function AnimSampler.sample(anim, time: number, out: { [string]: { number } })
	local keys = anim.keys
	local count = #keys
	local first, last = keys[1], keys[count]

	local from, to, alpha = first, first, 0
	if time >= last.t then
		from, to, alpha = last, last, 0
	elseif time > first.t then
		for i = 1, count - 1 do
			local a, b = keys[i], keys[i + 1]
			if time >= a.t and time < b.t then
				local span = b.t - a.t
				local raw = span > 0 and (time - a.t) / span or 1
				local ease = EASE[b.ease or "linear"] or EASE.linear
				from, to, alpha = a, b, ease(raw)
				break
			end
		end
	end

	for _, joint in ipairs(anim.joints) do
		local a, b = from.pose[joint], to.pose[joint]
		local v = out[joint]
		if not v then
			v = { 0, 0, 0, 0, 0, 0 }
			out[joint] = v
		end
		for i = 1, 6 do
			v[i] = a[i] + (b[i] - a[i]) * alpha
		end
	end
	return out
end

-- Поза сустава -> CFrame. pivot (необязательно) — точка { x, y, z }, вокруг которой идёт поворот.
function AnimSampler.toCFrame(v: { number }, pivot: { number }?): CFrame
	local rotation = CFrame.Angles(math.rad(v[1]), math.rad(v[2]), math.rad(v[3]))
	if pivot then
		local offset = Vector3.new(pivot[1], pivot[2], pivot[3])
		rotation = CFrame.new(offset) * rotation * CFrame.new(-offset)
	end
	return CFrame.new(v[4], v[5], v[6]) * rotation
end

return AnimSampler
