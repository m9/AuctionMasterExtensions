-- Runs the addon against a mock of the game and of AuctionMaster's panel.
--   luajit tests/test.lua

local dir = (arg and arg[0] or ""):match("^(.*)[/\\]tests[/\\][^/\\]+$") or "."
local FILES = { "Core.lua", "Locales.lua", "CrateData.lua", "CratePrices.lua", "CratePlanner.lua", "CrateScan.lua",
	"CrateList.lua", "CratePanel.lua" }

local passed, failed = 0, 0
local function check(ok, name)
	if ok then
		passed = passed + 1
	else
		failed = failed + 1
		io.write("FAIL " .. name .. "\n")
	end
end
local function eq(got, want, name)
	check(got == want, name .. " (got " .. tostring(got) .. ", want " .. tostring(want) .. ")")
end

-- The mock ---------------------------------------------------------------------------------------

local w -- the world of the current run

local Frame = {}
-- Methods the mock does not know do nothing; fields that were never set are nil.
local function Nothing() end
Frame.__index = function(_, key)
	return Frame[key] or (type(key) == "string" and key:find("^%u") and Nothing or nil)
end

local function NewFrame(kind, parent)
	local frame = setmetatable({ kind = kind or "Frame", parent = parent, children = {}, scripts = {}, shown = true,
		events = {} }, Frame)
	if parent then
		parent.children[#parent.children + 1] = frame
	end
	return frame
end

function Frame:GetChildren() return unpack(self.children) end
function Frame:GetParent() return self.parent end
function Frame:IsObjectType(kind) return self.kind == kind end
function Frame:GetHeight() return 24 end
function Frame:GetStringWidth() return 40 end
function Frame:IsEnabled() return self.enabled ~= false end
function Frame:SetEnabled(enabled) self.enabled = enabled and true or false end
function Frame:SetText(text) self.textValue = text end
function Frame:GetText() return self.textValue end
function Frame:CreateTexture() return NewFrame("Texture") end
function Frame:CreateFontString() return NewFrame("FontString") end
function Frame:GetHighlightTexture() return NewFrame("Texture") end
function Frame:RegisterEvent(event) self.events[event] = true end
function Frame:SetScript(name, fn) self.scripts[name] = fn end
function Frame:HookScript(name, fn)
	local old = self.scripts[name]
	self.scripts[name] = function(...)
		if old then old(...) end
		fn(...)
	end
end
function Frame:IsShown() return self.shown end
function Frame:IsVisible()
	return self.shown and (not self.parent or self.parent:IsVisible())
end
local function FireShow(frame)
	if frame.scripts.OnShow then frame.scripts.OnShow(frame) end
	for _, child in ipairs(frame.children) do
		if child.shown then FireShow(child) end
	end
end
function Frame:Show()
	if self.shown then return end
	self.shown = true
	if self:IsVisible() then FireShow(self) end
end
function Frame:Hide() self.shown = false end
function Frame:SetShown(shown)
	if shown then self:Show() else self:Hide() end
end
function Frame:Click()
	if self.enabled == false then return end
	if self.scripts.PreClick then self.scripts.PreClick(self) end
	if self.scripts.OnClick then self.scripts.OnClick(self) end
end

-- AuctionMaster's panel as ShoppingPanel.lua builds it, and what its Update does.
local function BuildPanel(house)
	local frame = NewFrame("Frame", house)
	frame.SetTitle = function(self, text) self.title = text end
	local inner = NewFrame("Frame", frame)
	local body = NewFrame("Frame", inner)
	local function Tab()
		local tab = NewFrame("Button", body)
		tab.text, tab.line = NewFrame("FontString"), NewFrame("Texture")
		tab.SetSelected = function(selected) tab.selected = selected end
		return tab
	end
	local panel = { frame = frame, body = body, listTab = Tab(), bargainsTab = Tab() }
	panel.content = NewFrame("Frame", body)
	panel.listView = NewFrame("Frame", panel.content)
	panel.bargainsView = NewFrame("Frame", panel.content)
	panel.tab = "list"
	function panel.Update()
		panel.listTab.SetSelected(panel.tab == "list")
		panel.bargainsTab.SetSelected(panel.tab == "bargains")
		panel.listView:SetShown(panel.tab == "list")
		panel.bargainsView:SetShown(panel.tab == "bargains")
		frame:SetTitle(panel.tab == "list" and "Shopping list" or "Bargains")
	end
	panel.listTab:SetScript("OnClick", function() panel.tab = "list" panel.Update() end)
	panel.bargainsTab:SetScript("OnClick", function() panel.tab = "bargains" panel.Update() end)
	panel.Update()
	return panel
end

-- A fresh game with the addon loaded. withPanel: AuctionMaster's panel exists.
local function NewWorld(withPanel)
	w = { now = 1000, timers = {}, frames = {}, prints = {}, sent = {}, results = {}, prices = {}, bags = {},
		dataListeners = {}, level = 60, rows = {} }

	function time() return math.floor(w.now) end
	function GetTime() return w.now end
	function GetLocale() return "enUS" end
	function UnitLevel() return w.level end
	function UnitGUID() return "Player-1" end
	function UnitFactionGroup() return "Horde" end
	C_GameRules = { GetCurrentGameModeRecordID = function() return 16 end }
	AuctionMasterDB = { global = {}, factions = { ["Horde-16"] = {} } }
	function print(...) w.prints[#w.prints + 1] = table.concat({ ... }, " ") end
	function GameTooltip_Hide() end
	function hooksecurefunc(target, name, hook)
		local original = target[name]
		target[name] = function(...)
			local a, b, c = original(...)
			hook(...)
			return a, b, c
		end
	end
	function CreateFrame(kind, _, parent)
		local frame = NewFrame(kind, parent)
		w.frames[#w.frames + 1] = frame
		return frame
	end
	C_Timer = { After = function(seconds, fn)
		w.timers[#w.timers + 1] = { at = w.now + seconds, fn = fn }
	end }
	C_Item = {
		GetItemCount = function(itemID) return w.bags[itemID] or 0 end,
		GetItemInfo = function(itemID) return "Crate: Item " .. itemID, nil, 1 end,
		GetItemIconByID = function() return 1 end,
	}
	C_Texture = { GetAtlasInfo = function() end }
	C_CurrencyInfo = { GetCurrencyInfo = function() return { iconFileID = 7 } end }
	C_AuctionHouse = {
		MakeItemKey = function(itemID) return { itemID = itemID } end,
		GetItemKeyInfo = function() return { isCommodity = true } end,
		IsThrottledMessageSystemReady = function() return true end,
		SendSearchQuery = function(key) w.sent[#w.sent + 1] = key.itemID end,
		SendBrowseQuery = function() end,
		ReplicateItems = function() end,
		GetNumCommoditySearchResults = function(itemID) return #(w.results[itemID] or {}) end,
		GetCommoditySearchResultInfo = function(itemID, index)
			local row = w.results[itemID][index]
			return { unitPrice = row[1], quantity = row[2], numOwnerItems = row[3] }
		end,
		HasFullCommoditySearchResults = function(itemID) return w.full ~= false end,
	}
	Enum = { AuctionHouseSortOrder = { Buyout = 1, Bid = 2 } }
	ITEM_QUALITY_COLORS = { [1] = { hex = "|cffffffff" } }
	ScrollBoxConstants = { RetainScrollPosition = 1 }
	AuctionHouseFrameDisplayMode = { Buy = 1, ItemBuy = 2, CommoditiesBuy = 3 }
	GameFontHighlight, GameFontHighlightSmall, GameFontNormalSmall = {}, {}, {}
	GameTooltip = NewFrame("GameTooltip")
	function CreateDataProvider(items) return items end
	function CreateScrollBoxListLinearView()
		return { SetElementExtentCalculator = function() end,
			SetElementFactory = function(self, fn) self.factory = fn end }
	end
	ScrollUtil = { InitScrollBoxListWithScrollBar = function(scrollBox, _, view)
		scrollBox.SetDataProvider = function(_, items)
			w.rows = {}
			for _, item in ipairs(items) do
				view.factory(function(kind, initializer)
					local row = NewFrame(kind)
					initializer(row, item)
					w.rows[#w.rows + 1] = row
				end)
			end
		end
	end }
	AuctionMaster = { API = {
		GetLowestPrice = function(itemID) return w.prices[itemID] and w.prices[itemID][1] end,
		GetAvailableQuantity = function(itemID) return w.prices[itemID] and w.prices[itemID][2] end,
		AddDataChangeListener = function(fn) w.dataListeners[#w.dataListeners + 1] = fn return true end,
	} }
	AuctionMasterExtensionsDB = nil
	AuctionHouseFrame = NewFrame("Frame")
	AuctionHouseFrame.GetDisplayMode = function() return 1 end
	AuctionHouseFrame.SetDisplayMode = function() end
	AuctionHouseFrame.SearchBar, AuctionHouseFrame.CommoditiesBuyFrame = false, false
	AuctionHouseFrame.SelectBrowseResult = function(_, result) w.opened = result.itemKey.itemID end
	NewFrame("Frame", AuctionHouseFrame) -- a frame of the game
	if withPanel then
		w.panel = BuildPanel(AuctionHouseFrame)
	end

	local ns = {}
	for _, file in ipairs(FILES) do
		assert(loadfile(dir .. "/" .. file))("AuctionMasterExtensions", ns)
	end
	w.ns = ns
	return ns
end

local function Event(event, ...)
	for _, frame in ipairs(w.frames) do
		if frame.events[event] and frame.scripts.OnEvent then
			frame.scripts.OnEvent(frame, event, ...)
		end
	end
end

-- Lets the time pass, running the timers that come due.
local function Wait(seconds)
	local target = w.now + seconds
	while true do
		local nextIndex
		for index, timer in ipairs(w.timers) do
			if timer.at <= target and (not nextIndex or timer.at < w.timers[nextIndex].at) then
				nextIndex = index
			end
		end
		if not nextIndex then break end
		local timer = table.remove(w.timers, nextIndex)
		w.now = math.max(w.now, timer.at)
		timer.fn()
	end
	w.now = target
end

-- The answer of the server to a search of the item.
local function Answer(itemID, rows)
	w.results[itemID] = rows
	Event("COMMODITY_SEARCH_RESULTS_UPDATED", itemID)
end

-- Data ---------------------------------------------------------------------------------------------

local ns = NewWorld(false)
eq(#ns.Crates.LIST, 30, "30 crates")
local seen = {}
for _, crate in ipairs(ns.Crates.LIST) do
	check(not seen[crate.id], "crate " .. crate.id .. " once")
	seen[crate.id] = true
	check(#crate.bundles >= 2, "crate " .. crate.id .. " has bundles")
	for _, bundle in ipairs(crate.bundles) do
		check(bundle.count > 0 and ns.Crates.ITEMS[bundle.id], "bundle of " .. crate.id)
	end
end
eq(ns.Crates.LIST[2].favor, 5, "Apprentice Ore favor")
eq(ns.Crates.LIST[20].favor, 10, "Apprentice Ingots favor")
eq(ns.Crates.LIST[27].favor, 30, "Expert Parts favor")
eq(ns.Crates.LIST[18].favor, nil, "Artisan favor unknown")
eq(ns.Crates.LIST[18].level, 35, "Artisan level")

-- Money --------------------------------------------------------------------------------------------

check(ns.Money(12345):find("^1|T.-|t 23|T.-|t$") ~= nil, "money drops copper from 1 gold")
check(ns.Money(450.4):find("^4|T.-|t 50|T.-|t$") ~= nil, "money rounds")

-- Prices -------------------------------------------------------------------------------------------

local Prices = ns.Prices
local ladder = { full = true, rows = { { 10, 5 }, { 12, 10 }, { 20, 100 } } }
eq(Prices.LadderCost(ladder, 5), 50, "ladder first row")
eq(Prices.LadderCost(ladder, 20), 5 * 10 + 10 * 12 + 5 * 20, "ladder across rows")
eq(select(2, Prices.LadderCost(ladder, 20)), true, "ladder is exact")
eq(Prices.LadderCost(ladder, 116), nil, "ladder too short")
ladder.full = false
eq(Prices.LadderCost(ladder, 116), 5 * 10 + 10 * 12 + 101 * 20, "open ladder continues at the last price")
eq(select(2, Prices.LadderCost(ladder, 116)), false, "open ladder is an estimate")
eq(Prices.LadderCost({ full = false, rows = {} }, 1), nil, "empty ladder")

eq(Prices.Cost(2770, 20), nil, "unknown item")
w.prices[2770] = { 100, 50 }
eq(Prices.Cost(2770, 20), 2000, "AuctionMaster price")
eq(select(2, Prices.Cost(2770, 20)), false, "AuctionMaster price is an estimate")
eq(Prices.Cost(2770, 51), nil, "more than is for sale")
check(Prices.IsKnown(2770) and not Prices.IsKnown(2771), "known items")

Answer(2770, { { 90, 10 }, { 80, 4, 4 }, { 110, 30 } })
eq(Prices.Cost(2770, 20), 10 * 90 + 10 * 110, "ladder from a search, own auctions left out")
eq(select(2, Prices.Cost(2770, 20)), true, "search price is exact")
check(Prices.IsFresh(2770), "fresh after a search")
Answer(5, { { 1, 1 } })
eq(Prices.Cost(5, 1), nil, "other items are not kept")

Wait(601)
eq(Prices.Cost(2770, 20), 2000, "old ladder no longer used")

Answer(2770, { { 90, 100 } })
C_AuctionHouse.ReplicateItems()
check(Prices.IsScanBusy(), "full scan runs")
Event("REPLICATE_ITEM_LIST_UPDATE")
for _, listener in ipairs(w.dataListeners) do listener() end
check(not Prices.IsScanBusy(), "full scan stored")
eq(Prices.Cost(2770, 20), 2000, "full scan replaces the ladders")

-- Planner ------------------------------------------------------------------------------------------

local Planner = ns.Planner
local cost, bags = {}, {}
local function costOf(itemID, count)
	local entry = cost[itemID]
	if entry then return entry[1] * count, entry[2] or false end
end
local function haveOf(itemID) return bags[itemID] or 0 end
local list = ns.Crates.LIST

eq(#Planner.Build(list, 60, costOf, haveOf), 0, "nothing known, nothing listed")

cost[248683] = { 500, true } -- Apprentice Ore, 5 Favor
cost[2770] = { 30, true } -- 20 Copper Ore = 600
cost[2771] = { 20 } -- 20 Tin Ore = 400, estimate
cost[248703] = { 300, true } -- Apprentice Ingots, 10 Favor
cost[2840] = { 100, true } -- 20 Copper Bar = 2000
cost[248699] = { 100, true } -- Artisan Curiosities, Favor unknown
cost[11176] = { 10, true }
cost[248682] = { 100, true } -- Apprentice Herbs without any herb
local plans = Planner.Build(list, 60, costOf, haveOf)
eq(#plans, 3, "three crates can be filled")
eq(plans[1].crate.id, 248683, "cheapest Favor first")
eq(plans[1].bundle.id, 2771, "cheapest bundle")
eq(plans[1].total, 900, "crate and bundle")
eq(plans[1].perFavor, 180, "per Favor")
eq(plans[1].exact, false, "an estimate in it makes the plan one")
eq(plans[2].crate.id, 248703, "second")
eq(plans[2].perFavor, 230, "second per Favor")
eq(plans[2].exact, true, "exact plan")
eq(plans[3].crate.id, 248699, "unknown Favor last")
eq(plans[3].perFavor, nil, "no per Favor without Favor")
eq(#plans[1].bundles, 2, "all bundles kept")

eq(#Planner.Build(list, 34, costOf, haveOf), 2, "level 34 cannot use Artisan")
eq(#Planner.Build(list, 9, costOf, haveOf), 0, "level 9 cannot use any")

bags[248703] = 2 -- owned crate
bags[2840] = 15 -- 5 Copper Bar missing = 500
plans = Planner.Build(list, 60, costOf, haveOf)
eq(plans[1].crate.id, 248703, "owned crate first")
eq(plans[1].crateCost, 0, "owned crate is free")
eq(plans[1].bundle.missing, 5, "bags count")
eq(plans[1].perFavor, 50, "per Favor of the rest")
bags[2840] = 99
plans = Planner.Build(list, 60, costOf, haveOf)
eq(plans[1].total, 0, "all in bags")
eq(plans[1].bundle.have, 20, "have is capped at the need")

bags[248682] = 1 -- owned crate nothing can be bought for
plans = Planner.Build(list, 60, costOf, haveOf)
eq(plans[#plans].crate.id, 248682, "owned crate without a bundle last")
eq(plans[#plans].bundle, nil, "no bundle")
bags = {}

plans = Planner.Build(list, 60, costOf, haveOf, "total")
eq(plans[1].crate.id, 248699, "overall: cheapest crate and bundle first, Favor known or not")
eq(plans[1].total, 300, "overall: its total")
eq(plans[2].crate.id, 248683, "overall: second")
eq(plans[3].crate.id, 248703, "overall: third")
bags[248703], bags[2840] = 1, 20
eq(Planner.Build(list, 60, costOf, haveOf, "total")[1].crate.id, 248703, "overall: owned crate and bundle cost nothing")
bags = {}

plans = Planner.Build(list, 19, costOf, haveOf)
local order = Planner.SearchOrder(list, 19, plans, function(itemID) return cost[itemID] ~= nil end, haveOf)
eq(order[1], 248683, "search: best crate")
eq(order[2], 2771, "search: its bundle")
eq(order[3], 248703, "search: next crate")
eq(order[4], 2840, "search: its bundle")
eq(order[5], 2770, "search: other bundles after")
local position = {}
for index, itemID in ipairs(order) do
	check(not position[itemID], "search: " .. itemID .. " once")
	position[itemID] = index
end
check(position[248682] < position[3576], "search: known items before unknown ones")
check(position[248686] ~= nil and position[248690] == nil, "search: only crates of the level")
eq(#order, 14 + 44, "search: every crate and material up to Journeyman")

-- Price update -------------------------------------------------------------------------------------

ns = NewWorld(false)
local Scan = ns.Scan
Scan.Start({ 2770, 2771, 2840 })
check(Scan.IsRunning(), "update runs")
eq(w.sent[1], 2770, "first query")
eq(#w.sent, 1, "one query at a time")
Answer(2770, { { 50, 100 } })
Answer(2770, { { 50, 100 } }) -- the game fires twice
Wait(0.5)
eq(#w.sent, 1, "pause after the answer")
Wait(0.5)
eq(w.sent[2], 2771, "second query")
eq(select(1, Scan.GetProgress()), 1, "progress")
Wait(4)
eq(#w.sent, 2, "waits for the answer")
Wait(2)
eq(ns.Prices.Cost(2771, 1), nil, "no answer: nobody sells it")
eq(w.sent[3], 2840, "third query")
C_AuctionHouse.SendBrowseQuery() -- the player searches
Wait(6)
eq(w.sent[4], 2840, "sent again after a search of someone else")
check(ns.Prices.Cost(2840, 1) == nil and not ns.Prices.IsFresh(2840), "not counted as empty")
Answer(2840, { { 70, 100 } })
Wait(1)
check(not Scan.IsRunning(), "update done")
eq(ns.Prices.Cost(2840, 20), 1400, "price after the update")

Scan.Start({ 2770, 2840 })
check(not Scan.IsRunning(), "fresh items are not searched again")
Wait(200)
Scan.Start({ 2770, 2840 })
check(Scan.IsRunning(), "searched again later")
Event("AUCTION_HOUSE_CLOSED")
check(not Scan.IsRunning(), "stops when the auction house closes")

-- The tab --------------------------------------------------------------------------------------

ns = NewWorld(true)
local panel = w.panel
w.prices[248683] = { 500, 10 } -- Apprentice Ore, 5 Favor
w.prices[2771] = { 20, 500 } -- 20 Tin Ore = 400: 900 in all, 180 per Favor
w.prices[248703] = { 300, 10 } -- Apprentice Ingots, 10 Favor
w.prices[2840] = { 60, 500 } -- 20 Copper Bar = 1200: 1500 in all, 150 per Favor
Event("AUCTION_HOUSE_SHOW")
Wait(3)
eq(#w.prints, 0, "no message when the panel is found")
local tab, view = panel.body.children[4], panel.content.children[3]
check(tab ~= nil and view ~= nil, "tab and view added")
check(not view:IsShown() and panel.listView:IsShown(), "AuctionMaster's view stays at first")

local function Text(row, part)
	return row[part].textValue or ""
end
local function Has(row, part, text)
	return Text(row, part):find(text, 1, true) ~= nil
end

tab:Click()
check(view:IsShown() and not panel.listView:IsShown() and not panel.bargainsView:IsShown(), "our view shown")
eq(panel.frame.title, "Crates", "title")
eq(panel.listTab.selected, false, "their tab not chosen")
eq(AuctionMasterExtensionsDB.cratesTab, true, "choice saved")

-- a block per crate: crate, what to buy (2), total; a gap between the blocks
eq(#w.rows, 9, "two blocks of four rows and a gap")
check(Has(w.rows[1], "left", "Item 248703") and not Has(w.rows[1], "left", "Crate:"), "cheapest Favor first, name shortened")
eq(Text(w.rows[1], "mid"), "10 |T7:0|t", "Favor of the crate")
check(Text(w.rows[1], "right"):find("^~1|T.-|t 50|T.-|t / |T7:0|t$") ~= nil, "then what a Favor costs")
check(Has(w.rows[2], "left", "Crate") and Text(w.rows[2], "right"):find("^~3|T") ~= nil, "crate row")
check(Has(w.rows[3], "left", "20 Crate: Item 2840") and Text(w.rows[3], "right"):find("^~12|T") ~= nil, "bundle row")
check(Has(w.rows[4], "right", "Total") and Has(w.rows[4], "right", "~15|T"), "total row")
eq(w.rows[4].add.textValue, "Add to list", "add button")
check(w.rows[4].add:IsShown() and not w.rows[3].add:IsShown(), "add button only on the total row")
eq(w.rows[5].item.kind, "gap", "gap")
check(Has(w.rows[6], "left", "Item 248683"), "second crate")
eq(Text(w.rows[6], "mid"), "5 |T7:0|t", "its Favor")
w.rows[1].scripts.OnEnter(w.rows[1])
w.rows[3].scripts.OnEnter(w.rows[3])

panel.Update() -- AuctionMaster redraws its panel
check(view:IsShown() and not panel.listView:IsShown(), "our view stays")
eq(panel.frame.title, "Crates", "title stays")
eq(panel.listTab.selected, false, "their tab stays not chosen")

w.rows[3]:Click()
eq(w.opened, 2840, "click opens the item")

-- the sort order
local perFavor, overall = view.choices[1], view.choices[2]
check(perFavor.line:IsShown() and not overall.line:IsShown(), "per Favor chosen at first")
overall:Click()
eq(AuctionMasterExtensionsDB.sort, "total", "sort order saved")
check(Has(w.rows[1], "left", "Item 248683"), "overall: cheapest crate and bundle first")
check(overall.line:IsShown() and not perFavor.line:IsShown(), "overall chosen")
perFavor:Click()
check(Has(w.rows[1], "left", "Item 248703"), "per Favor again")

-- AuctionMaster's shopping list
w.rows[4].add:Click()
local recipes = AuctionMasterDB.factions["Horde-16"].shoppingList.data.crafters["Player-1"].recipes
eq(#recipes, 1, "crate added to the shopping list")
eq(recipes[1].id, "AuctionMasterExtensions:crate:248703:2840", "its id: crate and bundle")
eq(recipes[1].qty, 1, "once")
eq(recipes[1].name, "Crate: Item 248703", "its name")
eq(recipes[1].reagents[1].itemId, 248703, "the crate is a reagent")
eq(recipes[1].reagents[1].quantity, 1, "one crate")
eq(recipes[1].reagents[2].itemId, 2840, "the bundle is a reagent")
eq(recipes[1].reagents[2].quantity, 20, "all of the bundle")
eq(recipes[1].reagents[2].itemIds[1], 2840, "item ids as AuctionMaster keeps them")
eq(w.rows[4].add.textValue, "Add to list", "button stays")
eq(Text(w.rows[4], "count"), "×1", "how many are on the list")
eq(Text(w.rows[9], "count"), "", "none of the other crate")
eq(Text(w.rows[3], "count"), "", "no count on other rows")
w.rows[4].add:Click()
w.rows[4].add:Click()
eq(#recipes, 1, "more clicks, same entry")
eq(recipes[1].qty, 3, "one more per click")
eq(Text(w.rows[4], "count"), "×3", "count follows")
check(ns.List.Add({ crate = { id = 248703 }, bundle = { id = 3576, count = 20 } }), "the same crate with another bundle")
eq(#recipes, 2, "is an entry of its own")
eq(recipes[2].reagents[2].itemId, 3576, "with that bundle")
eq(ns.List.Count(248703), 4, "counted per crate")
eq(ns.List.Count(2487), 0, "another id that starts alike is not counted")
AuctionMasterDB.factions["Horde-16"].shoppingList.data.activeGuid = "Player-2"
w.rows[9].add:Click()
eq(#recipes, 3, "second crate added")
eq(ns.List.Count(248683), 1, "its count")
eq(AuctionMasterDB.factions["Horde-16"].shoppingList.data.activeGuid, nil, "the list added to is the one shown")
eq(#w.prints, 0, "no message")

-- what is owned costs nothing
w.bags[248683] = 1
w.bags[2771] = 5
Event("BAG_UPDATE_DELAYED")
Wait(0.2)
check(Has(w.rows[1], "left", "Item 248683"), "owned crate is now the cheapest Favor")
check(Text(w.rows[1], "right"):find("^~60|T") ~= nil, "15 Tin Ore for 5 Favor")
check(Has(w.rows[2], "right", "Owned"), "owned crate")
check(Has(w.rows[3], "left", "5/20 Crate: Item 2771"), "partly owned bundle")
check(Has(w.rows[4], "right", "~3|T"), "total of what is left to buy")

view.button:Click()
check(ns.Scan.IsRunning(), "update button")
eq(w.sent[1], 2771, "owned crate is not searched")
eq(view.status.textValue, "0 / " .. select(2, ns.Scan.GetProgress()), "progress shown")
view.button:Click()
check(not ns.Scan.IsRunning(), "stop button")

panel.bargainsTab:Click()
check(not view:IsShown() and panel.bargainsView:IsShown(), "their tab gives the panel back")
eq(panel.frame.title, "Bargains", "their title")
eq(AuctionMasterExtensionsDB.cratesTab, false, "choice saved again")

-- AuctionMaster's data is not where it is expected: nothing is written.
ns = NewWorld(true)
AuctionMasterDB = { factions = { Horde = {} } }
w.prices[248683], w.prices[2771] = { 500, 10 }, { 20, 500 }
Event("AUCTION_HOUSE_SHOW")
Wait(1)
w.panel.body.children[4]:Click()
w.rows[4].add:Click()
eq(w.prints[1] and w.prints[1]:find("Shopping list not found", 1, true) ~= nil, true, "message when the list is not found")
eq(next(AuctionMasterDB.factions.Horde), nil, "nothing written")
AuctionMasterDB = { factions = { ["Horde-16"] = { shoppingList = { version = 1, data = { crafters = "?" } } } } }
check(not ns.List.Add({ crate = { id = 248683 }, bundle = { id = 2771, count = 20 } }), "unexpected data is left alone")
eq(AuctionMasterDB.factions["Horde-16"].shoppingList.data.crafters, "?", "as it was")

-- The choice is kept for the next time.
ns = NewWorld(true)
AuctionMasterExtensionsDB = { cratesTab = true }
Event("AUCTION_HOUSE_SHOW")
Wait(1)
check(w.panel.content.children[3]:IsShown() and not w.panel.listView:IsShown(), "our tab chosen again")

-- A panel that changed.
ns = NewWorld(false)
Event("AUCTION_HOUSE_SHOW")
Wait(3)
eq(#w.prints, 1, "one message when the panel is missing")
check(w.prints[1] and w.prints[1]:find("Crates tab not added", 1, true) ~= nil, "the message")
Event("AUCTION_HOUSE_SHOW")
Wait(3)
eq(#w.prints, 1, "only once")

io.write(("%d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
