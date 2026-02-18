local Players = game:GetService("Players")

local StateMachine = require(script.Parent.NPC_StateMachine)
local Pathfinder = require(script.Parent.NPC_Pathfinder)

local NPC_FOLDER = workspace:WaitForChild("NPCs")
local ROAM_RADIUS = 60
local ROAM_POINT_ATTEMPTS = 5
local AGGRO_CHECK_RATE = 0.1
local CHASE_REPATH_RATE = 0.45
local CHASE_REPATH_DISTANCE = 3
local ROAM_STUCK_SECONDS = 2
local SPEED_SMOOTH_ALPHA = 0.35
local ROAM_IDLE_MIN = 0.8
local ROAM_IDLE_MAX = 1.8

local ANIMATION_IDS = {
	Idle = "rbxassetid://507766666", -- replace with your preferred idle animation
	Walk = "rbxassetid://129812663635239",
	Run = "rbxassetid://74642014614789",
	Attack = "rbxassetid://74642014614789",
}

local function getNearestPlayer(position)
	local bestCharacter, bestDistance = nil, math.huge
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if root and humanoid and humanoid.Health > 0 then
			local distance = (root.Position - position).Magnitude
			if distance < bestDistance then
				bestCharacter, bestDistance = character, distance
			end
		end
	end
	return bestCharacter, bestDistance
end

local function randomPointAround(position, radius)
	local angle = math.random() * math.pi * 2
	local distance = math.random() * radius
	return position + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
end

local function pickReachableRoamTarget(npc, origin, radius)
	for _ = 1, ROAM_POINT_ATTEMPTS do
		local candidate = randomPointAround(origin, radius)
		if Pathfinder:CanPathTo(npc, candidate) then
			return candidate
		end
	end
	return randomPointAround(origin, radius)
end

local function loadAnimations(humanoid)
	local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator")
	animator.Parent = humanoid

	local tracks = {}
	for name, id in pairs(ANIMATION_IDS) do
		local animation = Instance.new("Animation")
		animation.AnimationId = id
		local track = animator:LoadAnimation(animation)
		if name == "Attack" then
			track.Priority = Enum.AnimationPriority.Action
		elseif name == "Idle" then
			track.Priority = Enum.AnimationPriority.Idle
		else
			track.Priority = Enum.AnimationPriority.Movement
		end
		tracks[name] = track
	end

	return tracks
end

local function playTrack(brain, desiredTrack)
	if brain.CurrentPlayingAnim == desiredTrack then
		return
	end

	if brain.CurrentPlayingAnim then
		brain.CurrentPlayingAnim:Stop(0.12)
	end

	desiredTrack:Play(0.12)
	brain.CurrentPlayingAnim = desiredTrack
end

local function smoothSetWalkSpeed(humanoid, desiredSpeed)
	humanoid.WalkSpeed = humanoid.WalkSpeed + (desiredSpeed - humanoid.WalkSpeed) * SPEED_SMOOTH_ALPHA
end

local brains = {}
local npcAnimations = {}

local function onStateEntered(npc, brain, newState)
	if newState == "ROAM" then
		brain.CurrentRoamTarget = nil
		brain.LastRoamProgressAt = nil
		brain.LastRoamDistance = nil
		brain.RoamPauseUntil = tick() + math.random() * (ROAM_IDLE_MAX - ROAM_IDLE_MIN) + ROAM_IDLE_MIN
		brain.AttackDamageDone = false
		Pathfinder:Stop(npc)
	elseif newState == "CHASE" then
		brain.RoamPauseUntil = nil
		brain.LastChaseRepath = nil
		brain.AttackDamageDone = false
		Pathfinder:Stop(npc)
	elseif newState == "ATTACK" then
		brain.AttackStartedAt = tick()
		brain.AttackDamageDone = false
		Pathfinder:Stop(npc)
	end
end

local function setState(npc, brain, newState, target)
	if brain:SetState(newState, target) then
		onStateEntered(npc, brain, newState)
	end
end

local function registerNpc(npc)
	local root = npc:FindFirstChild("HumanoidRootPart")
	if root then
		root:SetNetworkOwner(nil)
	end

	brains[npc] = StateMachine.new(npc)
end

for _, npc in ipairs(NPC_FOLDER:GetChildren()) do
	registerNpc(npc)
end

NPC_FOLDER.ChildAdded:Connect(registerNpc)
NPC_FOLDER.ChildRemoved:Connect(function(npc)
	brains[npc] = nil
	npcAnimations[npc] = nil
	Pathfinder:Stop(npc)
end)

while true do
	task.wait(AGGRO_CHECK_RATE)

	for npc, brain in pairs(brains) do
		if not npc.Parent then
			continue
		end

		local humanoid = npc:FindFirstChildOfClass("Humanoid")
		local root = npc:FindFirstChild("HumanoidRootPart")
		if not humanoid or not root or humanoid.Health <= 0 then
			continue
		end

		if not npcAnimations[npc] then
			npcAnimations[npc] = loadAnimations(humanoid)
		end
		local anims = npcAnimations[npc]

		local aggro = npc:GetAttribute("AggroRange") or 30
		local baseSpeed = npc:GetAttribute("WalkSpeedBase") or 10
		local alertMult = npc:GetAttribute("AlertSpeedMult") or 1.35
		local maxChaseSpeed = npc:GetAttribute("MaxChaseSpeed") or 13
		local attackRange = npc:GetAttribute("AttackRange") or 4
		local damage = npc:GetAttribute("Damage") or 10
		local cooldown = npc:GetAttribute("AttackCooldown") or 1.2
		local attackHitDelay = npc:GetAttribute("AttackHitDelay") or 0.2

		local nearestPlayer, nearestDistance = getNearestPlayer(root.Position)

		if brain.State == "ROAM" and nearestPlayer and nearestDistance <= aggro then
			setState(npc, brain, "CHASE", nearestPlayer)
		end

		if brain.State == "ROAM" then
			if brain.RoamPauseUntil and tick() < brain.RoamPauseUntil then
				smoothSetWalkSpeed(humanoid, 0)
				playTrack(brain, anims.Idle)
				continue
			end

			smoothSetWalkSpeed(humanoid, baseSpeed)
			if not brain.CurrentRoamTarget then
				brain.CurrentRoamTarget = pickReachableRoamTarget(npc, root.Position, ROAM_RADIUS)
				brain.LastRoamProgressAt = tick()
				brain.LastRoamDistance = (root.Position - brain.CurrentRoamTarget).Magnitude
				Pathfinder:MoveTo(npc, brain.CurrentRoamTarget, {
					waypointTimeout = 1.4,
				})
			else
				local remaining = (root.Position - brain.CurrentRoamTarget).Magnitude
				if remaining < 2 then
					brain.CurrentRoamTarget = nil
					brain.RoamPauseUntil = tick() + math.random() * (ROAM_IDLE_MAX - ROAM_IDLE_MIN) + ROAM_IDLE_MIN
					Pathfinder:Stop(npc)
				elseif not brain.LastRoamDistance or remaining < brain.LastRoamDistance - 1 then
					brain.LastRoamDistance = remaining
					brain.LastRoamProgressAt = tick()
				elseif brain.LastRoamProgressAt and tick() - brain.LastRoamProgressAt >= ROAM_STUCK_SECONDS then
					brain.CurrentRoamTarget = nil
					brain.RoamPauseUntil = tick() + 0.6
					Pathfinder:Stop(npc)
				end
			end
			playTrack(brain, anims.Walk)

		elseif brain.State == "CHASE" then
			local target = brain.Target
			local targetRoot = target and target:FindFirstChild("HumanoidRootPart")
			local targetHumanoid = target and target:FindFirstChildOfClass("Humanoid")
			if not targetRoot or not targetHumanoid or targetHumanoid.Health <= 0 then
				setState(npc, brain, "ROAM")
				continue
			end

			local distance = (targetRoot.Position - root.Position).Magnitude
			if distance <= attackRange then
				setState(npc, brain, "ATTACK", target)
				continue
			end

			if distance > aggro * 1.6 then
				setState(npc, brain, "ROAM")
				continue
			end

			local desiredChaseSpeed = math.min(baseSpeed * alertMult, maxChaseSpeed)
			smoothSetWalkSpeed(humanoid, desiredChaseSpeed)
			if not brain.LastChaseRepath or tick() - brain.LastChaseRepath >= CHASE_REPATH_RATE then
				brain.LastChaseRepath = tick()
				Pathfinder:MoveTo(npc, targetRoot.Position, {
					minRepathTime = CHASE_REPATH_RATE,
					minRepathDistance = CHASE_REPATH_DISTANCE,
					waypointTimeout = 0.9,
				})
			end
			playTrack(brain, anims.Run)

		elseif brain.State == "ATTACK" then
			local target = brain.Target
			local targetRoot = target and target:FindFirstChild("HumanoidRootPart")
			local targetHumanoid = target and target:FindFirstChildOfClass("Humanoid")
			if not targetRoot or not targetHumanoid or targetHumanoid.Health <= 0 then
				setState(npc, brain, "ROAM")
				continue
			end

			local distance = (targetRoot.Position - root.Position).Magnitude
			if distance > attackRange then
				setState(npc, brain, "CHASE", target)
				continue
			end

			smoothSetWalkSpeed(humanoid, 0)
			playTrack(brain, anims.Attack)

			local now = tick()
			if not brain.AttackDamageDone and now - (brain.AttackStartedAt or now) >= attackHitDelay then
				targetHumanoid:TakeDamage(damage)
				brain.AttackDamageDone = true
				brain.LastAttack = now
			end

			if brain.AttackDamageDone and now - brain.LastAttack >= cooldown then
				brain.AttackStartedAt = now
				brain.AttackDamageDone = false
			end
		end
	end
end
