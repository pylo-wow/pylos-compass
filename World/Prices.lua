local _, D = ...

-- Vendor prices without any discount (a reputation discount would skew everything).
-- Base: the neutral-standing price for one, from Data\ItemPrices.lua (ItemSparse BuyPrice /
-- VendorStackCount). Each merchant window checks it:
--   visit factor  what this vendor takes off now (reputation, PvP rank, ...): the factor most
--                 items agree on (observed bundle price vs base x bundle size, within
--                 ROUNDING); needs at least MIN_AGREE items and more than half, so one odd
--                 item cannot set it. Limited-stock items are ignored (maybe special offers).
--   no factor     (few items with a base, or no agreement) use the factor learned earlier at
--                 this vendor and standing, else at that standing anywhere (UnitReaction), if
--                 the window's items agree with it; else observations wait as pending.
--   each item     observed price divided by the factor; if it does not fit the base, the base
--                 is wrong for Forever (or missing) and the neutral price is kept as an
--                 override (dropped once the data fits again). Limited items never override a base.
-- Items with an extended cost (tokens, honour) are ignored.
-- Rounding: the server rounds a bundle's discounted price (vmangos: uint32(BuyPrice * discount
-- + 0.5)); ROUNDING allows one copper either way so floor or ceiling fit too. Discount steps
-- are not assumed (vmangos/pre-2.3: flat 10 % from honored, 10 % more from PvP rank 3; TBC on:
-- 5 % per standing above neutral; Forever's are unknown).
-- PylosCompassWorldDB.vendorPrices:
--   items      item ID -> copper for one at neutral standing (an override)
--   vendors    NPC ID -> { reaction = UnitReaction at last visit, factor = factor then (nil if unknown) }
--   reactions  UnitReaction (4 neutral ... 8 exalted) -> last factor found at a vendor of that standing
--   pending    item ID -> { npc, reaction, price, quantity, limited }: observation awaiting a factor
-- State "prices": an override or factor changed.

local ROUNDING = 1  -- copper either way on a bundle's price
local MIN_AGREE = 2 -- items that must agree on a visit's factor
local EPSILON = 1e-6

local Bump = D.BumpState

-- Data prices: item ID -> copper for one (built from the pairs on first use)
local data
local function DataPrice(itemID)
    if not data then
        data = {}
        local list = D.itemPrices or {}
        for i = 1, #list, 2 do data[list[i]] = list[i + 1] end
    end
    return data[itemID]
end

local function Saved() return D.world and D.world.vendorPrices end

local function Fits(price, neutral, factor)
    return math.abs(price - neutral * factor) <= ROUNDING + EPSILON
end

-- A value inside [lo, hi] with few decimals (0.9 rather than 0.9003)
local function Plain(lo, hi)
    local mid = (lo + hi) / 2
    for _, scale in ipairs({ 100, 1000, 10000 }) do
        local value = math.floor(mid * scale + 0.5) / scale
        if value >= lo - EPSILON and value <= hi + EPSILON then return value end
    end
    return mid
end

-- The factor most estimates agree on: each estimate (price, neutral) allows factors
-- [(price - ROUNDING) / neutral, (price + ROUNDING) / neutral]; picks the point most cover.
-- Returns the factor and how many agree.
local function Agreement(estimates)
    local ends = {}
    for _, e in ipairs(estimates) do
        ends[#ends + 1] = { (e.price - ROUNDING) / e.neutral, 1 }
        ends[#ends + 1] = { (e.price + ROUNDING) / e.neutral, -1 }
    end
    -- starts sort before ends at the same value (touching intervals agree)
    table.sort(ends, function(a, b) if a[1] ~= b[1] then return a[1] < b[1] end return a[2] > b[2] end)
    local count, best, lo, hi = 0, 0, nil, nil
    for i, point in ipairs(ends) do
        count = count + point[2]
        if count > best then best, lo, hi = count, point[1], ends[i + 1][1] end
    end
    if best == 0 then return nil, 0 end
    return Plain(lo, hi), best
end

local function Agreeing(estimates, factor)
    local n = 0
    for _, e in ipairs(estimates) do
        if Fits(e.price, e.neutral, factor) then n = n + 1 end
    end
    return n
end

-- Checks one item's observed price at a factor and sets the override it needs, if any.
-- Returns true if something changed.
local function Check(saved, itemID, price, quantity, factor, limited)
    saved.pending[itemID] = nil
    local own, base = saved.items[itemID], DataPrice(itemID)
    if base and Fits(price, base * quantity, factor) then
        if own then saved.items[itemID] = nil return true end -- the data fits again
        return false
    end
    if own and Fits(price, own * quantity, factor) then return false end
    if (own or base) and limited then return false end
    local neutral = math.floor(price / factor + 0.5) / quantity
    if neutral == own then return false end
    saved.items[itemID] = neutral
    return true
end

local function Learned(saved, npcID, reaction)
    local vendor = saved.vendors[npcID]
    if vendor and vendor.reaction == reaction and vendor.factor then return vendor.factor end
    return saved.reactions[reaction]
end

local function WindowItems()
    local list = {}
    for index = 1, GetMerchantNumItems() or 0 do
        local price, quantity, available, extended
        local info = C_MerchantFrame.GetItemInfo(index)
        if info then
            price, quantity, available, extended = info.price, info.stackCount, info.numAvailable, info.hasExtendedCost
        end
        local itemID = D.ItemIDFromLink(GetMerchantItemLink(index))
        local secret = D.Secret(price) or D.Secret(quantity) or D.Secret(available) or D.Secret(extended)
        if itemID and not secret and price and price > 0 and not extended then
            list[#list + 1] = { itemID = itemID, price = price, quantity = math.max(quantity or 1, 1),
                limited = (available or -1) > 0 }
        end
    end
    return list
end

local function NotePrices()
    local saved = Saved()
    if not saved then return end
    local npcID = D.NPCOf("npc")
    local reaction = UnitReaction("npc", "player")
    if not npcID or D.Secret(reaction) or not reaction then return end
    local list = WindowItems()
    if #list == 0 then return end -- not loaded yet (MERCHANT_UPDATE follows)
    -- estimates: items with a base and unlimited stock
    local estimates = {}
    for _, item in ipairs(list) do
        local base = saved.items[item.itemID] or DataPrice(item.itemID)
        if base and not item.limited then
            estimates[#estimates + 1] = { price = item.price, neutral = base * item.quantity }
        end
    end
    local changed = false
    local vendor = saved.vendors[npcID]
    if not vendor then
        vendor = {}
        saved.vendors[npcID] = vendor
    end
    if vendor.reaction ~= reaction then
        -- the factor belonged to the old standing
        vendor.reaction, vendor.factor = reaction, nil
        changed = true
    end
    local factor, agree = Agreement(estimates)
    local measured = factor ~= nil and agree >= MIN_AGREE and agree * 2 > #estimates
    if measured then
        if vendor.factor ~= factor or saved.reactions[reaction] ~= factor then changed = true end
        vendor.factor, saved.reactions[reaction] = factor, factor
    else
        factor = Learned(saved, npcID, reaction)
        if factor and #estimates > 0 and Agreeing(estimates, factor) * 2 <= #estimates then factor = nil end
    end
    for _, item in ipairs(list) do
        if factor then
            if Check(saved, item.itemID, item.price, item.quantity, factor, item.limited) then changed = true end
        else
            saved.pending[item.itemID] = { npc = npcID, reaction = reaction, price = item.price,
                quantity = item.quantity, limited = item.limited or nil }
        end
    end
    -- a factor was measured: resolve what waited for this vendor or standing
    if measured then
        for itemID, seen in pairs(saved.pending) do
            local f = Learned(saved, seen.npc, seen.reaction)
            if f and Check(saved, itemID, seen.price, seen.quantity, f, seen.limited) then changed = true end
        end
    end
    if changed then Bump("prices") end
end
D.On("MERCHANT_SHOW", NotePrices)
D.On("MERCHANT_UPDATE", NotePrices)

-- Neutral-standing price for one (copper): seen in Forever, else the data's; nil if unknown
function D.Price(itemID)
    local saved = Saved()
    return saved and saved.items[itemID] or DataPrice(itemID)
end

-- Price factor at a vendor (0.9: 10 % off): from its last visit, else the last one found at a
-- vendor of the same standing; nil if never visited
function D.PriceFactor(npcID)
    local saved = Saved()
    local vendor = saved and saved.vendors[npcID]
    if not vendor then return nil end
    return vendor.factor or saved.reactions[vendor.reaction]
end

-- What you pay for one at a vendor (copper): base times D.PriceFactor (1 if unknown); nil if no base
function D.PriceAt(itemID, npcID)
    local base = D.Price(itemID)
    if not base then return nil end
    return base * (npcID and D.PriceFactor(npcID) or 1)
end
