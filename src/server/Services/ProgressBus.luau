--!strict
-- A dependency-free progress channel. Any service reports what a player did
-- ("talk", "observe", "interact"...) without requiring the progression
-- services, which listen here. Nothing listens until they start.

local ProgressBus = {}

-- evidence: a unique id for what happened (a journal entry id), so the same
-- sighting never counts twice toward a quest.
export type Listener = (
	player: Player,
	kind: string,
	target: string?,
	amount: number?,
	evidence: string?
) -> ()

local listeners: { Listener } = {}

function ProgressBus.listen(fn: Listener)
	table.insert(listeners, fn)
end

function ProgressBus.emit(player: Player, kind: string, target: string?, amount: number?, evidence: string?)
	for _, fn in listeners do
		task.spawn(fn, player, kind, target, amount, evidence)
	end
end

return ProgressBus
