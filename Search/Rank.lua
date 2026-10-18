local ns = select(2, ...).search
if ns.off then return end

-- Relevance of the typed search: candidates get points, the list is sorted by them.
--   match    name fit: exact 400, start 300, a word's start 200, inside 100, category only 0.
--            Several words in any order (ns.index.Words): all starting words of the name 200,
--            of a name without other words 300, some only in category or extra words 100;
--            written together ("dead mines") as the text. Every typed word an extra word (a role
--            "innkeeper", a short name "bfd") 350. One typo away (ns.index.near) -1000, near a
--            whole word -950, the whole first word -900: below every real hit.
--   owned    +150: yours (a source defines it with "owned")
--   learned  up to +250: chosen before after the same text or one it starts with (Memory.lua);
--            a third for one letter, two thirds for two
--   used     up to +60: chosen often, whatever you typed
--   fit      up to +80: worth looking up now (engine reasons of kind "know"), best ones only
-- An exact name stays first: learning lifts nothing past it unless chosen after exactly this text.
-- The fit (80) never passes a better match (100 more).
-- Equal points: shorter name, then A-Z, then an item before the rest (herb Peacebloom before its
-- node), then lower item ID. Lists opened without text have the engine's own order.
local rank = {}
ns.rank = rank

local MATCH_EXACT, MATCH_START, MATCH_WORD, MATCH_INSIDE = 400, 300, 200, 100
local MATCH_EXTRA, NEAR, NEAR_WORD = 350, -1000, 50
local OWNED, LEARNED, USED, FIT = 150, 250, 60, 80
local FIT_FOR = 60 -- the best this many get the fit (the rest cannot reach the list)

local D = ns.data

function rank.Prepare()
    D.RefreshOwned()
end

rank.learnedNow = {} -- entries of the last search lifted by learning (marked in the list)

-- how much you use something, 0..1: the higher of the engine's and the search's own (the engine
-- does not know the categories as entries)
function rank.UsedNow()
    local own, rec = ns.memory.UsedNow(), ns.rec.UsedNow()
    return function(id) return math.max(own(id), rec(id)) end
end

-- The start page (bar opened without text, outside a category): what you would most want to look
-- up now in the switched-on categories, by the engine's "know" reasons; at most START_PER_SOURCE
-- per category, the row's right side shows the strongest reason. Marked if you use the entry.
local START_PER_SOURCE = 3

local function ActiveDomains()
    local set = {}
    for _, source in ipairs(ns.ActiveSources()) do
        if source.domain then set[source.domain] = true end
    end
    return set
end

function rank.StartPage(limit, out)
    wipe(rank.learnedNow)
    local relevant = ns.rec.Relevant(limit, START_PER_SOURCE, ActiveDomains())
    for _, item in ipairs(relevant) do
        out[#out + 1] = item.entry
        ns.rec.Shown(item.entry)
        if item.used > 0 then rank.learnedNow[item.entry] = true end
        ns.index.noted[item.entry] = ns.rec.Mark(item.entry)
    end
    return out
end

local byte, find = string.byte, string.find

local function MatchText(key, query)
    if key == query then return MATCH_EXACT end
    if key:sub(1, #query) == query then return MATCH_START end
    if find(key, " " .. query, 1, true) then return MATCH_WORD end
    if find(key, query, 1, true) then return MATCH_INSIDE end
    return 0
end

local function WholeWord(text, word)
    local at = 1
    while true do
        local from, to = find(text, word, at, true)
        if not from then return false end
        if (from == 1 or byte(text, from - 1) == 32) and (to == #text or byte(text, to + 1) == 32) then return true end
        at = from + 1
    end
end

-- the typed words (Index.lua, ns.index.Words) of this sort, with a space before each
local words, joined, spaced = nil, nil, {}
local typedAlone = {} -- { the text } when it is one word as typed (the extra words compared)

-- several words in any order: all start words of the name (the whole name if it has no other
-- words), or some sit in the category or the extra words
local function WordsMatch(entry)
    local key, WordAt = entry.key, ns.index.WordAt
    local inName = 0
    for k, word in ipairs(words) do
        if WordAt(key, word, spaced[k]) then
            inName = inName + 1
        elseif not (WordAt(ns.index.ExtraOf(entry), word, spaced[k]) or WordAt(entry.categoryKey, word, spaced[k])) then
            return 0
        end
    end
    if inName < #words then return inName > 0 and MATCH_INSIDE or 0 end
    local count, space = 1, find(key, " ", 1, true)
    while space do
        count = count + 1
        space = find(key, " ", space + 1, true)
    end
    return count == #words and MATCH_START or MATCH_WORD
end

-- every typed word is one of the entry's extra words (a role, a short name)
local function ExtraMatch(entry, query)
    local extra = ns.index.ExtraOf(entry)
    if not extra then return 0 end
    for _, word in ipairs(words or typedAlone) do
        if not WholeWord(extra, word) then return 0 end
    end
    return MATCH_EXTRA
end

local function Match(entry, query)
    local score = MatchText(entry.key, query)
    if score == MATCH_EXACT then return score end
    if joined then score = math.max(score, MatchText(entry.key, joined)) end
    if words then score = math.max(score, WordsMatch(entry)) end
    return math.max(score, ExtraMatch(entry, query))
end

local function Owned(entry)
    local owned = entry.source and entry.source.owned
    if owned == true then return true end
    return type(owned) == "function" and owned(entry) or false
end

local points = {}
local function Better(a, b)
    local pa, pb = points[a], points[b]
    if pa ~= pb then return pa > pb end
    if #a.key ~= #b.key then return #a.key < #b.key end
    if a.key ~= b.key then return a.key < b.key end
    -- same name: an item first (the herb, not its node as an NPC), then the lower ID
    return (a.itemID or math.huge) < (b.itemID or math.huge)
end

local best = {}
local matched, held = {}, {} -- entry -> its match; entry -> the points learning may not lift it past
function rank.Sort(list, text)
    local query = ns.SearchKey(text)
    local memory = ns.memory
    words, joined = ns.index.Words(query)
    typedAlone[1] = query
    wipe(spaced)
    for k, word in ipairs(words or typedAlone) do spaced[k] = " " .. word end
    -- without text (filters only) nothing is learned: only "used" counts
    local Learned = query ~= "" and memory.LearnedFor(text) or function() return 0, false end
    local characters = 0
    for _ in ns.EachChar(query) do characters = characters + 1 end
    local learnedScale = math.min(1, characters / 3)
    local Used = rank.UsedNow()
    local near = ns.index.near
    wipe(points)
    wipe(matched)
    wipe(held)
    wipe(rank.learnedNow)
    local exactThere = false
    for _, entry in ipairs(list) do
        local match = query ~= "" and Match(entry, query) or 0
        matched[entry] = match
        if match == MATCH_EXACT then exactThere = true end
    end
    for _, entry in ipairs(list) do
        local score = matched[entry]
        if near[entry] then score = score + NEAR + NEAR_WORD * (near[entry] - 1) end
        if Owned(entry) then score = score + OWNED end
        local id = ns.EntryID(entry)
        if id then
            score = score + USED * Used(id)
            local learned, exactText = Learned(id)
            if learned > 0 then
                rank.learnedNow[entry] = true
                local lift = LEARNED * learned * learnedScale
                -- an exact name stays first, unless this was chosen after exactly this text
                if exactThere and not exactText and matched[entry] < MATCH_EXACT then
                    held[entry] = math.max(MATCH_EXACT - 1, score)
                    lift = math.min(lift, math.max(0, held[entry] - score))
                end
                score = score + lift
            end
        end
        points[entry] = score
    end
    table.sort(list, Better)
    -- the fit, for the best ones only (reasons cost more than a name match; lower entries
    -- cannot climb into the list by 80 points)
    wipe(best)
    for i = 1, math.min(#list, FIT_FOR) do
        local entry = list[i]
        local fit = math.min(ns.rec.Fit(entry), FIT)
        -- held: still not past the exact name
        points[entry] = held[entry] and math.min(points[entry] + fit, held[entry]) or points[entry] + fit
        best[i] = entry
    end
    table.sort(best, Better)
    for i, entry in ipairs(best) do list[i] = entry end
end
