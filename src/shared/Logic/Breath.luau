--!strict
-- Pure hold-breath model. The server steps it from the player's request;
-- the client never decides how much breath is left.
--
-- Holding drains breath. Running out forces an involuntary gasp (a loud noise
-- event) and a short cooldown. Releasing early is quiet; releasing late is a
-- soft exhale that only very close listeners notice.

local Breath = {}

export type Config = {
	capacitySeconds: number,
	recoverPerSecond: number, -- fraction of full breath per second
	gaspCooldown: number,
	warnAt: number, -- fraction where the player feels pressure
	exhaleBelow: number, -- releasing below this fraction makes a soft exhale
}

export type State = {
	breath: number, -- 0..1
	holding: boolean,
	cooldown: number,
}

export type Event = "gasp" | "exhale" | "release"

Breath.Default = {
	capacitySeconds = 10,
	recoverPerSecond = 0.16,
	gaspCooldown = 4,
	warnAt = 0.25,
	exhaleBelow = 0.4,
} :: Config

function Breath.new(): State
	return { breath = 1, holding = false, cooldown = 0 }
end

-- Advances one tick. Returns an event when something audible happens.
function Breath.step(s: State, wantHold: boolean, dt: number, cfg: Config): Event?
	if s.cooldown > 0 then
		s.cooldown = math.max(s.cooldown - dt, 0)
		s.holding = false
		s.breath = math.min(1, s.breath + cfg.recoverPerSecond * dt)
		return nil
	end
	if wantHold and s.breath > 0 then
		s.holding = true
		s.breath -= dt / cfg.capacitySeconds
		if s.breath <= 0 then
			s.breath = 0
			s.holding = false
			s.cooldown = cfg.gaspCooldown
			return "gasp"
		end
		return nil
	end
	local event: Event? = nil
	if s.holding then
		event = if s.breath < cfg.exhaleBelow then "exhale" else "release"
	end
	s.holding = false
	s.breath = math.min(1, s.breath + cfg.recoverPerSecond * dt)
	return event
end

function Breath.straining(s: State, cfg: Config): boolean
	return s.holding and s.breath <= cfg.warnAt
end

return Breath
