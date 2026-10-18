local ns = select(2, ...).search
if ns.off then return end

-- the search: search bar over your spells and all items, recipes, NPCs, dungeons and quests.
-- Entries and facts come from Data; this addon searches and shows them.
-- Files: Core (helpers, state, registries), Recommend (ns.rec), Memory, Index, Rank, Filter,
-- Sources\ (one category each), Links\, Tools\, Filters\, UI\ (Base first, Bar last), View, Input,
-- Spotlight (open/close, events, options).
-- New category: a Sources file calling ns.RegisterSource; link: a Links file calling
-- ns.RegisterLink; tool: a Tools file calling ns.RegisterTool.

-- Pylos GatherInfo's tooltip service (a global it sets when installed): AddLine(tooltip, itemID), Wanted()
function ns.GatherInfo() return rawget(_G, "PylosGatherInfo") end

-- Width and row height are shared with the recommendations window: UI\Kit\Widgets.lua, W.WIDTH, W.ROW_HEIGHT
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

-- A typed text as searched (Data's D.SearchKey), with German umlauts folded: names are ASCII,
-- so "thörium" finds Thorium.
local FOLD = { ["\195\164"] = "a", ["\195\132"] = "a", ["\195\182"] = "o", ["\195\150"] = "o",
    ["\195\188"] = "u", ["\195\156"] = "u", ["\195\159"] = "ss" } -- ä Ä ö Ö ü Ü ß
function ns.SearchKey(text)
    text = text or ""
    if text:find("\195", 1, true) then text = text:gsub("\195[\132\150\156\159\164\182\188]", FOLD) end
    return ns.data.SearchKey(text)
end

function ns.EaseOutBack(p) -- overshoots a little and settles
    local c = 1.4
    return 1 + (c + 1) * (p - 1) ^ 3 + c * (p - 1) ^ 2
end

-- State: what the bar shows (View.lua changes it, UI\*.lua draw it)
--   scope     category (source) searched in, nil: all
--   results   list shown: matches, or the entries of a link
--   marked    index of the marked result; top: results above the first row
--   linked    a link's list: { entry = the entry, link = the link }
--   detail    entry in the detail view
--   history   states before every step forward
--   navigated a key chose in this list (keyMarked: the result it marked); hovered: the mouse marked a row (no choice)
ns.state = {
    query = "", filters = {}, results = {}, marked = 1, top = 0, history = {},
}

-- Sources: each a category of entries with its own index.
--   key         unique; names the option "source_<key>"
--   name, hint  shown name; hint in its search ("Search spells")
--   icon        tab symbol; iconAtlas instead; iconPart { file, left, right, top, bottom }; icon stays the fallback
--   domain      Data domain ("items", "npcs", ...): Data builds and rebuilds the entries, the index follows
--   actionLabel detail view action name, lower case ("cast"; follows "Ctrl+Enter:")
--   owned       true or function(entry) -> true if yours; yours rank higher; optional
--   overview    "bars": opened without text, a page of bars (overviewEntries() -> entries with entry.bar, UI\Overview.lua);
--               an entry with filter opens that subcategory on click
--   subcategories  function() -> subcategory filters made via ns.MakeFilter; else registered filters with subcategory and this source
--   defaultFilters  keys of filters the category starts with each time the search opens; optional
--   browse      function(take, filters): list opened without text (take(entry, heading, suggestion, note)); may return the
--               text an empty list shows (else emptyHint); browseFiltered: also with a filter set (else filtered entries A-Z)
--   emptyHint   text of an empty list opened without text; optional
--   findable    function(entry) -> true if a hidden entry may be found by typing; optional
--   leaveOut    function(entry) -> true for an entry never listed nor found; optional
--   beforeSearch function(): once before a search in this source; optional
--   pool        function() -> your entries, always searched in full; optional
-- An entry (Data's): name, key (name as searched), icon, category (right-hand text),
-- categoryKey; type = "spell"|"item" with value (secure: cast or used); itemID/spellID for the
-- tooltip; hidden = true: found only when a filter reveals it. entry.source is its category.
ns.sources = {}

-- Symbol of WoW Forever's micro menu, taken from the button itself by its names (they differ
-- between clients): atlas, file, or nothing. Atlas names guessed from data were not in the client.
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
    -- Data's entries of the domain answer entry.source
    ns.data.AddField(source.domain, "source", function() return source end)
    -- the category as a result: typing its name lists it ("c:<key>" is its memory ID)
    source.entry = { name = source.name, icon = source.icon, iconAtlas = source.iconAtlas, iconPart = source.iconPart,
        key = ns.data.SearchKey(source.name), category = ns.L["Category"], scope = source, entryID = "c:" .. source.key }
    return source
end

-- Entry ID, stable across sessions and rebuilds: Data's ("i:2589", "n:448", "s:2657", "q:7",
-- "d:36"), "c:<key>" for a category; nil for anything else (a filter, a quest row in a link list)
ns.EntryID = ns.data.EntryID

-- Tones of what an entry is for you, shared by a row's state (UI\List.lua) and the tooltip's
-- "For you" (UI\Tooltip.lua): good (doable now), active (going on), done (no use), no (not
-- possible yet), plain (a fact)
ns.TONES = { good = ns.widgets.GREEN, active = ns.widgets.GOLD, done = ns.widgets.DIM, no = ns.widgets.RED,
    plain = ns.widgets.LIGHT }

-- Trainer NPC IDs of a class or profession (Data's D.npcTrainers: NPC ID -> class ID or skill line)
function ns.TrainersOf(teaches)
    local list = {}
    for npcID, what in pairs(ns.data.npcTrainers or {}) do
        if what == teaches then list[#list + 1] = npcID end
    end
    table.sort(list)
    return list
end

-- The game's colour of a level against yours (as for foes and quests): grey no experience,
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
--   label     menu line, with the count ("Used for")
--   title     the bar's label for the list, %s the entry ("%s is used for:")
--   icon      symbol in the bar for the list
--   entries   function(entry) -> list of entries (empty: no link)
--   direct    true: with one entry, straight to its detail view
ns.links = {}

function ns.RegisterLink(link)
    ns.links[#ns.links + 1] = link
end

-- Filters: narrow a search, shown as tokens in the bar ("Not on bars"). Typing a filter's name
-- (or "#") suggests it; Tab, Enter or a click makes a token; Backspace on an empty bar or a click
-- removes it. An entry must pass every token, except filters of one group (one suffices).
-- Without text a filter lists everything that passes.
--   name      token text; words: more words that find it (optional)
--   description  tooltip sentence in the filter window
--   icon      symbol in the list; iconColor { r, g, b } tints it (optional)
--   color     token text colour "ffrrggbb" (optional)
--   group     filters of one group: one must pass (optional); groupName: the group's name
--   sources   keys of sources it applies to (optional: all); others are not searched while set
--   prepare   function(): once before a search (read action bars, ...)
--   test      function(entry) -> true if the entry passes
--   pool      function() -> the only entries that can pass (searched instead of the index); optional
--   reveals   true: hidden entries (not learned yet) can pass
--   order     function(a, b) -> true if a comes first; without text, all that pass in this order
--             (else ranked, at most SEARCH_LIMIT); optional
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

-- Tools: a line in an entry's menu that does something with it: key, label, available(entry) -> true if it fits, run(entry)
ns.tools = {}

function ns.RegisterTool(tool)
    ns.tools[#ns.tools + 1] = tool
end
