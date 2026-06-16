--!strict
-- Shared tuning constants for the QWOP-style runner.
-- Server (RigBuilder) and client (input/control) both read from here so the
-- rig geometry and the control mapping always agree.

local Config = {}

-- ===== World =====
Config.GroundY = 0 -- top surface of the baseplate (Baseplate is at y=-10, size 20)
Config.StartX = 0 -- runners spawn at this X and run toward +X
Config.MetersPerStud = 0.5 -- how studs are reported as "meters" on the HUD

-- ===== Race =====
Config.Race = {
	DistanceStuds = 150, -- finish line is StartX + DistanceStuds
	CountdownSeconds = 3,
	IntermissionSeconds = 6, -- wait between races / for players to gather
	ResultsSeconds = 8, -- how long the winner screen stays up
	RaceTimeoutSeconds = 120, -- race ends even if nobody finishes
	MinPlayers = 1, -- start a race once at least this many are present
	FallResetY = -8, -- a runner that drops below this is respawned at its lane start
}

-- Players are placed in parallel Z lanes so rigs never collide and all stay
-- visible from the side camera.
Config.Lane = {
	Spacing = 6, -- studs between lane centers
}

-- ===== Camera (client side-scroller) =====
Config.Camera = {
	Height = 5, -- studs above ground the camera looks at
	BaseDistance = 28, -- Z distance when runners are bunched
	MaxDistance = 80, -- clamp when the pack spreads out
	FieldMargin = 18, -- extra studs of horizontal headroom around the pack
	Smoothing = 6, -- higher = snappier camera follow
}

-- Names of the RemoteEvents created under ReplicatedStorage at runtime.
Config.Remotes = {
	RaceState = "RaceState", -- server -> clients: broadcast race phase + finish order
	RequestReset = "RequestReset", -- client -> server: respawn my rig (R)
}

-- CollectionService tag + attribute used to find rigs on the client.
Config.RigTag = "Runner"
Config.OwnerAttribute = "OwnerUserId"
Config.LaneAttribute = "LaneZ"

-- ===== Rig part sizes (studs) Vector3(X = forward, Y = up, Z = sideways) =====
Config.Sizes = {
	Torso = Vector3.new(0.8, 2.0, 0.8),
	Head = Vector3.new(0.9, 0.9, 0.9),
	Thigh = Vector3.new(0.5, 1.6, 0.5),
	Calf = Vector3.new(0.45, 1.5, 0.45),
	Foot = Vector3.new(1.0, 0.3, 0.5),
}

-- Legs are offset along Z so the left/right limbs sit in parallel planes and
-- never collide with each other while still reading clearly from the side cam.
Config.LegZOffset = 0.3 -- RightLeg = -offset, LeftLeg = +offset

-- ===== Joint motor behaviour =====
-- Hinges are driven as velocity motors: while a key is held we target a
-- non-zero angular velocity; otherwise we target 0 (limited torque lets gravity
-- still bend the joint, which is what gives QWOP its wobble).
Config.Hip = {
	MotorMaxTorque = 6000,
	MotorMaxAcceleration = 200,
	TargetSpeed = 5.0, -- rad/s while a thigh key is held
	LimitLow = -80, -- degrees
	LimitHigh = 80,
}

Config.Knee = {
	MotorMaxTorque = 4500,
	MotorMaxAcceleration = 200,
	TargetSpeed = 6.0, -- rad/s while a calf key is held
	-- Knees should only flex one way (calf swings back, never hyperextend).
	-- If a knee bends the wrong way in Studio, flip FlexSign and the limits.
	LimitLow = -130,
	LimitHigh = 5,
	FlexSign = -1, -- direction that bends the knee
}

-- ===== Plane lock =====
-- Keeps the torso (and therefore the whole hinge chain) upright in the X-Y
-- running plane so the runner can pitch/fall forward & back but not topple
-- sideways or spin. Responsiveness is intentionally soft so it still feels loose.
Config.PlaneLock = {
	Responsiveness = 40,
	MaxTorque = 40000,
}

-- ===== Control mapping =====
-- Each key, while held, contributes a signed multiple of the joint's target
-- speed. Opposing keys (Q vs W, O vs P) cancel. This produces the classic
-- alternating gait: Q/O drive the right leg, W/P drive the left leg.
--   Q -> right thigh forward, left thigh back
--   W -> left thigh forward, right thigh back
--   O -> right knee flex,     left knee extend
--   P -> left knee flex,      right knee extend
Config.Keys = {
	Q = Enum.KeyCode.Q,
	W = Enum.KeyCode.W,
	O = Enum.KeyCode.O,
	P = Enum.KeyCode.P,
	Reset = Enum.KeyCode.R,
}

-- drive[hingeName][key] = signed multiplier applied to that hinge's TargetSpeed
local fs = Config.Knee.FlexSign
Config.Drive = {
	RightHip = { Q = 1, W = -1 },
	LeftHip = { Q = -1, W = 1 },
	RightKnee = { O = fs, P = -fs },
	LeftKnee = { P = fs, O = -fs },
}

return Config
