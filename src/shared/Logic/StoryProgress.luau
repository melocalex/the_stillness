--!strict
-- Pure objective progression. Steps complete in order when their fact reaches
-- the target. Facts are numbers or booleans the server keeps up to date.

local StoryProgress = {}

export type Step = {
	id: string,
	text: string,
	fact: string,
	target: number?, -- numeric goal; nil means the fact must be truthy
	hint: string?,
}

export type Progress = {
	index: number,
	completed: { [string]: boolean },
}

function StoryProgress.new(): Progress
	return { index = 1, completed = {} }
end

local function factValue(facts: { [string]: any }, key: string): number
	local v = facts[key]
	if type(v) == "number" then
		return v
	elseif v == true then
		return 1
	end
	return 0
end

function StoryProgress.isDone(step: Step, facts: { [string]: any }): boolean
	return factValue(facts, step.fact) >= (step.target or 1)
end

-- Completes as many consecutive steps as the facts allow.
-- Returns the ids completed during this call.
function StoryProgress.advance(p: Progress, steps: { Step }, facts: { [string]: any }): { string }
	local done = {}
	while p.index <= #steps do
		local step = steps[p.index]
		if not StoryProgress.isDone(step, facts) then
			break
		end
		p.completed[step.id] = true
		table.insert(done, step.id)
		p.index += 1
	end
	return done
end

function StoryProgress.current(p: Progress, steps: { Step }): Step?
	return steps[p.index]
end

-- "Collect wood (3/8)" style label for the tracker.
function StoryProgress.label(step: Step, facts: { [string]: any }): string
	if step.target and step.target > 1 then
		return string.format(
			"%s (%d/%d)",
			step.text,
			math.min(factValue(facts, step.fact), step.target),
			step.target
		)
	end
	return step.text
end

return StoryProgress
