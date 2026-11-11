-- Управление. Клавиши задаются в Config.Controls; на телефоне появляются сенсорные кнопки.
-- Всё, что должно ощущаться мгновенно (рывок, анимация удара), клиент делает сам сразу,
-- а серверу отправляет запрос — тот проверит и выполнит «по-настоящему».

local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local FieldSpec = require(Shared.FieldSpec)
local Mover = require(Shared.Mover)
local Styles = require(Shared.Styles)
local Util = require(Shared.Util)
local ProcAnimator = require(script.Parent.ProcAnimator)
local State = require(script.Parent.State)

local SHOT, TACKLE, DASH, DRIBBLE = Config.Shot, Config.Tackle, Config.Dash, Config.Dribble
local CONTROLS = Config.Controls
local R = Config.Ball.Radius

local Controls = {}

Controls.charging = false
Controls.charge = 0 -- 0..1, для полоски в HUD
Controls.menuOpen = false -- HUD ставит true, пока открыто меню стилей
Controls.sprintHeld = false
Controls.onDenied = nil :: ((string, string) -> ())? -- HUD показывает, почему действие не сработало

local chargeStart = 0
local faceUntil = 0
local faceDir: Vector3? = nil
local autoRotateOff = false
local locks = {} -- защита от двойного срабатывания, пока сервер не подтвердил перезарядку
local dots = {} -- точки предпросмотра траектории

---------------------------------------------------------------------------
-- Прицеливание
---------------------------------------------------------------------------

local function cameraLook(): Vector3
	local camera = Workspace.CurrentCamera
	if camera then
		return camera.CFrame.LookVector
	end
	local root = State.root()
	return root and root.CFrame.LookVector or Vector3.new(0, 0, -1)
end

-- Куда смотрит камера, без наклона.
function Controls.aimFlat(): Vector3
	local root = State.root()
	return Util.flatUnit(cameraLook(), root and Util.flatUnit(root.CFrame.LookVector) or nil)
end

-- Направление удара: камера + базовый подъём. Смотришь выше — мяч летит выше.
function Controls.shotDirection(): Vector3
	local look = cameraLook()
	local pitch = math.deg(math.asin(math.clamp(look.Y, -1, 1)))
	local elevation = math.clamp(pitch + SHOT.BaseElevation, SHOT.MinElevation, SHOT.MaxElevation)
	return Util.withElevation(Controls.aimFlat(), elevation)
end

local function moveDirection(): Vector3
	local humanoid = State.humanoid()
	if humanoid and humanoid.MoveDirection.Magnitude > 0.1 then
		return Util.flatUnit(humanoid.MoveDirection)
	end
	return Vector3.zero
end

local function canAct(): boolean
	return State.isLive() and not State.isStunned() and not Controls.menuOpen and State.root() ~= nil
end

local function locked(key: string): boolean
	local untilTime = locks[key]
	return untilTime ~= nil and os.clock() < untilTime
end

local function lock(key: string, seconds: number)
	locks[key] = os.clock() + seconds
end

local function deny(key: string, reason: string)
	if Controls.onDenied then
		Controls.onDenied(key, reason)
	end
end

local function face(direction: Vector3, seconds: number)
	faceDir = Util.flatUnit(direction)
	faceUntil = os.clock() + seconds
end

---------------------------------------------------------------------------
-- Удар с зарядом
---------------------------------------------------------------------------

local function stopCharge(notifyServer: boolean)
	if not Controls.charging then
		return
	end
	Controls.charging = false
	Controls.charge = 0
	ProcAnimator.stop(State.character(), "ChargeHold")
	if notifyServer then
		State.send("Charge", false)
	end
end

local function beginCharge()
	if Controls.charging or not canAct() then
		return
	end
	if not State.hasBall() then
		return
	end
	Controls.charging = true
	Controls.charge = 0
	chargeStart = os.clock()
	ProcAnimator.play(State.character(), "ChargeHold")
	State.send("Charge", true)
end

local function releaseShot()
	if not Controls.charging then
		return
	end
	local charge = math.clamp((os.clock() - chargeStart) / SHOT.ChargeTime, 0, 1)
	local direction = Controls.shotDirection()
	local character = State.character()
	Controls.charging = false
	Controls.charge = 0
	ProcAnimator.stop(character, "ChargeHold")
	if State.hasBall() and canAct() then
		ProcAnimator.play(character, "Shoot")
		face(direction, 0.3)
		State.send("Shoot", direction, charge)
	else
		State.send("Charge", false)
	end
end

local function doPass(kind: string)
	if not canAct() or not State.hasBall() or locked("Pass") then
		return
	end
	lock("Pass", 0.25)
	stopCharge(false)
	local direction = Controls.aimFlat()
	ProcAnimator.play(State.character(), kind)
	face(direction, 0.25)
	State.send(kind, direction)
end

---------------------------------------------------------------------------
-- Подкат, дриблинг и рывок
---------------------------------------------------------------------------

local function doTackle()
	if not canAct() or locked("Tackle") or State.cooldown("Tackle") > 0 then
		return
	end
	if State.stamina() < TACKLE.Stamina then
		deny("Action", "НЕТ СИЛ")
		return
	end
	local root = State.root()
	if not root then
		return
	end
	local direction = moveDirection()
	if direction.Magnitude < 0.1 then
		direction = Util.flatUnit(root.CFrame.LookVector)
	end
	lock("Tackle", 0.6)
	Mover.dash(root, direction, TACKLE.Speed, TACKLE.Duration * 0.9)
	ProcAnimator.play(State.character(), "Slide")
	face(direction, TACKLE.Duration)
	State.send("Tackle", direction)
end

-- Дриблинг: короткий резкий уход с мячом в сторону движения. В этот момент подкат не проходит.
local function doDribble()
	if not canAct() or locked("Dribble") or State.cooldown("Dribble") > 0 then
		return
	end
	if State.stamina() < DRIBBLE.Stamina then
		deny("Action", "НЕТ СИЛ")
		return
	end
	local root = State.root()
	if not root then
		return
	end
	local direction = moveDirection()
	if direction.Magnitude < 0.1 then
		direction = Util.flatUnit(root.CFrame.LookVector)
	end
	lock("Dribble", 0.5)
	stopCharge(false)
	Mover.dash(root, direction, DRIBBLE.Speed, DRIBBLE.Duration)
	ProcAnimator.play(State.character(), "Dribble")
	State.send("Dribble", direction)
end

-- Одна клавиша: с мячом — дриблинг, без мяча — подкат.
local function doAction()
	if State.hasBall() then
		doDribble()
	else
		doTackle()
	end
end

local function doDash()
	if not canAct() or locked("Dash") or State.cooldown("Dash") > 0 then
		return
	end
	if State.stamina() < DASH.Stamina then
		deny("Dash", "НЕТ СИЛ")
		return
	end
	local root = State.root()
	if not root then
		return
	end
	local direction = moveDirection()
	if direction.Magnitude < 0.1 then
		direction = Controls.aimFlat()
	end
	lock("Dash", 0.5)
	stopCharge(true)
	Mover.dash(root, direction, DASH.Speed, DASH.Duration)
	ProcAnimator.play(State.character(), "Dash")
	State.send("Dash", direction)
end

---------------------------------------------------------------------------
-- Способности стиля
---------------------------------------------------------------------------

-- То, что получает функция predict способности.
local me = {}

function me.dash(direction: Vector3, speed: number, duration: number)
	local root = State.root()
	if root then
		Mover.dash(root, direction, speed, duration)
	end
end

function me.blink(direction: Vector3, distance: number)
	local root = State.root()
	if root then
		Mover.blink(root, direction, distance)
	end
end

function me.anim(name: string)
	ProcAnimator.play(State.character(), name)
end

local function doAbility(slot: number)
	if not canAct() then
		return
	end
	local ability = State.style().abilities[slot]
	if not ability then
		return
	end
	local key = "A" .. slot
	if locked(key) or State.cooldown(key) > 0 then
		return
	end
	local hasBall = State.hasBall()
	if ability.needsBall and not hasBall then
		deny(key, "НУЖЕН МЯЧ")
		return
	end
	if ability.needsNoBall and hasBall then
		deny(key, "ТОЛЬКО БЕЗ МЯЧА")
		return
	end
	if ability.ultimate and State.resonance() < Config.Resonance.Max then
		deny(key, "РЕЗОНАНС НЕ НАКОПЛЕН")
		return
	end

	lock(key, 0.7)
	stopCharge(false)
	local aim = Controls.aimFlat()
	local look = Controls.shotDirection()
	local move = moveDirection()
	if ability.predict then
		local ok, err = pcall(ability.predict, me, { aim = aim, aimLook = look, move = move, hasBall = hasBall })
		if not ok then
			warn("[Ability] predict: " .. tostring(err))
		end
	end
	if ability.needsBall then
		face(aim, 0.5)
	end
	State.send("Ability", slot, look, move)
end

---------------------------------------------------------------------------
-- Каждый кадр
---------------------------------------------------------------------------

local function hideDots()
	for _, dot in ipairs(dots) do
		dot.Transparency = 1
	end
end

-- Пунктир траектории, пока игрок держит удар.
local function updatePreview()
	if not Controls.charging then
		if #dots > 0 and dots[1].Transparency < 1 then
			hideDots()
		end
		return
	end
	local root, humanoid = State.root(), State.humanoid()
	if not root or not humanoid then
		return
	end
	if #dots == 0 then
		for i = 1, 12 do
			local dot = Instance.new("Part")
			dot.Name = "AimDot"
			dot.Shape = Enum.PartType.Ball
			dot.Size = Vector3.new(0.55, 0.55, 0.55)
			dot.Anchored = true
			dot.CanCollide = false
			dot.CanTouch = false
			dot.CanQuery = false
			dot.CastShadow = false
			dot.Material = Enum.Material.Neon
			dot.Transparency = 1
			dot.Parent = Workspace
			dots[i] = dot
		end
	end

	local style = State.style()
	local direction = Controls.shotDirection()
	local power = Util.lerp(SHOT.MinPower, SHOT.MaxPower, Controls.charge) * (style.stats.shot or 1)
	local gravity = Workspace.Gravity * Config.Ball.GravityScale
	local groundOffset = Util.groundOffset(root, humanoid)
	local start = root.Position - Vector3.new(0, groundOffset - R, 0) + Util.flatUnit(direction) * Config.Ball.HoldDistance
	local floor = FieldSpec.Origin.Y + R * 0.5
	local landed = false
	for i, dot in ipairs(dots) do
		local t = i * 0.065
		local point = start + direction * power * t - Vector3.new(0, 0.5 * gravity * t * t, 0)
		if landed or point.Y < floor then
			landed = true
			dot.Transparency = 1
		else
			dot.Color = style.color
			dot.CFrame = CFrame.new(point)
			dot.Transparency = 0.2 + i * 0.05
		end
	end
end

local function onRender()
	local humanoid, root = State.humanoid(), State.root()
	if not humanoid or not root then
		Controls.charging = false
		Controls.charge = 0
		hideDots()
		return
	end

	if Controls.charging then
		if not State.hasBall() or not canAct() then
			stopCharge(true)
		else
			Controls.charge = math.clamp((os.clock() - chargeStart) / SHOT.ChargeTime, 0, 1)
		end
	end

	-- Во время замаха и удара персонаж смотрит туда же, куда камера.
	local now = os.clock()
	if Controls.charging or now < faceUntil then
		humanoid.AutoRotate = false
		autoRotateOff = true
		local direction = Controls.charging and Controls.aimFlat() or (faceDir or Controls.aimFlat())
		local target = CFrame.lookAt(root.Position, root.Position + direction)
		root.CFrame = root.CFrame:Lerp(target, 0.35)
	elseif autoRotateOff then
		autoRotateOff = false
		humanoid.AutoRotate = true
	end

	updatePreview()
end

---------------------------------------------------------------------------
-- Привязка клавиш
---------------------------------------------------------------------------

local function toInputs(names: { string })
	local inputs = {}
	for _, name in ipairs(names) do
		local ok, key = pcall(function()
			return (Enum.KeyCode :: any)[name]
		end)
		if ok and key then
			table.insert(inputs, key)
		else
			local ok2, inputType = pcall(function()
				return (Enum.UserInputType :: any)[name]
			end)
			if ok2 and inputType then
				table.insert(inputs, inputType)
			end
		end
	end
	return inputs
end

local TOUCH_LAYOUT = {
	RS_Shoot = { "УДАР", UDim2.fromScale(0.52, 0.5) },
	RS_Pass = { "ПАС", UDim2.fromScale(0.26, 0.62) },
	RS_Lob = { "НАВЕС", UDim2.fromScale(0.26, 0.36) },
	RS_Action = { "ОТБОР/ФИНТ", UDim2.fromScale(0.52, 0.24) },
	RS_Dash = { "РЫВОК", UDim2.fromScale(0.78, 0.24) },
	RS_Sprint = { "БЕГ", UDim2.fromScale(0.02, 0.5) },
	RS_Ability1 = { "I", UDim2.fromScale(0.02, 0.1) },
	RS_Ability2 = { "II", UDim2.fromScale(0.26, 0.1) },
	RS_Ability3 = { "УЛЬТА", UDim2.fromScale(0.52, 0.0) },
}

local function bind(name: string, inputNames: { string }, handler)
	local touch = TOUCH_LAYOUT[name]
	ContextActionService:BindAction(name, handler, touch ~= nil, table.unpack(toInputs(inputNames)))
	if touch and UserInputService.TouchEnabled then
		pcall(function()
			ContextActionService:SetTitle(name, touch[1])
			ContextActionService:SetPosition(name, touch[2])
		end)
	end
end

local function onPress(fn: () -> ())
	return function(_, inputState: Enum.UserInputState)
		if inputState == Enum.UserInputState.Begin then
			fn()
		end
		return Enum.ContextActionResult.Pass
	end
end

-- Shift занят спринтом, поэтому стандартную блокировку камеры переносим на другую клавишу.
local function moveShiftLock()
	task.spawn(function()
		local scripts = State.player:WaitForChild("PlayerScripts", 10)
		local module = scripts and scripts:WaitForChild("PlayerModule", 10)
		local cameraModule = module and module:WaitForChild("CameraModule", 10)
		local mouseLock = cameraModule and cameraModule:WaitForChild("MouseLockController", 10)
		local bound = mouseLock and mouseLock:WaitForChild("BoundKeys", 10)
		if bound and bound:IsA("StringValue") then
			bound.Value = CONTROLS.ShiftLock
		end
	end)
end

function Controls.start()
	bind("RS_Shoot", CONTROLS.Shoot, function(_, inputState: Enum.UserInputState)
		if inputState == Enum.UserInputState.Begin then
			beginCharge()
		elseif inputState == Enum.UserInputState.End then
			releaseShot()
		elseif inputState == Enum.UserInputState.Cancel then
			stopCharge(true)
		end
		return Enum.ContextActionResult.Pass
	end)

	bind(
		"RS_Pass",
		CONTROLS.Pass,
		onPress(function()
			doPass("Pass")
		end)
	)
	bind(
		"RS_Lob",
		CONTROLS.Lob,
		onPress(function()
			doPass("Lob")
		end)
	)
	bind("RS_Action", CONTROLS.Action, onPress(doAction))
	bind("RS_Dash", CONTROLS.Dash, onPress(doDash))
	-- Способности есть только у стилей; пока стили отключены, клавиши Z/X/C свободны.
	if Styles.enabled then
		for slot = 1, 3 do
			bind(
				"RS_Ability" .. slot,
				(CONTROLS :: any)["Ability" .. slot],
				onPress(function()
					doAbility(slot)
				end)
			)
		end
	end

	-- Бег привязан с высоким приоритетом и «поглощает» клавишу: иначе Shift заодно
	-- переключал бы стандартную блокировку камеры Roblox.
	local function onSprint(_, inputState: Enum.UserInputState, input: InputObject)
		local isTouch = input and input.UserInputType == Enum.UserInputType.Touch
		if isTouch then
			-- На телефоне бег — переключатель.
			if inputState == Enum.UserInputState.Begin then
				Controls.sprintHeld = not Controls.sprintHeld
				State.send("Sprint", Controls.sprintHeld)
			end
		elseif inputState == Enum.UserInputState.Begin then
			Controls.sprintHeld = true
			State.send("Sprint", true)
		elseif inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
			Controls.sprintHeld = false
			State.send("Sprint", false)
		end
		return Enum.ContextActionResult.Sink
	end
	ContextActionService:BindActionAtPriority(
		"RS_Sprint",
		onSprint,
		true,
		Enum.ContextActionPriority.High.Value,
		table.unpack(toInputs(CONTROLS.Sprint))
	)
	if UserInputService.TouchEnabled then
		pcall(function()
			ContextActionService:SetTitle("RS_Sprint", TOUCH_LAYOUT.RS_Sprint[1])
			ContextActionService:SetPosition("RS_Sprint", TOUCH_LAYOUT.RS_Sprint[2])
		end)
	end

	-- После респауна сервер создаёт персонажа заново: напоминаем, что бег зажат.
	State.player.CharacterAdded:Connect(function()
		Controls.charging = false
		autoRotateOff = false
		task.wait(1)
		if Controls.sprintHeld then
			State.send("Sprint", true)
		end
	end)

	RunService:BindToRenderStep("ResonanceControls", Enum.RenderPriority.Character.Value + 1, onRender)
	moveShiftLock()
end

return Controls
