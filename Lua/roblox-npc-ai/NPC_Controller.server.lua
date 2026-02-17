local Players = game:GetService("Players")

local StateMachine = require(script.Parent.NPC_StateMachine)
local Pathfinder = require(script.Parent.NPC_Pathfinder)

local NPC_FOLDER = workspace:WaitForChild("NPCs")
local ROAM_RADIUS = 60
local AGGRO_CHECK_RATE = 0.2
local CHASE_REPATH_RATE = 0.8
local CHASE_REPATH_DISTANCE = 3
local ROAM_STUCK_SECONDS = 2

local ANIMATION_IDS = {
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
		brain.CurrentPlayingAnim:Stop(0.15)
	end

	desiredTrack:Play(0.15)
	brain.CurrentPlayingAnim = desiredTrack
end

local brains = {}
local npcAnimations = {}

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
		local alertMult = npc:GetAttribute("AlertSpeedMult") or 1.6
		local attackRange = npc:GetAttribute("AttackRange") or 4
		local damage = npc:GetAttribute("Damage") or 10
		local cooldown = npc:GetAttribute("AttackCooldown") or 1.2

		local nearestPlayer, nearestDistance = getNearestPlayer(root.Position)

		if brain.State == "ROAM" and nearestPlayer and nearestDistance <= aggro then
			brain:SetState("CHASE", nearestPlayer)
			brain.CurrentRoamTarget = nil
			brain.LastChaseRepath = nil
			Pathfinder:Stop(npc)
		end

		if brain.State == "ROAM" then
			humanoid.WalkSpeed = baseSpeed
			if not brain.CurrentRoamTarget then
				brain.CurrentRoamTarget = randomPointAround(root.Position, ROAM_RADIUS)
				brain.LastRoamProgressAt = tick()
				brain.LastRoamDistance = (root.Position - brain.CurrentRoamTarget).Magnitude
				Pathfinder:MoveTo(npc, brain.CurrentRoamTarget)
			else
				local remaining = (root.Position - brain.CurrentRoamTarget).Magnitude
				if remaining < 2 then
					brain.CurrentRoamTarget = nil
				elseif not brain.LastRoamDistance or remaining < brain.LastRoamDistance - 1 then
					brain.LastRoamDistance = remaining
					brain.LastRoamProgressAt = tick()
				elseif brain.LastRoamProgressAt and tick() - brain.LastRoamProgressAt >= ROAM_STUCK_SECONDS then
					brain.CurrentRoamTarget = nil
					Pathfinder:Stop(npc)
				end
			end
			playTrack(brain, anims.Walk)

		elseif brain.State == "CHASE" then
			local target = brain.Target
			local targetRoot = target and target:FindFirstChild("HumanoidRootPart")
			local targetHumanoid = target and target:FindFirstChildOfClass("Humanoid")
			if not targetRoot or not targetHumanoid or targetHumanoid.Health <= 0 then
				brain:SetState("ROAM")
				brain.CurrentRoamTarget = nil
				Pathfinder:Stop(npc)
				continue
			end

			local distance = (targetRoot.Position - root.Position).Magnitude
			if distance <= attackRange then
				brain:SetState("ATTACK", target)
				Pathfinder:Stop(npc)
				continue
			end

			if distance > aggro * 1.6 then
				brain:SetState("ROAM")
				brain.CurrentRoamTarget = nil
				Pathfinder:Stop(npc)
				continue
			end

			humanoid.WalkSpeed = baseSpeed * alertMult
			if not brain.LastChaseRepath or tick() - brain.LastChaseRepath >= CHASE_REPATH_RATE then
				brain.LastChaseRepath = tick()
				Pathfinder:MoveTo(npc, targetRoot.Position, {
					minRepathTime = CHASE_REPATH_RATE,
					minRepathDistance = CHASE_REPATH_DISTANCE,
				})
			end
			playTrack(brain, anims.Run)

		elseif brain.State == "ATTACK" then
			local target = brain.Target
			local targetRoot = target and target:FindFirstChild("HumanoidRootPart")
			local targetHumanoid = target and target:FindFirstChildOfClass("Humanoid")
			if not targetRoot or not targetHumanoid or targetHumanoid.Health <= 0 then
				brain:SetState("ROAM")
				brain.CurrentRoamTarget = nil
				continue
			end

			local distance = (targetRoot.Position - root.Position).Magnitude
			if distance > attackRange then
				brain:SetState("CHASE", target)
				brain.LastChaseRepath = nil
				continue
			end

			humanoid.WalkSpeed = 0
			Pathfinder:Stop(npc)
			playTrack(brain, anims.Attack)

			if tick() - brain.LastAttack >= cooldown then
				brain.LastAttack = tick()
				targetHumanoid:TakeDamage(damage)
			end
		end
	end
end
