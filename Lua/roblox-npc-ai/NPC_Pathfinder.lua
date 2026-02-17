local PathfindingService = game:GetService("PathfindingService")

local Pathfinder = {}
local activeJobs = {}

local function stopJob(model)
	local job = activeJobs[model]
	if not job then
		return
	end

	job.cancelled = true
	activeJobs[model] = nil
end

local function shouldSkipRepath(job, destination, now, minTime, minDistance)
	if not job or not job.lastDestination then
		return false
	end

	if minTime and minTime > 0 and now - (job.lastCompute or 0) < minTime then
		return true
	end

	if minDistance and minDistance > 0 then
		local moved = (job.lastDestination - destination).Magnitude
		if moved < minDistance then
			return true
		end
	end

	return false
end

function Pathfinder:Stop(model)
	stopJob(model)

	local humanoid = model and model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid:Move(Vector3.zero)
	end
end

function Pathfinder:MoveTo(model, destination, options)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root then
		return
	end

	options = options or {}
	local now = tick()
	local existingJob = activeJobs[model]
	if shouldSkipRepath(existingJob, destination, now, options.minRepathTime, options.minRepathDistance) then
		return
	end

	stopJob(model)

	local path = PathfindingService:CreatePath({
		AgentRadius = options.agentRadius or 2,
		AgentHeight = options.agentHeight or 5,
		AgentCanJump = options.agentCanJump ~= false,
	})

	local ok = pcall(function()
		path:ComputeAsync(root.Position, destination)
	end)

	if not ok or path.Status ~= Enum.PathStatus.Success then
		humanoid:MoveTo(destination)
		return
	end

	local waypoints = path:GetWaypoints()
	if #waypoints == 0 then
		return
	end

	local job = {
		cancelled = false,
		lastCompute = now,
		lastDestination = destination,
	}
	activeJobs[model] = job

	task.spawn(function()
		for _, wp in ipairs(waypoints) do
			if job.cancelled then
				return
			end

			if wp.Action == Enum.PathWaypointAction.Jump then
				humanoid.Jump = true
			end

			humanoid:MoveTo(wp.Position)
			local reached = humanoid.MoveToFinished:Wait()
			if job.cancelled then
				return
			end

			if not reached then
				break
			end
		end

		if activeJobs[model] == job then
			activeJobs[model] = nil
		end
	end)
end

return Pathfinder
