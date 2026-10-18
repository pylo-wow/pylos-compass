local _, D = ...
if D.off then return end
local ns = D.engine
local L = ns.L

-- Blocked you (knowing): a red error message named what you lack: a skill ("Requires Mining 50": that profession's
-- trainer), a tool, key or reagent ("Requires Blacksmith Hammer", "Missing reagent: Copper Bar": that item). Uses the
-- game's own formats (GlobalStrings), names compared with the data's names. Strongest right after, fading to nothing
-- within FRESH. Kept for this session only.

local FRESH = 5 * 60 -- seconds a block counts

-- the formats that name what is missing: skill and level first (the plain
-- "Requires %s" would catch "Mining 50" as a name)
local SKILL_FORMATS = { ERR_USE_LOCKED_WITH_SPELL_KNOWN_SI, SPELL_FAILED_MIN_SKILL, ITEM_MIN_SKILL }
local NAME_FORMATS = { SPELL_FAILED_REAGENTS, ERR_USE_LOCKED_WITH_ITEM_S, SPELL_FAILED_TOTEMS, LOCKED_WITH_ITEM,
    SPELL_FAILED_TOTEM_CATEGORY, ERR_USE_LOCKED_WITH_SPELL_S }
local skillPatterns, namePatterns = {}, {}
for _, format in ipairs(SKILL_FORMATS) do
    local pattern = ns.FormatPattern(format, false, true)
    if pattern then skillPatterns[#skillPatterns + 1] = pattern end
end
for _, format in ipairs(NAME_FORMATS) do
    local pattern = ns.FormatPattern(format, false, true)
    if pattern then namePatterns[#namePatterns + 1] = pattern end
end

local blocked = {} -- entry ID -> { time(), message }

-- a profession by its name: skill line (Data's names, English)
local skillOfName
local function SkillOf(name)
    if not skillOfName then
        skillOfName = {}
        for skillLine, skillName in pairs(D.professionNames or {}) do skillOfName[D.SearchKey(skillName)] = skillLine end
    end
    return skillOfName[D.SearchKey(name)]
end

-- an item by its name: the first entry whose key is the name's (the
-- items are sorted by key)
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
    if type(message) ~= "string" or (issecretvalue and issecretvalue(message)) then return end
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
    if not block then return nil end
    local share = 1 - (time() - block[1]) / FRESH
    if share <= 0 then
        blocked[id] = nil
        return nil
    end
    return share
end

ns.RegisterReason({
    key = "blocked",
    -- weight 1.2: what just stopped you is what you look up first
    stage = "know", weight = 1.2, label = "Blocked you",
    kind = "know",
    sources = { "items", "npcs" },
    depends = { "rec:blocked" }, -- (fading with time: kept at most STALE seconds, Reasons.lua)
    candidates = function(add)
        for id in pairs(blocked) do add(D.EntryByID(id)) end
    end,
    test = function(entry)
        local share = Freshness(D.EntryID(entry))
        return share and (0.4 + 0.6 * share) or nil
    end,
    reach = function() return ns.reach.NOW, nil end,
    note = function() return L["Blocked you"] end,
    why = function(entry)
        local block = blocked[D.EntryID(entry)]
        return block and L["Blocked you: %s"]:format(block[2]) or L["Blocked you"]
    end,
})
