local _, D = ...
local ns = D.engine
local L = ns.L

-- Looted (knowing): an item new in your bags that this character never had before: what is it? Strongest right after
-- it came, fading to nothing within FRESH; junk (grey) left out. Items ever had are kept per character
-- (PylosCompassEngineDB.seenItems); a character's first look only takes in what it has, nothing counts as new then.
-- An item that starts a quest counts more (easily missed in the bags).

local FRESH = 15 * 60       -- seconds an item counts as new
local STARTS_QUEST = 1.5   -- an item that starts a quest: this much stronger
local fresh = {}           -- item ID -> time() it came (this session)

local function Look()
    local db = ns.db
    if not db then return end
    D.RefreshOwned()
    -- an empty scan must not become the character's "first look" (every item would count as new next time)
    if not next(D.ownedItems) then return end
    local key = ns.Character()
    local first = db.seenItems[key] == nil
    local seen = db.seenItems[key] or {}
    db.seenItems[key] = seen
    local now = time()
    for itemID in pairs(D.ownedItems) do
        if not seen[itemID] then
            seen[itemID] = true
            if not first then fresh[itemID] = now end
        end
    end
end

-- your bags changed (state, also at entering the world)
D.OnState("bags", Look)

local function Newness(itemID)
    return ns.Fade(fresh, itemID, fresh[itemID], FRESH)
end

ns.RegisterReason({
    key = "looted",
    -- weight 1: the plain thing to look up (what is this?)
    stage = "know", label = "Looted",
    kind = "know",
    sources = { "items" },
    depends = { "bags" }, -- fades with time: kept at most STALE seconds (Reasons.lua)
    -- bags looked at here too: the state's listener runs a frame later, so a list computed before kept the old bags
    prepare = Look,
    candidates = function(add)
        for itemID in pairs(fresh) do add(D.ItemByID(itemID)) end
    end,
    test = function(entry)
        if (entry.quality or 0) < 1 then return nil end
        local share = Newness(entry.itemID)
        if not share then return nil end
        return (0.3 + 0.7 * share) * (entry.startsQuest and STARTS_QUEST or 1)
    end,
    reach = function() return ns.reach.NOW, nil end,
    note = function() return L["Just looted"] end,
    why = function(entry)
        return entry.startsQuest and L["Just looted: starts a quest"] or L["Just looted: new in your bags"]
    end,
})
