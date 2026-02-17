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

function Pathfinder:Stop(model)
	stopJob(model)

	local humanoid = model and model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid:Move(Vector3.zero)
	end
end

function Pathfinder:MoveTo(model, destination)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root then
		return
	end

	stopJob(model)

	local path = PathfindingService:CreatePath({
		AgentRadius = 2,
		AgentHeight = 5,
		AgentCanJump = true,
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

	local job = { cancelled = false }
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
