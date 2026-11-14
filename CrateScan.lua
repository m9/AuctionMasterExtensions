local _, ns = ...
local Prices = ns.Prices

-- Searches a list of items one after the other. Prices reads the results, and so does AuctionMaster.
-- The server throttles searches and disconnects a client that sends too many: a query is only sent once the game
-- says it is ready, after the answer to the last one and a pause, and never beside a search of someone else.
local Scan = {}
ns.Scan = Scan

local PAUSE = 0.7 -- seconds between an answer and the next query
local RETRY = 0.25 -- seconds to wait while the game is not ready
local TIMEOUT = 5 -- an item nobody sells gets no answer

local running = false
local runId = 0
local queue, done, current = {}, 0, nil
local retried = {} -- itemID -> true once its search was sent a second time
local lastQuery = 0 -- GetTime() of the last query of any addon or the player
local queries = 0 -- how many there were
local listeners = {}

function Scan.OnChange(listener)
	listeners[#listeners + 1] = listener
end

local function Fire()
	for _, listener in ipairs(listeners) do
		listener()
	end
end

function Scan.IsRunning()
	return running
end

-- Items searched so far and in all.
function Scan.GetProgress()
	return done, #queue
end

local function Finish()
	running = false
	runId = runId + 1
	current = nil
	Fire()
end

local SendNext

local function Later(seconds)
	local id = runId
	C_Timer.After(seconds, function()
		if id == runId then
			SendNext()
		end
	end)
end

local function Advance(token)
	if current ~= token then
		return
	end
	current = nil
	done = done + 1
	Fire()
	Later(PAUSE)
end

function SendNext()
	if not running then
		return
	end
	local itemID = queue[done + 1]
	if not itemID then
		Finish()
		return
	end
	if Prices.IsScanBusy() or GetTime() - lastQuery < PAUSE or not C_AuctionHouse.IsThrottledMessageSystemReady() then
		Later(RETRY)
		return
	end
	local token = { itemID = itemID }
	current = token
	local key = C_AuctionHouse.MakeItemKey(itemID)
	-- like the game: item searches are sorted by buyout, commodities get no sort
	local info = C_AuctionHouse.GetItemKeyInfo(key)
	local sorts = {}
	if info and not info.isCommodity then
		sorts = {
			{ sortOrder = Enum.AuctionHouseSortOrder.Buyout, reverseSort = false },
			{ sortOrder = Enum.AuctionHouseSortOrder.Bid, reverseSort = false },
		}
	end
	C_AuctionHouse.SendSearchQuery(key, sorts, false)
	local sent = queries
	local id = runId
	C_Timer.After(TIMEOUT, function()
		if id ~= runId or current ~= token then
			return
		end
		if queries == sent then
			Prices.SetEmpty(itemID) -- advances through the listener below
		elseif retried[itemID] then
			Advance(token)
		else
			-- another search came in between and may have replaced ours: once more
			retried[itemID] = true
			current = nil
			Later(PAUSE)
		end
	end)
end

-- Searches the items in the order given. Items searched a moment ago are left out.
function Scan.Start(items)
	if running or not (AuctionHouseFrame and AuctionHouseFrame:IsShown()) then
		return
	end
	queue, done, retried = {}, 0, {}
	for _, itemID in ipairs(items) do
		if not Prices.IsFresh(itemID) then
			queue[#queue + 1] = itemID
		end
	end
	if #queue == 0 then
		return
	end
	running = true
	runId = runId + 1
	Fire()
	SendNext()
end

function Scan.Stop()
	if running then
		Finish()
	end
end

Prices.OnChange(function(itemID)
	if current and current.itemID == itemID then
		Advance(current)
	end
end)

local function NoteQuery()
	lastQuery = GetTime()
	queries = queries + 1
end
for _, name in ipairs({ "SendSearchQuery", "SendBrowseQuery", "SendSellSearchQuery" }) do
	if C_AuctionHouse[name] then
		hooksecurefunc(C_AuctionHouse, name, NoteQuery)
	end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("AUCTION_HOUSE_CLOSED")
frame:SetScript("OnEvent", Scan.Stop)
