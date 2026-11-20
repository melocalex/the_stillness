--!strict
-- Pure day/night cycle math. No Roblox APIs, so it runs under Lune tests.
-- The server owns elapsed time; clients only read the published snapshot.

local TimeCycle = {}

export type Phase = "Day" | "Dusk" | "Night" | "Dawn"
export type Durations = { Day: number, Dusk: number, Night: number, Dawn: number }
export type Snapshot = {
	phase: Phase,
	phaseProgress: number,
	day: number,
	clockTime: number,
	secondsIntoPhase: number,
	secondsLeftInPhase: number,
}

local ORDER: { Phase } = { "Day", "Dusk", "Night", "Dawn" }
TimeCycle.Order = ORDER

-- Clock hour where each phase starts and how many clock hours it spans.
-- Day 06:30-18:00, Dusk 18:00-20:00, Night 20:00-05:00, Dawn 05:00-06:30.
TimeCycle.ClockStart = { Day = 6.5, Dusk = 18, Night = 20, Dawn = 5 } :: { [Phase]: number }
TimeCycle.ClockSpan = { Day = 11.5, Dusk = 2, Night = 9, Dawn = 1.5 } :: { [Phase]: number }

function TimeCycle.cycleLength(d: Durations): number
	return d.Day + d.Dusk + d.Night + d.Dawn
end

-- elapsed: seconds since Day 1 started.
function TimeCycle.snapshot(d: Durations, elapsed: number): Snapshot
	local total = TimeCycle.cycleLength(d)
	assert(total > 0, "cycle length must be positive")
	local e = math.max(elapsed, 0)
	local day = math.floor(e / total) + 1
	local t = e - (day - 1) * total
	for _, phase in TimeCycle.Order do
		local len = d[phase]
		if t < len or phase == "Dawn" then
			local progress = if len > 0 then math.clamp(t / len, 0, 1) else 1
			local clock = (TimeCycle.ClockStart[phase] + TimeCycle.ClockSpan[phase] * progress) % 24
			return {
				phase = phase,
				phaseProgress = progress,
				day = day,
				clockTime = clock,
				secondsIntoPhase = t,
				secondsLeftInPhase = math.max(len - t, 0),
			}
		end
		t -= len
	end
	error("unreachable")
end

-- Seconds of elapsed time at which `phase` of `day` begins.
function TimeCycle.phaseStart(d: Durations, day: number, phase: Phase): number
	local total = TimeCycle.cycleLength(d)
	local offset = 0
	for _, p in TimeCycle.Order do
		if p == phase then
			break
		end
		offset += d[p]
	end
	return (day - 1) * total + offset
end

-- 0 in full daylight, 1 in deep night. Smooth across dusk and dawn.
function TimeCycle.nightFactor(s: Snapshot): number
	if s.phase == "Day" then
		return 0
	elseif s.phase == "Night" then
		return 1
	elseif s.phase == "Dusk" then
		return s.phaseProgress
	else
		return 1 - s.phaseProgress
	end
end

export type Keyframe = { at: number, values: { number } }

-- Linear interpolation over keyframes keyed by clock hour (0-24, wraps around midnight).
function TimeCycle.sampleKeyframes(frames: { Keyframe }, clock: number): { number }
	assert(#frames >= 1, "need keyframes")
	if #frames == 1 then
		return table.clone(frames[1].values)
	end
	local prev = frames[#frames]
	local nxt = frames[1]
	for i, f in frames do
		if f.at > clock then
			nxt = f
			prev = frames[if i == 1 then #frames else i - 1]
			break
		end
		prev = f
		nxt = frames[if i == #frames then 1 else i + 1]
	end
	local span = (nxt.at - prev.at) % 24
	local into = (clock - prev.at) % 24
	local alpha = if span > 0 then math.clamp(into / span, 0, 1) else 0
	local out = {}
	for i, v in prev.values do
		local w = nxt.values[i] or v
		out[i] = v + (w - v) * alpha
	end
	return out
end

return TimeCycle
