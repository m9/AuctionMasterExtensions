local _, ns = ...

-- Puts a crate on AuctionMaster's shopping list of the current character. AuctionMaster has no function for other
-- addons to do that, so the entry is written into its saved data (AuctionMasterDB), in the shape its own entries
-- have: a recipe with the crate and the bundle as its reagents. Its list then counts what is owned, prices the
-- rest and searches it like the reagents of any recipe. Every table on the way is checked: if the data is not laid
-- out as expected, nothing is written.
local List = {}
ns.List = List

local PREFIX = "AuctionMasterExtensions:crate:"

-- The recipes on the list of the current character, the data of the lists and the character. With create, the
-- tables AuctionMaster would make on first use are made. Nil if its data is not there or looks different.
local function Recipes(create)
	local db = AuctionMasterDB
	local factions = type(db) == "table" and db.factions
	if type(factions) ~= "table" then
		return nil
	end
	-- one set of data per auction house: the faction and, on Forever, the rule set
	local key = UnitFactionGroup("player") or "Neutral"
	local rules = C_GameRules and C_GameRules.GetCurrentGameModeRecordID and C_GameRules.GetCurrentGameModeRecordID()
	if rules and rules ~= 0 then
		key = key .. "-" .. rules
	end
	local house = factions[key]
	if type(house) ~= "table" then
		return nil
	end
	if house.shoppingList == nil and create then
		house.shoppingList = { version = 1 }
	end
	local object = house.shoppingList
	if type(object) ~= "table" then
		return nil
	end
	if object.data == nil and create then
		object.data = {}
	end
	local data = object.data
	if type(data) ~= "table" then
		return nil
	end
	if data.crafters == nil and create then
		data.crafters = {}
	end
	if type(data.crafters) ~= "table" then
		return nil
	end
	local guid = UnitGUID("player")
	if data.crafters[guid] == nil and create then
		data.crafters[guid] = { guid = guid, recipes = {} }
	end
	local list = data.crafters[guid]
	if type(list) ~= "table" or type(list.recipes) ~= "table" then
		return nil
	end
	return list.recipes, data, guid
end

-- How many of the crate are on the list, with any bundle.
function List.Count(crateID)
	local prefix = PREFIX .. crateID .. ":"
	local count = 0
	for _, entry in ipairs(Recipes(false) or {}) do
		if type(entry.id) == "string" and entry.id:sub(1, #prefix) == prefix then
			count = count + (tonumber(entry.qty) or 0)
		end
	end
	return count
end

local function Reagent(itemID, count)
	return { itemId = itemID, itemIds = { itemID }, quantity = count }
end

-- Adds one crate of the plan with its bundle: to the quantity of its entry if that crate with that bundle is on
-- the list already, as a new entry otherwise. False if AuctionMaster's data was not found.
function List.Add(plan)
	local recipes, data, guid = Recipes(true)
	if not (recipes and plan.bundle) then
		return false
	end
	local crateID = plan.crate.id
	local id = PREFIX .. crateID .. ":" .. plan.bundle.id
	local found
	for _, entry in ipairs(recipes) do
		if entry.id == id then
			entry.qty = (tonumber(entry.qty) or 0) + 1
			found = true
			break
		end
	end
	if not found then
		recipes[#recipes + 1] = {
			id = id,
			qty = 1,
			name = C_Item.GetItemInfo(crateID) or ("item " .. crateID),
			icon = C_Item.GetItemIconByID(crateID),
			reagents = { Reagent(crateID, 1), Reagent(plan.bundle.id, plan.bundle.count) },
		}
	end
	-- the list that is added to has to be the one shown
	if data.activeGuid and data.activeGuid ~= guid then
		data.activeGuid = nil
	end
	return true
end
