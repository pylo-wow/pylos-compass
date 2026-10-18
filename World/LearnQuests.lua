local _, D = ...
if D.off then return end

-- Who gives and takes each quest, learned in play (the quest cache does not tell):
--   offered (QUEST_DETAIL)  the NPC or object you talk to, or the item you used (named by the event)
--   taken (QUEST_PROGRESS, _COMPLETE, _TURNED_IN)  the NPC or object
--   listed (GOSSIP_SHOW, QUEST_GREETING)  every quest an NPC or object offers and takes back
--                           (in your log, done or not) without taking one; daily/weekly as listed
-- PylosCompassWorldDB.quests[questID] = { from = npcID | fromObject = objectID | fromItem = itemID,
--   to = npcID | toObject = objectID, fromPlace / toPlace = an object's spot (packed like NPC
--   places; an NPC's own spot is its place, LearnNPCs.lua),
--   repeats = 0 once, 1 daily, 2 weekly (Enum.QuestFrequency; beats the data's, World\Quests.lua) }

local Secret = D.Secret

-- What the quest window belongs to: "npc", NPC ID (vehicles count) or "object", object ID;
-- nil otherwise (a player sharing a quest, none, a secret)
local function QuestPartner()
    local guid = UnitGUID("npc")
    if Secret(guid) or not guid then return nil end
    local kind, _, _, _, _, id = strsplit("-", guid)
    id = tonumber(id)
    if not id then return nil end
    if kind == "Creature" or kind == "Vehicle" then return "npc", id end
    if kind == "GameObject" then return "object", id end
    return nil
end

-- Notes who gives (offered) or takes a quest: kind and ID of QuestPartner or "item";
-- true if it was new
local function Note(questID, offered, kind, id)
    local quests = D.world.quests
    local learned = quests[questID] or {}
    quests[questID] = learned
    if offered then
        local before = learned.from or learned.fromObject or learned.fromItem
        learned.from, learned.fromObject, learned.fromItem, learned.fromPlace = nil, nil, nil, nil
        if kind == "npc" then learned.from = id
        elseif kind == "object" then learned.fromObject, learned.fromPlace = id, D.PlayerPlace()
        else learned.fromItem = id end
        return before ~= id
    end
    if kind == "item" then return false end
    local before = learned.to or learned.toObject
    learned.to, learned.toObject, learned.toPlace = nil, nil, nil
    if kind == "npc" then learned.to = id else learned.toObject, learned.toPlace = id, D.PlayerPlace() end
    return before ~= id
end

-- arg: the event's first value (QUEST_DETAIL: item used; QUEST_TURNED_IN: quest)
local function QuestWindow(event, arg)
    if not (D.world and D.world.quests) then return end
    local questID
    if event == "QUEST_TURNED_IN" then questID = arg elseif GetQuestID then questID = GetQuestID() end
    if Secret(questID) or not questID or questID == 0 then return end
    local kind, id = QuestPartner()
    local offered = event == "QUEST_DETAIL"
    -- QUEST_DETAIL names the item you used to begin it (0 or nil else)
    if offered and not Secret(arg) and arg and arg ~= 0 then kind, id = "item", arg end
    if not kind then return end
    Note(questID, offered, kind, id)
end
for _, event in ipairs({ "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE", "QUEST_TURNED_IN" }) do
    D.On(event, QuestWindow)
end

-- Quests an NPC offers and takes back, as listed by the gossip window
-- (C_GossipInfo.GetAvailableQuests / GetActiveQuests: questID, frequency) or the quest
-- greeting (GetAvailableQuestInfo: 5th value quest ID, 2nd frequency; GetActiveQuestID).
-- A quest in your log is listed where it is turned in.
local function NoteRepeats(questID, frequency)
    if Secret(frequency) or type(frequency) ~= "number" then return false end
    local learned = D.world.quests[questID]
    if learned.repeats == frequency then return false end
    learned.repeats = frequency
    local q = D.QuestOf and D.QuestOf(questID)
    if q then q.repeats = D.QuestRepeats(questID) end
    return true
end
local function Listed()
    if not (D.world and D.world.quests) or InCombatLockdown() then return end
    local kind, id = QuestPartner()
    if not kind then return end
    local changed = false
    local function Offers(questID, frequency)
        if Secret(questID) or not questID or questID == 0 then return end
        if Note(questID, true, kind, id) then changed = true end
        if NoteRepeats(questID, frequency) then changed = true end
    end
    local function Takes(questID)
        if Secret(questID) or not questID or questID == 0 then return end
        if Note(questID, false, kind, id) then changed = true end
    end
    if C_GossipInfo and C_GossipInfo.GetAvailableQuests then
        for _, info in ipairs(C_GossipInfo.GetAvailableQuests() or {}) do Offers(info.questID, info.frequency) end
        for _, info in ipairs(C_GossipInfo.GetActiveQuests() or {}) do Takes(info.questID) end
    end
    if GetNumAvailableQuests and GetAvailableQuestInfo then
        for i = 1, GetNumAvailableQuests() or 0 do
            local _, frequency, _, _, questID = GetAvailableQuestInfo(i)
            Offers(questID, frequency)
        end
    end
    if GetNumActiveQuests and GetActiveQuestID then
        for i = 1, GetNumActiveQuests() or 0 do Takes(GetActiveQuestID(i)) end
    end
    if changed then D.BumpState("npcs") end
end
D.On("GOSSIP_SHOW", Listed)
D.On("QUEST_GREETING", Listed)

local REPEATS = { "daily", "weekly" }
function D.QuestRepeats(questID)
    local learned = D.world and D.world.quests and D.world.quests[questID]
    if learned and learned.repeats then return REPEATS[learned.repeats] end
    return D.QuestFact and D.QuestFact(questID, "repeats") or nil
end

-- Givers, takers and prerequisites: seen in play first, then the client's data (quest-starting
-- items, Data\QuestFacts.lua; next quest from the quest cache), then the 1.12 data
-- (Data\QuestLinks.lua, vmangos). Each answer names its origin:
--   "seen"  seen in Forever (PylosCompassWorldDB.quests, Data\Seen.lua)
--   nil     the client's own data
--   "1.12"  1.12 data only: unchecked

-- "n197,o31" -> { { "npc", 197 }, { "object", 31 } }
local KIND = { n = "npc", o = "object" }
local function Parties(text)
    local list = {}
    for kind, id in (text or ""):gmatch("([no])(%d+)") do list[#list + 1] = { KIND[kind], tonumber(id) } end
    return list
end
local function IDs(text)
    local list = {}
    for id in (text or ""):gmatch("%d+") do list[#list + 1] = tonumber(id) end
    return list
end
local function PlaceOf(kind, id)
    if kind == "npc" then return D.npcPlaces and D.npcPlaces[id] end
    return nil -- the 1.12 data has no object spots here
end

-- All known givers: list of { kind, id, place, origin }, kind "npc" | "object" | "item".
-- Order: seen in play, items that begin it, then 1.12 data (minus duplicates); empty if none
function D.QuestGivers(questID)
    local list, have = {}, {}
    local function Add(kind, id, place, origin)
        if have[kind .. id] then return end
        have[kind .. id] = true
        list[#list + 1] = { kind, id, place, origin }
    end
    local learned = D.world and D.world.quests and D.world.quests[questID]
    if learned then
        if learned.from then Add("npc", learned.from, PlaceOf("npc", learned.from), "seen")
        elseif learned.fromObject then Add("object", learned.fromObject, learned.fromPlace, "seen")
        elseif learned.fromItem then Add("item", learned.fromItem, nil, "seen") end
    end
    local q = D.QuestOf and D.QuestOf(questID)
    for _, item in ipairs(q and q.startedBy or {}) do Add("item", item, nil, nil) end
    for _, p in ipairs(Parties(D.questGivers and D.questGivers[questID])) do Add(p[1], p[2], PlaceOf(p[1], p[2]), "1.12") end
    return list
end
-- First of D.QuestGivers: kind, ID, place (NPC: D.npcPlaces; object: spot seen; nil if unknown), origin
function D.QuestGiver(questID)
    local first = D.QuestGivers(questID)[1]
    if first then return first[1], first[2], first[3], first[4] end
    return nil
end
-- All known takers: { kind, id, place, origin } ("npc" | "object"); seen in play first, then 1.12 data
function D.QuestTakers(questID)
    local list, have = {}, {}
    local learned = D.world and D.world.quests and D.world.quests[questID]
    if learned then
        if learned.to then list[1] = { "npc", learned.to, PlaceOf("npc", learned.to), "seen" } have["npc" .. learned.to] = true
        elseif learned.toObject then list[1] = { "object", learned.toObject, learned.toPlace, "seen" } have["object" .. learned.toObject] = true end
    end
    for _, p in ipairs(Parties(D.questTakers and D.questTakers[questID])) do
        if not have[p[1] .. p[2]] then list[#list + 1] = { p[1], p[2], PlaceOf(p[1], p[2]), "1.12" } end
    end
    return list
end
function D.QuestTaker(questID)
    local first = D.QuestTakers(questID)[1]
    if first then return first[1], first[2], first[3], first[4] end
    return nil
end

-- Prerequisites (1.12 data): nil if none known, else { anyOf = { questID, ... } one done,
-- allOf = { ... } all done, inLog = questID or nil (that quest in your log), origin = "1.12" }
function D.QuestPrevious(questID)
    local any = IDs(D.questPre and D.questPre[questID])
    local all = IDs(D.questPreAll and D.questPreAll[questID])
    local inLog = D.questPreActive and D.questPreActive[questID]
    if #any == 0 and #all == 0 and not inLog then return nil end
    return { anyOf = any, allOf = all, inLog = inLog, origin = "1.12" }
end

-- Quests a quest opens: list of { questID, origin }; the quest cache's next quest first
-- (origin nil), then quests whose D.QuestPrevious names it ("1.12"), ascending; empty if none
local opens -- questID -> list of quest IDs (built on first call)
function D.QuestNext(questID)
    if not opens then
        opens = {}
        for _, map in ipairs({ D.questPre or {}, D.questPreAll or {} }) do
            for later, text in pairs(map) do
                for _, earlier in ipairs(IDs(text)) do
                    opens[earlier] = opens[earlier] or {}
                    table.insert(opens[earlier], later)
                end
            end
        end
        for _, list in pairs(opens) do table.sort(list) end
    end
    local list, have = {}, {}
    local q = D.QuestOf and D.QuestOf(questID)
    if q and q.nextQuest then list[1] = { q.nextQuest, nil } have[q.nextQuest] = true end
    for _, later in ipairs(opens[questID] or {}) do
        if not have[later] then have[later] = true list[#list + 1] = { later, "1.12" } end
    end
    return list
end

-- Quests that exclude this one (only one of a group can be done; 1.12 data): list of quest IDs, "1.12"
function D.QuestExclusive(questID)
    local list = IDs(D.questExclusive and D.questExclusive[questID])
    return list, #list > 0 and "1.12" or nil
end

-- Quests an NPC gives and takes back: two ascending lists of quest IDs. As seen in play;
-- withData also adds the 1.12 data's (D.questGivers / D.questTakers) where play showed no other
-- giver or taker (a pass over a few thousand quests)
function D.QuestsOfNPC(npcID, withData)
    local given, taken, have = {}, {}, { {}, {} }
    local quests = D.world and D.world.quests or {}
    for questID, learned in pairs(quests) do
        if learned.from == npcID then given[#given + 1] = questID have[1][questID] = true end
        if learned.to == npcID then taken[#taken + 1] = questID have[2][questID] = true end
    end
    if withData then
        local key = "n" .. npcID
        for i, map in ipairs({ D.questGivers or {}, D.questTakers or {} }) do
            local out = i == 1 and given or taken
            for questID, text in pairs(map) do
                local learned = quests[questID]
                local other = learned and (i == 1 and (learned.from or learned.fromObject or learned.fromItem)
                    or i == 2 and (learned.to or learned.toObject))
                if not have[i][questID] and not other then
                    for who in text:gmatch("[no]%d+") do
                        if who == key then out[#out + 1] = questID have[i][questID] = true break end
                    end
                end
            end
        end
    end
    table.sort(given)
    table.sort(taken)
    return given, taken
end
