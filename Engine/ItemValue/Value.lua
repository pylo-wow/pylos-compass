local _, D = ...
if D.off then return end
local ns = D.engine

-- The item valuer: what an item is worth to your character by its stats (D.ItemStats; the facts stay there), weighed for
-- your class, talent tree and level (Weights.lua) with caps for hit and defense. A module apart from the reasons:
-- the host asks it via ns.UpgradeOf (the one check of "an upgrade for you"), other addons via ns.ItemValue.
--   Compare(item)   item: item ID or link -> nil (not wearable, or stats unknown), else { value, worn, gain,
--                   percent (against what you wear there; nil: free slot), share (gain in percent of all you wear),
--                   free, slot, replaces (item ID or nil), top = { stat key, ... } (what makes the difference, most
--                   first; empty unless a gain), topAmounts (key -> by how much), drops, dropAmounts (same for a loss
--                   of 3 % or more), procs (true: the new item or one it replaces has an effect the stats do not show) }
--   Total()         the worth of all you wear
--   Value(item, slot)  its worth in that slot (caps as you are now)
--   Profile()       class, tree (1-3), "leveling" or "endgame", weights
--   Weights(class, tree, profile)  a table with your changes in it
--   SetWeight(key, value), ResetWeights()  your changes, for the current profile
--   UseSettings(db)  the table holding the settings (see below)
-- Items whose stats come by chance ("of the Monkey") are known only from their link: worn ones and links are valued,
-- the bare item ID is not.

local V = {}
ns.ItemValue = V

local W = ns.ITEM_WEIGHTS
local MAX_LEVEL = 60
-- caps per profile: hit (melee and ranged) and spell hit in percent, defense as skill; above them a point counts OVER
-- of its weight. Levelling: foes of your level (5 % melee, 4 % spells); end game: raid bosses (8 %, 17 %: Forever's own
-- numbers from CR_<CLASS>_HIT_CAP_TOOLTIP in GlobalStrings; Era's were 9 and 16), defense 440 (no more critical hits
-- from a boss). An off-hand weapon (dual wielding) adds 19 % to the melee cap (24 % and 27 % in the same tooltips;
-- Forever's DUAL_WIELD_HIT_PENALTY = 19, PaperDollFrame.lua).
-- shortcut: only what is worn now counts, an off-hand weapon you compare is
-- measured against the cap of how you stand, upgrade if that matters.
local CAPS = {
    leveling = { HIT = 5, SPELLHIT = 4 },
    endgame = { HIT = 8, SPELLHIT = 17, DEF = 440 },
}
local DUAL_WIELD_HIT = 19
local OVER = { HIT = 0, SPELLHIT = 0, DEF = 0.3 }

local SLOTS = {
    INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_BODY = { 4 },
    INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 }, INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 },
    INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 }, INVTYPE_FINGER = { 11, 12 },
    INVTYPE_TRINKET = { 13, 14 }, INVTYPE_CLOAK = { 15 }, INVTYPE_WEAPON = { 16, 17 },
    INVTYPE_2HWEAPON = { 16 }, INVTYPE_WEAPONMAINHAND = { 16 }, INVTYPE_WEAPONOFFHAND = { 17 },
    INVTYPE_SHIELD = { 17 }, INVTYPE_HOLDABLE = { 17 }, INVTYPE_RANGED = { 18 }, INVTYPE_RANGEDRIGHT = { 18 },
    INVTYPE_THROWN = { 18 }, INVTYPE_RELIC = { 18 },
}
local MAIN_HAND, OFF_HAND, RANGED = 16, 17, 18
local DUAL_WIELD = 674 -- the spell
V.SLOTS = SLOTS

-- Kept while what they depend on stays the same (Core\State.lua states): the profile, comparisons, what you wear, your
-- ratings. "rec:weights": your weights and the profile options (SetWeight). A reading the client may not have yet (a
-- worn link's stats, a link not loaded) is kept for its frame only.
local states = D.Cache({ "gear", "level", "talents", "spells", "ratings", "rec:weights" })
local thisFrame = D.Cache({ "frame" })
local generation = 0 -- grows whenever the kept results are thrown away
local unsure         -- a reading the client may not have had yet was kept in this frame
local profile, compared = nil, {}
local wornData, wornID, ratings = {}, {}, nil -- slot -> stats or false; slot -> item ID
local function Fresh()
    local _, renewed = states.Get()
    local _, newFrame = thisFrame.Get()
    if renewed or (unsure and newFrame) then
        unsure = nil
        generation = generation + 1
        profile, ratings = nil, nil
        wipe(compared)
        wipe(wornData)
        wipe(wornID)
    end
end

-- Weights

-- The valuer's settings: itemSpec ("auto" or a tree "1"-"3"), itemProfile ("auto", "leveling", "endgame"), itemWeights
-- (your changes per class .. tree .. profile). The addon showing them hands its saved table over (V.UseSettings);
-- without one the defaults count.
local DEFAULT_SETTINGS = { itemSpec = "auto", itemProfile = "auto", itemWeights = {} }
local settings = DEFAULT_SETTINGS
local function Options() return settings end
function V.UseSettings(db)
    settings = db or DEFAULT_SETTINGS
    if settings.itemWeights == nil then settings.itemWeights = {} end
    ns.data.BumpState("rec:weights")
end

function V.Weights(class, tree, kind)
    local base = W[class] and W[class][tree] and W[class][tree][kind] or {}
    local own = Options() and Options().itemWeights[class .. tree .. kind]
    if not own then return base end
    local merged = {}
    for k, v in pairs(base) do merged[k] = v end
    for k, v in pairs(own) do merged[k] = v end
    return merged
end

function V.Profile()
    Fresh()
    if not profile then
        local class, tree = D.PlayerSpec()
        local options = Options()
        if options and tonumber(options.itemSpec) then tree = tonumber(options.itemSpec) end
        tree = tree or ns.ITEM_WEIGHTS_DEFAULT_TREE[class] or 1
        local kind = options and options.itemProfile ~= "auto" and options.itemProfile
            or (UnitLevel("player") < MAX_LEVEL and "leveling" or "endgame")
        profile = { class, tree, kind, V.Weights(class, tree, kind) }
    end
    return profile[1], profile[2], profile[3], profile[4]
end

function V.SetWeight(key, value)
    local options = Options()
    if not options then return end
    local class, tree, kind = V.Profile()
    local id = class .. tree .. kind
    options.itemWeights[id] = options.itemWeights[id] or {}
    options.itemWeights[id][key] = value
    if not next(options.itemWeights[id]) then options.itemWeights[id] = nil end
    D.BumpState("rec:weights")
end
function V.ResetWeights()
    local options = Options()
    if not options then return end
    local class, tree, kind = V.Profile()
    options.itemWeights[class .. tree .. kind] = nil
    D.BumpState("rec:weights")
end

-- Stats

local function ItemID(item)
    if type(item) == "number" then return item end
    return D.ItemIDFromLink(item)
end

-- an item's stats: a link's as the game tells them (they include random ones: in Forever "of the Wolf" is a bonus ID,
-- not a suffix ID in the link, and the data's randomSuffix flag only comes from items the data collection met), else Pylos
-- Data's (item ID); nil if not known
local function Stats(item)
    local itemID = ItemID(item)
    local data = itemID and D.ItemStats and D.ItemStats(itemID)
    if type(item) == "string" then
        local live = D.LiveItemStats(item)
        if live and next(live.stats) then
            -- (the data's weapon numbers where the game gives none, and its note of effects: the game's stats do not tell them)
            live.dps = live.dps or (data and data.dps)
            live.procs = data and data.procs
            return live
        end
    end
    if data and not data.randomSuffix then return data end
    return nil
end
V.Stats = Stats

local function Worn(slot)
    Fresh()
    local data = wornData[slot]
    if data == nil then
        local itemID = GetInventoryItemID("player", slot)
        data = itemID and Stats(GetInventoryItemLink("player", slot) or itemID)
        if itemID and not data then
            data, unsure = { stats = {} }, true
        end
        data = data or false
        wornData[slot], wornID[slot] = data, itemID
    end
    if not data then return nil end
    return data, wornID[slot]
end

-- Valuing

-- the worth of stats in a slot; room: what is left below each cap, nil no cap; parts: key -> worth (to say what makes
-- a difference). No closure or table per call (324 items compared per refresh made 1 MB of garbage).
local NO_STATS = {}
-- a stat's amount in the stat's own unit (DPS: damage per second)
local function Amount(d, key)
    if key == "DPS" or key == "RDPS" then return d.dps or 0 end
    return (d.stats or NO_STATS)[key] or 0
end
local function Score(data, slot, weights, room, parts)
    local total = 0
    for key, amount in pairs(data.stats or NO_STATS) do
        local weight = weights[key]
        if weight and weight ~= 0 then
            local left = room and room[key]
            local worth
            if left then
                local under = math.min(amount, math.max(left, 0))
                worth = weight * under + weight * OVER[key] * (amount - under)
            else
                worth = weight * amount
            end
            total = total + worth
            if parts then parts[key] = (parts[key] or 0) + worth end
        end
    end
    if data.dps then
        local key, worth
        if slot == RANGED then
            key, worth = "RDPS", (weights.RDPS or 0) * data.dps
        elseif slot == MAIN_HAND or slot == OFF_HAND then
            key, worth = "DPS", (weights.DPS or 0) * data.dps * (slot == OFF_HAND and 0.5 or 1)
        end
        if key then
            total = total + worth
            if parts then parts[key] = (parts[key] or 0) + worth end
        end
    end
    return total
end

local function Room(kind, replaced)
    local caps = CAPS[kind]
    Fresh()
    ratings = ratings or D.PlayerRatings()
    local room = {}
    local offHand = GetInventoryItemID("player", OFF_HAND)
    local equipLoc = offHand and select(4, C_Item.GetItemInfoInstant(offHand))
    local dualWield = equipLoc == "INVTYPE_WEAPON" or equipLoc == "INVTYPE_WEAPONOFFHAND"
    for key, cap in pairs(caps) do
        if key == "HIT" and dualWield then cap = cap + DUAL_WIELD_HIT end
        local mine = (key == "HIT" and ratings.hit or key == "SPELLHIT" and ratings.spellHit
            or key == "DEF" and ratings.defense) or 0
        for _, data in ipairs(replaced) do mine = mine - ((data.stats or NO_STATS)[key] or 0) end
        room[key] = cap - mine
    end
    return room
end

function V.Value(item, slot)
    local data = Stats(item)
    if not data then return nil end
    local _, _, kind, weights = V.Profile()
    local worn = Worn(slot)
    return Score(data, slot, weights, Room(kind, { worn }))
end

local function TwoHanderWorn()
    local main = GetInventoryItemID("player", MAIN_HAND)
    return main ~= nil and select(4, C_Item.GetItemInfoInstant(main)) == "INVTYPE_2HWEAPON"
end

-- What is replaced in a slot (a two-hander: both hands): the worn stats,
-- their slots, the first item ID, the room below the caps without them.
-- The same for every item compared: kept with the comparisons (Fresh).
local replacing = {} -- slot (or "2h") -> { list of stats, list of slots, first ID, room }
local replacingFor, replacingKind
local function Replacing(slot, twoHander, kind)
    Fresh()
    if replacingFor ~= generation or replacingKind ~= kind then
        replacingFor, replacingKind = generation, kind
        wipe(replacing)
    end
    local key = twoHander and "2h" or slot
    local known = replacing[key]
    if not known then
        local stats, slots, first = {}, {}, nil
        for _, s in ipairs(twoHander and { MAIN_HAND, OFF_HAND } or { slot }) do
            local worn, id = Worn(s)
            if worn then
                stats[#stats + 1], slots[#slots + 1] = worn, s
                first = first or id
            end
        end
        -- (a one-hander for the main hand while a two-hander is worn takes the
        -- two-hander's place; the off hand stays empty: compared as it is)
        known = { stats, slots, first, Room(kind, stats) }
        replacing[key] = known
    end
    return known[1], known[2], known[3], known[4]
end

local NO_TOP = {}
local LOSS_NAMED = 3 -- percent: from this loss on the stats behind it are named
local function InSlot(data, slot, equipLoc, weights, kind)
    local replaced, slots, first, room = Replacing(slot, equipLoc == "INVTYPE_2HWEAPON", kind)
    local value = Score(data, slot, weights, room)
    local worn = 0
    for i, stats in ipairs(replaced) do worn = worn + Score(stats, slots[i], weights, room) end
    local procs = data.procs
    for _, stats in ipairs(replaced) do procs = procs or stats.procs end
    local result = { value = value, worn = worn, gain = value - worn, slot = slot, replaces = first,
        free = #replaced == 0, top = NO_TOP, procs = procs }
    if not result.free and worn > 0 then result.percent = result.gain / worn * 100 end
    -- what makes the difference, most first: for a gain and for a loss from LOSS_NAMED percent on; most items are neither
    local sign = result.gain > 0 and 1 or (result.percent and result.percent <= -LOSS_NAMED and -1)
    if sign then
        local diffs = {}
        Score(data, slot, weights, room, diffs)
        local oldParts = {}
        for i, stats in ipairs(replaced) do Score(stats, slots[i], weights, room, oldParts) end
        for key, worth in pairs(oldParts) do diffs[key] = (diffs[key] or 0) - worth end
        local keys = {}
        for key, diff in pairs(diffs) do
            if diff * sign > 0 then keys[#keys + 1] = key end
        end
        table.sort(keys, function(a, b) return diffs[a] * sign > diffs[b] * sign end)
        -- by how much each differs, in the stat's own unit (DPS: damage per second)
        local amounts = {}
        for _, key in ipairs(keys) do
            local diff = Amount(data, key)
            for _, stats in ipairs(replaced) do diff = diff - Amount(stats, key) end
            amounts[key] = diff
        end
        if sign > 0 then result.top, result.topAmounts = keys, amounts
        else result.drops, result.dropAmounts = keys, amounts end
    end
    return result
end
-- the worth of all you wear, caps as you are now: what a gain is measured against (share). Kept with the comparisons (Fresh).
local totalFor, total
function V.Total()
    Fresh()
    if totalFor ~= generation then
        totalFor, total = generation, 0
        local _, _, kind, weights = V.Profile()
        local room = Room(kind, {})
        for slot = 1, 18 do
            local worn = slot ~= 4 and Worn(slot) -- (the shirt carries nothing)
            if worn then total = total + Score(worn, slot, weights, room) end
        end
    end
    return total
end

function V.Compare(item)
    Fresh()
    local known = compared[item]
    if known ~= nil then return known or nil end
    local result = false
    local equipLoc = select(4, C_Item.GetItemInfoInstant(item))
    local slots = SLOTS[equipLoc or ""]
    local data = slots and Stats(item)
    if slots and not data and type(item) == "string" then unsure = true end -- (a link not loaded yet)
    if data then
        local _, _, kind, weights = V.Profile()
        local dualWield = D.SpellKnown(DUAL_WIELD)
        if equipLoc == "INVTYPE_WEAPON" and not dualWield then slots = { MAIN_HAND } end
        -- an off-hand weapon needs Dual Wield; nothing for the off hand while
        -- a two-hander is worn (it would be measured against the two-hander)
        local offHandOnly = #slots == 1 and slots[1] == OFF_HAND
        if not ((equipLoc == "INVTYPE_WEAPONOFFHAND" and not dualWield) or (offHandOnly and TwoHanderWorn())) then
            for _, slot in ipairs(slots) do
                if not (slot == OFF_HAND and TwoHanderWorn()) then -- (also a one-hander that could dual wield)
                    local r = InSlot(data, slot, equipLoc, weights, kind)
                    if not result or r.gain > result.gain then result = r end
                end
            end
        end
    end
    -- the gain against all you wear: how much stronger you get (a two-hander
    -- 10 % better brings more than a ring 50 % better)
    if result then
        local all = V.Total()
        result.share = all > 0 and result.gain / all * 100 or (result.gain > 0 and 100 or 0)
    end
    compared[item] = result
    return result or nil
end
