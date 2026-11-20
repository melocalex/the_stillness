--!strict
-- Pure night classification. Early nights are scripted for the story; later
-- nights are drawn from configurable weights.

local NightClass = {}

export type NightType = "Peaceful" | "Uneasy" | "Bad" | "Black"

export type Config = {
	scripted: { [number]: NightType },
	weights: { Peaceful: number, Uneasy: number, Bad: number, Black: number },
	blackMinDay: number,
}

local ORDER: { NightType } = { "Peaceful", "Uneasy", "Bad", "Black" }
NightClass.Order = ORDER

-- roll: uniform random in [0, 1).
function NightClass.classify(day: number, roll: number, config: Config): NightType
	local scripted = config.scripted[day]
	if scripted then
		return scripted :: any
	end
	local w = table.clone(config.weights)
	if day < config.blackMinDay then
		w.Bad += w.Black
		w.Black = 0
	end
	local total = w.Peaceful + w.Uneasy + w.Bad + w.Black
	if total <= 0 then
		return "Peaceful"
	end
	local pick = math.clamp(roll, 0, 0.999999) * total
	for _, name in ORDER do
		local weight = (w :: any)[name] :: number
		if pick < weight then
			return name :: any
		end
		pick -= weight
	end
	return "Peaceful"
end

function NightClass.isDangerous(t: NightType): boolean
	return t == "Bad" or t == "Black"
end

return NightClass
