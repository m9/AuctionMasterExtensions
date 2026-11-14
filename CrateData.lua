local _, ns = ...

-- Waylaid Crates of WoW Forever, build 1.60.1. Read from the Wowhead Forever item tooltips on 2026-11-13.
-- A crate is filled with any one of its bundles and becomes a sealed crate of its tier, handed in for Merchant's Favor.
local Crates = {}
ns.Crates = Crates

Crates.CURRENCY = 3402 -- Merchant's Favor

-- Tiers: 1 Apprentice, 2 Journeyman, 3 Expert, 4 Artisan.
local LEVEL = { 10, 10, 20, 35 }
-- Favor of the sealed crate, plain and green. Artisan is not known yet.
local FAVOR = { { 5, 10 }, { 10, 20 }, { 15, 30 } }

-- { crate, tier, green, { item, count, ... } }. Fabrics, Ingots and Parts are green.
local DATA = {
	{ 248682, 1, false, { 2447, 20, 765, 20, 2449, 10, 785, 10, 2450, 10 } }, -- Apprentice Herbs
	{ 248683, 1, false, { 2770, 20, 2771, 20 } }, -- Apprentice Ore
	{ 248684, 1, false, { 2589, 40, 2318, 20 } }, -- Apprentice Textiles
	{ 248685, 1, false, { 10940, 20, 10939, 4, 10978, 6, 11084, 2 } }, -- Apprentice Curiosities
	{ 248686, 2, false, { 3820, 10, 2453, 10, 3355, 10, 3369, 10, 3356, 10 } }, -- Journeyman Herbs
	{ 248687, 2, false, { 2775, 10, 2772, 20 } }, -- Journeyman Ore
	{ 248688, 2, false, { 2592, 20, 4306, 40, 2319, 20 } }, -- Journeyman Textiles
	{ 248689, 2, false, { 11083, 20, 11082, 4, 11138, 6, 11139, 2 } }, -- Journeyman Curiosities
	{ 248690, 3, false, { 3357, 20, 3818, 10, 3821, 10, 3358, 10 } }, -- Earthly Expert Herbs
	{ 248691, 3, false, { 3819, 10, 4625, 10, 8831, 20, 8836, 10 } }, -- Flowering Expert Herbs
	{ 248692, 3, false, { 2776, 10, 3858, 20 } }, -- Expert Ore
	{ 248693, 3, false, { 4338, 40, 4234, 20 } }, -- Expert Textiles
	{ 248694, 3, false, { 11137, 20, 11135, 4, 11177, 6, 11178, 2 } }, -- Expert Curiosities
	{ 248695, 4, false, { 13464, 10, 8838, 20, 8839, 10, 8845, 10, 8846, 10 } }, -- Earthly Artisan Herbs
	{ 248696, 4, false, { 13463, 20, 13465, 20, 13466, 20, 13467, 20 } }, -- Flowering Artisan Herbs
	{ 248697, 4, false, { 7911, 10, 10620, 20, 11099, 20 } }, -- Artisan Ore
	{ 248698, 4, false, { 14047, 40, 4304, 20, 8170, 20 } }, -- Artisan Textiles
	{ 248699, 4, false, { 11176, 20, 11175, 4, 14343, 6, 14344, 2 } }, -- Artisan Curiosities
	{ 248702, 1, true, { 4231, 2, 2996, 20 } }, -- Apprentice Fabrics
	{ 248703, 1, true, { 2840, 20, 3576, 20, 2841, 10 } }, -- Apprentice Ingots
	{ 248704, 1, true, { 4359, 16, 4361, 16, 4363, 4 } }, -- Apprentice Parts
	{ 248705, 2, true, { 2997, 6, 4305, 10, 4233, 2 } }, -- Journeyman Fabrics
	{ 248706, 2, true, { 2842, 10, 3575, 20 } }, -- Journeyman Ingots
	{ 248707, 2, true, { 4371, 8, 4375, 7, 4382, 4, 10558, 45 } }, -- Journeyman Parts
	{ 248708, 3, true, { 4339, 8, 4236, 2 } }, -- Expert Fabrics
	{ 248709, 3, true, { 3860, 20, 3859, 15, 3577, 10 } }, -- Expert Ingots
	{ 248710, 3, true, { 4387, 8, 10559, 5, 10560, 12, 10561, 5 } }, -- Expert Parts
	{ 248711, 4, true, { 14048, 8, 8172, 2 } }, -- Artisan Fabrics
	{ 248712, 4, true, { 11371, 2, 6037, 10, 12359, 20 } }, -- Artisan Ingots
	{ 248713, 4, true, { 15994, 5, 18631, 5, 16000, 2 } }, -- Artisan Parts
}

Crates.LIST = {}
Crates.ITEMS = {} -- every crate and material

for index, row in ipairs(DATA) do
	local id, tier, green, flat = row[1], row[2], row[3], row[4]
	local favor = FAVOR[tier]
	local crate = { id = id, tier = tier, level = LEVEL[tier], favor = favor and favor[green and 2 or 1], bundles = {} }
	Crates.ITEMS[id] = true
	for i = 1, #flat, 2 do
		crate.bundles[#crate.bundles + 1] = { id = flat[i], count = flat[i + 1] }
		Crates.ITEMS[flat[i]] = true
	end
	Crates.LIST[index] = crate
end
