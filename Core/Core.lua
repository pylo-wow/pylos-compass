local _, D = ...

-- Data: the game's data and what follows from it, for other addons. Facts only: no weighing, no interface.
-- Folders: Core\ (frame, domains, entries, IDs, events, maps, state, background builder, saved data),
-- World\ (one file per domain plus data learned while playing), You\ (the current character), Data\ (generated files).
--
-- The root namespace of Pylos Compass: the search (D.search) and the recommendations (D.advice) read Data's names from it.
-- Gathering(itemID) -> nil or { kind "mine"/"herb"/"skin"/"drop", skill, zones = { uiMapID, ... } fullest first, low, high, creatureType }.
-- QuestGiver(s)/QuestTaker(s) also return their origin: "seen" (played), nil (client items) or "1.12" (data).
-- Entries answer facts as fields (entry.name, entry.icon, ...; per domain in its file).
-- entry.searchWords: lowercase English words an entry is also found by, single-spaced, nil if none
-- (NPC services "flight master innkeeper vendor repair", dungeon short names "bfd").
-- D.version is only for old readers: use D.State("data") or D.State("data:<key>").

D.API = 1
D.DOT = "  ·  " -- separator inside one line (tooltip lines, reason texts)


-- Text

-- lower case incl. German umlauts (string.lower only knows A-Z); keeps the byte length so positions map back
function D.Lower(text)
    return (text:lower():gsub("Ä", "ä"):gsub("Ö", "ö"):gsub("Ü", "ü"))
end

-- Money as the game shows it, e.g. "1[g] 25[s] 3[c]" with coin icons, zero parts omitted.
-- (Forever has no GetCoinTextureString.)
local COIN = "%d|TInterface\\MoneyFrame\\UI-%sIcon:0:0:2:0|t"
function D.Money(copper)
    copper = math.floor(math.abs(copper) + 0.5)
    local gold, silver = math.floor(copper / 10000), math.floor(copper / 100) % 100
    local parts = {}
    if gold > 0 then parts[#parts + 1] = COIN:format(gold, "Gold") end
    if silver > 0 then parts[#parts + 1] = COIN:format(silver, "Silver") end
    if copper % 100 > 0 or #parts == 0 then parts[#parts + 1] = COIN:format(copper % 100, "Copper") end
    return table.concat(parts, " ")
end

function D.EachChar(text)
    return text:gmatch("[%z\1-\127\194-\244][\128-\191]*")
end

-- Name as searched: lower case, apostrophes dropped ("Hogger's" -> "hoggers"), other punctuation a space,
-- spaces collapsed and trimmed ("Wanted: Hogger" -> "wanted hogger"). Used for every entry key and typed text.
-- withMap: also returns map[i] = source byte of key byte i (to highlight the match in the name).
local DROP = { ["'"] = true, ["\226\128\153"] = true, ["\226\128\152"] = true } -- ' ’ ‘
local SPACE = { [" "] = true, ["-"] = true, ["/"] = true, ["_"] = true, ['"'] = true, [":"] = true, [","] = true,
    ["."] = true, ["!"] = true, ["?"] = true, ["("] = true, [")"] = true, ["["] = true, ["]"] = true, ["&"] = true,
    [";"] = true, ["\226\128\156"] = true, ["\226\128\157"] = true } -- “ ”
local PLAIN = "^[^'\":,%.!%?%(%)%[%]&;%-/_\226]*$" -- nothing to change but case (most names)
local keyParts = {}
function D.SearchKey(text, withMap)
    local lowered = D.Lower(text)
    if lowered:find(PLAIN) and not lowered:find("  ", 1, true) and lowered:sub(1, 1) ~= " "
            and lowered:sub(-1) ~= " " then
        if not withMap then return lowered end
        local map = {}
        for i = 1, #lowered do map[i] = i end
        return lowered, map
    end
    wipe(keyParts)
    local map = withMap and {} or nil
    local bytes, pos, space = 0, 1, true -- space: the last one kept was a space (or none yet)
    for char in D.EachChar(lowered) do
        local keep
        if SPACE[char] then
            if not space then keep, space = " ", true end
        elseif not DROP[char] then
            keep, space = char, false
        end
        if keep then
            keyParts[#keyParts + 1] = keep
            if map then
                for k = 0, #keep - 1 do map[bytes + k + 1] = pos + k end
            end
            bytes = bytes + #keep
        end
        pos = pos + #char
    end
    if keyParts[#keyParts] == " " then
        keyParts[#keyParts] = nil
        if map then map[bytes] = nil end
    end
    return table.concat(keyParts), map
end

-- a value the game keeps secret (Forever, in combat/instances): neither compare nor store
function D.Secret(value) return issecretvalue ~= nil and issecretvalue(value) end

-- Events
-- One frame for all events. D.On(event, fn) calls fn(event, ...) in registration order; returns false if the
-- client does not know the event (an unknown event would abort the file, seen in game).
-- A handler error is reported, the others still run.
local handlers = {} -- event -> list of functions
local dispatcher = CreateFrame("Frame")
dispatcher:SetScript("OnEvent", function(_, event, ...)
    local list = handlers[event]
    for i = 1, #list do
        local ok, err = pcall(list[i], event, ...)
        if not ok then geterrorhandler()(err) end
    end
end)
function D.On(event, fn)
    local list = handlers[event]
    if not list then
        if not pcall(dispatcher.RegisterEvent, dispatcher, event) then return false end
        list = {}
        handlers[event] = list
    end
    list[#list + 1] = fn
    return true
end

-- NPC ID of a GUID (Creature-0-...-npcID-...); nil for none or a secret. Cached per GUID (name plates ask many
-- times a second), reset at GUID_KEEP entries.
local GUID_KEEP = 500
local npcOfGuid, guids = {}, 0
function D.NPCOfGUID(guid)
    if D.Secret(guid) or not guid then return nil end -- (a secret is not tested: Secret first)
    local id = npcOfGuid[guid]
    if id == nil then
        local kind, _, _, _, _, npc = strsplit("-", guid)
        id = kind == "Creature" and tonumber(npc) or false
        if guids >= GUID_KEEP then wipe(npcOfGuid) guids = 0 end
        npcOfGuid[guid], guids = id, guids + 1
    end
    return id or nil
end
function D.NPCOf(unit)
    return D.NPCOfGUID(UnitGUID(unit))
end

-- Domains
-- A domain is one kind of entry, registered by its World\ file with D.RegisterDomain:
--   key, collect(list, Pause), background (true: built in the background), events (optional),
--   signature (optional function() -> text; rebuild only when it changed)
-- Entries are plain tables with a per-domain metatable; fields not stored are computed on demand
-- (D.fields[domain][name](entry)) to save table slots (19,224 items). Hosts may add fields (D.AddField); Data never reads them.
D.domains = {}   -- key -> domain
D.order = {}     -- domains in registration order (spells before professions: "s:" IDs)
D.fields = {}    -- domain key -> field name -> function(entry)
-- counts builds and drops; legacy, same as D.State("data")
D.version = 0

local metas = {}
function D.Meta(key)
    local meta = metas[key]
    if not meta then
        local fields = D.fields[key]
        meta = { __index = function(entry, field)
            local get = fields[field]
            if get then return get(entry) end
        end }
        metas[key] = meta
    end
    return meta
end

function D.RegisterDomain(domain)
    D.domains[domain.key] = domain
    D.order[#D.order + 1] = domain
    local fields = D.fields[domain.key] or {}
    D.fields[domain.key] = fields
    local key = domain.key
    fields.domain = function() return key end
    fields.categoryKey = function(entry) return entry.category and D.SearchKey(entry.category) or nil end
    return domain
end

function D.AddField(key, name, get)
    local fields = D.fields[key]
    assert(fields, "unknown domain " .. tostring(key))
    assert(not fields[name] or name == "source", "field " .. name .. " of " .. key .. " exists already")
    fields[name] = get
end

-- a domain's entries, sorted by key (empty while not built)
function D.Entries(key)
    local domain = D.domains[key]
    return domain and domain.list or {}
end
function D.Built(key)
    local domain = D.domains[key]
    return domain ~= nil and domain.list ~= nil
end
function D.DomainKeys()
    local keys = {}
    for i, domain in ipairs(D.order) do keys[i] = domain.key end
    return keys
end
function D.DomainInBackground(key)
    local domain = D.domains[key]
    return domain ~= nil and domain.background == true
end

-- IDs
-- An entry's ID, stable across sessions and rebuilds: "i:<item>", "n:<NPC>", "q:<quest>", "z:<zone>", "s:<spell>"
-- ("s:<spell>:<skill line>" for a recipe of two professions), "d:<map>"; nil otherwise.

-- Cached per entry (weak keys): asked several times per refresh, each miss costs metatable lookups and a string.
local entryIDs = setmetatable({}, { __mode = "k" }) -- entry -> ID or false
local function MakeEntryID(entry)
    if entry.entryID then return entry.entryID end
    if entry.itemID then return "i:" .. entry.itemID end
    if entry.npcID then return "n:" .. entry.npcID end
    if entry.questID then return "q:" .. entry.questID end
    if entry.zoneID then return "z:" .. entry.zoneID end
    if entry.spellID then return "s:" .. entry.spellID end
    if entry.mapID then return "d:" .. entry.mapID end
    return nil
end
function D.EntryID(entry)
    local id = entryIDs[entry]
    if id == nil then
        id = MakeEntryID(entry) or false
        entryIDs[entry] = id
    end
    return id or nil
end

function D.EntryByID(id)
    if type(id) ~= "string" then return nil end
    local kind, rest = id:match("^(%a):(.+)$")
    if kind == "i" then return D.ItemByID(tonumber(rest)) end
    if kind == "n" then return D.NPCByID(tonumber(rest)) end
    for _, domain in ipairs(D.order) do
        local entry = domain.byEntryID and domain.byEntryID[id]
        if entry then return entry end
    end
    return nil
end
function D.ItemByID(itemID)
    local domain = D.domains.items
    return domain and domain.byItem and domain.byItem[itemID] or nil
end
function D.NPCByID(npcID)
    local domain = D.domains.npcs
    return domain and domain.byNPC and domain.byNPC[npcID] or nil
end

-- English name of an item/NPC/quest by ID from the data files, whatever the client language; nil if unknown
local NAMES = { item = "itemNamesEN", npc = "npcNamesEN", quest = "questNamesEN" }
function D.NameEN(kind, id)
    local names = D[NAMES[kind]]
    return names and names[id] or nil
end

-- Who needs what
-- Domains are built only when an addon needs them: D.Need(key, who, true/false). D.OnBuilt(function(key, list)) hears every finished build.

local needs = {} -- domain key -> who -> true
function D.Need(key, who, on)
    needs[key] = needs[key] or {}
    needs[key][who] = on ~= false or nil
    if not D.Needed(key) and D.domains[key] then D.Drop(key) end
end
function D.Needed(key)
    return needs[key] ~= nil and next(needs[key]) ~= nil
end

local listeners = {}
function D.OnBuilt(listener) listeners[#listeners + 1] = listener end
function D.Announce(key, list)
    for _, listener in ipairs(listeners) do
        local ok, err = pcall(listener, key, list)
        if not ok then geterrorhandler()(err) end
    end
end
