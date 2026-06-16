--!strict
-- QWOP Race -- client.
--
-- Responsibilities:
--   * read Q/W/O/P (+R) and drive the local runner's hinge motors
--   * run the adaptive side-scroller camera (frame the whole pack, fall back to
--     following yourself when the pack spreads too far)
--   * draw the HUD: race phase / countdown, your distance, and a live leaderboard

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
camera.CameraType = Enum.CameraType.Scriptable

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local raceStateEvent = remotes:WaitForChild(Config.Remotes.RaceState) :: RemoteEvent
local resetEvent = remotes:WaitForChild(Config.Remotes.RequestReset) :: RemoteEvent

-- ===== Input state =====
local held: { [string]: boolean } = { Q = false, W = false, O = false, P = false }

local keyMap = Config.Keys :: { [string]: Enum.KeyCode }
local keyByEnum: { [Enum.KeyCode]: string } = {}
for label, code in keyMap do
	if label ~= "Reset" then
		keyByEnum[code] = label
	end
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if input.KeyCode == Config.Keys.Reset then
		resetEvent:FireServer()
		return
	end
	local label = keyByEnum[input.KeyCode]
	if label then
		held[label] = true
	end
end)

UserInputService.InputEnded:Connect(function(input)
	local label = keyByEnum[input.KeyCode]
	if label then
		held[label] = false
	end
end)

-- ===== Finding the local rig =====
local function rigOwner(model: Model): number?
	return model:GetAttribute(Config.OwnerAttribute) :: number?
end

local function findOwnRig(): Model?
	for _, model in CollectionService:GetTagged(Config.RigTag) do
		if model:IsA("Model") and rigOwner(model) == player.UserId then
			return model
		end
	end
	return nil
end

-- Cache of this rig's four driven hinges.
local function getHinges(rig: Model): { [string]: HingeConstraint }?
	local folder = rig:FindFirstChild("Hinges")
	if not folder then
		return nil
	end
	local h = {}
	for _, name in { "RightHip", "LeftHip", "RightKnee", "LeftKnee" } do
		local hinge = folder:FindFirstChild(name)
		if not hinge or not hinge:IsA("HingeConstraint") then
			return nil
		end
		h[name] = hinge
	end
	return h
end

-- ===== Hinge control =====
-- Each frame, set every driven hinge's target angular velocity from held keys.
local function driveHinges(hinges: { [string]: HingeConstraint })
	for hingeName, hinge in hinges do
		local drive = Config.Drive[hingeName]
		local target = 0
		if drive then
			for key, sign in drive do
				if held[key] then
					local speed = (hingeName == "RightKnee" or hingeName == "LeftKnee")
							and Config.Knee.TargetSpeed
						or Config.Hip.TargetSpeed
					target += sign * speed
				end
			end
		end
		hinge.AngularVelocity = target
	end
end

-- ===== Camera =====
local function updateCamera(dt: number, ownRig: Model?)
	-- Gather X positions of every live runner to frame the pack.
	local minX, maxX = math.huge, -math.huge
	local ownX: number? = nil
	for _, model in CollectionService:GetTagged(Config.RigTag) do
		if model:IsA("Model") and model.PrimaryPart then
			local x = model.PrimaryPart.Position.X
			minX = math.min(minX, x)
			maxX = math.max(maxX, x)
			if model == ownRig then
				ownX = x
			end
		end
	end
	if minX == math.huge then
		return -- no runners yet
	end

	local cfg = Config.Camera
	local span = maxX - minX
	-- Distance needed so `span + margin` fits the horizontal field of view.
	local halfFovRad = math.rad(camera.FieldOfView / 2)
	local aspect = camera.ViewportSize.X / math.max(1, camera.ViewportSize.Y)
	local neededDist = ((span + cfg.FieldMargin) / 2) / (math.tan(halfFovRad) * aspect)
	local dist = math.clamp(math.max(neededDist, cfg.BaseDistance), cfg.BaseDistance, cfg.MaxDistance)

	-- Center on the pack; if it's too spread to fit, keep yourself centered.
	local centerX = (minX + maxX) / 2
	if neededDist > cfg.MaxDistance and ownX then
		centerX = ownX
	end

	local target = Vector3.new(centerX, Config.GroundY + cfg.Height, 0)
	local goalCFrame = CFrame.lookAt(target + Vector3.new(0, 0, dist), target)

	local alpha = math.clamp(dt * cfg.Smoothing, 0, 1)
	camera.CFrame = camera.CFrame:Lerp(goalCFrame, alpha)
end

-- ===== HUD =====
local gui = Instance.new("ScreenGui")
gui.Name = "QWOPHud"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = player:WaitForChild("PlayerGui")

local function label(name: string, pos: UDim2, size: UDim2, scale: number, align: Enum.TextXAlignment): TextLabel
	local t = Instance.new("TextLabel")
	t.Name = name
	t.BackgroundTransparency = 1
	t.Position = pos
	t.Size = size
	t.Font = Enum.Font.GothamBold
	t.TextScaled = false
	t.TextSize = scale
	t.TextColor3 = Color3.new(1, 1, 1)
	t.TextStrokeTransparency = 0.4
	t.TextXAlignment = align
	t.TextYAlignment = Enum.TextYAlignment.Top
	t.Parent = gui
	return t
end

local statusLabel =
	label("Status", UDim2.new(0.5, -300, 0, 12), UDim2.fromOffset(600, 60), 42, Enum.TextXAlignment.Center)
local distanceLabel =
	label("Distance", UDim2.new(0.5, -300, 0, 70), UDim2.fromOffset(600, 30), 24, Enum.TextXAlignment.Center)
local boardLabel = label("Board", UDim2.fromOffset(16, 120), UDim2.fromOffset(320, 400), 20, Enum.TextXAlignment.Left)
local controlsLabel =
	label("Controls", UDim2.new(0.5, -300, 1, -44), UDim2.fromOffset(600, 36), 20, Enum.TextXAlignment.Center)
controlsLabel.Text = "Q / W  thighs      O / P  calves      R  reset"
controlsLabel.TextColor3 = Color3.fromRGB(200, 200, 200)

local function meters(studs: number): number
	return math.max(0, math.floor(studs * Config.MetersPerStud * 10) / 10)
end

-- Latest race snapshot from the server.
local race = {
	state = "Intermission",
	timeLeft = 0,
	finishX = Config.StartX + Config.Race.DistanceStuds,
	startX = Config.StartX,
	results = {} :: { { userId: number, name: string, place: number } },
}

raceStateEvent.OnClientEvent:Connect(function(data)
	race = data
end)

local function placeOf(userId: number): number?
	for _, r in race.results do
		if r.userId == userId then
			return r.place
		end
	end
	return nil
end

local function updateHud(ownRig: Model?)
	-- Status / countdown line.
	local s = race.state
	if s == "Countdown" then
		statusLabel.Text = string.format("GET READY  %d", math.ceil(race.timeLeft))
		statusLabel.TextColor3 = Color3.fromRGB(255, 220, 120)
	elseif s == "Racing" then
		statusLabel.Text = "RACE!"
		statusLabel.TextColor3 = Color3.fromRGB(140, 255, 150)
	elseif s == "Results" then
		local winner = race.results[1]
		statusLabel.Text = winner and (winner.name .. " WINS!") or "No finishers"
		statusLabel.TextColor3 = Color3.fromRGB(255, 230, 140)
	else
		statusLabel.Text = "WAITING FOR RUNNERS…"
		statusLabel.TextColor3 = Color3.fromRGB(180, 200, 255)
	end

	-- Your distance.
	local total = race.finishX - race.startX
	if ownRig and ownRig.PrimaryPart then
		local d = ownRig.PrimaryPart.Position.X - race.startX
		distanceLabel.Text = string.format("%.1f m  /  %.1f m", meters(d), meters(total))
	else
		distanceLabel.Text = ""
	end

	-- Leaderboard: sort all live runners by distance (finishers ranked by place).
	type Row = { name: string, dist: number, place: number? }
	local rows: { Row } = {}
	for _, model in CollectionService:GetTagged(Config.RigTag) do
		if model:IsA("Model") and model.PrimaryPart then
			local uid = rigOwner(model)
			local p = uid and Players:GetPlayerByUserId(uid) or nil
			table.insert(rows, {
				name = p and p.DisplayName or "??",
				dist = model.PrimaryPart.Position.X - race.startX,
				place = uid and placeOf(uid) or nil,
			})
		end
	end
	table.sort(rows, function(a, b)
		if (a.place ~= nil) ~= (b.place ~= nil) then
			return a.place ~= nil -- finishers first
		end
		if a.place and b.place then
			return a.place < b.place
		end
		return a.dist > b.dist
	end)

	local lines = { "LEADERBOARD" }
	for i, row in rows do
		local tag = row.place and ("#" .. row.place) or string.format("%.0fm", meters(row.dist))
		table.insert(lines, string.format("%d. %s  —  %s", i, row.name, tag))
	end
	boardLabel.Text = table.concat(lines, "\n")
end

-- ===== Main loop =====
RunService.RenderStepped:Connect(function(dt)
	local ownRig = findOwnRig()
	if ownRig then
		local hinges = getHinges(ownRig)
		if hinges then
			driveHinges(hinges)
		end
	end
	updateCamera(dt, ownRig)
	updateHud(ownRig)
end)

print("[QWOP Race] client ready")
