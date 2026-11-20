--!strict
-- A dependency-free progress channel. Any service reports what a player did
-- ("talk", "observe", "interact"...) without requiring the progression
-- services, which listen here. Nothing listens until they start.

local ProgressBus = {}

export type Listener = (player: Player, kind: string, target: string?, amount: number?) -> ()

local listeners: { Listener } = {}

function ProgressBus.listen(fn: Listener)
	table.insert(listeners, fn)
end

function ProgressBus.emit(player: Player, kind: string, target: string?, amount: number?)
	for _, fn in listeners do
		task.spawn(fn, player, kind, target, amount)
	end
end

return ProgressBus
