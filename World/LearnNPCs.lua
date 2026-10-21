local _, D = ...

-- NPCs as Forever has them, learned in play: the data files hold the 1.12 data (vmangos), but
-- Forever moved, changed and added NPCs. What the game shows is stored in PylosCompassWorldDB and
-- takes precedence over the 1.12 data.
--   meeting one        a name plate, target or mouseover means the NPC is near, so in your zone
--                      (C_Map.GetBestMapForUnit; world map shapes are coarse).
--                      PylosCompassWorldDB.met: NPC ID -> uiMapID (false once two zones were seen:
--                      border or wanderer); D.NPCZones puts it first
--   talking to one     your spot is its spot; its window gives its role (vendor, repair,
--                      trainer, flight master, banker, auctioneer, quest giver)
--   a vendor's window  what it really sells
--   pointing at one    level, reaction, rank and type (target, mouseover, name plates; not in
--                      combat or instances: unit values can be secret there)
--   looting one        drops: from MIN_LOOTS corpses the chances seen replace the 1.12 ones, from
--                      MIN_LOOTS_REMOVE corpses a rare 1.12 drop that never fell is dropped
-- PylosCompassWorldDB.npcs[npcID] = { place = uiMapID * 1000000 + x * 1000 + y,
--   roles = bits seen (D.NPC_ROLE), noRepair = true (vendor seen without repairing),
--   levelMin, levelMax, rank (entry.npcRank), type (entry.creatureType),
--   reaction = { Alliance = 1|2|3, Horde = 1|2|3 }, sells = "itemID,...",
--   limited = "itemID:most,..." (limited-stock wares, most seen on offer at once; "" = none,
--   then the data's are not used), teaches = "spellID,...",
--   teachesFull = true (trainer window seen, LearnTrainers.lua), loots = corpses looted,
--   drops = { itemID = times } }. Stays on your computer.
-- Quest givers/takers: LearnQuests.lua; dungeon entrances: Dungeons.lua.

local Secret = D.Secret
local MIN_LOOTS = 10 -- corpses looted before the chances seen replace the 1.12 ones
local MIN_LOOTS_REMOVE = 100 -- corpses looted before a 1.12 drop that never fell may be removed ...
local REMOVE_BELOW = 20 -- ... if its 1.12 chance is under this many percent (a few corpses prove nothing about rare drops)
local unverified = {} -- NPC ID -> true: its drop list still holds 1.12 drops that were not seen
local ROLE = D.NPC_ROLE
local RANKS = { elite = 1, rareelite = 2, worldboss = 3, rare = 4, normal = 0, trivial = 0, minus = 0 }
-- UnitCreatureType answers in the client's language: English names plus the client's own
-- names for the same IDs
local TYPES = { Beast = 1, Dragonkin = 2, Demon = 3, Elemental = 4, Giant = 5, Undead = 6, Humanoid = 7,
    Critter = 8, Mechanical = 9, ["Not specified"] = 10, Totem = 11 }
for id = 1, 11 do
    local info = C_CreatureInfo.GetCreatureTypeInfo(id)
    if info and info.name and info.name ~= "" then TYPES[info.name] = id end
end

function D.Learned(npcID)
    local npcs = D.world and D.world.npcs
    return npcs and npcs[npcID] or nil
end

-- Learned facts of an NPC of the data, created if missing (also used by LearnTrainers.lua);
-- nil for an NPC the data does not know
function D.NoteNPC(npcID)
    local npcs = D.world and D.world.npcs
    if not npcs or not npcID or not (D.npcNamesEN and D.npcNamesEN[npcID]) then return nil end
    local learned = npcs[npcID] or {}
    npcs[npcID] = learned
    return learned
end
local Note = D.NoteNPC

-- Learned facts are written into D.npcPlaces, D.npcSells / D.itemSoldBy and D.npcDrops /
-- D.itemDroppedBy (at load and when learned), so every reader sees Forever's truth first.

local function Split(text, out)
    for part in (text or ""):gmatch("[^,]+") do out[#out + 1] = part end
    return out
end
-- Removes an NPC from an item's list ("npcID" or "npcID:chance" parts)
local function Without(text, npcID)
    local parts = {}
    for _, part in ipairs(Split(text, {})) do
        if tonumber(part:match("^(%d+)")) ~= npcID then parts[#parts + 1] = part end
    end
    return #parts > 0 and table.concat(parts, ",") or nil
end

-- A new place bumps the states "npcs" and "places" (the neighbour index of Reach.lua depends on places only)
local function ApplyPlace(npcID, learned)
    if learned.place and D.npcPlaces[npcID] ~= learned.place then
        D.npcPlaces[npcID] = learned.place
        D.BumpState("places")
        D.BumpState("npcs")
    end
end

local function ApplySells(npcID, learned)
    if not learned.sells then return end
    for _, item in ipairs(Split(D.npcSells[npcID], {})) do
        local itemID = tonumber(item)
        D.itemSoldBy[itemID] = Without(D.itemSoldBy[itemID], npcID)
    end
    D.npcSells[npcID] = learned.sells ~= "" and learned.sells or nil
    for _, item in ipairs(Split(learned.sells, {})) do
        local itemID = tonumber(item)
        local list = D.itemSoldBy[itemID]
        D.itemSoldBy[itemID] = list and (list .. "," .. npcID) or tostring(npcID)
    end
end

-- Sorts an item's droppers by chance, best first (Reach.lua reads the first as the best)
local function SortDrops(text)
    local parts = Split(text, {})
    table.sort(parts, function(a, b)
        return tonumber(a:match(":(%d+)")) > tonumber(b:match(":(%d+)"))
    end)
    return #parts > 0 and table.concat(parts, ",") or nil
end

-- The chances of the items seen replace the listed ones; a listed drop that was not seen stays, except a rare one
-- (REMOVE_BELOW) once MIN_LOOTS_REMOVE corpses were looted.
local function ApplyDrops(npcID, learned)
    local loots = learned.loots or 0
    if loots < MIN_LOOTS or not learned.drops then return end
    local listed = {} -- itemID -> the part of the list as it is now ("itemID:chance")
    for _, part in ipairs(Split(D.npcDrops[npcID], {})) do
        listed[tonumber(part:match("^(%d+)"))] = part
    end
    local entries, seen, changed = {}, {}, false -- { itemID, chance, part }
    for itemID, times in pairs(learned.drops) do
        if D.itemNamesEN[itemID] then
            local chance = math.floor(times / loots * 100 + 0.5)
            seen[itemID] = true
            entries[#entries + 1] = { itemID, chance, itemID .. ":" .. chance }
            -- only lists whose entry for this NPC differs are rewritten (and sorted again)
            if listed[itemID] ~= itemID .. ":" .. chance then
                local list = Without(D.itemDroppedBy[itemID], npcID)
                D.itemDroppedBy[itemID] = SortDrops((list and (list .. ",") or "") .. npcID .. ":" .. chance)
                changed = true
            end
        end
    end
    local kept = false
    for itemID, part in pairs(listed) do -- in the old list only: not seen dropping
        if not seen[itemID] then
            local chance = tonumber(part:match(":(%d+)")) or 0
            if loots >= MIN_LOOTS_REMOVE and chance < REMOVE_BELOW then
                D.itemDroppedBy[itemID] = Without(D.itemDroppedBy[itemID], npcID)
                changed = true
            else
                entries[#entries + 1] = { itemID, chance, part }
                kept = true
            end
        end
    end
    unverified[npcID] = kept and loots < MIN_LOOTS_REMOVE or nil
    table.sort(entries, function(a, b) return a[2] > b[2] or (a[2] == b[2] and a[1] < b[1]) end)
    for i, entry in ipairs(entries) do entries[i] = entry[3] end
    local text = #entries > 0 and table.concat(entries, ",") or nil
    if text ~= D.npcDrops[npcID] then changed = true end
    if not changed then return end
    D.npcDrops[npcID] = text
    D.BumpState("drops")
end

-- Where an NPC fact comes from:
--   "seen"  seen in Forever
--   "1.12"  1.12 data only (vmangos), unchecked
--   nil     unknown (or the client's own: type, rank, model, name, title)
-- what: "level", "reaction" (to your faction), "place", "drops", "sells", "trains";
-- roles: D.NPCRoleOrigin; zones: D.NPCZones (first is the one met, see D.MetZone).
local ORIGIN = {
    level = function(entry, learned)
        if learned and learned.levelMax then return "seen" end
        return entry.levelMax > 0 and "1.12" or nil
    end,
    reaction = function(entry, learned)
        local side = UnitFactionGroup("player")
        if learned and learned.reaction and side and learned.reaction[side] then return "seen" end
        return entry.reaction ~= 0 and "1.12" or nil
    end,
    place = function(entry, learned)
        if learned and learned.place then return "seen" end
        return D.npcPlaces[entry.npcID] and "1.12" or nil
    end,
    drops = function(entry, learned)
        if learned and (learned.loots or 0) >= MIN_LOOTS and learned.drops and not unverified[entry.npcID] then
            return "seen"
        end
        return D.npcDrops[entry.npcID] and "1.12" or nil
    end,
    sells = function(entry, learned)
        if learned and learned.sells then return "seen" end
        return D.npcSells[entry.npcID] and "1.12" or nil
    end,
    trains = function(entry, learned)
        if learned and learned.teachesFull then return "seen" end
        return D.npcTrainers[entry.npcID] and "1.12" or nil
    end,
}
function D.NPCOrigin(entry, what)
    return ORIGIN[what](entry, D.Learned(entry.npcID))
end
-- By NPC ID (nil for an NPC the data does not know)
function D.NPCOriginByID(npcID, what)
    local entry = D.NPCByID(npcID)
    return entry and D.NPCOrigin(entry, what) or nil
end
-- Origin of a role (bit of D.NPC_ROLE): "seen" (window seen) or "1.12"; nil if the NPC lacks it
function D.NPCRoleOrigin(entry, role)
    if not D.NPCHasRole(entry, role) then return nil end
    local learned = D.Learned(entry.npcID)
    return learned and learned.roles and math.floor(learned.roles / role) % 2 == 1 and "seen" or "1.12"
end

function D.ApplyLearned()
    for npcID, learned in pairs(D.world.npcs) do
        ApplyPlace(npcID, learned)
        ApplySells(npcID, learned)
        ApplyDrops(npcID, learned)
    end
end
D.OnLoaded(D.ApplyLearned)

local WINDOW_ROLES = {
    MERCHANT_SHOW = ROLE.VENDOR, TRAINER_SHOW = ROLE.TRAINER, TAXIMAP_OPENED = ROLE.FLIGHT_MASTER,
    BANKFRAME_OPENED = ROLE.BANKER, AUCTION_HOUSE_SHOW = ROLE.AUCTIONEER, QUEST_GREETING = ROLE.QUEST_GIVER,
    QUEST_DETAIL = ROLE.QUEST_GIVER, QUEST_PROGRESS = ROLE.QUEST_GIVER, QUEST_COMPLETE = ROLE.QUEST_GIVER,
}

-- true if the role is new
local function AddRole(learned, role)
    local roles = learned.roles or 0
    if math.floor(roles / role) % 2 == 0 then
        learned.roles = roles + role
        return true
    end
    return false
end

-- Stock of a ware on offer: -1 unlimited, else the stock left (0: sold out); nil if unknown
-- (C_MerchantFrame.GetItemInfo numAvailable)
local function OnOffer(index)
    local info = C_MerchantFrame.GetItemInfo(index)
    local available = info and info.numAvailable
    if Secret(available) then return nil end
    return available
end

-- Most seen of each limited ware ("itemID:most,..."), updated with the current stock; a ware seen unlimited drops out
local function Limited(before, now)
    local most = {}
    for id, n in (before or ""):gmatch("(%d+):(%d+)") do most[tonumber(id)] = tonumber(n) end
    for itemID, available in pairs(now) do
        if available < 0 then most[itemID] = nil
        else most[itemID] = math.max(most[itemID] or 0, available) end
    end
    local ids = {}
    for itemID in pairs(most) do ids[#ids + 1] = itemID end
    table.sort(ids)
    for i, itemID in ipairs(ids) do ids[i] = itemID .. ":" .. most[itemID] end
    return table.concat(ids, ",")
end

-- What a vendor sells: its window's items (of the data's items) and which have limited stock; true if that is news
local function NoteSells(npcID, learned)
    local items, seen, stock = {}, {}, {}
    for index = 1, GetMerchantNumItems() or 0 do
        local itemID = D.ItemIDFromLink(GetMerchantItemLink(index))
        if itemID and not seen[itemID] and D.itemNamesEN[itemID] then
            seen[itemID] = true
            items[#items + 1] = itemID
            stock[itemID] = OnOffer(index)
        end
    end
    if #items == 0 then return false end -- items not loaded yet (MERCHANT_UPDATE follows)
    table.sort(items)
    local sells = table.concat(items, ",")
    local changed = sells ~= learned.sells
    if changed then
        learned.sells = sells
        ApplySells(npcID, learned)
    end
    local limited = Limited(learned.limited, stock)
    local kept = {}
    for part in limited:gmatch("[^,]+") do
        if seen[tonumber(part:match("^(%d+)"))] then kept[#kept + 1] = part end
    end
    local keptText = table.concat(kept, ",")
    if keptText ~= learned.limited then
        learned.limited, changed = keptText, true
    end
    return changed
end

-- Most of an item a vendor has on offer at once (limited stock, restocks over time); nil if
-- unlimited. As seen at its window, else the data's (D.npcLimited: 1.12 npc_vendor maxcount).
function D.VendorStock(npcID, itemID)
    local learned = D.Learned(npcID)
    local text = learned and learned.limited
    if text == nil then text = D.npcLimited[npcID] end
    if not text or text == "" then return nil end
    local most = ("," .. text):match("," .. itemID .. ":(%d+)")
    return most and tonumber(most) or nil
end

local function Talked(event)
    if not D.world or InCombatLockdown() then return end
    local npcID = D.NPCOf("npc")
    local learned = Note(npcID)
    if not learned then return end
    local changed = false -- MERCHANT_UPDATE comes with every sale, buy and repair: bump only for news
    local spot = D.PlayerPlace()
    if spot and spot ~= learned.place then
        learned.place = spot
        ApplyPlace(npcID, learned)
        changed = true
    end
    local role = WINDOW_ROLES[event]
    if role and AddRole(learned, role) then changed = true end
    if event == "MERCHANT_SHOW" or event == "MERCHANT_UPDATE" then
        if AddRole(learned, ROLE.VENDOR) then changed = true end
        local repair = CanMerchantRepair()
        if repair and AddRole(learned, ROLE.REPAIR) then changed = true end
        local noRepair = not repair or nil
        if learned.noRepair ~= noRepair then
            learned.noRepair, changed = noRepair, true
        end
        if NoteSells(npcID, learned) then changed = true end
    end
    if changed then D.BumpState("npcs") end
end
for _, event in ipairs({ "GOSSIP_SHOW", "MERCHANT_SHOW", "MERCHANT_UPDATE", "TRAINER_SHOW", "TRAINER_UPDATE",
        "TAXIMAP_OPENED", "BANKFRAME_OPENED", "AUCTION_HOUSE_SHOW", "QUEST_GREETING", "QUEST_DETAIL", "QUEST_PROGRESS",
        "QUEST_COMPLETE" }) do
    D.On(event, Talked)
end

-- One listener for name plates, target and mouseover: the zone met, then the NPC's facts.

function D.MetZone(npcID)
    local met = D.world and D.world.met
    return met and met[npcID] or nil
end

local function Met(npcID)
    local met = D.world.met
    if met[npcID] == false then return end
    local zone = D.PlayerZone()
    if not zone then return end
    local before = met[npcID]
    if before == nil then
        met[npcID] = zone
    elseif before ~= zone then
        met[npcID] = false
    else
        return
    end
    -- update only the two zones' NPC lists (D.NPCsInZone), not a full pass
    D.NPCMoved(npcID, before)
    D.BumpState("npcs")
end

-- A spawn is not re-read for SEEN_AGAIN seconds (name plates and mouseover repeat constantly;
-- level, rank and type never change, reaction seldom). GUID -> GetTime(), reset at GUID_KEEP.
local SEEN_AGAIN, GUID_KEEP = 30, 300
local readAt, reads = {}, 0

local function Pointed(unit, guid, npcID)
    local now = GetTime()
    local last = readAt[guid]
    if last and now - last < SEEN_AGAIN then return end
    local level, reaction = UnitLevel(unit), UnitReaction(unit, "player")
    local class, kind = UnitClassification(unit), UnitCreatureType(unit)
    if Secret(level) or Secret(reaction) or Secret(class) or Secret(kind) then return end
    if reads >= GUID_KEEP then wipe(readAt) reads = 0 end
    readAt[guid], reads = now, reads + 1
    local learned = Note(npcID)
    if not learned then return end
    local wasMin, wasMax, wasRank, wasType = learned.levelMin, learned.levelMax, learned.rank, learned.type
    local side = UnitFactionGroup("player") or "?"
    local wasReaction = learned.reaction and learned.reaction[side]
    if level and level > 0 then -- -1: too high to tell (skull)
        learned.levelMin = math.min(learned.levelMin or level, level)
        learned.levelMax = math.max(learned.levelMax or level, level)
    end
    if reaction then
        learned.reaction = learned.reaction or {}
        learned.reaction[side] = reaction <= 3 and 1 or reaction == 4 and 2 or 3
    end
    if class and RANKS[class] then learned.rank = RANKS[class] end
    if kind and TYPES[kind] then learned.type = TYPES[kind] end
    if wasMin ~= learned.levelMin or wasMax ~= learned.levelMax or wasRank ~= learned.rank
            or wasType ~= learned.type or wasReaction ~= (learned.reaction and learned.reaction[side]) then
        D.BumpState("npcs")
    end
end

-- Not in combat or instances: unit values can be secret there in Forever. Only NPCs of the
-- data, and none a player controls (a warlock's Voidwalker is a data NPC too, and its
-- level and reaction would be learned as the NPC's).
local function Seen(unit)
    if not D.world or InCombatLockdown() or IsInInstance() then return end
    local guid = UnitGUID(unit)
    if Secret(guid) or not guid then return end
    local npcID = D.NPCOfGUID(guid)
    if not npcID or not (D.npcNamesEN and D.npcNamesEN[npcID]) or UnitIsPlayer(unit) then return end
    local controlled = UnitPlayerControlled(unit)
    if Secret(controlled) or controlled then return end
    Met(npcID)
    if D.npcEvents and D.npcEvents[npcID] then D.EventSeen(npcID) end
    Pointed(unit, guid, npcID)
end
D.On("NAME_PLATE_UNIT_ADDED", function(_, unit) Seen(unit) end)
D.On("PLAYER_TARGET_CHANGED", function() Seen("target") end)
D.On("UPDATE_MOUSEOVER_UNIT", function() Seen("mouseover") end)

-- Pick Pocket and Skinning open a loot window that is no corpse's drops: the pickpocket's source is a living NPC
-- (its corpse is counted when it is looted), and a skinned corpse may never have been looted by you. The window
-- right after such a cast is not counted. Spells: Pick Pocket (ClassSpells.lua) and every spell of the Skinning
-- skill line (ProfessionSpells.lua).
local PICK_POCKET, SKINNING_LINE, NOT_DROPS_FOR = 921, 393, 2 -- the last: seconds
local notDrops = { [PICK_POCKET] = true }
local skinning = D.professionSpells and D.professionSpells[SKINNING_LINE] or {}
for i = 1, #skinning, 5 do notDrops[skinning[i]] = true end
local notDropsUntil = 0
D.On("UNIT_SPELLCAST_SUCCEEDED", function(_, _, _, spellID)
    if spellID and not Secret(spellID) and notDrops[spellID] then notDropsUntil = GetTime() + NOT_DROPS_FOR end
end)

-- corpse GUID -> true: counted once (skinning reopens it); reset at LOOTED_KEEP
local LOOTED_KEEP = 200
local looted, lootedCount = {}, 0
-- Also in dungeons (boss loot); secret values are skipped
D.On("LOOT_OPENED", function()
    if not D.world then return end
    local skip = GetTime() < notDropsUntil
    notDropsUntil = 0
    if skip then return end
    local counted, npcs = {}, {} -- corpse GUID -> true: counted in this window; npcID -> true
    for slot = 1, GetNumLootItems() do
        local link = GetLootSlotLink(slot)
        local itemID = not Secret(link) and D.ItemIDFromLink(link) or nil
        local sources = GetLootSourceInfo and { GetLootSourceInfo(slot) } or {}
        for i = 1, #sources, 2 do
            local guid = sources[i]
            local npcID = not Secret(guid) and guid and D.NPCOfGUID(guid) or nil
            local learned = npcID and Note(npcID)
            if learned then
                if not looted[guid] then
                    if lootedCount >= LOOTED_KEEP then wipe(looted) lootedCount = 0 end
                    looted[guid], lootedCount = true, lootedCount + 1
                    learned.loots = (learned.loots or 0) + 1
                    counted[guid], npcs[npcID] = true, true
                end
                -- an item of a corpse counted earlier (area loot) is not counted again
                if itemID and counted[guid] then
                    learned.drops = learned.drops or {}
                    learned.drops[itemID] = (learned.drops[itemID] or 0) + 1
                end
            end
        end
    end
    for npcID in pairs(npcs) do ApplyDrops(npcID, D.world.npcs[npcID]) end
    if next(npcs) then D.BumpState("npcs") end
end)
