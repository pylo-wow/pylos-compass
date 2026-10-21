local ns = select(2, ...).search

-- The search: a search bar over your spells and all items, recipes, NPCs, dungeons and quests.
-- Entries and facts come from the data layer; the search finds and shows them.
-- Files, in load order: Core (helpers, state, registries), Recommend (ns.rec), Memory, Index, Rank, Filter,
-- Sources\ (one category each), Links\, UI\ (Base first, Bar last), Tools\, Filters\, View, Input, Control
-- (open/close, events, options).
-- New category: a Sources file calling ns.RegisterSource; link: a Links file calling ns.RegisterLink;
-- filter: a Filters file calling ns.RegisterFilter; tool: a Tools file calling ns.RegisterTool.

-- The tooltip interface of the addon Pylos GatherInfo (global PylosGatherInfo, nil if not loaded):
-- AddLine(tooltip, itemID), Wanted()
function ns.GatherInfo() return rawget(_G, "PylosGatherInfo") end

-- Width and row height are shared with the recommendations window (UI\Kit\Widgets.lua: W.WIDTH, W.ROW_HEIGHT)
ns.BAR_HEIGHT = 44
ns.MAX_RESULTS = 8   -- rows shown at once; longer lists scroll
ns.SEARCH_LIMIT = 50 -- results a search finds at most

-- "value / maximum" with the game's thousands separator ("1,250 / 3,000")
function ns.Progress(value, maximum)
    local Number = BreakUpLargeNumbers or tostring
    return ("%s / %s"):format(Number(math.floor(value + 0.5)), Number(math.floor(maximum + 0.5)))
end

-- characters of a text (UTF-8 characters take several bytes)
ns.EachChar = ns.data.EachChar

-- A typed text as searched (D.SearchKey) with umlauts folded: names are ASCII, so "thörium" finds Thorium.
local FOLD = { ["\195\164"] = "a", ["\195\132"] = "a", ["\195\182"] = "o", ["\195\150"] = "o",
    ["\195\188"] = "u", ["\195\156"] = "u", ["\195\159"] = "ss" } -- ä Ä ö Ö ü Ü ß
function ns.SearchKey(text)
    text = text or ""
    if text:find("\195", 1, true) then text = text:gsub("\195[\132\150\156\159\164\182\188]", FOLD) end
    return ns.data.SearchKey(text)
end

-- State: what the bar shows (View.lua changes it, UI\*.lua draw it)
--   query     the typed text
--   filters   the set filters (tokens in the bar)
--   scope     category (source) searched in, nil: all
--   results   list shown: matches, or the entries of a link
--   marked    index of the marked result; top: results above the first row
--   linked    a link's list: { entry = the entry, link = the link }
--   detail    entry in the detail view
--   history   states before every step forward
--   navigated a key chose in this list (keyMarked: the result it marked); hovered: the mouse marked a row (no choice)
--   unfocused the keyboard is back with the game (Input.lua)
--   openedAt, closingAt, barTop   when the bar opened, when it began to close (nil: not closing), its top offset
ns.state = {
    query = "", filters = {}, results = {}, marked = 1, top = 0, history = {},
}

-- Sources: each a category of entries with its own index (the fields in the order registrations list them).
--   key         unique; names the option "source_<key>"
--   domain      domain of the data layer ("items", "npcs", ...): it builds and rebuilds the entries, the index follows
--   name        shown name
--   emptyHint   text of an empty list opened without text; optional
--   icon        tab symbol; iconAtlas instead; iconPart { file, left, right, top, bottom }; icon stays the fallback
--   actionLabel detail view action name, lower case ("cast"; follows "Ctrl+Enter:")
--   owned       true or function(entry) -> true if yours; yours rank higher; optional
--   pool        function() -> your entries, always searched in full; optional
--   findable    function(entry) -> true if a hidden entry may be found by typing; optional
--   leaveOut    function(entry) -> true for an entry never listed nor found; optional
--   beforeSearch function(): once before a search in this source; optional
--   defaultFilters  keys of filters the category starts with each time the search opens; optional
--   subcategories  function() -> subcategory filters made via ns.MakeFilter; else registered filters with subcategory
--               and this source
--   overview    "bars": opened without text, a page of bars (overviewEntries() -> entries with entry.bar,
--               UI\Overview.lua); an entry with filter opens that subcategory on click
--   browse      function(take, filters): list opened without text (take(entry, heading)); may return the
--               text an empty list shows (else emptyHint); browseFiltered: also with a filter set (else the
--               entries that pass, ranked)
--   describe    function(entry) -> parts of the grey line below the name (UI\List.lua)
--   state       function(entry) -> text, tone: what it is for you now, on the right of its row (UI\List.lua)
--   forYou      function(entry, add): lines of the tooltip's "For you", add(text, tone) (UI\Tooltip.lua)
-- RegisterSource adds entry (the category as a result), Index.lua index and maps, UI\Tabs.lua chip.
-- An entry (from the data layer): name, key (name as searched), icon, category (right-hand text),
-- categoryKey; type = "spell"|"item" with value (secure: cast or used); itemID/spellID for the
-- tooltip; hidden = true: found only when a filter reveals it. entry.source is its category.
ns.sources = {}

-- Symbol of WoW Forever's micro menu, read from the button itself by its names (they differ
-- between clients): atlas, file, or nothing.
function ns.MicroMenuSymbol(...)
    for _, name in ipairs({ ... }) do
        local button = _G[name]
        local texture = button and button.GetNormalTexture and button:GetNormalTexture()
        if texture then
            local atlas = texture.GetAtlas and texture:GetAtlas()
            if atlas and atlas ~= "" then return atlas, nil end
            local file = texture:GetTextureFileID()
            if file then return nil, file end
        end
    end
end

ns.sourceByKey = {}
function ns.RegisterSource(source)
    ns.sources[#ns.sources + 1] = source
    ns.sourceByKey[source.key] = source
    -- the entries of the domain answer entry.source
    ns.data.AddField(source.domain, "source", function() return source end)
    -- the category as a result: typing its name lists it ("c:<key>" is its memory ID)
    source.entry = { name = source.name, icon = source.icon, iconAtlas = source.iconAtlas, iconPart = source.iconPart,
        key = ns.data.SearchKey(source.name), category = ns.L["Category"], scope = source,
        entryID = "c:" .. source.key }
    return source
end

-- Entry ID, stable across sessions and rebuilds: the data layer's ("i:2589", "n:448", "s:2657", "q:7",
-- "d:36"), "c:<key>" for a category; nil for anything else (a filter, a quest row in a link list)
ns.EntryID = ns.data.EntryID

ns.LEVEL_BELOW, ns.LEVEL_ABOVE = 5, 3 -- "your level": foes and quests this far below or above yours

-- The hidden spells and recipes (not learned yet), rebuilt only when the data layer rebuilt them.
local hiddenCache = ns.data.Cache({ "data:spells", "data:professions" })
function ns.HiddenLearnables()
    local list, renewed = hiddenCache.Get()
    if renewed then
        for _, key in ipairs({ "spells", "professions" }) do
            for _, entry in ipairs(ns.data.Entries(key)) do
                if entry.hidden then list[#list + 1] = entry end
            end
        end
    end
    return list
end

-- The level a spell is learned at (a trainer seen since the list was built counts), the skill a recipe needs.
function ns.LearnNeeds(entry)
    if entry.trainLevel then
        return ns.data.TrainingLevel(entry.spellID) or entry.trainLevel
    end
    return entry.learn or entry.skill or 0
end

-- What a trainer still has to teach (teaches: a D.npcTrainers value, a class below 100, else a profession's
-- skill line): its spells or recipes not learned yet, or nil for another class's or a profession you lack.
-- The list is shared: copy it before changing it.
local taught = ns.data.Cache({ "data:spells", "data:professions" })
function ns.TrainerTeaches(teaches)
    if teaches < 100 then
        if teaches ~= select(3, UnitClass("player")) then return nil end
    elseif not ns.data.ProfessionRanks()[teaches] then
        return nil
    end
    local cache = taught.Get()
    local list = cache[teaches]
    if not list then
        list = {}
        cache[teaches] = list
        if teaches < 100 then
            for _, spell in ipairs(ns.data.Entries("spells")) do
                if spell.hidden and spell.trainLevel then list[#list + 1] = spell end
            end
        else
            for _, recipe in ipairs(ns.data.Entries("professions")) do
                if recipe.hidden and recipe.skillLine == teaches and (recipe.recipeItem or 0) == 0 then
                    list[#list + 1] = recipe
                end
            end
        end
    end
    return list
end

-- Tones of what an entry is for you, shared by a row's state (UI\List.lua) and the tooltip's
-- "For you" (UI\Tooltip.lua): good (doable now), active (going on), done (no use), no (not
-- possible yet), plain (a fact)
ns.TONES = { good = ns.widgets.GREEN, active = ns.widgets.GOLD, done = ns.widgets.DIM, no = ns.widgets.RED,
    plain = ns.widgets.LIGHT }

-- Trainer NPC IDs of a class or profession (D.npcTrainers: NPC ID -> class ID or skill line)
function ns.TrainersOf(teaches)
    local list = {}
    for npcID, what in pairs(ns.data.npcTrainers or {}) do
        if what == teaches then list[#list + 1] = npcID end
    end
    table.sort(list)
    return list
end

-- The game's color of a level against yours (as for foes and quests): grey no experience,
-- green easy, yellow even, orange hard, red very hard.
local CON = { grey = { 0.55, 0.55, 0.55, dim = true }, green = { 0.25, 0.75, 0.25 }, yellow = { 1, 1, 0 },
    orange = { 1, 0.5, 0.25 }, red = { 1, 0.1, 0.1 } }
function ns.ConColor(level)
    local yours = UnitLevel("player")
    local diff = level - yours
    if diff >= 5 then return CON.red end
    if diff >= 3 then return CON.orange end
    if diff >= -2 then return CON.yellow end
    if level > ns.data.GreyLevel(yours) then return CON.green end
    return CON.grey
end

function ns.ActiveSources()
    local active = {}
    if ns.db and ns.db.searchOn == false then return active end -- the search is switched off: nothing is built
    for _, source in ipairs(ns.sources) do
        if not ns.db or ns.db["source_" .. source.key] ~= false then active[#active + 1] = source end
    end
    return active
end

-- Links: from an entry's menu to a list of entries.
--   key       unique; Links\Order.lua orders the links by it
--   label     menu line, with the count ("Used for")
--   title     the bar's label for the list, %s the entry ("%s is used for:")
--   icon      symbol in the bar for the list
--   direct    true: with one entry, straight to its detail view; optional
--   entries   function(entry) -> list of entries (empty: no link)
ns.links = {}

function ns.RegisterLink(link)
    ns.links[#ns.links + 1] = link
end

-- Filters: narrow a search, shown as tokens in the bar ("Not on bars"). Typing a filter's name
-- (or "#") suggests it; Tab, Enter or a click makes a token; Backspace on an empty bar or a click
-- removes it. An entry must pass every token, except filters of one group (one suffices).
-- Without text a filter lists what passes.
--   key       unique
--   name      token text; words: more words that find it (optional)
--   description  tooltip sentence in the filter window
--   icon      symbol in the list; iconColor { r, g, b } tints it (optional)
--   color     token text color "ffrrggbb" (optional)
--   group     filters of one group: one must pass (optional); groupName: the group's name
--   sources   keys of sources it applies to (optional: all); others are not searched while set
--   prepare   function(): once before a search (read action bars, ...)
--   test      function(entry) -> true if the entry passes
--   pool      function() -> the only entries that can pass (searched instead of the index); optional;
--             without text all that pass are listed (up to BROWSE_LIMIT of Index.lua)
--   reveals   true: hidden entries (not learned yet) can pass
--   refines   true: only narrows (a quality); for a category's list opened without text it is no filter of its own
--   order    function(a, b) -> true if a comes first; without text, all that pass in this order
--             (else ranked: at most SEARCH_LIMIT, up to BROWSE_LIMIT of Index.lua if a filter has a pool); optional
--   static    true: test reads only the entry's own facts, never character or game state;
--             Index.lua then keeps what passes until the index is built again
--   subcategory  true: part of its category (Cooking in Professions), not a token: a tab left of
--             the list (Tab opens it, one at a time); offered: function() -> true if suggested;
--             background: { atlas, focus x, focus y, zoom, alpha } behind list and detail view
--             (UI\Detail.lua, ui.SetArt)
ns.filters = {}

-- A filter made ready without registering it (a category's own subcategories)
function ns.MakeFilter(filter)
    filter.find = ns.data.SearchKey(filter.name .. " " .. (filter.words or ""))
    filter.entry = { name = filter.name, icon = filter.icon, iconColor = filter.iconColor,
        key = ns.data.SearchKey(filter.name), category = filter.subcategory and ns.L["Category"] or ns.L["Filter"],
        filter = filter }
    return filter
end

ns.filterByKey = {}
function ns.RegisterFilter(filter)
    ns.filters[#ns.filters + 1] = filter
    ns.filterByKey[filter.key] = filter
    return ns.MakeFilter(filter)
end

-- Subcategories of a source: its own, or registered filters marked as its subcategories (offered only)
function ns.Subcategories(source)
    local list = {}
    if source.subcategories then
        for _, f in ipairs(source.subcategories()) do list[#list + 1] = f end
    else
        for _, f in ipairs(ns.filters) do
            if f.subcategory and f.sources[1] == source.key and (not f.offered or f.offered()) then
                list[#list + 1] = f
            end
        end
    end
    return list
end

-- Tools: a line in an entry's menu that does something with it:
-- key, label, available(entry) -> true if it fits, run(entry)
ns.tools = {}

function ns.RegisterTool(tool)
    ns.tools[#ns.tools + 1] = tool
end
