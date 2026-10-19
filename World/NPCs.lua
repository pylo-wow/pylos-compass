local _, D = ...

-- NPCs: every server NPC (Data\NPCNames_enUS.lua) with title and facts (Data\NPCFacts.lua):
-- type, rank and model from the client's creature cache (1.12's where the cache lacks the NPC);
-- levels, roles, reaction and zones from the 1.12 data (NPCs new in Forever have none of those).
-- Built in the background (13,000 entries). Also: an NPC's zones (met zone first), distance
-- to you, and the gap between two NPCs.

D.NPC_ROLE = { VENDOR = 1, TRAINER = 2, QUEST_GIVER = 4, FLIGHT_MASTER = 8, INNKEEPER = 16, BANKER = 32,
    AUCTIONEER = 64, REPAIR = 128 }
-- entry.creatureType: 1 beast, 2 dragonkin, 3 demon, 4 elemental, 5 giant,
-- 6 undead, 7 humanoid, 8 critter, 9 mechanical, 10 not specified, 11 totem,
-- 12 non-combat pet, 14 wild pet (0 unknown);
-- entry.npcRank: 1 elite, 2 rare elite, 3 boss, 4 rare

local facts, zones, displays
local titles = {} -- id -> title, for NPCs that have one (kept)
-- id -> display ID for NPCs whose zones and display ID do not fit one number (zones set and
-- display ID from 2^17 on: 36 + 18 bits exceed a double's exact range; Forever's new models)
local bigDisplays = {}
local DISPLAY_FITS = 131072

-- Memory: an entry keeps only its name and two packed numbers (plus the build key):
-- packed = facts (with reaction) + NPC ID * 2^33, zones = zones + display ID * 2^36.
-- Four fields fill a table's four slots exactly (nine fields took sixteen: 0.89 KB per NPC,
-- measured in game). The rest is computed on demand via the domain metatable.
local ID_SHIFT, DISPLAY_SHIFT = 8589934592, 68719476736
local REACTION_SHIFT = 536870912

-- Your faction, read on first ask (at file load the client may not know it yet and every
-- character would count as Alliance)
local faction
local function Faction()
    faction = faction or UnitFactionGroup("player")
    return faction
end

local fields = D.fields.npcs or {}
D.fields.npcs = fields
fields.npcID = function(entry) return math.floor(entry.packed / ID_SHIFT) end
-- Seen facts (LearnNPCs.lua) beat the 1.12 data; LearnNPCs.lua loads after this file, so look up lazily
local function Learned(npcID) return D.Learned(npcID) end
-- Are 1.12 facts (levels, roles, reaction) or seen facts known (false: new in Forever and not
-- met yet; it may still have type, rank and model from the creature cache)
fields.hasFacts = function(entry)
    local packed = entry.packed % ID_SHIFT
    return packed % 16384 ~= 0 or packed >= 2097152 or Learned(entry.npcID) ~= nil
end
-- Toward you: 1 hostile, 2 neutral, 3 friendly, 0 unknown (as seen, else as to a new
-- character of your faction: Data\NPCFacts.lua)
fields.reaction = function(entry)
    local side = Faction()
    local learned = Learned(entry.npcID)
    local seen = learned and learned.reaction and side and learned.reaction[side]
    if seen then return seen end
    local both = math.floor(entry.packed / REACTION_SHIFT) % 16
    return side ~= "Horde" and math.floor(both / 4) or both % 4
end
fields.title = function(entry) return titles[entry.npcID] or "" end
fields.displayID = function(entry)
    local display = bigDisplays[entry.npcID] or math.floor(entry.zones / DISPLAY_SHIFT)
    return display > 0 and display or nil
end
fields.place = function(entry) return D.npcPlaces and D.npcPlaces[entry.npcID] end
fields.levelMin = function(entry)
    local learned = Learned(entry.npcID)
    return learned and learned.levelMin or entry.packed % 128
end
fields.levelMax = function(entry)
    local learned = Learned(entry.npcID)
    return learned and learned.levelMax or math.floor(entry.packed / 128) % 128
end
fields.creatureType = function(entry)
    local learned = Learned(entry.npcID)
    return learned and learned.type or math.floor(entry.packed / 16384) % 16
end
fields.npcRank = function(entry)
    local learned = Learned(entry.npcID)
    return learned and learned.rank or math.floor(entry.packed / 262144) % 8
end
-- 1.12 roles plus those seen (a window of that kind); a vendor seen without repairing does not repair
fields.roles = function(entry)
    local roles = math.floor(entry.packed / 2097152) % 256
    local learned = Learned(entry.npcID)
    if not learned then return roles end
    local seen = learned.roles or 0
    for bit = 0, 7 do
        local value = 2 ^ bit
        if math.floor(seen / value) % 2 == 1 and math.floor(roles / value) % 2 == 0 then roles = roles + value end
    end
    if learned.noRepair and math.floor(roles / 128) % 2 == 1 then roles = roles - 128 end
    return roles
end

function D.NPCHasRole(entry, role)
    return math.floor(entry.roles / role) % 2 == 1
end

-- Extra search words besides name and title (entry.searchWords): services, from the roles
-- above and what it teaches (D.npcTrainers, also as seen). Titles often name the service
-- differently ("Gryphon Master", "Journeyman Blacksmith") or not at all ("Innkeeper Farley").
-- Lowercase English phrases separated by single spaces; nil without a service.
-- Stable masters and guild masters are omitted: their titles say it.
local ROLE_WORDS = { -- in this order
    { D.NPC_ROLE.FLIGHT_MASTER, "flight master" }, { D.NPC_ROLE.INNKEEPER, "innkeeper" },
    { D.NPC_ROLE.BANKER, "banker" }, { D.NPC_ROLE.AUCTIONEER, "auctioneer" },
    { D.NPC_ROLE.VENDOR, "vendor" }, { D.NPC_ROLE.REPAIR, "repair" },
}
local TEACHES_WORDS = {
    [1] = "warrior", [2] = "paladin", [3] = "hunter", [4] = "rogue", [5] = "priest", [7] = "shaman",
    [8] = "mage", [9] = "warlock", [11] = "druid",
    [129] = "first aid", [164] = "blacksmithing", [165] = "leatherworking", [171] = "alchemy",
    [182] = "herbalism", [185] = "cooking", [186] = "mining", [197] = "tailoring", [202] = "engineering",
    [333] = "enchanting", [356] = "fishing", [393] = "skinning",
}
fields.searchWords = function(entry)
    local roles = entry.roles
    local teaches = D.npcTrainers and D.npcTrainers[entry.npcID]
    if roles == 0 and not teaches then return nil end
    local words = {}
    for _, pair in ipairs(ROLE_WORDS) do
        if math.floor(roles / pair[1]) % 2 == 1 then words[#words + 1] = pair[2] end
    end
    if teaches and TEACHES_WORDS[teaches] then
        words[#words + 1] = TEACHES_WORDS[teaches] .. " trainer"
    elseif teaches or math.floor(roles / D.NPC_ROLE.TRAINER) % 2 == 1 then
        words[#words + 1] = "trainer"
    end
    return words[1] and table.concat(words, " ") or nil
end

local meta -- D.Meta("npcs"), once the domain is registered

local function AddNPC(list, id, name, title)
    if title ~= "" then titles[id] = title end
    local zone, display = zones[id] or 0, displays[id] or 0
    if zone ~= 0 and display >= DISPLAY_FITS then
        bigDisplays[id] = display
        display = 0
    end
    list[#list + 1] = setmetatable({ name = name, packed = (facts[id] or 0) + id * ID_SHIFT,
        zones = zone + display * DISPLAY_SHIFT }, meta)
end

local function Facts(Pause)
    if facts then return end
    facts, zones, displays = {}, {}, {}
    wipe(bigDisplays)
    local list = D.npcFacts or {}
    for i = 1, #list, 4 do
        facts[list[i]], zones[list[i]], displays[list[i]] = list[i + 1], list[i + 2], list[i + 3]
        if i % 512 == 1 then Pause() end
    end
end

D.RegisterDomain({
    key = "npcs",
    background = true,
    collect = function(list, Pause)
        meta = meta or D.Meta("npcs")
        Facts(Pause)
        wipe(titles)
        local titlesEN = D.npcTitlesEN or {}
        local count = 0
        for id, name in pairs(D.npcNamesEN or {}) do
            AddNPC(list, id, name, titlesEN[id] or "")
            count = count + 1
            if count % 32 == 0 then Pause() end
        end
        facts, zones, displays = nil, nil, nil -- the entries hold theirs now
    end,
})

-- An NPC's zones (uiMapIDs): the one you met it in first (LearnNPCs.lua), then up to three from the 1.12 data
function D.NPCZones(entry)
    local packed, list = entry.zones % DISPLAY_SHIFT, {}
    local met = D.MetZone(entry.npcID)
    if met then list[1] = met end
    while packed > 0 do
        local zone = packed % 4096
        if zone ~= met then list[#list + 1] = zone end
        packed = math.floor(packed / 4096)
    end
    return list
end

function D.NPCInZone(entry, zone)
    if D.MetZone(entry.npcID) == zone then return true end
    local packed = entry.zones % DISPLAY_SHIFT
    while packed > 0 do
        if packed % 4096 == zone then return true end
        packed = math.floor(packed / 4096)
    end
    return false
end

-- NPCs of each zone (D.NPCInZone) in entry order: all zones in one pass per NPC build, run in
-- the background right after it (job "npc zones"). A pass per zone made the NPC tab lag, and a
-- pass per NPC met cost ~8 ms per refresh, so a met NPC (LearnNPCs.lua) only moves itself
-- between the two zones' lists (D.NPCMoved).
local EMPTY = {}
local byZone, byZoneVersion -- zone -> list of entries; state "data:npcs" it was built at
local mobLevels = {}        -- zone -> middle level of its foes, or false (D.ZoneMobLevel)

local function EachZone(entry, fn)
    local met = D.MetZone(entry.npcID)
    if met then fn(met) end
    local packed = entry.zones % DISPLAY_SHIFT
    while packed > 0 do
        local zone = packed % 4096
        if zone ~= met then fn(zone) end
        packed = math.floor(packed / 4096)
    end
end

local function MakeIndex(Pause)
    local version = D.State("data:npcs")
    local index, entry = {}, nil
    local function Add(zone)
        local list = index[zone]
        if not list then
            list = {}
            index[zone] = list
        end
        if list[#list] ~= entry then list[#list + 1] = entry end
    end
    for i, e in ipairs(D.Entries("npcs")) do
        entry = e
        EachZone(e, Add)
        if i % 256 == 0 then Pause() end
    end
    -- rebuilt meanwhile: this index is stale, the next ask builds it again
    if version ~= D.State("data:npcs") then return end
    byZone, byZoneVersion = index, version
    wipe(mobLevels)
end
local function NoPause() end

local function Index()
    if not D.Built("npcs") then return nil end
    if byZoneVersion ~= D.State("data:npcs") then MakeIndex(NoPause) end
    return byZone
end

D.OnBuilt(function(key)
    if key ~= "npcs" then return end
    D.Background("npc zones", function(Pause)
        MakeIndex(Pause)
        -- also every zone's foes (the first route search asks most zones)
        local zones = {}
        for zone in pairs(byZone or EMPTY) do zones[#zones + 1] = zone end
        for i, zone in ipairs(zones) do
            D.ZoneMobLevel(zone)
            if i % 8 == 0 then Pause() end
        end
    end)
end)

function D.NPCsInZone(zone)
    local index = Index()
    return index and index[zone] or EMPTY
end

-- An NPC met in another zone (LearnNPCs.lua; before: zone it was met in earlier, or nil):
-- moves between the two zones' lists, keeping the entries' order
function D.NPCMoved(npcID, before)
    if not byZone or byZoneVersion ~= D.State("data:npcs") then return end
    local entry = D.NPCByID(npcID)
    if not entry then return end
    for _, zone in ipairs({ before or 0, D.MetZone(npcID) or 0 }) do
        if zone ~= 0 then
            local list = byZone[zone]
            local at
            for i, other in ipairs(list or EMPTY) do
                if other == entry then at = i break end
            end
            local inside = D.NPCInZone(entry, zone)
            if inside and not at then
                if not list then
                    list = {}
                    byZone[zone] = list
                end
                local i = #list + 1
                while i > 1 and list[i - 1].key > entry.key do i = i - 1 end
                table.insert(list, i, entry)
            elseif at and not inside then
                table.remove(list, at)
            end
            mobLevels[zone] = nil
        end
    end
end

-- Strength of a zone's foes: median of the lowest levels of NPCs hostile to you there, minus
-- critters and "not specified" (spotlights, triggers); nil with fewer than MOB_SAMPLE (your
-- own city's guards are friendly). Used for the danger of crossing a zone (Routes.lua); quest
-- levels miss most high zones. Cached per zone with the zone's NPC list.
local MOB_SAMPLE, CRITTER, UNSPECIFIED = 15, 8, 10
function D.ZoneMobLevel(zone)
    local index = Index()
    if not index then return nil end
    local known = mobLevels[zone]
    if known == nil then
        local levels = {}
        for _, entry in ipairs(index[zone] or EMPTY) do
            local kind = entry.creatureType
            if entry.reaction == 1 and kind ~= CRITTER and kind ~= UNSPECIFIED and entry.levelMin > 0 then
                levels[#levels + 1] = entry.levelMin
            end
        end
        known = false
        if #levels >= MOB_SAMPLE then
            table.sort(levels)
            known = levels[math.ceil(#levels / 2)]
        end
        mobLevels[zone] = known
    end
    return known or nil
end

-- Does the NPC stand in your current zone (see You\Zone.lua); false if the client does not
-- know it. For the reach of NPCs with no known distance.
function D.NPCInCurrentZone(entry)
    local zone = D.PlayerZone(true)
    return zone ~= nil and D.NPCInZone(entry, zone)
end

-- Yards from you to an NPC's spot (Data\NPCPlaces.lua or learned; D.PlaceDistance); nil if unknown
function D.NPCDistance(entry)
    return D.PlaceDistance(D.npcPlaces and D.npcPlaces[entry.npcID])
end

-- Yards between two NPCs' spots, by NPC ID (nil: not on the same map, or unknown)
function D.NPCGap(a, b)
    local places = D.npcPlaces
    return D.PlaceGap(places and places[a], places and places[b])
end

-- What NPCs drop and sell (Data\NPCLinks.lua, 1.12 data; replaced by what was seen, LearnNPCs.lua),
-- as texts, nil if none. Read these instead of D.npcDrops, D.itemDroppedBy, D.npcSells, D.itemSoldBy.
--   D.DropsOf(npcID)     "itemID:chance,..."
--   D.DroppedBy(itemID)  "npcID:chance,...", best first (chance in whole percent, 0: small share)
--   D.Sells(npcID)       "itemID,..."
--   D.SoldBy(itemID)     "npcID,..."
function D.DropsOf(npcID) return D.npcDrops and D.npcDrops[npcID] end
function D.DroppedBy(itemID) return D.itemDroppedBy and D.itemDroppedBy[itemID] end
function D.Sells(npcID) return D.npcSells and D.npcSells[npcID] end
function D.SoldBy(itemID) return D.itemSoldBy and D.itemSoldBy[itemID] end