local ns = select(2, ...).search

-- The search index of every source, and the search.
-- Search runs on every keystroke. Measured with 100,000 entries: scanning all took up to 26 ms per key; the tiers
-- below take 0.035 ms for names starting with the query, under 2 ms worst case. Stops at SEARCH_LIMIT found:
-- 1. name starts with the query (entries sorted by name, binary search); 2. a word of the name starts with it
-- (sorted list of word starts); 3. name contains it (only entries holding the query's rarest character pair);
-- 4. category contains it, 4b. an extra word (Data's entry.searchWords: an NPC's role, a dungeon's short
-- name) starts with it; 3b. several words (or a plural, a leading "the") in any order, then written together
-- ("dead mines" -> deadmines); 5. hardly anything found: names one typo away (NearFrom).
-- A source's index: entries (Data's list of its domain, sorted by key = name as searched), wordStarts (every
-- word start after the first word as entry position * 256 + start byte, sorted by the text from there on),
-- pairs (character pair -> packed positions of the entries holding it, in name order, see PackPositions),
-- categories (lower-case category -> packed positions), extraWords (distinct searchWords, sorted) with
-- extraOf (word -> packed positions) and extraText (entry -> searchWords), and the domain's maps byID (item
-- ID -> entry), byNPC (NPC ID -> entry), byEntryID (ns.EntryID -> entry; not for items and NPCs).
-- The tiers only gather candidates (up to SEARCH_LIMIT per source, plus a source's pool and what you chose
-- before for this text); Rank.lua scores and sorts them. Built after Data built the domain: small sources in
-- one go behind the loading screen, big ones in Data's background builder.

local D = ns.data
local EachChar, SearchKey = ns.EachChar, ns.SearchKey
local SEARCH_LIMIT = ns.SEARCH_LIMIT
local byte, sub, find = string.byte, string.sub, string.find
ns.index = {}

-- Packs entry positions (up to 16,777,215) into a string, three bytes each (a list of numbers took 16 bytes per position)
local bytes, chunks = {}, {}
local function PackPositions(list)
    wipe(chunks)
    local n = 0
    for _, position in ipairs(list) do
        bytes[n + 1] = math.floor(position / 65536)
        bytes[n + 2] = math.floor(position / 256) % 256
        bytes[n + 3] = position % 256
        n = n + 3
        if n >= 240 then
            chunks[#chunks + 1] = string.char(unpack(bytes, 1, n))
            n = 0
        end
    end
    if n > 0 then chunks[#chunks + 1] = string.char(unpack(bytes, 1, n)) end
    return table.concat(chunks)
end

local function Note(map, key, entry)
    local list = map[key]
    if not list then
        list = {}
        map[key] = list
    end
    list[#list + 1] = entry
end

-- the index's ID maps are Data's (D.ItemByID, D.NPCByID, D.EntryByID), filtered to the source's own domain
local function MapOf(lookup, domain)
    return setmetatable({}, { __index = function(_, id)
        local entry = lookup(id)
        if entry and entry.domain == domain then return entry end
    end })
end

-- Builds a source's index from its domain's list (sorted by key there). Pause() yields to the next frame in the background.
local function BuildSource(source, Pause)
    if not D.Built(source.domain) then return end -- Data has not built it yet
    local entries = D.Entries(source.domain)
    local wordStarts, wordTexts, pairsOf, categories, seenPairs = {}, {}, {}, {}, {}
    local extraWords, extraOf, extraText = {}, {}, {}
    for i, entry in ipairs(entries) do
        local key = entry.key
        -- word starts after the first word (the texts only for sorting)
        local space = find(key, " ", 1, true)
        while space do
            if space < #key and space < 255 then
                local n = #wordStarts + 1
                wordStarts[n], wordTexts[n] = i * 256 + space + 1, key:sub(space + 1)
            end
            space = find(key, " ", space + 1, true)
        end
        -- character pairs, each once per entry, walked byte by byte (a gmatch and a string per pair were most of the build's garbage)
        wipe(seenPairs)
        local lastFrom, lastTo
        local at, length = 1, #key
        while at <= length do
            local b = byte(key, at)
            if b < 128 or (b >= 194 and b <= 244) then
                local to = at
                while to < length do
                    local c = byte(key, to + 1)
                    if c < 128 or c > 191 then break end
                    to = to + 1
                end
                if lastFrom then
                    local pair = lastTo + 1 == at and sub(key, lastFrom, to)
                        or sub(key, lastFrom, lastTo) .. sub(key, at, to)
                    if not seenPairs[pair] then
                        seenPairs[pair] = true
                        Note(pairsOf, pair, i)
                    end
                end
                lastFrom, lastTo = at, to
                at = to + 1
            else
                at = at + 1
            end
        end
        local categoryKey = entry.categoryKey
        if categoryKey and categoryKey ~= "" then Note(categories, categoryKey, i) end
        -- extra words Data gives an entry (an NPC's role "flight master", a dungeon's "bfd"), each like a category
        local searchWords = entry.searchWords
        if searchWords and searchWords ~= "" then
            extraText[entry] = searchWords -- Data recomputes the field on each read
            for word in searchWords:gmatch("%S+") do
                local list = extraOf[word]
                if not list then extraWords[#extraWords + 1] = word end
                if not list or list[#list] ~= i then Note(extraOf, word, i) end
            end
        end
        if i % 32 == 0 then Pause() end
    end
    D.SortSideBySide(wordTexts, wordStarts, Pause)
    wordTexts = nil
    table.sort(extraWords)
    local count = 0
    for _, map in ipairs({ pairsOf, categories, extraOf }) do
        for key, positions in pairs(map) do
            map[key] = PackPositions(positions)
            count = count + 1
            if count % 16 == 0 then Pause() end
        end
    end
    source.maps = source.maps or { MapOf(D.ItemByID, source.domain), MapOf(D.NPCByID, source.domain),
        MapOf(D.EntryByID, source.domain) }
    source.index = { entries = entries, wordStarts = wordStarts, pairs = pairsOf, categories = categories,
        extraWords = extraWords, extraOf = extraOf, extraText = extraText,
        byID = source.maps[1], byNPC = source.maps[2], byEntryID = source.maps[3] }
end
ns.index.Build = BuildSource

-- Background building in Data's builder (one budget per frame for every addon), after its domain.
local function NoPause() end
local function RefreshOpen()
    local S = ns.state
    if ns.ui.bar:IsShown() and not S.closingAt and not S.detail and not S.linked then
        ns.view.Refresh({ marked = S.marked, top = S.top })
    end
end
local function Big(source) return D.DomainInBackground(source.domain) end

-- builds a source in the background; asked again while waiting, it is built once
function ns.index.Rebuild(source)
    D.Background("index:" .. source.key, function(Pause)
        BuildSource(source, Pause)
        if ns.db and ns.db["source_" .. source.key] == false then source.index = nil end
        RefreshOpen()
    end)
end

-- Builds what is missing of the switched-on sources: small ones at once, big ones in the
-- background. Until they are done, the search goes without them.
function ns.index.BuildMissing()
    local active = ns.ActiveSources()
    for _, source in ipairs(active) do D.Need(source.domain, "PylosCompass", true) end
    D.BuildMissing() -- small domains at once (their index follows in OnBuilt below)
    for _, source in ipairs(active) do
        if not source.index and not D.Waiting("index:" .. source.key) then
            if Big(source) then
                ns.index.Rebuild(source) -- queued after its domain
            elseif D.Built(source.domain) then
                BuildSource(source, NoPause)
            end
        end
    end
end

D.OnBuilt(function(key)
    for _, source in ipairs(ns.ActiveSources()) do
        if source.domain == key then
            if Big(source) then
                ns.index.Rebuild(source)
            else
                BuildSource(source, NoPause)
                RefreshOpen()
            end
        end
    end
end)

-- a source switched off gives its index free (and Data its domain's list, if no other addon needs it)
function ns.index.Drop(source)
    source.index = nil
    D.Need(source.domain, "PylosCompass", false)
end
-- Search

local best = {}       -- the shown results, best first
local gathered = {}   -- candidates, before ranking
local chosen = {}     -- entry -> true for those gathered
local looks = {}      -- the IDs of the shown entries
local looksByKey = {} -- key -> the first shown entry of that name
local looksMore = {}  -- key -> more shown entries of that name that look different

-- do two entries of the same name look the same in the list (icon, category)
local function LookAlike(a, b)
    local ia, ib = a.icon, b.icon
    if ia ~= ib and (type(ia) == type(ib) or tostring(ia) ~= tostring(ib)) then return false end
    return (a.categoryKey or "") == (b.categoryKey or "")
end
-- true if a shown entry looks like this one; else it counts as shown
local function SameLook(entry)
    local key = entry.key
    local first = looksByKey[key]
    if not first then
        looksByKey[key] = entry
        return false
    end
    if LookAlike(first, entry) then return true end
    local more = looksMore[key]
    if more then
        for _, other in ipairs(more) do
            if LookAlike(other, entry) then return true end
        end
    else
        more = {}
        looksMore[key] = more
    end
    more[#more + 1] = entry
    return false
end
local BROWSE_LIMIT = 400 -- limit for lists browsed without text (a zone's NPCs go up to 367)
ns.index.suggested = {} -- entry -> true: a suggestion of the last search (below its heading, dimmed)
ns.index.noted = {}     -- entry -> the text a browse gave an entry, or its strongest reason's (below on the right of its row)
ns.index.browsed = false      -- the last list was a category's own, opened without text (source.browse)
ns.index.browseHint = nil     -- what the browse returned: the text an empty list shows instead of the source's emptyHint
-- headings in a browsed list: rows that only label the ones below (UI\List.lua
-- draws them as a narrow gap; they cannot be marked), one per label
local headings = {}   -- label -> its heading row
local headingOf = {}  -- entry -> the label it was taken under
local function Heading(label)
    headings[label] = headings[label] or { header = true, name = label, key = "" }
    return headings[label]
end

local passes -- the set filters' test for this search (nil: no filters)
local reveal -- a set filter asks for hidden entries (spells not learned yet)
local typed  -- text is typed (hidden entries a source calls findable show)

-- takes a candidate once if it passes the filters; hidden entries only when a filter asks for them,
-- or text is typed and their source lets them be found (findable: recipes to come)
local function Gather(entry)
    if chosen[entry] then return false end
    chosen[entry] = true
    if entry.source and entry.source.leaveOut and entry.source.leaveOut(entry) then return false end
    if entry.hidden and not reveal
            and not (typed and entry.source.findable and entry.source.findable(entry)) then
        return false
    end
    if passes and not passes(entry) then return false end
    gathered[#gathered + 1] = entry
    return true
end

-- first position in a list sorted by key whose key is not below the query;
-- keyOf(item) -> the key (nil: item.key)
local function LowerBound(list, query, keyOf)
    local low, high = 1, #list + 1
    while low < high do
        local middle = math.floor((low + high) / 2)
        local item = list[middle]
        local key = keyOf and keyOf(item) or item.key
        if key < query then low = middle + 1 else high = middle end
    end
    return low
end

local function WordStart(entries, start)
    return entries[math.floor(start / 256)], start % 256
end

-- the text from a word start on (LowerBound's keyOf); reads the entries of the index searched now to avoid a closure per search
local startEntries
local function WordStartKey(start)
    local entry, at = WordStart(startEntries, start)
    return entry.key:sub(at)
end

-- Tier 4 went through every category of every source on each keystroke (NPCs alone have ~1,500 titles). Typing only adds
-- to the text and a category holding the longer text holds the shorter one, so the categories that held the last query are
-- all that can hold the next. index -> { query, matching keys }, weak keys; hits: the cache to use (words in any order keep their own).
local categoryHits = setmetatable({}, { __mode = "k" })
local wordCategoryHits = setmetatable({}, { __mode = "k" })
local function MatchingCategories(index, query, hits)
    hits = hits or categoryHits
    local last = hits[index]
    local from
    if last and query:find(last.query, 1, true) then
        if last.query == query then return last.keys end
        from = last.keys
    end
    local keys = {}
    if from then
        for _, categoryKey in ipairs(from) do
            if categoryKey:find(query, 1, true) then keys[#keys + 1] = categoryKey end
        end
    else
        for categoryKey in pairs(index.categories) do
            if categoryKey:find(query, 1, true) then keys[#keys + 1] = categoryKey end
        end
    end
    hits[index] = { query = query, keys = keys }
    return keys
end

-- Filters set and nothing typed: the tiers walk the index in name order until SEARCH_LIMIT pass. A filter few entries pass
-- (Legendary, Rare NPCs) scanned all 19,224 items or 12,231 NPCs on every refresh (12 ms). Filters whose test reads only
-- the entry's own facts say static = true; their first passing positions are kept per index and set of filters.
local staticFirst = setmetatable({}, { __mode = "k" }) -- index -> filter set key -> positions
local staticKey -- the key of the filters set now if all are static, else nil

-- the positions of the entries of an index whose name holds the query's
-- rarest character pair, packed (see PackPositions); "" if a pair is in no
-- name, nil for a single character (all entries)
local function Candidates(index, query)
    local source, last
    for char in EachChar(query) do
        if last then
            local bucket = index.pairs[last .. char]
            if not bucket then return "" end
            if not source or #bucket < #source then source = bucket end
        end
        last = char
    end
    return source
end

-- the tiers for one index; each returns true when the index gave SEARCH_LIMIT candidates
local taken -- candidates the index gave so far (Take)
local function Take(entry)
    if Gather(entry) then taken = taken + 1 end
    return taken >= SEARCH_LIMIT
end

local function At(entries, packed, p)
    local a, b, c = byte(packed, p, p + 2)
    return entries[a * 65536 + b * 256 + c]
end

local function Itself(text) return text end

-- 1. the name starts with the text
local function ByStart(index, query)
    local entries, length = index.entries, #query
    local i = LowerBound(entries, query)
    while entries[i] and sub(entries[i].key, 1, length) == query do
        if Take(entries[i]) then return true end
        i = i + 1
    end
    return false
end

-- 2. a word in the name starts with it
local function ByWordStart(index, query)
    local entries, starts, length = index.entries, index.wordStarts, #query
    startEntries = entries
    local i = LowerBound(starts, query, WordStartKey)
    while starts[i] do
        local entry, at = WordStart(entries, starts[i])
        if sub(entry.key, at, at + length - 1) ~= query then break end
        if Take(entry) then return true end
        i = i + 1
    end
    return false
end

-- 3. the name contains it (the entries holding its rarest pair)
local function ByInside(index, query)
    local entries = index.entries
    local positions = Candidates(index, query)
    for p = 1, positions and #positions or #entries * 3, 3 do
        local entry = positions and At(entries, positions, p) or entries[(p + 2) / 3]
        if find(entry.key, query, 1, true) and Take(entry) then return true end
    end
    return false
end

-- 4. the category contains it
local function ByCategory(index, query)
    local entries = index.entries
    for _, categoryKey in ipairs(MatchingCategories(index, query)) do
        local members = index.categories[categoryKey]
        for p = 1, #members, 3 do
            if Take(At(entries, members, p)) then return true end
        end
    end
    return false
end

-- 4b. an extra word (entry.searchWords: "flight master", "bfd") starts with it
local function ByExtra(index, query)
    local extra, entries = index.extraWords, index.entries
    local i = LowerBound(extra, query, Itself)
    while extra[i] and sub(extra[i], 1, #query) == query do
        local members = index.extraOf[extra[i]]
        for p = 1, #members, 3 do
            if Take(At(entries, members, p)) then return true end
        end
        i = i + 1
    end
    return false
end

-- The words of a typed text, for words in any order ("ore copper"): a plural or possessive loses its
-- "s" ("copper bars", "hoggers"; "hogger's" has lost its apostrophe already), a leading "the" goes.
-- Returns the words (nil if they say nothing the text does not: one word, unchanged) and the words
-- written together (nil for one word: "dead mines" is "deadmines").
local wordsFor, wordList, wordsJoined = nil, nil, nil
local wordSpaced = {} -- " " .. each word (found after a space)
function ns.index.Words(query)
    if query == wordsFor then return wordList, wordsJoined end
    local list, raw, joined = {}, 0, {}
    for word in query:gmatch("%S+") do
        raw = raw + 1
        if not (raw == 1 and word == "the" and query ~= "the") then
            joined[#joined + 1] = word
            if #word >= 4 and sub(word, -1) == "s" then word = sub(word, 1, -2) end
            list[#list + 1] = word
        end
    end
    wordsFor = query
    wordList = (raw > 1 or list[1] ~= query) and #list > 0 and list or nil
    wordsJoined = #joined > 1 and table.concat(joined) or nil
    wipe(wordSpaced)
    for k, word in ipairs(list) do wordSpaced[k] = " " .. word end
    return wordList, wordsJoined
end

-- does a word of the text start with word (spaced: " " .. word)
local function WordAt(text, word, spaced)
    return text ~= nil and (sub(text, 1, #word) == word or find(text, spaced, 1, true) ~= nil)
end
ns.index.WordAt = WordAt

-- an entry's extra words (its searchWords as its index keeps them), or nil
local function ExtraOf(entry)
    local index = entry.source and entry.source.index
    return index and index.extraText and index.extraText[entry]
end
ns.index.ExtraOf = ExtraOf

local function AllWords(entry)
    for k = 1, #wordList do
        local word, spaced = wordList[k], wordSpaced[k]
        if not (WordAt(entry.key, word, spaced) or WordAt(ExtraOf(entry), word, spaced)
                or WordAt(entry.categoryKey, word, spaced)) then
            return false
        end
    end
    return true
end

-- 3b. every word starts a word of the name, category or extra words, in any order; looked for among the entries where the
-- longest word starts the name or a word in it, is in the category or starts an extra word
local function Fits(entry) return not chosen[entry] and AllWords(entry) and Take(entry) end
local function ByWords(index)
    local entries, longest = index.entries, wordList[1]
    for k = 2, #wordList do
        if #wordList[k] > #longest then longest = wordList[k] end
    end
    local length = #longest
    local i = LowerBound(entries, longest)
    while entries[i] and sub(entries[i].key, 1, length) == longest do
        if Fits(entries[i]) then return true end
        i = i + 1
    end
    local starts = index.wordStarts
    startEntries = entries
    i = LowerBound(starts, longest, WordStartKey)
    while starts[i] do
        local entry, at = WordStart(entries, starts[i])
        if sub(entry.key, at, at + length - 1) ~= longest then break end
        if Fits(entry) then return true end
        i = i + 1
    end
    for _, categoryKey in ipairs(MatchingCategories(index, longest, wordCategoryHits)) do
        local members = index.categories[categoryKey]
        for p = 1, #members, 3 do
            if Fits(At(entries, members, p)) then return true end
        end
    end
    local extra = index.extraWords
    local i = LowerBound(extra, longest, Itself)
    while extra[i] and sub(extra[i], 1, #longest) == longest do
        local members = index.extraOf[extra[i]]
        for p = 1, #members, 3 do
            if Fits(At(entries, members, p)) then return true end
        end
        i = i + 1
    end
    return false
end

local function GatherFrom(index, query)
    local length = #query
    taken = 0
    local entries = index.entries
    -- no text, only static filters: reuse the positions found last time (see staticFirst)
    local byFilters = length == 0 and staticKey and staticFirst[index]
    local known = byFilters and byFilters[staticKey]
    if known then
        for _, position in ipairs(known) do Take(entries[position]) end
        return
    end
    -- 1. the name starts with it (no text: the positions passing are kept)
    local i = LowerBound(entries, query)
    local found = length == 0 and staticKey and {} or nil -- the positions to keep
    while entries[i] and entries[i].key:sub(1, length) == query do
        local before = taken
        local full = Take(entries[i])
        if found and taken > before then found[#found + 1] = i end
        if full then break end
        i = i + 1
    end
    if found then
        if not byFilters then
            byFilters = {}
            staticFirst[index] = byFilters
        end
        byFilters[staticKey] = found
    end
    -- no text (filters only): every entry started with it, once is enough
    if length == 0 or taken >= SEARCH_LIMIT then return end
    if ByWordStart(index, query) then return end
    -- a single character: only names and words starting with it (looking inside every name was too slow)
    local characters = 0
    for _ in EachChar(query) do characters = characters + 1 end
    if characters == 1 then return end
    if ByExtra(index, query) or ByInside(index, query) or ByCategory(index, query) then return end
    local words, joined = ns.index.Words(query)
    if words and ByWords(index) then return end
    if joined and not ByStart(index, joined) and not ByWordStart(index, joined) then ByInside(index, joined) end
end

-- Near names (a typo: "linnen", "thorim", "hoger") when the tiers found fewer than NEAR_BELOW: names with a word start
-- from which the text is one edit away (letter wrong, missing, extra, or two swapped), at most NEAR_LIMIT per category,
-- ranked below every real hit (ns.index.near, Rank.lua); a near whole word before a near word start ("thorim": Thorium
-- before Thor'mok). Candidates: the text's pairs that share no letter (li nn en for "linnen") lose at most one to a
-- single edit, so a near name holds one of the two rarest.
local NEAR_BELOW, NEAR_MIN, NEAR_LIMIT = 3, 4, 12 -- results, characters of the text, near names per category
ns.index.near = {} -- entry -> found only as a near name: 3 first word, 2 a word, 1 a word start (Near)

-- query (n bytes) from byte q on is the same as key from byte s + k on:
-- the byte of key after it, else nil
local function RestSame(key, s, query, n, k, q)
    for d = 0, n - q do
        if byte(key, s + k + d) ~= byte(query, q + d) then return nil end
    end
    return s + k + n - q + 1
end
-- how near: 2 if the near part of key ends a word (after: the byte after
-- it), 1 if more of the word follows, 0 if it is not near
local function Ends(key, after)
    if not after then return 0 end
    local next = byte(key, after)
    return (not next or next == 32) and 2 or 1
end
-- is query one edit away from the start of key at byte s (the rest of key
-- may follow): 2, 1 or 0 as Ends
local function NearAt(key, s, query, n)
    local i = 0
    while i < n and byte(key, s + i) == byte(query, i + 1) do i = i + 1 end
    if i == n then return Ends(key, s + n) end
    -- first difference after i bytes: a wrong letter, one missing in the text, one too many, two swapped
    -- (each tried: "thorim" is "thoriu" with a wrong letter, but "thorium" with one missing)
    local near = math.max(Ends(key, RestSame(key, s, query, n, i + 1, i + 2)),
        Ends(key, RestSame(key, s, query, n, i + 1, i + 1)), Ends(key, RestSame(key, s, query, n, i, i + 2)))
    if near < 2 and byte(key, s + i) == byte(query, i + 2) and byte(key, s + i + 1) == byte(query, i + 1) then
        near = math.max(near, Ends(key, RestSame(key, s, query, n, i + 2, i + 3)))
    end
    return near
end
-- 3 if query is near the whole first word of key, 2 near a later one, 1 near a word's start, else nil.
-- A word's first letter counts as typed right ("hoger": Hogger, not Roger); checking more cost 4 ms a key.
local function Near(key, query, n)
    local s, near, first = 1, nil, byte(query, 1)
    while s do
        local at = byte(key, s) == first and NearAt(key, s, query, n) or 0
        if at == 2 then return s == 1 and 3 or 2 end
        if at == 1 then near = 1 end
        s = find(key, " ", s, true)
        if s then s = s + 1 end
    end
    return near
end
-- All names near a text, kept per index for the next keys: typing on only removes names, so while
-- the text starts with the kept one, its names are all there is to look at (scanning the pairs'
-- buckets took up to 4 ms a key). Index -> { query, names in name order }; weak keys.
local nearKept = setmetatable({}, { __mode = "k" })
local seen = {} -- (an entry in both buckets: looked at once)
local function NearNames(index, query)
    local kept = nearKept[index]
    if kept and sub(query, 1, #kept.query) == kept.query then return kept.names end
    local entries, pairsOf, n = index.entries, index.pairs, #query
    -- the pairs from the first letter on or from the second (both share no
    -- letter), whichever two rarest hold fewer names
    local rarest, second
    for from = 1, 2 do
        local a, b -- (a pair in no name counts as "": the typo may have made it)
        for at = from, n - 1, 2 do
            local bucket = pairsOf[sub(query, at, at + 1)] or ""
            if not a or #bucket < #a then
                a, b = bucket, a
            elseif not b or #bucket < #b then
                b = bucket
            end
        end
        if b and (not rarest or #a + #b < #rarest + #second) then rarest, second = a, b end
    end
    local names = {}
    wipe(seen)
    for round = 1, 2 do
        local positions = (round == 1 and rarest or second) or ""
        for p = 1, #positions, 3 do
            local entry = At(entries, positions, p)
            if not seen[entry] and Near(entry.key, query, n) then names[#names + 1] = entry end
            seen[entry] = true
        end
    end
    nearKept[index] = { query = query, names = names }
    return names
end

local later = {} -- near names not from their first word on, taken after those
local function NearFrom(index, query)
    local n = #query
    taken = 0
    -- the names near from their first word on first ("thorim": Thorium Bar,
    -- before Heavy Thorium Bar used up the limit), then the others
    wipe(later)
    for _, entry in ipairs(NearNames(index, query)) do
        local near = not chosen[entry] and Near(entry.key, query, n)
        if near == 3 then
            local full = Take(entry) or taken >= NEAR_LIMIT
            if gathered[#gathered] == entry then ns.index.near[entry] = near end
            if full then return end
        elseif near then
            later[#later + 1] = entry
            later[entry] = near
        end
    end
    for _, entry in ipairs(later) do
        local full = Take(entry) or taken >= NEAR_LIMIT
        if gathered[#gathered] == entry then ns.index.near[entry] = later[entry] end
        if full then return end
    end
end

-- Entries per switched-on category for a typed text (the number at its tab): the tiers of each index
-- without filters, up to SEARCH_LIMIT (then that or more); nil without text. Counted once per text and
-- set of indexes (a rebuilt one is a new table); the list just searched is untouched.
local counts, countedFor, countedIndexes = {}, nil, {}
local function CountsValid(query, active)
    if query ~= countedFor then return false end
    for _, source in ipairs(active) do
        if countedIndexes[source] ~= (source.index or false) then return false end
    end
    return true
end
function ns.index.Count(text)
    local query = SearchKey(text or "")
    if query == "" then return nil end
    local active = ns.ActiveSources()
    if CountsValid(query, active) then return counts end
    wipe(counts)
    wipe(countedIndexes)
    passes, reveal, typed, staticKey = nil, nil, true, nil
    for _, source in ipairs(active) do
        countedIndexes[source] = source.index or false
        if source.index then
            if source.beforeSearch then source.beforeSearch() end
            wipe(chosen)
            wipe(gathered)
            GatherFrom(source.index, query)
            counts[source] = #gathered
        end
    end
    wipe(chosen)
    wipe(gathered)
    countedFor = query
    return counts
end

-- an entry from outside the tiers (yours, learned): taken if it fits the query and its source is searched
local function GatherFitting(entry, query, searched)
    if not searched[entry.source] then return end
    local words = ns.index.Words(query)
    if entry.key:find(query, 1, true) or (entry.categoryKey and entry.categoryKey:find(query, 1, true))
            or (words and AllWords(entry)) then
        Gather(entry)
    end
end

local offered = {} -- the filters a typed text asks for (below the results)

-- Searched in all: the best of every category stands within the first rows ("thorium" showed 31 items
-- before the first NPC). The list keeps its order until the rows left equal the categories whose best
-- is still missing; those come then, best first. Categories, filters and near names are no category's best.
local isHead, placed, mixed, headOf, present = {}, {}, {}, {}, {}
local function Mix(list, rows)
    wipe(headOf)
    wipe(isHead)
    local heads, late = 0, false
    for i, entry in ipairs(list) do
        local source = not entry.scope and not entry.filter and not ns.index.near[entry] and entry.source
        if source and not headOf[source] then
            headOf[source], isHead[entry] = entry, true
            heads = heads + 1
            if i > rows then late = true end
        end
    end
    if not late then return end
    wipe(placed)
    wipe(mixed)
    local pending, nextHead, nextAny = heads, 1, 1
    for row = 1, #list do
        local entry
        if row <= rows and pending >= rows - row + 1 then
            while placed[list[nextHead]] or not isHead[list[nextHead]] do nextHead = nextHead + 1 end
            entry = list[nextHead]
        else
            while placed[list[nextAny]] do nextAny = nextAny + 1 end
            entry = list[nextAny]
        end
        placed[entry] = true
        if isHead[entry] then pending = pending - 1 end
        mixed[row] = entry
    end
    for row, entry in ipairs(mixed) do list[row] = entry end
end

-- The best SEARCH_LIMIT entries for a typed text, in the category scope (a source) or all switched-on
-- sources, passing the filter tokens (Filter.lua), ranked (Rank.lua). First the categories and
-- subcategories the text asks for, the filters it asks for last. Without text: with filters everything
-- that passes, in a category its first entries, else nothing. The returned list is reused by the next search.
function ns.index.Search(text, scope, filters)
    filters = filters or {}
    local query = SearchKey(text)
    wipe(best)
    wipe(gathered)
    wipe(chosen)
    wipe(ns.index.suggested)
    wipe(ns.index.noted)
    wipe(ns.index.near)
    wipe(offered)
    -- only punctuation typed ("("): nothing is found
    if query == "" and text:find("%S") then
        ns.index.browsed, ns.index.browseHint = false, nil
        wipe(ns.rank.learnedNow)
        return best
    end
    -- the reasons (the recommendations) read your level, skills and gear once
    ns.rec.Prepare()
    local searches, pool
    passes, searches, pool, reveal = ns.filter.Prepare(filters)
    typed = query ~= ""
    -- key of the filter set if all are static (see staticFirst)
    staticKey = nil
    if #filters > 0 and not reveal then
        staticKey = ""
        for _, f in ipairs(filters) do
            if not f.static then
                staticKey = nil
                break
            end
            staticKey = staticKey .. f.key .. "\1"
        end
    end
    local searched = {}
    for _, source in ipairs(scope and { scope } or ns.ActiveSources()) do
        if source.index and searches(source) then
            searched[source] = true
            if source.beforeSearch then source.beforeSearch() end
        end
    end
    -- a category that lists its own entries when nothing is typed (items: yours, then suggestions)
    -- A filter marked refines (a quality) only narrows, it is no filter of its own
    local plainFilter = false
    for _, f in ipairs(filters) do
        if not f.subcategory and not f.refines then plainFilter = true end
    end
    -- with a filter set only where the browse goes through everything anyway (browseFiltered: the
    -- dungeons' order by level), else everything that passes, A-Z
    local browsed = query == "" and scope and scope.browse and searched[scope]
        and (not plainFilter or scope.browseFiltered)
    ns.index.browsed = browsed and true or false -- View.lua: passing over counts only there
    ns.index.browseHint = nil
    if browsed then
        -- take(entry, heading, suggestion, note): the entry under that heading (nil: none), a suggestion
        -- dimmed, a note on the right of its row; hidden entries (spells to learn) too, the source chose them
        wipe(headingOf)
        ns.index.browseHint = scope.browse(function(entry, heading, suggestion, note)
            if scope.leaveOut and scope.leaveOut(entry) then return false end
            if entry.hidden then
                if chosen[entry] or (passes and not passes(entry)) then return false end
                chosen[entry] = true
                gathered[#gathered + 1] = entry
            elseif not Gather(entry) then
                return false
            end
            headingOf[entry] = heading
            if suggestion then ns.index.suggested[entry] = true end
            -- no note given: the strongest reason's (Recommend.lua)
            if note == nil then note = ns.rec.Mark(entry) end
            ns.index.noted[entry] = note
            return true
        end, filters)
        wipe(ns.rank.learnedNow)
    elseif query == "" and #filters == 0 then
        -- nothing typed, no category: the start page (Rank.lua); passing over counts there too (View.lua)
        if not scope then
            ns.index.browsed = true
            return ns.rank.StartPage(ns.MAX_RESULTS, best)
        end
        wipe(ns.rank.learnedNow) -- marks of the previous search would stay
        if scope and scope.index then
            for _, entry in ipairs(scope.index.entries) do
                if #best >= SEARCH_LIMIT then break end
                if not entry.hidden and not D.EventAway(entry) then best[#best + 1] = entry end
            end
        end
        return best
    end
    if query ~= "" then
        -- categories whose name starts with the query come first ("spe" + Tab)
        if not scope then
            for _, source in ipairs(ns.ActiveSources()) do
                if source.entry.key:sub(1, #query) == query then best[#best + 1] = source.entry end
            end
        end
        -- the filters it asks for go below the results (they took the first row: "innkeeper" was the
        -- filter Services); subcategories stay with the categories ("mining": Professions/Mining);
        -- "#..." asks for filters only
        local hash = ns.filter.Suggest(query, filters, scope, offered)
        local plain = 0
        for _, entry in ipairs(offered) do
            if entry.filter.subcategory then
                best[#best + 1] = entry
            else
                plain = plain + 1
                offered[plain] = entry
            end
        end
        for i = #offered, plain + 1, -1 do offered[i] = nil end
        if hash then
            for _, entry in ipairs(offered) do best[#best + 1] = entry end
            return best
        end
    end
    if browsed then
        -- in the source's order
    elseif pool then
        -- a filter knows its few possible entries: only those
        for _, entry in ipairs(pool) do GatherFitting(entry, query, searched) end
    else
        -- searched in all without filters: the tiers also yield the tabs' numbers (as Count would)
        local counting = not scope and #filters == 0 and query ~= ""
        if counting then
            wipe(counts)
            wipe(countedIndexes)
            for _, source in ipairs(ns.ActiveSources()) do countedIndexes[source] = source.index or false end
            countedFor = query
        end
        for source in pairs(searched) do
            GatherFrom(source.index, query)
            if counting then counts[source] = taken end
            if source.pool then
                for _, entry in ipairs(source.pool()) do GatherFitting(entry, query, searched) end
            end
        end
    end
    if query ~= "" then
        ns.memory.EachLearned(text, function(id)
            local entry = ns.index.EntryByID(id)
            if entry then GatherFitting(entry, query, searched) end
        end)
        if #gathered < NEAR_BELOW and not pool and #query >= NEAR_MIN and not query:find("[\128-\255]") then
            for source in pairs(searched) do NearFrom(source.index, query) end
        end
    end
    local order
    if query == "" then
        for _, f in ipairs(filters) do order = order or f.order end
    end
    if order then
        table.sort(gathered, order)
    elseif not browsed then
        ns.rank.Sort(gathered, text)
    end
    -- entries that look the same in the list (name, icon, category; 442 item names have several IDs,
    -- like two Dark Iron Ores) show once, the best ranked; variants that look different stay. An entry
    -- also shows once (a spell of the spell book that is a profession's too). The first entry of each
    -- name is kept and only same-name entries compared (a string per candidate was garbage).
    wipe(looks)
    wipe(looksByKey)
    wipe(looksMore)
    local limit = (browsed or order) and BROWSE_LIMIT or SEARCH_LIMIT
    -- in all with text: past the limit still the best of a category that
    -- has none in the list yet (Mix moves it up; "thorium": the quests)
    local mixing = query ~= "" and not scope
    wipe(present)
    -- without text, no NPC or quest of a world event not running now (typed, it is found, grey: its
    -- row's state names the event); Data's D.EventAway
    local away = query == "" and D.EventAway
    for _, entry in ipairs(gathered) do
        local source = entry.source
        if away and away(entry) then
            -- left out
        elseif #best >= limit and not (mixing and source and not present[source] and not ns.index.near[entry]) then
            if not mixing then break end
        else
            local id = ns.EntryID(entry)
            if not (id and looks[id]) and not SameLook(entry) then
                if id then looks[id] = true end
                best[#best + 1] = entry
                if source then present[source] = true end
            end
        end
    end
    passes = nil
    if mixing then Mix(best, ns.MAX_RESULTS) end
    for _, entry in ipairs(offered) do best[#best + 1] = entry end
    if browsed then
        local last
        local i = 1
        while best[i] do
            local label = headingOf[best[i]]
            if label and label ~= last then
                table.insert(best, i, Heading(label))
                i = i + 1
            end
            last = label
            i = i + 1
        end
    end
    return best
end

-- an entry by its ns.EntryID (Data's), if its category is built here (switched on, indexed)
function ns.index.EntryByID(id)
    local entry = D.EntryByID(id)
    local source = entry and entry.source
    return source and source.index and entry or nil
end

function ns.index.ItemByID(itemID)
    local entry = D.ItemByID(itemID)
    local source = entry and entry.source
    return source and source.index and entry or nil
end
