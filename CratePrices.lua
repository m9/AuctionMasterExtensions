local _, ns = ...
local API = ns.API
local Crates = ns.Crates

-- What it costs to buy a number of an item. Two sources:
--   a ladder: every listing of the item (price, count) from the last search of it, by anyone. Exact.
--   AuctionMaster: lowest price and the amount for sale from its last scan. An estimate, as only one price is known.
-- A ladder counts for LADDER_SECONDS and until the next full scan.
local Prices = {}
ns.Prices = Prices

local LADDER_SECONDS = 600
local FRESH_SECONDS = 120 -- an item searched this recently is not searched again
local SCAN_SECONDS = 60 -- a full scan that never reports back stops counting as running

local ladders = {} -- itemID -> { time, full, rows = { { price, count }, ... } }, cheapest first
local listeners = {}
local scanStarted, scanAnswered

-- listener(itemID) after a search of the item, listener() after other changes.
function Prices.OnChange(listener)
	listeners[#listeners + 1] = listener
end

local function Fire(itemID)
	for _, listener in ipairs(listeners) do
		listener(itemID)
	end
end

local function Ladder(itemID)
	local ladder = ladders[itemID]
	if ladder and time() - ladder.time <= LADDER_SECONDS then
		return ladder
	end
end

-- Cost of `need` items from a ladder and whether it is exact. Nil if that many are not for sale.
-- A ladder that is not full only holds the cheapest listings: the rest is counted at its last price.
function Prices.LadderCost(ladder, need)
	local cost, left, last = 0, need, nil
	for _, row in ipairs(ladder.rows) do
		local take = math.min(left, row[2])
		cost = cost + take * row[1]
		left = left - take
		last = row[1]
		if left == 0 then
			return cost, true
		end
	end
	if ladder.full or not last then
		return nil
	end
	return cost + left * last, false
end

-- Cost of `need` items in copper and whether it is exact. Nil if unknown or not for sale.
function Prices.Cost(itemID, need)
	local ladder = Ladder(itemID)
	if ladder then
		return Prices.LadderCost(ladder, need)
	end
	local low = API.GetLowestPrice(itemID)
	if not low then
		return nil
	end
	local available = API.GetAvailableQuantity(itemID)
	if available and available < need then
		return nil
	end
	return low * need, false
end

function Prices.IsKnown(itemID)
	local ladder = Ladder(itemID)
	if ladder then
		return #ladder.rows > 0
	end
	return API.GetLowestPrice(itemID) ~= nil
end

function Prices.IsFresh(itemID)
	local ladder = ladders[itemID]
	return ladder ~= nil and time() - ladder.time <= FRESH_SECONDS
end

-- True while a full scan of AuctionMaster keeps the server busy.
function Prices.IsScanBusy()
	return scanStarted ~= nil and GetTime() - scanStarted < SCAN_SECONDS
end

local function Store(itemID, rows, full)
	table.sort(rows, function(a, b) return a[1] < b[1] end)
	ladders[itemID] = { time = time(), full = full, rows = rows }
	Fire(itemID)
end

-- A search that got no answer: nobody sells the item.
function Prices.SetEmpty(itemID)
	Store(itemID, {}, true)
end

local function OnCommodity(itemID)
	if not Crates.ITEMS[itemID] then
		return
	end
	local rows = {}
	for index = 1, C_AuctionHouse.GetNumCommoditySearchResults(itemID) do
		local result = C_AuctionHouse.GetCommoditySearchResultInfo(itemID, index)
		-- own auctions cannot be bought
		local count = result and result.quantity - (result.numOwnerItems or 0) or 0
		if count > 0 then
			rows[#rows + 1] = { result.unitPrice, count }
		end
	end
	local full = C_AuctionHouse.HasFullCommoditySearchResults(itemID)
	-- the game fires the event without results while it restarts a search
	if #rows > 0 or full then
		Store(itemID, rows, full)
	end
end

local function OnItem(itemKey)
	local itemID = itemKey and itemKey.itemID
	if not Crates.ITEMS[itemID] then
		return
	end
	local rows = {}
	for index = 1, C_AuctionHouse.GetNumItemSearchResults(itemKey) do
		local result = C_AuctionHouse.GetItemSearchResultInfo(itemKey, index)
		local price = result and result.buyoutAmount
		if price and price > 0 and not result.containsOwnerItem then
			rows[#rows + 1] = { price, math.max(result.quantity or 1, 1) }
		end
	end
	local full = C_AuctionHouse.HasFullItemSearchResults(itemKey)
	if #rows > 0 or full then
		Store(itemID, rows, full)
	end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("COMMODITY_SEARCH_RESULTS_UPDATED")
frame:RegisterEvent("ITEM_SEARCH_RESULTS_UPDATED")
frame:RegisterEvent("REPLICATE_ITEM_LIST_UPDATE")
frame:RegisterEvent("AUCTION_HOUSE_CLOSED")
frame:SetScript("OnEvent", function(_, event, arg)
	if event == "COMMODITY_SEARCH_RESULTS_UPDATED" then
		OnCommodity(arg)
	elseif event == "ITEM_SEARCH_RESULTS_UPDATED" then
		OnItem(arg)
	elseif event == "REPLICATE_ITEM_LIST_UPDATE" then
		scanAnswered = scanStarted ~= nil
	else
		scanStarted, scanAnswered = nil, nil
	end
end)

-- AuctionMaster's full scan. Its data is newer than every ladder once it is stored.
hooksecurefunc(C_AuctionHouse, "ReplicateItems", function()
	scanStarted, scanAnswered = GetTime(), false
end)

if API.AddDataChangeListener then
	API.AddDataChangeListener(function()
		if scanStarted and scanAnswered then
			scanStarted, scanAnswered = nil, nil
			ladders = {}
		end
		Fire()
	end)
end
