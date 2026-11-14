local _, ns = ...

local T = {
	enUS = {
		tab = "Crates",
		crate = "Crate",
		owned = "Owned",
		none = "Not listed",
		total = "Total",
		cheapest = "Cheapest",
		perFavor = "Per Favor",
		overall = "Overall",
		addList = "Add to list",
		update = "Update",
		stop = "Stop",
		empty = "No crates listed",
		favor = "Favor",
		broken = "Crates tab not added.",
		noList = "Shopping list not found.",
	},
}

ns.L = setmetatable(T[GetLocale()] or {}, { __index = T.enUS })
