--!strict
-- Pure creature state machine. The Roblox controller measures the world,
-- feeds a Tick, and executes the returned Intent. Positions are opaque values
-- (Vector3 in game, anything in tests); the brain never does geometry, so the
-- caller reports `arrived`.
--
-- The brain never receives the player's true position unless the creature
-- currently perceives them. It works from `lastKnown`, which ages and expires.

local CreatureBrain = {}

export type State =
	"DORMANT"
	| "PATROL"
	| "SUSPICIOUS"
	| "INVESTIGATE"
	| "SEARCH"
	| "HUNT"
	| "LOST_TARGET"
	| "RETREAT"

export type BrainConfig = {
	suspiciousThreshold: number,
	investigateThreshold: number,
	huntThreshold: number,
	awarenessDecay: number,
	hearingGain: number,
	suspiciousTime: number,
	searchDuration: number,
	lostTargetTime: number,
	memorySeconds: number,
}

export type Stimulus = {
	gainPerSecond: number,
	position: any,
	targetId: number?,
	visible: boolean,
}

export type Heard = {
	strength: number,
	position: any,
}

export type Tick = {
	dt: number,
	active: boolean,
	shouldRetreat: boolean,
	stimulus: Stimulus?,
	heard: Heard?,
	arrived: boolean,
	targetProtected: boolean,
}

export type IntentKind = "Idle" | "Patrol" | "Look" | "MoveTo" | "Chase" | "Wander" | "Retreat"
export type Speed = "slow" | "walk" | "run"

export type Intent = {
	kind: IntentKind,
	position: any?,
	speed: Speed,
	targetId: number?,
}

export type Brain = {
	state: State,
	stateTime: number,
	awareness: number,
	lastKnown: any?,
	lastKnownAge: number,
	searchCenter: any?,
	targetId: number?,
	config: BrainConfig,
	transitions: number,
}

function CreatureBrain.new(config: BrainConfig, initial: State?): Brain
	return {
		state = initial or "DORMANT",
		stateTime = 0,
		awareness = 0,
		lastKnown = nil,
		lastKnownAge = 0,
		searchCenter = nil,
		targetId = nil,
		config = config,
		transitions = 0,
	}
end

local function enter(brain: Brain, state: State)
	if brain.state ~= state then
		brain.state = state
		brain.stateTime = 0
		brain.transitions += 1
		if state == "SEARCH" then
			brain.searchCenter = brain.lastKnown
		end
	end
end

-- Forget everything about the target. Used on retreat and dormancy.
function CreatureBrain.forget(brain: Brain)
	brain.awareness = 0
	brain.lastKnown = nil
	brain.lastKnownAge = 0
	brain.searchCenter = nil
	brain.targetId = nil
end

local function updateMemory(brain: Brain, tick: Tick)
	local cfg = brain.config
	local gain = 0
	if tick.stimulus then
		gain = tick.stimulus.gainPerSecond
	end
	brain.awareness = math.clamp(brain.awareness + (gain - cfg.awarenessDecay) * tick.dt, 0, 1.5)

	local stim = tick.stimulus
	local heard = tick.heard
	if stim and stim.gainPerSecond > 0 then
		brain.lastKnown = stim.position
		brain.lastKnownAge = 0
		brain.targetId = stim.targetId
	elseif heard and heard.strength > 0 then
		brain.awareness = math.clamp(brain.awareness + heard.strength * cfg.hearingGain, 0, 1.5)
		brain.lastKnown = heard.position
		brain.lastKnownAge = 0
	else
		brain.lastKnownAge += tick.dt
		if brain.lastKnownAge > cfg.memorySeconds then
			brain.lastKnown = nil
		end
	end
end

local function confirmed(brain: Brain, tick: Tick): boolean
	local stim = tick.stimulus
	return stim ~= nil and stim.visible and brain.awareness >= brain.config.huntThreshold
end

function CreatureBrain.step(brain: Brain, tick: Tick): Intent
	local cfg = brain.config
	brain.stateTime += tick.dt

	if tick.shouldRetreat and brain.state ~= "DORMANT" and brain.state ~= "RETREAT" then
		CreatureBrain.forget(brain)
		enter(brain, "RETREAT")
	end

	if brain.state == "RETREAT" then
		if tick.arrived then
			enter(brain, "DORMANT")
			return { kind = "Idle", speed = "slow" }
		end
		return { kind = "Retreat", speed = "walk" }
	end

	if brain.state == "DORMANT" then
		if tick.active and not tick.shouldRetreat then
			enter(brain, "PATROL")
		else
			return { kind = "Idle", speed = "slow" }
		end
	end

	updateMemory(brain, tick)
	local a = brain.awareness

	if brain.state == "PATROL" then
		if confirmed(brain, tick) then
			enter(brain, "HUNT")
		elseif a >= cfg.investigateThreshold and brain.lastKnown ~= nil then
			enter(brain, "INVESTIGATE")
		elseif a >= cfg.suspiciousThreshold then
			enter(brain, "SUSPICIOUS")
		else
			return { kind = "Patrol", speed = "slow" }
		end
	end

	if brain.state == "SUSPICIOUS" then
		if confirmed(brain, tick) then
			enter(brain, "HUNT")
		elseif a >= cfg.investigateThreshold and brain.lastKnown ~= nil then
			enter(brain, "INVESTIGATE")
		elseif brain.stateTime >= cfg.suspiciousTime then
			if a >= cfg.suspiciousThreshold and brain.lastKnown ~= nil then
				enter(brain, "INVESTIGATE")
			elseif a < cfg.suspiciousThreshold then
				enter(brain, "PATROL")
				return { kind = "Patrol", speed = "slow" }
			end
		end
		if brain.state == "SUSPICIOUS" then
			return { kind = "Look", position = brain.lastKnown, speed = "slow" }
		end
	end

	if brain.state == "INVESTIGATE" then
		if confirmed(brain, tick) then
			enter(brain, "HUNT")
		elseif brain.lastKnown == nil or (tick.arrived and brain.stateTime > 0.5) then
			enter(brain, "SEARCH")
		else
			return { kind = "MoveTo", position = brain.lastKnown, speed = "walk" }
		end
	end

	if brain.state == "SEARCH" then
		if confirmed(brain, tick) then
			enter(brain, "HUNT")
		elseif brain.stateTime >= cfg.searchDuration then
			enter(brain, "LOST_TARGET")
		else
			-- A fresh, strong lead elsewhere pulls the search there.
			if a >= cfg.investigateThreshold and brain.lastKnownAge == 0 and brain.stateTime > 2 then
				brain.searchCenter = brain.lastKnown
			end
			return { kind = "Wander", position = brain.searchCenter, speed = "walk" }
		end
	end

	if brain.state == "HUNT" then
		if tick.targetProtected then
			enter(brain, "LOST_TARGET")
		elseif tick.stimulus and tick.stimulus.visible and tick.stimulus.gainPerSecond > 0 then
			return {
				kind = "Chase",
				position = tick.stimulus.position,
				speed = "run",
				targetId = tick.stimulus.targetId,
			}
		elseif
			brain.lastKnown == nil
			or a < cfg.investigateThreshold
			or (tick.arrived and brain.stateTime > 0.5)
		then
			enter(brain, "SEARCH")
			return { kind = "Wander", position = brain.searchCenter, speed = "walk" }
		else
			return { kind = "MoveTo", position = brain.lastKnown, speed = "run" }
		end
	end

	if brain.state == "LOST_TARGET" then
		if confirmed(brain, tick) and not tick.targetProtected then
			enter(brain, "HUNT")
			return { kind = "Chase", position = brain.lastKnown, speed = "run", targetId = brain.targetId }
		end
		if brain.stateTime >= cfg.lostTargetTime then
			CreatureBrain.forget(brain)
			enter(brain, "PATROL")
			return { kind = "Patrol", speed = "slow" }
		end
		return { kind = "Look", position = brain.lastKnown, speed = "slow" }
	end

	return { kind = "Idle", speed = "slow" }
end

return CreatureBrain
