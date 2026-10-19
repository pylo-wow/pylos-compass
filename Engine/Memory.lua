local _, D = ...
local ns = D.engine

-- Memory: what you do, learned over time, keyed by entry IDs of the data layer ("s:133", "i:2589", "n:1234"). The
-- search tells it what you chose there. All of it stays on your computer.
-- PylosCompassEngineDB:
--   chosen    what you chose in the search: "" -> entry ID -> { value, time }, plus "\1rest", "\1instance", "\1group",
--             "\1world": the choices in that situation ("\1" cannot be typed). A choice adds 1, only looking 0.5;
--             values halve every two weeks
--   did       what you did in the game, not only what you chose in the search: spells cast (crafting too), items used
--             and bought, NPCs talked to, quests turned in; entry ID -> { value, time }, halves every two weeks
--   bought    item ID -> { value, time, stock }; stock: how many you usually have after buying (to tell when you
--             run low); halves every month
--   skipped   suggestions passed over, per kind ("do": the window, "know": the search's lists): kind -> entry ID ->
--             { value, time }; you chose one further down a list (the ones above were seen and not wanted) or called
--             one bad. Passing over in the search does not tire the window's suggestions. Halves every week;
--             choosing the entry forgets it
--   hidden    entry ID -> true or the text they come back on ("Don't suggest"; reasons.Renew)
--   reasonStats  how often you followed each reason (kept by Learning.lua)
-- Changes are told as states (D.BumpState; Reasons.lua keeps its results by them): "rec:chosen" (memory.Chose),
-- "rec:memory" (did, bought, skipped, forgotten), "rec:hidden".

local memory = {}
ns.memory = memory

local HALF_LIFE = 14 * 86400       -- seconds: choices, things done
local SKIP_HALF_LIFE = 7 * 86400   -- passing over
local BUY_HALF_LIFE = 30 * 86400   -- buying
local SKIPS_FOR_HALF = 3           -- skips that make a suggestion half as tired
local DONE_FOR_HALF = 5            -- times done that count half as much as possible
local REGULAR = 0.6                -- bought this often (two purchases lately): a regular buy
local LOW_SHARE = 0.35             -- less than this share of the usual stock: running low
local FORGOTTEN = 0.05             -- values below are dropped at login
local USED_CHOSEN, USED_HERE, USED_DONE = 0.5, 0.2, 0.3
local KINDS = { "do", "know" }

-- only IDs of entries are kept (a quest item's spell would only fill it)
local function Accept(id) return D.EntryByID(id) ~= nil end

-- auto attacks are active spells but every swing-timer cast would count as "done": Auto Shot, Attack, Shoot, Throw,
-- Shoot Bow / Gun / Crossbow
local AUTO_ATTACKS = {
    [75] = true, [6603] = true, [5019] = true, [2764] = true, [2480] = true, [7918] = true, [7919] = true
}

-- memory.OnAction(function(id)): called when you chose an entry, did it in the game or talked to the NPC
-- (Learning.lua checks there whether a recommendation was followed)
local listeners = {}
function memory.OnAction(listener) listeners[#listeners + 1] = listener end
local function Acted(id)
    for _, listener in ipairs(listeners) do listener(id) end
end

local function DB() return ns.db end
local function Changed() D.BumpState("rec:memory") end

-- how strongly a record counts now, 0..1: value / (value + half), so with half = 1 one choice is 0.5, three are 0.75
local function Strength(record, now, halfLife, half)
    if not record then return 0 end
    local value = D.Decay(record[1], now - record[2], halfLife)
    return value / (value + (half or 1))
end

local function Bump(bucket, id, now, halfLife, amount)
    local record = bucket[id]
    local value = record and D.Decay(record[1], now - record[2], halfLife) or 0
    record = record or {}
    record[1], record[2] = value + (amount or 1), now
    bucket[id] = record
    return record
end

-- The situation (once per frame): resting (city or inn), instance, in a group outside, or alone in the world
local perFrame = D.Cache({ "frame" })
function memory.Situation()
    local kept = perFrame.Get()
    if not kept.situation then
        kept.situation = IsInInstance() and "instance" or IsResting() and "rest" or IsInGroup() and "group" or "world"
    end
    return kept.situation
end
local function SituationKey() return "\1" .. memory.Situation() end

-- Choices

-- Remembers a chosen entry (the search tells it); amount 1 (default), 0.5 for only looking; choosing an entry clears
-- its passing over. A choice changes only that entry, so it is told as state "rec:chosen" with the IDs
-- (memory.TakeChosen) and Reasons.lua recomputes just that entry.
local chosenSince = {} -- IDs chosen since Reasons.lua last took them
function memory.Chose(id, amount)
    local db = DB()
    if not db or not id or not Accept(id) then return end
    local chosen, now = db.chosen, time()
    for _, key in ipairs({ "", SituationKey() }) do
        chosen[key] = chosen[key] or {}
        Bump(chosen[key], id, now, HALF_LIFE, amount)
    end
    for _, kind in ipairs(KINDS) do db.skipped[kind][id] = nil end
    chosenSince[#chosenSince + 1] = id
    D.BumpState("rec:chosen")
    Acted(id)
end
function memory.TakeChosen()
    local list = chosenSince
    chosenSince = {}
    return list
end

-- how much an entry is used, 0..1 (chosen, chosen in this situation, done in the game); UsedNow() returns a
-- function(id) with buckets and time looked up once (for many candidates)
function memory.UsedNow()
    local db = DB()
    local now = time()
    local all = db and db.chosen[""]
    local here = db and db.chosen[SituationKey()]
    local did = db and db.did
    return function(id)
        if not id then return 0 end
        return USED_CHOSEN * (all and Strength(all[id], now, HALF_LIFE) or 0)
            + USED_HERE * (here and Strength(here[id], now, HALF_LIFE) or 0)
            + USED_DONE * (did and Strength(did[id], now, HALF_LIFE, DONE_FOR_HALF) or 0)
    end
end

function memory.SinceActed(id)
    local db = DB()
    if not db or not id then return nil end
    local last
    local chosen = db.chosen[""] and db.chosen[""][id]
    if chosen then last = chosen[2] end
    local done = db.did[id]
    if done and (not last or done[2] > last) then last = done[2] end
    return last and time() - last or nil
end

-- "used" taken apart (Reasons\LookedUp.lua): chosen, chosen here, done (each 0..1), then their shares in UsedNow
function memory.UsedParts(id)
    local db = DB()
    if not db or not id then return 0, 0, 0, USED_CHOSEN, USED_HERE, USED_DONE end
    local now = time()
    local all, here = db.chosen[""], db.chosen[SituationKey()]
    return all and Strength(all[id], now, HALF_LIFE) or 0,
        here and Strength(here[id], now, HALF_LIFE) or 0,
        Strength(db.did[id], now, HALF_LIFE, DONE_FOR_HALF),
        USED_CHOSEN, USED_HERE, USED_DONE
end

function memory.Recent()
    local db = DB()
    local bucket = db and db.chosen[""]
    local list = {}
    if not bucket then return list end
    for id, record in pairs(bucket) do list[#list + 1] = { id, record[2] } end
    table.sort(list, function(a, b) return a[2] > b[2] end)
    for i, item in ipairs(list) do list[i] = item[1] end
    return list
end

-- IDs chosen or done that start with a prefix ("n:"), so a caller need not ask every entry (14,000 NPCs)
function memory.IDs(prefix)
    local db = DB()
    local list, seen = {}, {}
    if not db then return list end
    for _, bucket in ipairs({ db.chosen[""] or {}, db.did }) do
        for id in pairs(bucket) do
            if not seen[id] and id:sub(1, #prefix) == prefix then
                seen[id] = true
                list[#list + 1] = id
            end
        end
    end
    return list
end

-- Done in the game

function memory.DoneSince(seconds)
    local db = DB()
    local list = {}
    if not db then return list end
    local from = time() - seconds
    for id, record in pairs(db.did) do
        if record[2] >= from then list[#list + 1] = id end
    end
    return list
end

function memory.Did(id)
    local db = DB()
    if not db or not id or not Accept(id) then return end
    Bump(db.did, id, time(), HALF_LIFE)
    Changed()
    Acted(id)
end

ns.On("UNIT_SPELLCAST_SUCCEEDED", function(_, _, _, spellID)
    if spellID and not D.Secret(spellID) and not AUTO_ATTACKS[spellID] then memory.Did("s:" .. spellID) end
end)
-- buying: items bought at this vendor with the count in the bags before; their stock is taken when the window closes
-- (what you top up to), and only for items the bags gained (the server refuses a buy without gold or room)
local boughtNow = {}
ns.On("MERCHANT_CLOSED", function()
    local db = DB()
    if not db or not next(boughtNow) then return end
    local now = time()
    for itemID, before in pairs(boughtNow) do
        local count = C_Item.GetItemCount(itemID)
        if count > before then
            local record = Bump(db.bought, itemID, now, BUY_HALF_LIFE)
            record[3] = record[3] and (record[3] + count) / 2 or count
            memory.Did("i:" .. itemID)
        end
    end
    wipe(boughtNow)
end)
hooksecurefunc("BuyMerchantItem", function(index)
    local itemID = D.ItemIDFromLink(GetMerchantItemLink(index))
    if itemID and not boughtNow[itemID] then boughtNow[itemID] = C_Item.GetItemCount(itemID) end
end)
-- items used from bags (the last of a stack is gone before this sees it, so it is not counted); the same call sells
-- at a vendor, deposits in the bank and attaches to mail or a trade
local function Shown(frame) return frame ~= nil and frame:IsShown() end
hooksecurefunc(C_Container, "UseContainerItem", function(bag, slot)
    if Shown(MerchantFrame) or Shown(BankFrame) or Shown(MailFrame) or Shown(TradeFrame) then return end
    local id = C_Container.GetContainerItemID(bag, slot)
    if id then memory.Did("i:" .. id) end
end)

-- Items bought regularly and running low on: item ID -> count left (below LOW_SHARE of the usual stock after buying)
function memory.RunningLow()
    local db = DB()
    local low = {}
    if not db then return low end
    local now = time()
    for itemID, record in pairs(db.bought) do
        if Strength(record, now, BUY_HALF_LIFE) >= REGULAR and (record[3] or 0) >= 2 then
            local count = C_Item.GetItemCount(itemID)
            if count < record[3] * LOW_SHARE then low[itemID] = count end
        end
    end
    return low
end

-- Talking to NPCs
-- opening a gossip, merchant, trainer, quest, bank, taxi or auction window counts as using the NPC

local function Talked()
    local id = DB() and D.NPCOf("npc")
    if id then memory.Did("n:" .. id) end
end
for _, event in ipairs({ "GOSSIP_SHOW", "MERCHANT_SHOW", "TRAINER_SHOW", "QUEST_GREETING", "QUEST_DETAIL",
        "QUEST_PROGRESS", "QUEST_COMPLETE", "BANKFRAME_OPENED", "TAXIMAP_OPENED", "AUCTION_HOUSE_SHOW" }) do
    ns.On(event, Talked)
end

ns.On("QUEST_TURNED_IN", function(_, questID)
    if questID and not D.Secret(questID) then memory.Did("q:" .. questID) end
end)

-- Passing over and hiding

-- a suggestion passed over (one further down was chosen); amount: counts as that many times (a "Bad suggestion" six);
-- kind "do" (default) or "know"
function memory.Skipped(id, amount, kind)
    local db = DB()
    if not db or not id then return end
    Bump(db.skipped[kind or "do"], id, time(), SKIP_HALF_LIFE, amount)
    Changed()
end

-- how tired a suggestion is of being passed over, 0..1 (three times lately: 0.5); fades within weeks
function memory.Tired(id, kind)
    local db = DB()
    return db and id and Strength(db.skipped[kind or "do"][id], time(), SKIP_HALF_LIFE, SKIPS_FOR_HALF) or 0
end

-- Never suggest an entry again, or undo; renew: text kept with it (reasons.Renew): when what it was suggested for
-- grows (a trainer with new spells), it comes back
function memory.Hide(id, hidden, renew)
    local db = DB()
    if not db or not id then return end
    if hidden == false then
        db.hidden[id] = nil
    else
        db.hidden[id] = (renew and renew ~= "") and renew or true
    end
    D.BumpState("rec:hidden")
end
function memory.HiddenAs(id)
    local db = DB()
    return db and id and db.hidden[id] or nil
end
function memory.Hidden(id)
    return memory.HiddenAs(id) ~= nil
end
function memory.AllHidden()
    local db = DB()
    return db and db.hidden or {}
end

-- Forgetting

-- whether the engine learned anything about an entry (the search offers to forget it)
function memory.Knows(id)
    local db = DB()
    if not db or not id then return false end
    for _, bucket in pairs(db.chosen) do
        if bucket[id] then return true end
    end
    return db.did[id] ~= nil or db.skipped["do"][id] ~= nil or db.skipped.know[id] ~= nil
end

-- forgets one entry: its choices, what you did with it and its passing over
-- (not hiding: that one you undo yourself)
function memory.Forget(id)
    local db = DB()
    if not db or not id then return end
    for key, bucket in pairs(db.chosen) do
        bucket[id] = nil
        if next(bucket) == nil then db.chosen[key] = nil end
    end
    db.did[id] = nil
    for _, kind in ipairs(KINDS) do db.skipped[kind][id] = nil end
    Changed()
end

function memory.Prune()
    local db = DB()
    if not db then return end
    local now = time()
    local function Prune(bucket, halfLife)
        local left = false
        for id, record in pairs(bucket) do
            if D.Decay(record[1], now - record[2], halfLife) < FORGOTTEN then bucket[id] = nil else left = true end
        end
        return left
    end
    for key, bucket in pairs(db.chosen) do
        if not Prune(bucket, HALF_LIFE) then db.chosen[key] = nil end
    end
    Prune(db.did, HALF_LIFE)
    Prune(db.bought, BUY_HALF_LIFE)
    for _, kind in ipairs(KINDS) do Prune(db.skipped[kind], SKIP_HALF_LIFE) end
end
