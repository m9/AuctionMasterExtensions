local _, ns = ...

-- AuctionMaster's public API (see its API.md). Its other tables are private.
ns.API = AuctionMaster.API

local GOLD = "|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t"
local SILVER = "|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t"
local COPPER = "|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t"

-- Copper as coins. Copper is left out from 1 gold on.
function ns.Money(copper)
	copper = math.floor(copper + 0.5)
	local gold = math.floor(copper / 10000)
	local silver = math.floor(copper / 100) % 100
	local rest = copper % 100
	local parts = {}
	if gold > 0 then parts[#parts + 1] = gold .. GOLD end
	if silver > 0 then parts[#parts + 1] = silver .. SILVER end
	if rest > 0 and gold == 0 then parts[#parts + 1] = rest .. COPPER end
	return #parts > 0 and table.concat(parts, " ") or "0" .. COPPER
end

function ns.Print(text)
	print("|cffffd100AuctionMaster Extensions:|r " .. text)
end
