local _, D = ...
local ns = D.engine

-- What is most relevant now across Data's domains (the search's start page shows it; Learning.lua watches whether
-- you follow it).
--   candidates  what each domain puts forward (CANDIDATES: what you have, what has a reason, what you use) and what you
--               chose lately
--   score       the weighed fit (Reasons.lua); only with a reason. How much you use it only breaks a tie.
--   mix         at most perDomain per domain, best first; one NPC per errand (reasons.Errand); in the list of all, one row
--               per errand also where an item and the row it is got at both stand (Merge: an upgrade and the quest of
--               your log rewarding it, something to restock and its vendor)
-- Hidden ones ("Don't suggest") and ones another row stands for (a spell: its trainer) stay out.

local reasons, memory = ns.reasons, ns.memory

-- Use is only a tie breaker (habit is no recommendation; counted as a reason it filled the start page).
local RECENT = 40 -- recent choices looked at

-- Candidates per domain: add(entry) for each. Fit is reasons.Fit.
local CANDIDATES = {
    -- what you carry and wear, items near your level with a reason, and what you buy regularly and have none of left
    -- (arrows, reagents)
    items = function(add, Fit)
        D.RefreshOwned()
        local owned = D.ownedItems
        for id in pairs(owned) do add(D.ItemByID(id)) end -- items not in the data: left out
        for _, entry in ipairs(D.ItemsNearLevel(UnitLevel("player"))) do
            if not owned[entry.itemID] and Fit(entry) > 0 then add(entry) end
        end
        for itemID in pairs(memory.RunningLow()) do
            local entry = D.ItemByID(itemID)
            if entry and not owned[itemID] and not entry.startsQuest and Fit(entry) > 0 then add(entry) end
        end
    end,
    -- the useful NPCs of your zone and the ones you use, anywhere (not a pass over all 14,000 NPCs)
    npcs = function(add, Fit)
        local zone = D.PlayerZone(true)
        for _, entry in ipairs(zone and D.NPCsInZone(zone) or {}) do
            if Fit(entry) > 0 then add(entry) end
        end
        for _, id in ipairs(memory.IDs("n:")) do add(D.EntryByID(id)) end
    end,
    -- the spells a trainer teaches you now, and yours
    spells = function(add, Fit)
        for _, entry in ipairs(D.Entries("spells")) do
            if not entry.hidden or Fit(entry) > 0 then add(entry) end
        end
    end,
    professions = function(add)
        for _, entry in ipairs(D.Entries("professions")) do
            if not entry.hidden then add(entry) end
        end
    end,
    dungeons = function(add)
        for _, entry in ipairs(D.Entries("dungeons")) do add(entry) end
    end,
    quests = function(add)
        D.EachLoggedQuest(function(questID) add(D.EntryByID("q:" .. questID)) end)
    end,
    zones = function(add, Fit)
        for _, entry in ipairs(D.Entries("zones")) do
            if Fit(entry) > 0 then add(entry) end
        end
    end,
}

-- every candidate worth something now: list of { entry, score, fit, used }, best first; domains: set of domain keys,
-- nil: all; kind "do" (default) or "know". Knowing takes the candidates its reasons bring and has no use filler:
-- lookups are a reason of their own there.
local function Scored(domains, kind)
    kind = kind or "do"
    reasons.Refresh()
    local Used = memory.UsedNow()
    local seen, candidates = {}, {}
    local function Add(entry)
        if entry and (not domains or domains[entry.domain]) and not seen[entry] then
            seen[entry] = true
            candidates[#candidates + 1] = entry
        end
    end
    if kind == "do" then
        for i, id in ipairs(memory.Recent()) do
            if i > RECENT then break end
            Add(D.EntryByID(id))
        end
        for _, key in ipairs(D.DomainKeys()) do
            local get = CANDIDATES[key]
            if get and (not domains or domains[key]) and D.Built(key) then get(Add, reasons.Fit) end
        end
    end
    -- what the reasons bring themselves (knowing: what you looted, your target; a "do" reason may too)
    reasons.EachCandidates(kind, Add)
    local scored = {}
    for _, entry in ipairs(candidates) do
        local id = D.EntryID(entry)
        if id and not reasons.Hidden(entry, id) then
            local fit = reasons.Weighed(entry, id, kind)
            -- a hidden entry (not learned yet) only with a reason (a spell to learn); none another row stands for
            if (not entry.hidden or fit > 0) and not reasons.Covered(entry, kind) then
                -- only with a reason; use only breaks a tie
                if fit > 0 then scored[#scored + 1] = { entry = entry, id = id, score = fit, fit = fit, used = Used(id) } end
            end
        end
    end
    table.sort(scored, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        if a.used ~= b.used then return a.used > b.used end
        return a.entry.key < b.entry.key
    end)
    if kind ~= "do" then return scored end
    -- one row per errand group (reasons.Group: a quest's rewards), the best;
    -- it carries the others (the window's tooltip names them)
    local leaders, kept = {}, {}
    for _, item in ipairs(scored) do
        local group = reasons.Group(item.entry)
        local leader = group and leaders[group]
        if leader then
            leader.carries = leader.carries or {}
            leader.carries[#leader.carries + 1] = item.entry
        else
            if group then leaders[group] = item end
            kept[#kept + 1] = item
        end
    end
    return kept
end

-- One row per errand where an entry and the row it is got at both stand in a scored list (doing): the entry goes, the
-- other row carries it (its carries) and takes the better score. Returns a new list of new items; the scored list stays
-- as it is (the topics' lists are mixed from it).
local function Merge(scored)
    local byID, hosts = {}, nil
    for _, item in ipairs(scored) do byID[item.id] = item end
    for _, item in ipairs(scored) do
        local host = byID[reasons.Via(item.entry) or false]
        if host and host ~= item then
            hosts = hosts or {}
            hosts[item] = host
        end
    end
    if not hosts then return scored end
    local merged, copies = {}, {}
    local function Copy(item)
        local copy = copies[item]
        if not copy then
            copy = {}
            for key, value in pairs(item) do copy[key] = value end
            copy.carries = { unpack(item.carries or {}) }
            copies[item] = copy
        end
        return copy
    end
    for _, item in ipairs(scored) do
        local host = hosts[item]
        if host then
            host = Copy(host)
            table.insert(host.carries, item.entry)
            for _, carried in ipairs(item.carries or {}) do table.insert(host.carries, carried) end
            host.score = math.max(host.score, item.score)
        else
            merged[#merged + 1] = item
        end
    end
    for i, item in ipairs(merged) do merged[i] = copies[item] or item end
    table.sort(merged, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        if a.used ~= b.used then return a.used > b.used end
        return a.entry.key < b.entry.key
    end)
    return merged
end

-- the best of a scored list: at most limit, perDomain per domain, one NPC
-- per errand; only those accept(item) takes, if given; merged: one row
-- where an entry and the row it is got at both stand (Merge)
local function Mix(scored, limit, perDomain, accept, kind, merged)
    local chosen, counts, errands = {}, {}, {}
    if merged then scored = Merge(scored) end
    for _, item in ipairs(scored) do
        if #chosen >= limit then break end
        local domain = item.entry.domain
        local errand = item.entry.npcID and item.fit > 0 and reasons.Errand(item.entry, kind)
        if (counts[domain] or 0) < perDomain and not (errand and errands[errand]) and (not accept or accept(item)) then
            counts[domain] = (counts[domain] or 0) + 1
            chosen[#chosen + 1] = item
            if errand then errands[errand] = true end
        end
    end
    return chosen
end

-- The most relevant entries now: list of { entry, score, fit, used }, best first, at most perDomain per domain; domains:
-- a set of domain keys (a host's switched-on categories), nil: all; kind "do" (default) or "know" (the search's start page).
-- Kept while the reasons' results are (reasons.generation) for the same question, so a host asking with ns.Refresh gets
-- its list again without recomputing. Do not change the list. A few questions are kept side by side (KEEP): the start
-- page and the NPC tab ask with other limits and domains, and one kept answer each threw the other's away.
local KEEP = 4
local last = {} -- kind -> list of { list, generation, limit, perDomain, domains (a copy) }, oldest first
local function SameDomains(a, b)
    if a == nil or b == nil then return a == b end
    for key in pairs(a) do if not b[key] then return false end end
    for key, on in pairs(b) do if on and not a[key] then return false end end
    return true
end
function ns.Relevant(limit, perDomain, domains, kind)
    kind = kind or "do"
    reasons.Refresh()
    local kept = last[kind]
    if not kept then
        kept = {}
        last[kind] = kept
    end
    local generation = reasons.generation
    for i = #kept, 1, -1 do
        local k = kept[i]
        if k[2] ~= generation then
            table.remove(kept, i)
        elseif k[3] == limit and k[4] == perDomain and SameDomains(k[5], domains) then
            return k[1]
        end
    end
    local list = Mix(Scored(domains, kind), limit, perDomain, nil, kind, kind == "do")
    local copy
    if domains then
        copy = {}
        for key, on in pairs(domains) do if on then copy[key] = true end end
    end
    if #kept >= KEEP then table.remove(kept, 1) end
    kept[#kept + 1] = { list, generation, limit, perDomain, copy }
    return list
end

-- The same per topic (a reason's topic; the tabs of Window.lua): { all = list, class = list, gear = list, ... }. "all" is
-- Relevant(limit, perDomain); a topic holds the entries with a reason of it, perDomain not counted. Only "all" merges an
-- entry into the row it is got at (the Gear tab keeps the upgrade a quest rewards). One scoring for all; kept while the
-- reasons' results are (reasons.generation). Do not change the lists.
local byTopic, byTopicFor = nil, nil -- the lists; generation, limit, perDomain they were made for
function ns.RelevantByTopic(limit, perDomain)
    reasons.Refresh()
    local key = byTopicFor
    if byTopic and key[1] == reasons.generation and key[2] == limit and key[3] == perDomain then return byTopic end
    local scored, topics = Scored(), {}
    for _, item in ipairs(scored) do
        item.topics = reasons.Topics(item.entry)
        for topic in pairs(item.topics) do topics[topic] = true end
    end
    local lists = { all = Mix(scored, limit, perDomain, nil, "do", true) }
    for topic in pairs(topics) do
        lists[topic] = Mix(scored, limit, limit, function(item) return item.topics[topic] end)
    end
    byTopic, byTopicFor = lists, { reasons.generation, limit, perDomain }
    return lists
end
