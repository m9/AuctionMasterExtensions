local _, ns = ...

-- Ranks the crates by what one Favor costs. Plain functions: prices and bags are passed in.
--   costOf(itemID, count)  copper and whether it is exact, nil if it cannot be bought
--   haveOf(itemID)         count the character owns
local Planner = {}
ns.Planner = Planner

-- The order of the plans. "favor": what one Favor costs, crates without a known Favor after the others by their
-- total. "total": what crate and bundle cost together. Owned crates nothing can be bought for come last.
local function Sorter(mode)
	local function Group(plan)
		if mode == "total" then
			return plan.total and 1 or 3
		end
		return plan.perFavor and 1 or plan.total and 2 or 3
	end
	local function Value(plan)
		return mode ~= "total" and plan.perFavor or plan.total or 0
	end
	return function(a, b)
		local groupA, groupB = Group(a), Group(b)
		if groupA ~= groupB then
			return groupA < groupB
		end
		local valueA, valueB = Value(a), Value(b)
		if valueA ~= valueB then
			return valueA < valueB
		end
		return a.crate.id < b.crate.id
	end
end

-- A plan per crate the character can use and get: the crate and its cheapest bundle, sorted by mode ("favor" if
-- omitted, or "total"). What is owned does not have to be bought and costs nothing.
--   plan.crate, plan.owned     the crate and how many are owned (the crate then costs nothing)
--   plan.crateCost, crateExact
--   plan.bundles               every bundle: id, count, have, missing, cost, exact (cost nil: not for sale)
--   plan.bundle                the cheapest of them, nil if none is for sale
--   plan.total, plan.exact     crate and bundle; plan.perFavor is nil while the Favor of the crate is not known
function Planner.Build(crates, level, costOf, haveOf, mode)
	local plans = {}
	for _, crate in ipairs(crates) do
		local owned = haveOf(crate.id)
		local crateCost, crateExact = 0, true
		if owned == 0 then
			crateCost, crateExact = costOf(crate.id, 1)
		end
		if level >= crate.level and crateCost then
			local plan = { crate = crate, owned = owned, crateCost = crateCost, crateExact = crateExact, bundles = {} }
			for index, bundle in ipairs(crate.bundles) do
				local have = math.min(haveOf(bundle.id), bundle.count)
				local missing = bundle.count - have
				local cost, exact = 0, true
				if missing > 0 then
					cost, exact = costOf(bundle.id, missing)
				end
				local option = { id = bundle.id, count = bundle.count, have = have, missing = missing, cost = cost,
					exact = exact }
				plan.bundles[index] = option
				if cost and (not plan.bundle or cost < plan.bundle.cost) then
					plan.bundle = option
				end
			end
			if plan.bundle then
				plan.total = crateCost + plan.bundle.cost
				plan.exact = (crateExact and plan.bundle.exact) and true or false
				plan.perFavor = crate.favor and plan.total / crate.favor
			end
			if plan.bundle or owned > 0 then
				plans[#plans + 1] = plan
			end
		end
	end
	table.sort(plans, Sorter(mode))
	return plans
end

-- The items to search for exact prices, the ones that decide the top of the list first: the crate and the bundle of
-- every plan, then the other bundles, then the crates without a plan. Items without any known price come last, as a
-- search for an item nobody sells takes long. Owned crates and bundles are left out.
function Planner.SearchOrder(crates, level, plans, isKnown, haveOf)
	local order, later, seen = {}, {}, {}
	local function Add(itemID)
		if not seen[itemID] then
			seen[itemID] = true
			local list = isKnown(itemID) and order or later
			list[#list + 1] = itemID
		end
	end
	local function AddBundles(crate)
		for _, bundle in ipairs(crate.bundles) do
			if haveOf(bundle.id) < bundle.count then
				Add(bundle.id)
			end
		end
	end
	local planned = {}
	for _, plan in ipairs(plans) do
		planned[plan.crate] = true
		if plan.owned == 0 then
			Add(plan.crate.id)
		end
		if plan.bundle and plan.bundle.missing > 0 then
			Add(plan.bundle.id)
		end
	end
	for _, plan in ipairs(plans) do
		AddBundles(plan.crate)
	end
	for _, crate in ipairs(crates) do
		if level >= crate.level and not planned[crate] then
			Add(crate.id)
			AddBundles(crate)
		end
	end
	for _, itemID in ipairs(later) do
		order[#order + 1] = itemID
	end
	return order
end
