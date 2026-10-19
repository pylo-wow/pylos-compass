local _, D = ...
local ns = D.engine
local L = ns.L

-- Blocked you (knowing): a red error message named what you lack: a skill ("Requires Mining 50": that profession's
-- trainer), a tool, key or reagent ("Requires Blacksmith Hammer", "Missing reagent: Copper Bar": that item). Uses the
-- game's own formats (GlobalStrings), names compared with the data's names. Strongest right after, fading to nothing
-- within FRESH. Kept for this session only.

local FRESH = 5 * 60 -- seconds a block counts

-- the formats that name what is missing: skill and level first (the plain "Requires %s" would catch "Mining 50" as a
-- name). Varargs: a format missing in this client is a nil in the middle and must not end the list.
local function Patterns(...)
    local list = {}
    for i = 1, select("#", ...) do
        local pattern = ns.FormatPattern((select(i, ...)), false, true)
        if pattern then list[#list + 1] = pattern end
    end
    return list
end
local skillPatterns = Patterns(ERR_USE_LOCKED_WITH_SPELL_KNOWN_SI, SPELL_FAILED_MIN_SKILL, ITEM_MIN_SKILL)
local namePatterns = Patterns(SPELL_FAILED_REAGENTS, ERR_USE_LOCKED_WITH_ITEM_S, SPELL_FAILED_TOTEMS,
    LOCKED_WITH_ITEM, SPELL_FAILED_TOTEM_CATEGORY, ERR_USE_LOCKED_WITH_SPELL_S)

local blocked = {} -- entry ID -> { time(), message }

-- a profession by its name: skill line (the data layer's names, English)
local skillOfName
local function SkillOf(name)
    if not skillOfName then
        skillOfName = {}
        for skillLine, skillName in pairs(D.professionNames or {}) do
            skillOfName[D.SearchKey(skillName)] = skillLine
        end
    end
    return skillOfName[D.SearchKey(name)]
end

-- an item by its name: the first entry whose key is the name's (the items are sorted by key)
local function ItemNamed(name)
    local key, list = D.SearchKey(name), D.Entries("items")
    local low, high = 1, #list + 1
    while low < high do
        local middle = math.floor((low + high) / 2)
        if list[middle].key < key then low = middle + 1 else high = middle end
    end
    local entry = list[low]
    return entry and entry.key == key and entry or nil
end

-- what a name stands for: a profession (its nearest trainer) or an item
local function EntryOf(name)
    local skillLine = SkillOf(name)
    if skillLine then return ns.reach.Trainer(skillLine) end
    return ItemNamed(name)
end

ns.On("UI_ERROR_MESSAGE", function(_, _, message)
    if type(message) ~= "string" or D.Secret(message) then return end
    local entry
    for _, pattern in ipairs(skillPatterns) do
        local name = message:match(pattern)
        if name then entry = EntryOf(name) break end
    end
    if not entry then
        for _, pattern in ipairs(namePatterns) do
            local name = message:match(pattern)
            if name then entry = EntryOf(name) break end
        end
    end
    local id = entry and D.EntryID(entry)
    if not id then return end
    blocked[id] = { time(), message }
    D.BumpState("rec:blocked")
end)

-- how fresh: 1 right after the message, 0 after FRESH; nil if none
local function Freshness(id)
    local block = id and blocked[id]
    return block and ns.Fade(blocked, id, block[1], FRESH)
end

ns.RegisterReason({
    key = "blocked",
    -- weight 1.2: what just stopped you is what you look up first
    stage = "know", weight = 1.2, label = "Blocked you",
    kind = "know",
    sources = { "items", "npcs" },
    depends = { "rec:blocked" }, -- fades with time: kept at most STALE seconds (Reasons.lua)
    candidates = function(add)
        for id in pairs(blocked) do add(D.EntryByID(id)) end
    end,
    test = function(entry)
        local share = Freshness(D.EntryID(entry))
        return share and (0.4 + 0.6 * share) or nil
    end,
    reach = function() return ns.reach.NOW, nil end,
    errand = false, -- the note is the same for every item or trainer it names
    note = function() return L["Blocked you"] end,
    why = function(entry)
        local block = blocked[D.EntryID(entry)]
        return block and L["Blocked you: %s"]:format(block[2]) or L["Blocked you"]
    end,
})
