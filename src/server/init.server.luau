--!strict
-- QWOP Race -- server game manager.
--
-- Runs a continuous race loop for everyone in the server:
--   Intermission -> Countdown -> Racing -> Results -> (repeat)
-- Every player gets a rig in their own lane; first across the finish wins.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local RigBuilder = require(script.RigBuilder)

Players.CharacterAutoLoads = false -- we spawn our own rigs, not default avatars

local FINISH_X = Config.StartX + Config.Race.DistanceStuds

-- ===== Remotes =====
local remotesFolder = Instance.new("Folder")
remotesFolder.Name = "Remotes"
remotesFolder.Parent = ReplicatedStorage

local raceStateEvent = Instance.new("RemoteEvent")
raceStateEvent.Name = Config.Remotes.RaceState
raceStateEvent.Parent = remotesFolder

local resetEvent = Instance.new("RemoteEvent")
resetEvent.Name = Config.Remotes.RequestReset
resetEvent.Parent = remotesFolder

-- ===== Track =====
local function buildTrack()
	local track = Instance.new("Folder")
	track.Name = "Track"
	track.Parent = workspace

	local function marker(name: string, x: number, color: Color3)
		local p = Instance.new("Part")
		p.Name = name
		p.Anchored = true
		p.CanCollide = false
		p.Size = Vector3.new(1, 30, 60)
		p.Position = Vector3.new(x, Config.GroundY + 15, 0)
		p.Color = color
		p.Transparency = 0.3
		p.Material = Enum.Material.Neon
		p.Parent = track
	end

	marker("StartLine", Config.StartX, Color3.fromRGB(120, 200, 255))
	marker("FinishLine", FINISH_X, Color3.fromRGB(120, 255, 140))

	-- Distance markers every 25 studs.
	for x = 25, Config.Race.DistanceStuds - 1, 25 do
		local tick = Instance.new("Part")
		tick.Name = "Mark_" .. x
		tick.Anchored = true
		tick.CanCollide = false
		tick.Size = Vector3.new(0.3, 0.2, 60)
		tick.Position = Vector3.new(Config.StartX + x, Config.GroundY + 0.1, 0)
		tick.Color = Color3.fromRGB(255, 255, 255)
		tick.Transparency = 0.5
		tick.Parent = track
	end
end
buildTrack()

-- ===== Runner registry =====
type Runner = {
	player: Player,
	model: Model,
	laneIndex: number,
	laneZ: number,
	finished: boolean,
	finishTime: number?,
}

local runners: { [Player]: Runner } = {}
local nextLane = 0

local function laneZFor(index: number): number
	-- Lanes fan out from center: 0, +s, -s, +2s, -2s, ...
	local step = math.ceil(index / 2)
	local sign = (index % 2 == 0) and 1 or -1
	return sign * step * Config.Lane.Spacing
end

local function spawnRig(runner: Runner)
	if runner.model and runner.model.Parent then
		runner.model:Destroy()
	end
	local model = RigBuilder.build(runner.player, runner.laneZ)
	model.Parent = workspace
	runner.model = model
	runner.finished = false
	runner.finishTime = nil
end

local function addRunner(player: Player)
	local laneIndex = nextLane
	nextLane += 1
	local runner: Runner = {
		player = player,
		model = nil :: any,
		laneIndex = laneIndex,
		laneZ = laneZFor(laneIndex),
		finished = false,
		finishTime = nil,
	}
	runners[player] = runner
	spawnRig(runner)
end

-- ===== Race state =====
local STATE = {
	Intermission = "Intermission",
	Countdown = "Countdown",
	Racing = "Racing",
	Results = "Results",
}

local current = {
	state = STATE.Intermission,
	endsAt = 0, -- os.clock() time the current phase ends (for client timers)
	results = {} :: { { userId: number, name: string, place: number } },
}

local function broadcast()
	raceStateEvent:FireAllClients({
		state = current.state,
		timeLeft = math.max(0, current.endsAt - os.clock()),
		finishX = FINISH_X,
		startX = Config.StartX,
		results = current.results,
	})
end

local function setState(state: string, duration: number)
	current.state = state
	current.endsAt = os.clock() + duration
	broadcast()
end

local function freezeAll(anchored: boolean)
	for _, r in runners do
		if r.model and r.model.Parent then
			RigBuilder.setAnchored(r.model, anchored)
		end
	end
end

local function respawnAll()
	for _, r in runners do
		spawnRig(r)
	end
end

-- Wait helper that keeps broadcasting time updates so client countdowns stay live.
local function phase(state: string, duration: number)
	setState(state, duration)
	local t = 0
	while t < duration do
		local dt = task.wait(0.25)
		t += dt
		broadcast()
	end
end

-- ===== Main race loop =====
task.spawn(function()
	while true do
		-- Intermission: wait for players.
		current.results = {}
		respawnAll()
		freezeAll(true)
		setState(STATE.Intermission, Config.Race.IntermissionSeconds)
		repeat
			task.wait(0.5)
			broadcast()
		until (#Players:GetPlayers() >= Config.Race.MinPlayers and os.clock() >= current.endsAt)
			or os.clock() >= current.endsAt + 30

		if #Players:GetPlayers() == 0 then
			continue
		end

		-- Fresh rigs at the line, frozen for the countdown.
		respawnAll()
		freezeAll(true)
		phase(STATE.Countdown, Config.Race.CountdownSeconds)

		-- GO: unfreeze and hand control to each owner.
		for _, r in runners do
			if r.model and r.model.Parent then
				RigBuilder.giveOwnership(r.model, r.player)
			end
		end

		-- Racing: tick until everyone finishes or we time out.
		setState(STATE.Racing, Config.Race.RaceTimeoutSeconds)
		local place = 0
		local raceConn: RBXScriptConnection
		raceConn = RunService.Heartbeat:Connect(function()
			for _, r in runners do
				local model = r.model
				if not model or not model.Parent or not model.PrimaryPart then
					continue
				end
				local pos = model.PrimaryPart.Position
				-- Fell off the world -> respawn at lane start (out of the race fairly).
				if pos.Y < Config.Race.FallResetY then
					spawnRig(r)
					RigBuilder.setAnchored(r.model, false)
					RigBuilder.giveOwnership(r.model, r.player)
				elseif not r.finished and pos.X >= FINISH_X then
					r.finished = true
					r.finishTime = os.clock()
					place += 1
					table.insert(current.results, {
						userId = r.player.UserId,
						name = r.player.DisplayName,
						place = place,
					})
					broadcast()
				end
			end
		end)

		local raceStart = os.clock()
		repeat
			task.wait(0.25)
			broadcast()
			local allDone = true
			for _, r in runners do
				if not r.finished then
					allDone = false
					break
				end
			end
		until allDone or (os.clock() - raceStart) >= Config.Race.RaceTimeoutSeconds
			or #Players:GetPlayers() == 0
		raceConn:Disconnect()

		-- Results.
		phase(STATE.Results, Config.Race.ResultsSeconds)
	end
end)

-- ===== Players & remotes =====
Players.PlayerAdded:Connect(function(player)
	addRunner(player)
end)

Players.PlayerRemoving:Connect(function(player)
	local r = runners[player]
	if r and r.model then
		r.model:Destroy()
	end
	runners[player] = nil
end)

-- Allow a player to respawn their own rig (R) during a race if they get stuck.
resetEvent.OnServerEvent:Connect(function(player)
	if current.state ~= STATE.Racing then
		return
	end
	local r = runners[player]
	if not r or r.finished then
		return
	end
	spawnRig(r)
	RigBuilder.setAnchored(r.model, false)
	RigBuilder.giveOwnership(r.model, r.player)
end)

print("[QWOP Race] server ready -- finish line at X =", FINISH_X)
