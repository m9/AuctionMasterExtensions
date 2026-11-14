local _, ns = ...
local L = ns.L
local Crates, Prices, Planner, Scan, List = ns.Crates, ns.Prices, ns.Planner, ns.Scan, ns.List

-- A third tab in AuctionMaster's panel beside the Buy tab (Shopping list, Bargains): the crates worth buying.
-- AuctionMaster keeps the panel to itself, so its frames are found by their shape. Nothing of it is replaced: while
-- our tab is chosen its two views are hidden again whenever it shows one, and a click on one of its tabs gives the
-- panel back. If the panel has changed and is not found, one line is printed and nothing else happens.
--
-- A crate is a block of rows in the list:
--   [icon] Apprentice Ore              5 [Favor]    1s 80c / [Favor]     the reward, then what one Favor costs
--          Crate                                                  5s     what to buy, or "Owned"
--          20 Tin Ore                                             4s
--          [Add to list] ×2                              Total    9s     each click puts one more on the list
-- The two numbers of the top row have a column each, so they line up from crate to crate.

local PADDING = 8
local FOOTER_HEIGHT = 22
local SORT_HEIGHT = 20 -- the strip above the list with the sort order
local HEAD_HEIGHT, ROW_HEIGHT, TOTAL_HEIGHT, GAP_HEIGHT = 24, 18, 24, 6
local INDENT = 24 -- of the rows below the crate
local COST_WIDTH = 92 -- column of what a Favor costs, the Favor column is left of it
local GUTTER = 22 -- room right of the list for the scroll bar
local INSET = 3 -- border of the sunken panel
local EMBER = { 0.973, 0.322, 0 } -- line below the chosen tab, as on AuctionMaster's tabs
local WHITE = "Interface\\Buttons\\WHITE8X8"
local LIST_FILL = "auctionhouse-background-index"

local am -- AuctionMaster's panel: frame, body, listTab, bargainsTab, content, listView, bargainsView
local tab, view
local active = false -- our tab is the one chosen
local hooked, warned = false, false
local refreshPending = false
local plans = {}

local function DB()
	AuctionMasterExtensionsDB = AuctionMasterExtensionsDB or {}
	return AuctionMasterExtensionsDB
end

-- What the character owns and so does not have to buy: bags, bank and reagent bank, as AuctionMaster's shopping
-- list counts it.
local function Have(itemID)
	return C_Item.GetItemCount(itemID, true, false, true, true) or 0
end

local function SortMode()
	return DB().sort == "total" and "total" or "favor"
end

local function Name(itemID)
	return C_Item.GetItemInfo(itemID) or ("item " .. itemID)
end

local function Price(cost, exact)
	return (exact and "" or "~") .. ns.Money(cost)
end

local function Colored(hex, text)
	return "|cff" .. hex .. text .. "|r"
end

local favorIcon
local function FavorIcon()
	if favorIcon == nil then
		local info = C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo and C_CurrencyInfo.GetCurrencyInfo(Crates.CURRENCY)
		favorIcon = info and info.iconFileID and ("|T" .. info.iconFileID .. ":0|t") or false
	end
	return favorIcon or L.favor
end

-- Opening an item in the buy view ----------------------------------------------------------------

local pendingItem -- waits for the item key info
local pendingQuantity -- { itemID, quantity } to enter once the commodity is shown

-- True if the quantity was entered. A click older than a few seconds no longer counts.
local function ApplyQuantity()
	local pending = pendingQuantity
	local buy = AuctionHouseFrame and AuctionHouseFrame.CommoditiesBuyFrame
	local event = AuctionHouseFrameMixin and AuctionHouseFrameMixin.Event
	if pending and GetTime() - pending.time < 10 and event and buy and buy:IsShown() and buy.GetItemID
		and buy:GetItemID() == pending.itemID then
		AuctionHouseFrame:TriggerEvent(event.CommoditiesQuantitySelectionChanged, pending.quantity)
		return true
	end
	return false
end

-- Shows the item in the buy view of the auction house, with the quantity entered.
local function OpenItem(itemID, quantity)
	if not (AuctionHouseFrame and AuctionHouseFrame:IsShown()) then
		return
	end
	pendingQuantity = { itemID = itemID, quantity = quantity, time = GetTime() }
	local key = C_AuctionHouse.MakeItemKey(itemID)
	-- the game asks the server for the key info on the first call, ITEM_KEY_ITEM_INFO_RECEIVED tells when it is there
	if not C_AuctionHouse.GetItemKeyInfo(key) then
		pendingItem = itemID
		return
	end
	pendingItem = nil
	if AuctionHouseFrameDisplayMode and AuctionHouseFrame.SetDisplayMode then
		AuctionHouseFrame:SetDisplayMode(AuctionHouseFrameDisplayMode.Buy)
	end
	AuctionHouseFrame:SelectBrowseResult({ itemKey = key, minPrice = 0 })
	ApplyQuantity()
	local box = AuctionHouseFrame.SearchBar and AuctionHouseFrame.SearchBar.SearchBox
	local name = C_Item.GetItemInfo(itemID)
	if box and name then
		box:SetText(name)
	end
end

-- Rows -------------------------------------------------------------------------------------------

local MUTED, TEXT, GAIN = "a0a0a0", "e2dcd6", "1aff1a"

local Refresh

-- The item of the row. On a crate also its bundles with what each costs.
local function ShowTooltip(row)
	local item = row.item
	if not (item and item.itemID) then
		return
	end
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	GameTooltip:SetItemByID(item.itemID)
	if item.kind == "crate" then
		GameTooltip:AddLine(" ")
		for _, option in ipairs(item.plan.bundles) do
			local cost = option.missing == 0 and L.owned or option.cost and Price(option.cost, option.exact) or L.none
			GameTooltip:AddDoubleLine(option.count .. " " .. Name(option.id), cost, 0.8, 0.8, 0.8, 1, 1, 1)
		end
	end
	GameTooltip:Show()
end

local function CreateRow(row)
	row.back = row:CreateTexture(nil, "BACKGROUND")
	row.back:SetAllPoints()
	row.back:SetColorTexture(1, 1, 1, 0.07)
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	row.right = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	row.right:SetPoint("RIGHT", -6, 0)
	row.right:SetJustifyH("RIGHT")
	row.mid = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	row.mid:SetPoint("RIGHT", -(6 + COST_WIDTH), 0)
	row.mid:SetJustifyH("RIGHT")
	row.left = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	row.left:SetJustifyH("LEFT")
	row.left:SetWordWrap(false)
	row.add = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
	row.add:SetSize(84, 18)
	row.add:SetPoint("LEFT", INDENT, 0)
	row.add:SetNormalFontObject(GameFontNormalSmall)
	row.add:SetHighlightFontObject(GameFontHighlightSmall)
	-- how many of the crate are on the shopping list
	row.count = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	row.count:SetPoint("LEFT", row.add, "RIGHT", 6, 0)
	row.add:SetScript("OnClick", function()
		local plan = row.item and row.item.plan
		if plan and not List.Add(plan) then
			ns.Print(L.noList)
		end
		Refresh()
	end)
	row:SetHighlightTexture(WHITE)
	row:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.08)
	row:SetScript("OnClick", function(self)
		local item = self.item
		if item and item.itemID then
			OpenItem(item.itemID, item.count)
		end
	end)
	row:SetScript("OnEnter", ShowTooltip)
	row:SetScript("OnLeave", GameTooltip_Hide)
end

local function SetupRow(row, item)
	if not row.left then
		CreateRow(row)
	end
	row.item = item
	local isCrate = item.kind == "crate"
	row.back:SetShown(isCrate)
	row.icon:SetShown(item.itemID ~= nil)
	row.left:ClearAllPoints()
	if item.itemID then
		local size = isCrate and 18 or 14
		row.icon:SetSize(size, size)
		row.icon:ClearAllPoints()
		row.icon:SetPoint("LEFT", isCrate and 4 or INDENT, 0)
		row.icon:SetTexture(C_Item.GetItemIconByID(item.itemID))
		row.left:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
	else
		row.left:SetPoint("LEFT", INDENT, 0)
	end
	row.left:SetPoint("RIGHT", isCrate and row.mid or row.right, "LEFT", -8, 0)
	row.left:SetFontObject(isCrate and GameFontHighlight or GameFontHighlightSmall)
	row.left:SetText(item.left or "")
	row.mid:SetText(item.mid or "")
	row.right:SetText(item.right or "")
	row.add:SetShown(item.kind == "total")
	local onList = item.kind == "total" and List.Count(item.plan.crate.id) or 0
	row.add:SetText(L.addList)
	row.count:SetText(onList > 0 and ("×" .. onList) or "")
	row:EnableMouse(item.itemID ~= nil)
end

-- The rows of the list, a block per plan (see the top of the file).
local function BuildItems()
	local items = {}
	local function Add(height, item)
		item.height = height
		items[#items + 1] = item
	end
	local favor = FavorIcon()
	local owned = Colored(GAIN, L.owned)
	for index, plan in ipairs(plans) do
		local crate = plan.crate
		if index > 1 then
			Add(GAP_HEIGHT, { kind = "gap" })
		end
		-- "Waylaid Crate: Apprentice Ore": the part that tells the crates apart
		local name, _, quality = C_Item.GetItemInfo(crate.id)
		name = name and (name:match(":%s*(.+)$") or name) or ("item " .. crate.id)
		local color = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
		if color and color.hex then
			name = color.hex .. name .. "|r"
		end
		Add(HEAD_HEIGHT, { kind = "crate", plan = plan, itemID = crate.id, count = 1, left = name,
			mid = (crate.favor or "?") .. " " .. favor,
			right = plan.perFavor and (Price(plan.perFavor, plan.exact) .. " / " .. favor) or Colored(MUTED, "--") })
		Add(ROW_HEIGHT, { kind = "item", itemID = crate.id, count = 1, left = Colored(TEXT, L.crate),
			right = plan.owned > 0 and owned or Price(plan.crateCost, plan.crateExact) })
		local bundle = plan.bundle
		if bundle then
			local amount = bundle.have > 0 and bundle.missing > 0 and (bundle.have .. "/" .. bundle.count) or bundle.count
			Add(ROW_HEIGHT, { kind = "item", itemID = bundle.id, count = math.max(bundle.missing, 1),
				left = Colored(TEXT, amount .. " " .. Name(bundle.id)),
				right = bundle.missing == 0 and owned or Price(bundle.cost, bundle.exact) })
			Add(TOTAL_HEIGHT, { kind = "total", plan = plan,
				right = Colored(MUTED, L.total) .. "   " .. Price(plan.total, plan.exact) })
		else
			Add(ROW_HEIGHT, { kind = "note", left = Colored(MUTED, L.none) })
		end
	end
	return items
end

-- The view ---------------------------------------------------------------------------------------

local function UpdateFooter()
	if not view then
		return
	end
	local running = Scan.IsRunning()
	view.button:SetText(running and L.stop or L.update)
	if running then
		local done, total = Scan.GetProgress()
		view.status:SetText(done .. " / " .. total)
	else
		view.status:SetText("")
	end
end

function Refresh()
	refreshPending = false
	if not (view and view:IsVisible()) then
		return
	end
	plans = Planner.Build(Crates.LIST, UnitLevel("player"), Prices.Cost, Have, SortMode())
	view.SetItems(BuildItems())
	view.empty:SetShown(#plans == 0)
	for _, choice in ipairs(view.choices) do
		choice.Update()
	end
	UpdateFooter()
end

-- Prices, bags and item names change in bursts: one redraw for all of them.
local function RefreshSoon()
	if refreshPending or not (view and view:IsVisible()) then
		return
	end
	refreshPending = true
	C_Timer.After(0.1, Refresh)
end

local function ToggleScan()
	if Scan.IsRunning() then
		Scan.Stop()
		return
	end
	Refresh()
	Scan.Start(Planner.SearchOrder(Crates.LIST, UnitLevel("player"), plans, Prices.IsKnown, Have))
end

-- The list as in the auction house: a sunken panel with the game's scroll box, the scroll bar right of it.
-- Returns the function that shows new rows, the one that scrolls to the top and the text for an empty list.
local function CreateList(parent, top)
	local panel = CreateFrame("Frame", nil, parent, "InsetFrameTemplate")
	panel:SetPoint("TOPLEFT", PADDING, -top)
	panel:SetPoint("BOTTOMRIGHT", -GUTTER, FOOTER_HEIGHT)
	if C_Texture.GetAtlasInfo(LIST_FILL) then
		local fill = panel:CreateTexture(nil, "BACKGROUND", nil, -4)
		fill:SetPoint("TOPLEFT", INSET, -INSET)
		fill:SetPoint("BOTTOMRIGHT", -INSET, INSET)
		fill:SetAtlas(LIST_FILL, false)
	end
	local shade = panel:CreateTexture(nil, "BACKGROUND", nil, 7)
	shade:SetPoint("TOPLEFT", INSET, -INSET)
	shade:SetPoint("BOTTOMRIGHT", -INSET, INSET)
	shade:SetColorTexture(0.04, 0.03, 0.03, 0.85)

	local scrollBox = CreateFrame("Frame", nil, panel, "WowScrollBoxList")
	scrollBox:SetPoint("TOPLEFT", INSET, -INSET)
	scrollBox:SetPoint("BOTTOMRIGHT", -INSET, INSET)
	local scrollBar = CreateFrame("EventFrame", nil, panel, "MinimalScrollBar")
	scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", INSET + 6, 0)
	scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", INSET + 6, 0)

	local linear = CreateScrollBoxListLinearView()
	linear:SetElementExtentCalculator(function(_, item)
		return item.height
	end)
	linear:SetElementFactory(function(factory)
		factory("Button", SetupRow)
	end)
	ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, linear)

	local empty = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	empty:SetPoint("CENTER")
	empty:SetText(L.empty)

	return function(items)
		scrollBox:SetDataProvider(CreateDataProvider(items), ScrollBoxConstants.RetainScrollPosition)
	end, function()
		scrollBox:ScrollToBegin()
	end, empty
end

-- A sort order to choose in the strip above the list: gold with a line below it while it is the one chosen.
local function CreateChoice(parent, text, mode)
	local button = CreateFrame("Button", nil, parent)
	button.text = button:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	button.text:SetPoint("CENTER")
	button.text:SetText(text)
	button:SetSize(button.text:GetStringWidth() + 14, SORT_HEIGHT)
	button.line = button:CreateTexture(nil, "ARTWORK")
	button.line:SetPoint("BOTTOMLEFT", 5, 1)
	button.line:SetPoint("BOTTOMRIGHT", -5, 1)
	button.line:SetHeight(1)
	button.line:SetColorTexture(1, 0.82, 0, 1)
	button:SetHighlightTexture(WHITE)
	button:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.08)
	button:SetScript("OnClick", function()
		if SortMode() ~= mode then
			DB().sort = mode
			Refresh()
			view.ScrollToTop()
		end
	end)
	function button.Update()
		local chosen = SortMode() == mode
		button.line:SetShown(chosen)
		if chosen then
			button.text:SetTextColor(1, 0.82, 0)
		else
			button.text:SetTextColor(0.89, 0.86, 0.84)
		end
	end
	return button
end

local Enforce

local function CreateView()
	view = CreateFrame("Frame", nil, am.content)
	view:SetAllPoints()
	view:Hide()

	-- "Cheapest  Per Favor  Overall"
	local label = view:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	label:SetPoint("LEFT", view, "TOPLEFT", PADDING + 4, -(PADDING + SORT_HEIGHT / 2))
	label:SetText(L.cheapest)
	local perFavor = CreateChoice(view, L.perFavor, "favor")
	perFavor:SetPoint("LEFT", label, "RIGHT", 6, 0)
	local overall = CreateChoice(view, L.overall, "total")
	overall:SetPoint("LEFT", perFavor, "RIGHT", 2, 0)
	view.choices = { perFavor, overall }

	view.SetItems, view.ScrollToTop, view.empty = CreateList(view, PADDING + SORT_HEIGHT + 4)

	view.button = CreateFrame("Button", nil, view, "UIPanelButtonTemplate")
	view.button:SetSize(90, FOOTER_HEIGHT - 2)
	view.button:SetPoint("BOTTOMRIGHT", -PADDING, -1)
	view.button:SetScript("OnClick", ToggleScan)
	view.status = view:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	view.status:SetPoint("LEFT", view, "BOTTOMLEFT", PADDING, FOOTER_HEIGHT / 2 - 2)

	-- the panel came back into view with our tab chosen
	view:SetScript("OnShow", function()
		Enforce()
		Refresh()
	end)
end

-- The tab --------------------------------------------------------------------------------------

-- Looks like AuctionMaster's tabs: gold text and a line below it while chosen.
local function CreateTab()
	tab = CreateFrame("Button", nil, am.body)
	tab:SetHeight(am.bargainsTab:GetHeight())
	tab:SetPoint("LEFT", am.bargainsTab, "RIGHT", 0, 0)
	tab.text = tab:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	tab.text:SetPoint("CENTER", 0, 1)
	tab.text:SetText(L.tab)
	tab:SetWidth(tab.text:GetStringWidth() + 24)
	tab.line = tab:CreateTexture(nil, "ARTWORK")
	tab.line:SetPoint("BOTTOMLEFT")
	tab.line:SetPoint("BOTTOMRIGHT")
	tab.line:SetHeight(2)
	tab:SetHighlightTexture(WHITE)
	tab:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.08)
	function tab.SetSelected(selected)
		if selected then
			tab.line:SetColorTexture(EMBER[1], EMBER[2], EMBER[3], 1)
			tab.text:SetTextColor(1, 0.82, 0)
		else
			tab.line:SetColorTexture(0, 0, 0, 0)
			tab.text:SetTextColor(0.89, 0.86, 0.84)
		end
	end
	tab.SetSelected(false)
	tab:SetScript("OnClick", function()
		active = true
		DB().cratesTab = true
		Enforce()
	end)
end

-- Puts our view in place of AuctionMaster's. Safe to call again and again.
function Enforce()
	if not active then
		return
	end
	am.listView:Hide()
	am.bargainsView:Hide()
	am.listTab.SetSelected(false)
	am.bargainsTab.SetSelected(false)
	tab.SetSelected(true)
	view:Show()
	if am.frame.SetTitle then
		am.frame:SetTitle(L.tab)
	end
end

-- A tab of AuctionMaster was clicked: it shows its own view right after.
local function Release()
	if not active then
		return
	end
	active = false
	DB().cratesTab = false
	view:Hide()
	tab.SetSelected(false)
end

-- Finding AuctionMaster's panel ----------------------------------------------------------------

local function IsTab(frame)
	return frame:IsObjectType("Button") and type(frame.SetSelected) == "function" and frame.line ~= nil
		and frame.text ~= nil
end

-- The body of the panel has three children: its two tabs and the frame holding their two views.
local function FindPanel(parent, depth)
	for _, child in ipairs({ parent:GetChildren() }) do
		local kids = { child:GetChildren() }
		if #kids == 3 and IsTab(kids[1]) and IsTab(kids[2]) and not IsTab(kids[3]) then
			local views = { kids[3]:GetChildren() }
			local inner = child:GetParent()
			local frame = inner and inner:GetParent()
			if #views == 2 and frame then
				return { frame = frame, body = child, listTab = kids[1], bargainsTab = kids[2], content = kids[3],
					listView = views[1], bargainsView = views[2] }
			end
		end
		if depth > 1 then
			local found = FindPanel(child, depth - 1)
			if found then
				return found
			end
		end
	end
end

local function Attach()
	if am or not (AuctionHouseFrame and AuctionHouseFrame:IsShown()) then
		return
	end
	local ok, found = pcall(FindPanel, AuctionHouseFrame, 3)
	if not (ok and found) then
		return
	end
	am = found
	CreateTab()
	CreateView()
	-- AuctionMaster shows one of its views on every update of the panel
	local function Reclaim()
		Enforce()
	end
	am.listView:HookScript("OnShow", Reclaim)
	am.bargainsView:HookScript("OnShow", Reclaim)
	am.listTab:HookScript("PreClick", Release)
	am.bargainsTab:HookScript("PreClick", Release)
	if type(am.frame.SetTitle) == "function" then
		hooksecurefunc(am.frame, "SetTitle", function(_, text)
			if active and text ~= L.tab then
				am.frame:SetTitle(L.tab)
			end
		end)
	end
	if DB().cratesTab then
		active = true
		Enforce()
	end
end

local function InBuyMode()
	local modes = AuctionHouseFrameDisplayMode
	local mode = AuctionHouseFrame.GetDisplayMode and AuctionHouseFrame:GetDisplayMode()
	return modes ~= nil and mode ~= nil
		and (mode == modes.Buy or mode == modes.ItemBuy or mode == modes.CommoditiesBuy)
end

-- The panel exists once the buy view was shown. Still missing some time after that: it has changed.
local function Check()
	Attach()
	if am or warned or not (AuctionHouseFrame and AuctionHouseFrame:IsShown() and InBuyMode()) then
		return
	end
	-- AuctionMaster's own window covers the buy view, the panel is not made while it is open
	local window = _G.AuctionMasterTab
	if window and not window:IsEnabled() then
		return
	end
	warned = true
	ns.Print(L.broken)
end

local events = CreateFrame("Frame")
events:RegisterEvent("AUCTION_HOUSE_SHOW")
events:RegisterEvent("BAG_UPDATE_DELAYED")
events:RegisterEvent("PLAYER_LEVEL_UP")
events:RegisterEvent("GET_ITEM_INFO_RECEIVED")
events:RegisterEvent("ITEM_KEY_ITEM_INFO_RECEIVED")
events:RegisterEvent("COMMODITY_SEARCH_RESULTS_RECEIVED")
events:SetScript("OnEvent", function(_, event, arg)
	if event == "AUCTION_HOUSE_SHOW" then
		if not hooked and AuctionHouseFrame then
			hooked = true
			if AuctionHouseFrame.SetDisplayMode then
				hooksecurefunc(AuctionHouseFrame, "SetDisplayMode", function()
					C_Timer.After(0, Attach)
				end)
			end
		end
		C_Timer.After(0.1, Attach)
		C_Timer.After(2, Check)
	elseif event == "GET_ITEM_INFO_RECEIVED" then
		if Crates.ITEMS[arg] then
			RefreshSoon()
		end
	elseif event == "ITEM_KEY_ITEM_INFO_RECEIVED" then
		if pendingItem and pendingQuantity then
			OpenItem(pendingItem, pendingQuantity.quantity)
		end
	elseif event == "COMMODITY_SEARCH_RESULTS_RECEIVED" then
		-- the game resets the quantity when the auctions arrive; after its own handlers. The answers to the
		-- price update come here too, so the click is only forgotten once its item got the quantity.
		C_Timer.After(0, function()
			if ApplyQuantity() then
				pendingQuantity = nil
			end
		end)
	else
		RefreshSoon()
	end
end)

Prices.OnChange(RefreshSoon)
Scan.OnChange(UpdateFooter)
