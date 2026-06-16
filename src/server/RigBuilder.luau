--!strict
-- Builds a QWOP runner rig out of primitive parts at runtime.
--
-- The rig is a chain: Torso -> (Right/Left) Thigh -> Calf -> Foot, plus a Head.
-- Hips and knees are HingeConstraints (axis = world Z) driven as velocity
-- motors. Feet and head are rigidly welded. The torso carries an AlignOrientation
-- that locks the whole assembly into its X-Y running plane.
--
-- To swap in custom art later: keep the part names + the "Hinges" folder + the
-- attribute/tag wiring, and replace the visual parts (or parent meshes under them).

local CollectionService = game:GetService("CollectionService")
local PhysicsService = game:GetService("PhysicsService")

local Config = require(game:GetService("ReplicatedStorage").Shared.Config)

local RigBuilder = {}

local COLLISION_GROUP = "Runners"

-- Register a collision group so a runner's own parts never collide with each
-- other (or with other runners) -- they only collide with the world.
local function ensureCollisionGroup()
	local ok = pcall(function()
		PhysicsService:RegisterCollisionGroup(COLLISION_GROUP)
	end)
	if ok then
		PhysicsService:CollisionGroupSetCollidable(COLLISION_GROUP, COLLISION_GROUP, false)
	end
end
ensureCollisionGroup()

local function makePart(name: string, size: Vector3, color: Color3): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CanCollide = true
	part.CollisionGroup = COLLISION_GROUP
	return part
end

-- Create an attachment whose primary (X) axis points along world +Z, i.e. the
-- hinge rotation axis. localPos is in the part's local space.
local function makeAxisAttachment(part: BasePart, name: string, localPos: Vector3): Attachment
	local att = Instance.new("Attachment")
	att.Name = name
	att.Parent = part
	att.Position = localPos
	att.Axis = Vector3.new(0, 0, 1) -- rotate about world Z
	return att
end

local function makeHinge(
	name: string,
	parent: Instance,
	a0: Attachment,
	a1: Attachment,
	params: { MotorMaxTorque: number, MotorMaxAcceleration: number, LimitLow: number, LimitHigh: number }
): HingeConstraint
	local hinge = Instance.new("HingeConstraint")
	hinge.Name = name
	hinge.Attachment0 = a0
	hinge.Attachment1 = a1
	hinge.ActuatorType = Enum.ActuatorType.Motor
	hinge.AngularVelocity = 0
	hinge.MotorMaxTorque = params.MotorMaxTorque
	hinge.MotorMaxAcceleration = params.MotorMaxAcceleration
	hinge.LimitsEnabled = true
	hinge.LowerAngle = params.LimitLow
	hinge.UpperAngle = params.LimitHigh
	hinge.Parent = parent
	return hinge
end

-- Builds one leg (thigh + calf + foot) attached to the torso. `side` is -1 for
-- right (Z negative) or +1 for left (Z positive). Returns the hip & knee hinges.
local function buildLeg(
	model: Model,
	torso: BasePart,
	hingeFolder: Folder,
	side: number,
	prefix: string,
	color: Color3
): (HingeConstraint, HingeConstraint)
	local S = Config.Sizes
	local legZ = side * Config.LegZOffset
	local origin = torso.Position

	-- World joint heights (see Config / comments in geometry below):
	local hipY = torso.Position.Y - S.Torso.Y / 2 -- bottom of torso
	local kneeY = hipY - S.Thigh.Y

	-- Thigh: center halfway down from hip.
	local thigh = makePart(prefix .. "Thigh", S.Thigh, color)
	thigh.Position = Vector3.new(origin.X, hipY - S.Thigh.Y / 2, origin.Z + legZ)
	thigh.Parent = model

	-- Calf.
	local calf = makePart(prefix .. "Calf", S.Calf, color)
	calf.Position = Vector3.new(origin.X, kneeY - S.Calf.Y / 2, origin.Z + legZ)
	calf.Parent = model

	-- Foot: sits on the ground, extends forward (+X) from the ankle.
	local foot = makePart(prefix .. "Foot", S.Foot, Color3.fromRGB(40, 40, 40))
	foot.Position = Vector3.new(origin.X + 0.3, Config.GroundY + S.Foot.Y / 2, origin.Z + legZ)
	foot.Parent = model

	-- Hip hinge: torso bottom <-> thigh top.
	local hipOnTorso = makeAxisAttachment(torso, prefix .. "HipA0", Vector3.new(0, -S.Torso.Y / 2, legZ))
	local hipOnThigh = makeAxisAttachment(thigh, prefix .. "HipA1", Vector3.new(0, S.Thigh.Y / 2, 0))
	local hip = makeHinge(prefix .. "Hip", hingeFolder, hipOnTorso, hipOnThigh, Config.Hip)

	-- Knee hinge: thigh bottom <-> calf top.
	local kneeOnThigh = makeAxisAttachment(thigh, prefix .. "KneeA0", Vector3.new(0, -S.Thigh.Y / 2, 0))
	local kneeOnCalf = makeAxisAttachment(calf, prefix .. "KneeA1", Vector3.new(0, S.Calf.Y / 2, 0))
	local knee = makeHinge(prefix .. "Knee", hingeFolder, kneeOnThigh, kneeOnCalf, Config.Knee)

	-- Ankle: rigid weld (feet are passive in QWOP).
	local ankleWeld = Instance.new("WeldConstraint")
	ankleWeld.Part0 = calf
	ankleWeld.Part1 = foot
	ankleWeld.Parent = calf

	return hip, knee
end

-- Adds the AlignOrientation that keeps the torso (and the whole hinge chain)
-- in its X-Y plane: free to pitch about world Z, locked against roll/yaw.
local function addPlaneLock(torso: BasePart)
	local att = Instance.new("Attachment")
	att.Name = "PlaneLock"
	att.Parent = torso

	local align = Instance.new("AlignOrientation")
	align.Name = "PlaneLockAlign"
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.Attachment0 = att
	align.PrimaryAxisOnly = true -- only pin the primary axis -> free spin about it
	align.Responsiveness = Config.PlaneLock.Responsiveness
	align.MaxTorque = Config.PlaneLock.MaxTorque
	align.RigidityEnabled = false
	-- Target frame whose primary (X) axis is world +Z, so the torso's pinned
	-- axis stays along Z and it can only rotate within the X-Y plane.
	align.CFrame = CFrame.fromMatrix(Vector3.zero, Vector3.new(0, 0, 1), Vector3.new(0, 1, 0))
	align.Parent = torso

	-- Orient the attachment's primary axis along world Z to match.
	att.Axis = Vector3.new(0, 0, 1)
end

-- Public: build a rig for `player` at lane Z `laneZ`. Returns the Model.
function RigBuilder.build(player: Player, laneZ: number): Model
	local S = Config.Sizes
	local color = Color3.fromHSV((player.UserId % 16) / 16, 0.65, 0.95)

	local model = Instance.new("Model")
	model.Name = "Runner_" .. player.UserId

	-- Torso sits so the feet rest on the ground at spawn.
	local ankleY = Config.GroundY + S.Foot.Y
	local kneeY = ankleY + S.Calf.Y
	local hipY = kneeY + S.Thigh.Y
	local torsoY = hipY + S.Torso.Y / 2

	local torso = makePart("Torso", S.Torso, color)
	torso.Position = Vector3.new(Config.StartX, torsoY, laneZ)
	torso.Parent = model
	model.PrimaryPart = torso

	local head = makePart("Head", S.Head, Color3.fromRGB(245, 220, 180))
	head.Shape = Enum.PartType.Ball
	head.Position = torso.Position + Vector3.new(0, S.Torso.Y / 2 + S.Head.Y / 2, 0)
	head.Parent = model
	local neck = Instance.new("WeldConstraint")
	neck.Part0 = torso
	neck.Part1 = head
	neck.Parent = torso

	local hingeFolder = Instance.new("Folder")
	hingeFolder.Name = "Hinges"
	hingeFolder.Parent = model

	buildLeg(model, torso, hingeFolder, -1, "Right", color)
	buildLeg(model, torso, hingeFolder, 1, "Left", color:Lerp(Color3.new(0, 0, 0), 0.25))

	addPlaneLock(torso)

	-- Metadata so clients can find & label this rig.
	model:SetAttribute(Config.OwnerAttribute, player.UserId)
	model:SetAttribute(Config.LaneAttribute, laneZ)
	CollectionService:AddTag(model, Config.RigTag)

	return model
end

-- Hand network ownership of every part to the player so their client can drive
-- the hinge motors with no latency. Call only on unanchored parts.
function RigBuilder.giveOwnership(model: Model, player: Player)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = false
			pcall(function()
				d:SetNetworkOwner(player)
			end)
		end
	end
end

function RigBuilder.setAnchored(model: Model, anchored: boolean)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = anchored
		end
	end
end

return RigBuilder
