--!strict
-- Small shared client-side state (presentation only; the server owns truth).

local ClientState = {
	inMenu = true,
	observing = false,
	panelOpen = false,
	building = false,
	items = {} :: { [string]: number },
	chest = {} :: { [string]: number },
	lastDiscovery = -1e9,
	lastThreatTime = -1e9,
	listeners = {} :: { () -> () },
}

function ClientState.onInventory(fn: () -> ())
	table.insert(ClientState.listeners, fn)
end

function ClientState.setInventory(items: { [string]: number }, chest: { [string]: number }?)
	ClientState.items = items
	if chest then
		ClientState.chest = chest
	end
	for _, fn in ClientState.listeners do
		task.spawn(fn)
	end
end

return ClientState
