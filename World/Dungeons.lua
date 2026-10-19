local _, D = ...

-- Dungeons and raids from Data\Dungeons_*.lua (client tables): level range, players, entrance
-- zone (unknown for instances new in Forever), bosses in order. Also group levels, level fit
-- and entrances learned in play.

local KEY = "dungeons"

-- Category of an instance without a known entrance zone
local KINDS = { "Dungeon", "Raid" }
-- Dungeon finder icon (Interface\LFGFrame\LFGIcon-*, file IDs) by map ID; instances new in
-- Forever borrow the nearest icon, the rest get the plain dungeon/raid icon
local MAP_ICONS = {
    [33] = 136357, [34] = 136358, [36] = 136332, [43] = 136364, [47] = 136353, [48] = 136325, [70] = 136363,
    [90] = 136336, [109] = 136360, [129] = 136352, [189] = 136354, [209] = 136368, [229] = 136327,
    [230] = 136326, [249] = 329121, [289] = 136355, [309] = 136369, [329] = 136359, [349] = 136345,
    [389] = 136350, [409] = 136346, [429] = 136333, [469] = 136329, [509] = 136320, [531] = 136321,
    [533] = 136347, [2832] = 5409263, [2875] = 136343, [2959] = 460862, [2999] = 460869,
    [2856] = 643268,
}
local ICONS = { 136334, 136351 } -- plain dungeon and raid icons

-- Single-faction dungeons (not in the client tables): entry.side, as for quests; they never
-- fit the other faction's level (D.DungeonLevelFit)
local SIDES = { [389] = "Horde", [3065] = "Alliance" } -- Ragefire Chasm, The Hall of Thanes

-- Short names players use (entry.searchWords) by map ID, lowercase, space separated. None for
-- Forever's own instances. "dm" covers both Deadmines and Dire Maul.
local SHORT_NAMES = {
    [389] = "rfc", [43] = "wc", [36] = "dm vc", [33] = "sfk", [48] = "bfd", [34] = "stocks",
    [90] = "gnomer", [47] = "rfk", [189] = "sm", [129] = "rfd", [70] = "ulda", [209] = "zf",
    [349] = "mara", [109] = "st", [230] = "brd", [229] = "lbrs ubrs", [429] = "dm", [289] = "scholo",
    [329] = "strat", [409] = "mc", [249] = "ony onyxia", [469] = "bwl", [309] = "zg", [509] = "aq20",
    [531] = "aq40", [533] = "naxx",
}

local function ZoneName(id)
    local info = id and id > 0 and C_Map.GetMapInfo(id)
    return info and info.name or nil
end

function D.DungeonBosses(entry)
    local list = {}
    for part in (entry.bosses or ""):gmatch("[^|]+") do
        local name, npc = part:match("^(.-)=(%d+)$")
        list[#list + 1] = { name or part, npc and tonumber(npc) }
    end
    return list
end

-- Entry of the dungeon a boss belongs to, nil if the NPC is no boss; rebuilt with the data
local bossCache = D.Cache({ "data:" .. KEY })
function D.DungeonOfBoss(npcID)
    local bossOf, renewed = bossCache.Get()
    if renewed then
        for _, entry in ipairs(D.Entries(KEY)) do
            for _, boss in ipairs(D.DungeonBosses(entry)) do
                if boss[2] then bossOf[boss[2]] = entry end
            end
        end
    end
    return bossOf[npcID]
end

local function Collect(list)
    local meta = D.Meta(KEY)
    for _, d in ipairs(D.dungeons or {}) do
        local mapID, name, kind, players, level, zone, bosses, place, maxLevel = unpack(d)
        -- learned entrance wins: Forever's own instances have none in the client tables
        local learned = D.LearnedDungeon(mapID)
        if learned then place, zone = learned, math.floor(learned / 1000000) end
        list[#list + 1] = setmetatable({
            name = name, icon = MAP_ICONS[mapID] or ICONS[kind] or ICONS[1], mapID = mapID, kind = kind,
            players = players, level = level, maxLevel = maxLevel or 0, zone = zone, bosses = bosses,
            place = place ~= 0 and place or nil, category = ZoneName(zone) or KINDS[kind],
            entranceSeen = learned ~= nil, -- else the entrance is from the 1.12 data (unchecked)
            side = SIDES[mapID],
        }, meta)
    end
end

D.RegisterDomain({ key = KEY, collect = Collect })
D.AddField(KEY, "searchWords", function(entry) return SHORT_NAMES[entry.mapID] end)

-- Level fit

local DUNGEON_SPAN = 10 -- levels above a dungeon's own when it has no range
local levelsCache = D.Cache({ "frame" })

-- Your level and your party's (not raid), yours first; read once per frame, shared (do not
-- change). Members with a secret level (in combat in Forever) are left out.
function D.GroupLevels()
    local levels, renewed = levelsCache.Get()
    if not renewed then return levels end
    levels[1] = UnitLevel("player")
    if IsInGroup and IsInGroup() and not (IsInRaid and IsInRaid()) then
        for i = 1, 4 do
            local unit = "party" .. i
            if UnitExists(unit) then
                local level = UnitLevel(unit)
                if not D.Secret(level) and level and level > 0 then levels[#levels + 1] = level end
            end
        end
    end
    return levels
end

-- Lowest and highest level (group browser range, else level up to DUNGEON_SPAN above); nil without a level
function D.DungeonLevelRange(entry)
    if entry.level <= 0 then return nil end
    return entry.level, entry.maxLevel > 0 and entry.maxLevel or entry.level + DUNGEON_SPAN
end

-- Alone: true or nil. In a party: the share that fits if at least half, else nil.
function D.DungeonLevelFit(entry)
    if entry.level <= 0 then return nil end
    if entry.side and entry.side ~= UnitFactionGroup("player") then return nil end -- other faction's
    local group = D.GroupLevels()
    local _, top = D.DungeonLevelRange(entry)
    local fitting = 0
    for _, each in ipairs(group) do
        if entry.level <= each and each <= top then fitting = fitting + 1 end
    end
    local share = fitting / #group
    if #group == 1 then return share == 1 or nil end
    return share >= 0.5 and share or nil
end

-- Entrances
-- Forever's own instances have no entrance in the client tables, and
-- C_EncounterJournal.GetDungeonEntrancesForMap returns 0 everywhere (confirmed in game), so
-- entrances are learned: the spot before the loading screen (PLAYER_LEAVING_WORLD) becomes the
-- entrance of the instance's map (GetInstanceInfo). Skipped after a summons or the group
-- finder (the spot would be anywhere).
-- PylosCompassWorldDB.dungeons[mapID] = place (uiMapID * 1000000 + x * 1000 + y)
local SUMMON_WINDOW = 120 -- seconds an accepted summons counts
local before, summonedAt -- spot before the loading screen (outdoors); time a summons was accepted

function D.LearnedDungeon(mapID)
    return D.world and D.world.dungeons and D.world.dungeons[mapID] or nil
end

D.On("CONFIRM_SUMMON", function() summonedAt = GetTime() end)
D.On("PLAYER_LEAVING_WORLD", function() before = not IsInInstance() and D.PlayerPlace() or nil end)
D.On("PLAYER_ENTERING_WORLD", function()
    if D.world and IsInInstance() then
        local mapID = select(8, GetInstanceInfo())
        local summoned = summonedAt and GetTime() - summonedAt < SUMMON_WINDOW
        local finder = IsInLFGDungeon and IsInLFGDungeon()
        if before and not D.Secret(mapID) and mapID and not summoned and not finder then
            D.world.dungeons = D.world.dungeons or {}
            if D.world.dungeons[mapID] ~= before then
                D.world.dungeons[mapID] = before
                if D.Built(KEY) then D.Rebuild(KEY) end
            end
        end
    end
    before = nil
end)