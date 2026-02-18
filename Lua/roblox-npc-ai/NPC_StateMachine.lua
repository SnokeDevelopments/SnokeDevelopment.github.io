local StateMachine = {}
StateMachine.__index = StateMachine

function StateMachine.new(npc)
	local self = setmetatable({}, StateMachine)
	self.NPC = npc
	self.State = "ROAM"
	self.Target = nil
	self.StateChanged = tick()
	self.LastAttack = 0
	self.CurrentRoamTarget = nil
	self.CurrentPlayingAnim = nil
	return self
end

function StateMachine:SetState(newState, target)
	if self.State == newState and target == self.Target then
		return false
	end

	self.State = newState
	self.Target = target
	self.StateChanged = tick()
	return true
end

function StateMachine:TimeInState()
	return tick() - self.StateChanged
end

return StateMachine
