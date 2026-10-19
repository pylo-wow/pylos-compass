local _, D = ...
if D.off then return end

-- Game state as versions: one caching concept for Data, Recommendations and Spotlight.
--
-- A state is a named part of the game that results depend on; its version grows whenever it may have changed.
-- A result kept with the versions it was made from is valid while they are unchanged.
--   D.State(name)          version now (0 before anything happened)
--   D.BumpState(name)      something changed it (addons may add their own states)
--   D.OnState(names, fn)   fn() once in the next frame after any of the states (name or list) changed
--   D.Cache(deps, maxAge)  table that empties itself when a dep state changed or after maxAge seconds (nil: never):
--                          c = D.Cache({ "gear", "level" }); c.Get() -> table, renewed (true when just emptied);
--                          c.Clear() empties it at once
-- A state learns of a change by events (bump at once, one frame for all), polls (a cheap reading, at most once per
-- frame and only when the state is asked for: for what changes without an event, e.g. position, and as a guard where
-- events come late: UnitLevel is still the old level during PLAYER_LEVEL_UP) or code (D.BumpState from the changing file).
-- The states (event-driven ones: see EVENTS below):
--   frame       every frame (per-frame cache: D.Cache({ "frame" }))
--   bags, durability, spells, skills, target, group, quests: events only
--   gear        poll: the worn item IDs
--   level       poll: UnitLevel
--   money       poll: GetMoney
--   zone        poll: the best map and whether you are in an instance
--   position    poll: your map and spot (to a ten-thousandth of the map)
--   ratings     poll: hit, spell hit and defense (D.PlayerRatings; auras change them without an event)
--   talents     PLAYER_LOGIN too: talents can be read from then on
--   travel      also code: flight point learned (You\Taxi.lua), mount speed seen (You\Hearth.lua)
--   npcs        code: NPC met in a zone or its facts learned (World\LearnNPCs.lua, LearnTrainers.lua)
--   drops       code: NPC drops learned (D.npcDrops, D.itemDroppedBy); apart from "npcs", which bumps far more often
--   prices      code: vendor price or discount learned at a merchant window (World\Prices.lua)
--   events      code: a world event begins/ends, or one of its NPCs was first seen (World\Events.lua)
--   data:<key>  code: that domain built or dropped (Core\Build.lua)
--   data        code: any domain built or dropped
-- Caching: depend on exactly what a result needs ("frame" empties every frame, "data:items" lives until items are
-- rebuilt); leave cheap results uncached. A poll runs once per frame whenever anything asks, so keep it cheap
-- (no string building, no pass over the data).

local versions = {}   -- name -> version
local polls = {}      -- name -> function(): a reading (number) of the game
local readings = {}   -- name -> the last reading
local readAt = {}     -- name -> GetTime() of the last reading
local listeners = {}  -- name -> list of functions
local changed = {}    -- name -> true: changed since the listeners were told
local telling = false -- a call to the listeners is due next frame

local function Tell()
    telling = false
    -- listeners of what changed, each once (one may bump again: told next frame)
    local due, called = {}, {}
    for name in pairs(changed) do
        for _, listener in ipairs(listeners[name]) do
            if not called[listener] then
                called[listener] = true
                due[#due + 1] = listener
            end
        end
    end
    wipe(changed)
    for _, listener in ipairs(due) do
        local ok, err = pcall(listener)
        if not ok then geterrorhandler()(err) end
    end
end

-- listeners are told next frame by a hidden frame (C_Timer.After made a timer per changed frame)
local teller = CreateFrame("Frame")
teller:Hide()
teller:SetScript("OnUpdate", function(self)
    self:Hide()
    Tell()
end)

function D.BumpState(name)
    versions[name] = (versions[name] or 0) + 1
    if listeners[name] then
        changed[name] = true
        if not telling then
            telling = true
            teller:Show()
        end
    end
end
local Bump = D.BumpState

function D.State(name)
    local poll = polls[name]
    if poll then
        local now = GetTime()
        if readAt[name] ~= now then
            readAt[name] = now
            local reading = poll()
            if reading ~= readings[name] then
                readings[name] = reading
                Bump(name)
            end
        end
    end
    return versions[name] or 0
end
local State = D.State

function D.OnState(names, fn)
    if type(names) == "string" then names = { names } end
    for _, name in ipairs(names) do
        listeners[name] = listeners[name] or {}
        table.insert(listeners[name], fn)
    end
end

function D.Cache(deps, maxAge)
    local data, seen, madeAt = {}, {}, nil
    local cache = {}
    function cache.Get()
        local renewed = madeAt == nil or (maxAge ~= nil and GetTime() - madeAt > maxAge)
        for i = 1, #deps do
            local version = State(deps[i])
            if seen[i] ~= version then
                seen[i] = version
                renewed = true
            end
        end
        if renewed then
            wipe(data)
            madeAt = GetTime()
        end
        return data, renewed
    end
    function cache.Clear() madeAt = nil end
    return cache
end

-- Polls

polls.frame = GetTime
polls.level = function() return UnitLevel("player") end
polls.money = function() return GetMoney and GetMoney() or 0 end
polls.zone = function()
    local mapID = C_Map.GetBestMapForUnit("player")
    if D.Secret(mapID) then return -1 end
    return (mapID or 0) * 2 + (IsInInstance() and 1 or 0)
end
polls.position = function()
    local mapID = C_Map.GetBestMapForUnit("player")
    if D.Secret(mapID) or not mapID then return 0 end
    local pos = C_Map.GetPlayerMapPosition(mapID, "player")
    local x, y
    if pos then x, y = D.PositionXY(pos) end
    if not x then return mapID end
    return mapID * 100000000 + math.floor(x * 10000) * 10000 + math.floor(y * 10000)
end
-- same calls as D.PlayerRatings without its table; hit and spell hit are percents below 100, so the three fit one number
polls.ratings = function()
    local hit = GetHitModifier and GetHitModifier() or 0
    local spellHit = GetSpellHitModifier and GetSpellHitModifier() or 0
    local defense = 0
    local defenseSkill = UnitDefenseSkill or UnitDefense -- UnitDefenseSkill is the client's name (UnitDocumentation.lua)
    if defenseSkill then
        local base, bonus = defenseSkill("player")
        if D.Secret(base) or D.Secret(bonus) then return -1 end
        defense = (base or 0) + (bonus or 0)
    end
    if D.Secret(hit) or D.Secret(spellHit) then return -1 end
    return (hit or 0) + (spellHit or 0) * 1000 + defense * 1000000
end
-- worn items as one number: each slot's item ID times its own prime, so a change in any slot changes the sum
local PRIMES = { [0] = 2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37, 41, 43, 47, 53, 59, 61, 67, 71 }
polls.gear = function()
    local sum = 0
    for slot = 0, 19 do sum = sum + (GetInventoryItemID("player", slot) or 0) * PRIMES[slot] end
    return sum
end

-- Events

local EVENTS = {
    BAG_UPDATE_DELAYED = { "bags" },
    PLAYER_ENTERING_WORLD = { "bags", "zone" },
    PLAYER_EQUIPMENT_CHANGED = { "gear" },
    UPDATE_INVENTORY_DURABILITY = { "durability" },
    PLAYER_LEVEL_UP = { "level" },
    PLAYER_MONEY = { "money" },
    ZONE_CHANGED = { "zone" }, ZONE_CHANGED_INDOORS = { "zone" }, ZONE_CHANGED_NEW_AREA = { "zone" },
    QUEST_LOG_UPDATE = { "quests" }, QUEST_ACCEPTED = { "quests" }, QUEST_REMOVED = { "quests" },
    QUEST_TURNED_IN = { "quests" },
    SPELLS_CHANGED = { "spells" }, LEARNED_SPELL_IN_TAB = { "spells" }, LEARNED_SPELL_IN_SKILL_LINE = { "spells" },
    SKILL_LINES_CHANGED = { "skills" },
    PLAYER_TALENT_UPDATE = { "talents" }, TRAIT_CONFIG_UPDATED = { "talents" }, CHARACTER_POINTS_CHANGED = { "talents" },
    PLAYER_LOGIN = { "talents" },
    HEARTHSTONE_BOUND = { "travel" },
    PLAYER_TARGET_CHANGED = { "target" },
    GROUP_ROSTER_UPDATE = { "group" }, UNIT_LEVEL = { "group" }, PLAYER_UPDATE_RESTING = { "group" },
}
local function OnEvent(event, unit)
    -- a level change of anyone else (name plates, targets) is no change of the group
    if event == "UNIT_LEVEL" and (D.Secret(unit) or type(unit) ~= "string"
            or not (unit == "player" or unit:find("^party") or unit:find("^raid"))) then
        return
    end
    local names = EVENTS[event]
    for i = 1, #names do Bump(names[i]) end
end
for event in pairs(EVENTS) do D.On(event, OnEvent) end
