local ns = select(2, ...).search
if ns.off then return end
local L = ns.L

-- What the bar shows and how one moves through it:
--   Tab/Shift+Tab/Up/Down   choose (also a category or filter result; in the detail view an option)
--   Tab, empty bar          step through the categories; Ctrl+Tab/Ctrl+Shift+Tab: next/previous, text stays
--   Escape                  in stages: the menu, back from a detail view or link list, the typed text; then close
--   Enter, Right            confirm: category -> its search, result -> detail view, in a detail view its menu (Space too)
--   Enter after typing      the first result or the one chosen with the keys (the mouse only points); nothing found in a category: same text in all
--   Left/Backspace on an empty bar (or in a detail view), the back arrow: back, the way you came (right click is for menus)
--   Ctrl+Enter              the action at once; Enter on an empty bar closes (after Up/Down it opens the marked one)
-- Detail views and link lists are steps in history; categories and filter tokens are not.

local S = ns.state
local ui = ns.ui
local view = {}
ns.view = view

-- what the action keys and buttons act on: the detail view's entry, else
-- the marked result (an item of a link's list stands for its item entry)
function view.Target()
    local entry = S.detail or S.results[S.marked]
    return entry and (entry.target or entry)
end

local function Carried(entry)
    return entry.itemID ~= nil and C_Item.GetItemCount(entry.itemID) > 0
end

-- the action an entry has: a spell to cast or an item you carry to use
local function HasAction(entry)
    if not entry or entry.scope or entry.filter then return false end
    if entry.itemID then return Carried(entry) end
    return entry.type ~= nil
end
view.HasAction = HasAction

-- a step forward: the state before it into history
local function Push()
    S.history[#S.history + 1] = { query = S.query, scope = S.scope, filters = { unpack(S.filters) }, linked = S.linked,
        marked = S.marked, top = S.top, detail = S.detail }
end

-- what can be done with an entry (its menu): its links that have entries,
-- then the tools that fit it
local byRank = {}
local function Options(entry)
    local options = {}
    -- links in the order this kind of entry needs (Links\Order.lua), the others after as registered
    local rank = ns.LinkRank(entry)
    wipe(byRank)
    for i, link in ipairs(ns.links) do byRank[#byRank + 1] = { link, rank[link.key] or (100 + i) } end
    table.sort(byRank, function(a, b) return a[2] < b[2] end)
    for _, ranked in ipairs(byRank) do
        local link = ranked[1]
        local count = 0
        local entries = link.entries(entry)
        for _, linked in ipairs(entries) do
            if not linked.header then count = count + 1 end -- a divider is no entry
        end
        if count > 0 then
            -- a direct link with one entry leads straight to it: no count
            local text = (link.direct and count == 1) and link.label or ("%s (%d)"):format(link.label, count)
            -- entries too: the detail view previews them (UI\Detail.lua)
            options[#options + 1] = { kind = "link", link = link, text = text, count = count, entries = entries }
        end
    end
    for _, tool in ipairs(ns.tools) do
        if tool.available(entry) then
            options[#options + 1] = { kind = "tool", tool = tool, text = tool.label }
        end
    end
    return options
end

-- Marks a result (index in the results): the list scrolls to keep it in view; Ctrl+Enter is armed for
-- the action. A heading is passed over in the direction moved (step, down if none); the heading above
-- the marked one stays in view. keepTop (wheel or bar scrolling): the list stays where it is.
function view.Mark(index, step, keepTop)
    local count = #S.results
    for _ = 1, count do
        local entry = S.results[index]
        if not (entry and entry.header) then break end
        index = (index - 1 + (step or 1)) % count + 1
    end
    S.marked = index
    local top = S.top
    if not keepTop then
        local above = S.results[index - 1]
        if above and above.header and index - 1 <= top then top = index - 2 end
        if index <= top then top = index - 1 end
        if index > top + ui.Rows() then top = index - ui.Rows() end
    end
    if top ~= S.top then
        S.top = math.max(top, 0)
        ui.RenderRows()
        ui.FitList()
    end
    ui.MarkRows()
    ns.input.ArmEnter(nil)
    ns.input.ArmQuick(view.Target())
    ui.ShowTooltip(S.results[S.marked])
end

-- Shows the state. restored: an earlier state, whose marked result and scroll position are kept.
function view.Refresh(restored)
    if not S.detail and not S.linked then view.ApplyDefaults() end
    ui.RenderBar()
    if S.detail then
        -- options are in the entry's menu (right click); the action stays on Ctrl+Enter
        ui.RenderDetail(S.detail)
        ui.ShowCounts(nil)
        ns.input.ArmQuick(S.detail)
        ns.input.ArmEnter(nil)
        return
    end

    -- a category with an overview (Professions), opened without text: its page instead of a list
    local overview = not S.linked and S.scope and S.scope.overview and S.query == "" and #S.filters == 0
        and S.scope.overviewEntries()
    if overview then
        S.results = {}
    elseif S.linked then
        S.results = S.linked.link.entries(S.linked.entry)
    else
        S.results = ns.index.Search(S.query, S.scope, S.filters)
    end
    S.marked, S.top = 1, 0
    if restored then
        S.marked = math.min(restored.marked or 1, math.max(#S.results, 1))
        S.top = math.min(restored.top or 0, math.max(#S.results - ui.Rows(), 0))
        S.keyMarked = S.marked
    else
        -- a new list: nothing chosen in it yet
        S.navigated, S.hovered, S.keyMarked = false, false, nil
    end
    -- the tabs: how many each category has for the text typed; with filters also how many pass
    local counts = not S.linked and ns.index.Count(S.query) or nil
    local passing
    if counts and #S.filters > 0 then
        passing = {}
        for _, source in ipairs(S.scope and { S.scope } or ns.ActiveSources()) do passing[source] = 0 end
        for _, entry in ipairs(S.results) do
            local source = not entry.header and not entry.scope and not entry.filter
                and not ns.index.near[entry] and entry.source
            if source and passing[source] then passing[source] = passing[source] + 1 end
        end
    end
    ui.ShowCounts(counts, passing)
    -- the list shows always: the start page says when it has nothing
    ui.RenderList(true, overview or nil)
    view.Mark(S.marked)
end

local function Restore(state)
    S.query, S.scope, S.linked, S.filters = state.query, state.scope, state.linked, state.filters
    S.detail = state.detail
    view.Refresh(state)
end

-- Filters are kept per category for the session (subcategories are not).
local remembered = {} -- category key ("" for all) -> its plain filters
local function ScopeKey(source) return source and source.key or "" end

-- A category's own filters (source.defaultFilters: Quests "In your log", Items "In bags") are set only while it is browsed without text,
-- so the list holds what the tab counts. Yours stay. If you take them away (Backspace, the filter window), they stay away until the search opens again.
local auto = {}     -- filter -> true: set as a category's own, not by you
local declined = {} -- category key -> true: you took its own filters away

function view.ApplyDefaults()
    local source = S.scope
    local own = source and source.defaultFilters
    local want = own and S.query == "" and not declined[source.key]
    for i = #S.filters, 1, -1 do
        local f = S.filters[i]
        if auto[f] and not (want and tContains(own, f.key)) then
            table.remove(S.filters, i)
            auto[f] = nil
        end
    end
    if not want then return end
    for _, key in ipairs(own) do
        local f = ns.filterByKey[key]
        if f and not tContains(S.filters, f) then
            S.filters[#S.filters + 1] = f
            auto[f] = true
        end
    end
end

-- you took filters away: a category's own among them stay away
local function Declined(f)
    if auto[f] then
        auto[f] = nil
        if S.scope then declined[S.scope.key] = true end
    end
end

local function RemoveFilters(sub)
    for i = #S.filters, 1, -1 do
        if (not not S.filters[i].subcategory) == sub then table.remove(S.filters, i) end
    end
end

-- notes the current category's plain filters (yours, not its own)
local function Stash()
    local list = {}
    for _, f in ipairs(S.filters) do
        if not f.subcategory and not auto[f] then list[#list + 1] = f end
    end
    remembered[ScopeKey(S.scope)] = list
end

local function Recall(source)
    RemoveFilters(false)
    wipe(auto)
    for _, f in ipairs(remembered[ScopeKey(source)] or {}) do S.filters[#S.filters + 1] = f end
end

-- a fresh, empty search (when the bar opens). A category with filters of its own (source.defaultFilters)
-- starts with only them each opening; switching between tabs keeps what you chose.
function view.Reset()
    if S.scope then Stash() end -- the category's filters survive closing
    for _, source in ipairs(ns.sources) do
        if source.defaultFilters then remembered[ScopeKey(source)] = {} end
    end
    wipe(declined)
    S.query, S.scope, S.linked, S.detail = "", nil, nil, nil
    S.filters = {}
    Recall(nil)
    wipe(S.history)
    view.Refresh()
end

-- Steps

-- a step outside the history (typing, a category, a filter): leaves a detail view or link list and
-- clears history (the detail view stayed while the tabs changed)
local function NewWay()
    if S.detail or S.linked then
        wipe(S.history)
        S.detail, S.linked = nil, nil
    end
end

-- narrows the search to a category (nil: all), with the filters remembered for it; the typed text goes,
-- unless keepText (click on a category, Ctrl+Tab: same words searched elsewhere; a category result
-- found by typing, "spe" + Tab, empties the bar)
function view.SetScope(source, keepText)
    NewWay()
    if source ~= S.scope then Stash() end
    S.scope = source
    if not keepText then S.query = "" end
    RemoveFilters(true) -- a subcategory belongs to the category left
    Recall(source)
    view.Refresh()
end

function view.PickScope(source)
    view.SetScope(source ~= S.scope and source or nil, true)
end

-- sets a filter token: from a filter result the typed text goes; keepText (from the filter menu): it stays
function view.AddFilter(f, keepText)
    NewWay()
    if f.subcategory then
        -- a subcategory: its category becomes the one searched in; it replaces another subcategory and stands first
        RemoveFilters(true)
        for _, source in ipairs(ns.sources) do
            if source.key == f.sources[1] and source ~= S.scope then
                Stash()
                S.scope = source
                Recall(source)
            end
        end
        table.insert(S.filters, 1, f)
    else
        table.insert(S.filters, f)
        auto[f] = nil
    end
    if not keepText then S.query = "" end
    view.Refresh()
end

-- the red × at the filter button: every filter goes (a subcategory stays, the text too)
function view.ClearFilters()
    NewWay()
    for _, f in ipairs(S.filters) do Declined(f) end
    RemoveFilters(false)
    view.Refresh()
end

function view.ToggleFilter(f)
    for i, set in ipairs(S.filters) do
        if set == f then return view.RemoveFilter(i) end
    end
    view.AddFilter(f, true)
end

function view.Subcategory()
    local first = S.filters[1]
    return first and first.subcategory and first or nil
end

function view.RemoveFilter(index)
    NewWay()
    local f = table.remove(S.filters, index or #S.filters)
    if f then Declined(f) end
    view.Refresh()
end

-- Ctrl+Tab (and Tab in an empty bar): the next (1) or previous (-1) category, "all" between the last and the first
function view.CycleScope(step)
    local active = ns.ActiveSources()
    local index = 0
    for i, source in ipairs(active) do
        if source == S.scope then index = i end
    end
    view.SetScope(active[(index + step) % (#active + 1)], true)
end

function view.Escape()
    if ui.MenuShown() then return ui.HideMenu() end
    if S.detail or S.linked then return view.Back() end
    if S.query ~= "" then
        S.query = ""
        return view.Refresh()
    end
    ns.Close()
end

-- in a category, typed text found nothing there: the same text in all. Only when the category itself has
-- nothing for it (its count), not when a filter left nothing ("In bags": the items are there), and only
-- when another category has something. Filters offered below count as nothing found.
function view.NothingHere()
    if not (S.scope and S.query ~= "" and not S.linked and not S.detail) then return false end
    for _, entry in ipairs(S.results) do
        if not entry.filter then return false end
    end
    local counts = ns.index.Count(S.query)
    if not (counts and counts[S.scope] == 0) then return false end
    for source, count in pairs(counts) do
        if source ~= S.scope and count > 0 then return true end
    end
    return false
end

-- Deeper (Enter, Right, a click): in the detail view its menu (the links are there); in a list a
-- category's search, every other result's detail view
function view.Deeper()
    if S.detail then return ui.ShowMenu(S.detail, true, true) end
    local entry = S.results[S.marked]
    if not entry then return end
    if entry.scope then return view.SetScope(entry.scope) end
    if entry.filter then return view.AddFilter(entry.filter) end
    if entry.open then return entry.open() end -- a row of its own (a zone: the world map)
    view.Open(entry.target or entry)
end

-- An entry was chosen: the memory (Memory.lua and the engine's) learns it after the typed text (if
-- any); amount 0.5 for looking at it (detail view, link list), 0.5 more for doing something with it
-- there, 1 for doing it straight from the list. Chosen from a list opened without text, the
-- suggestions above it (entries with a reason) were passed over: they sink a little next time.
local function Chose(entry, amount)
    local id = entry and ns.EntryID(entry)
    if not id then return end
    ns.memory.Chose(id, S.query, amount)
    ns.rec.Chose(id, amount, S.query)
    -- only in a list opened without text that suggests (a category's own, the start page; not a filtered
    -- A-Z list), and only for rows that stood there as suggestions, i.e. with a reason
    local marked = S.results[S.marked]
    if S.query ~= "" or S.linked or S.detail or not ns.index.browsed then return end
    if not marked or (marked ~= entry and marked.target ~= entry) then return end
    for i = 1, S.marked - 1 do
        local above = S.results[i]
        if above and not above.header and ns.rec.Fit(above) > 0 then
            ns.rec.PassedOver(ns.EntryID(above))
        end
    end
end

-- opens an entry's detail view (from a list or an overview click); a step in history; the entry counts as chosen
function view.Open(entry)
    Chose(entry, 0.5)
    Push()
    -- the link's list stays in history only: its label does not belong to the detail view
    S.detail, S.linked = entry, nil
    view.Refresh()
end

-- One step back: the state before the last step forward; without one, the typed text goes, then the category
function view.Back()
    if #S.history > 0 then
        Restore(table.remove(S.history))
    elseif S.query ~= "" then
        NewWay()
        S.query = ""
        view.Refresh()
    elseif #S.filters > 0 then
        view.RemoveFilter()
    elseif S.scope then
        view.SetScope(nil)
    end
end

view.Options = Options
function view.OpenLink(entry, link)
    if link.direct then
        local entries = link.entries(entry)
        if #entries == 1 then return view.Open(entries[1].target or entries[1]) end
    end
    Chose(entry, 0.5)
    Push()
    S.linked = { entry = entry, link = link }
    S.detail, S.query = nil, ""
    view.Refresh()
end
function view.RunTool(entry, tool)
    if S.detail ~= entry then view.Open(entry) end -- else the detail is pushed to the history twice
    Chose(entry, 0.5)
    tool.run(entry)
end
function view.OnlyFilter(f)
    for _, set in ipairs(S.filters) do Declined(set) end
    RemoveFilters(false)
    view.AddFilter(f, true)
end

function view.Forget(entry)
    ns.memory.Forget(ns.EntryID(entry))
    ns.rec.Forget(ns.EntryID(entry))
    view.Refresh({ marked = S.marked, top = S.top })
end

function view.Feedback(entry, good)
    ns.rec.Feedback(entry, good)
    ns.widgets.Notice(good and L["Noted: suggestions like this count more for you."]
        or L["Noted: suggestions like this count less for you."])
    if not S.detail then view.Refresh({ marked = S.marked, top = S.top }) end
end

function view.HideSuggestion(entry, hidden)
    ns.rec.Hide(entry, hidden)
    if not S.detail then view.Refresh({ marked = S.marked, top = S.top }) end
end

-- a row of the detail view's previews opened (UI\Detail.lua): its entry's detail view, a zone's world map
function view.OpenPreview(entry)
    if not entry then return end
    if entry.open then return entry.open() end
    view.Open(entry.target or entry)
end

function view.Step(step)
    S.navigated = true -- Enter opens what is marked, also on the start page
    if S.detail then
        local count = ui.detail.previewCount or 0
        if count > 0 then
            local at = ui.detail.previewMarked
            ui.MarkPreview(at and ((at - 1 + step) % count + 1) or (step > 0 and 1 or count))
        end
        return
    end
    if #S.results > 0 then
        view.Mark((S.marked - 1 + step) % #S.results + 1, step)
        S.keyMarked = S.marked -- (the mouse may mark another one later)
    end
end

-- from a detail view or a link's list back to the search it started from (the state, not shown yet)
function view.ToSearch()
    if (S.detail or S.linked) and #S.history > 0 then
        local root = S.history[1]
        wipe(S.history)
        S.query, S.scope, S.linked, S.detail = root.query, root.scope, nil, nil
        S.filters = root.filters
    end
end

-- Typing: adds to the search text (from a detail view or link list: back to the search first)
function view.Type(text)
    view.ToSearch()
    NewWay()
    S.query = S.query .. text
    view.Refresh()
end

-- removes the last typed character (UTF-8 characters take several bytes); false when there is none
function view.Erase()
    if S.query == "" or S.detail or S.linked then return false end
    NewWay()
    S.query = S.query:match("^(.*)[%z\1-\127\192-\255][\128-\191]*$") or ""
    view.Refresh()
    return true
end

function view.AfterAction()
    local entry = view.Target()
    if not HasAction(entry) then return end
    -- from the list at once (Ctrl+Enter): a whole choice; from the detail
    -- view the other half (opening it counted the first)
    Chose(entry, S.detail and 0.5 or 1)
    ns.Close()
end

-- Enter, after its secure part: in the detail view the chosen option (the
-- action has run, a link opens), in a list the marked result goes deeper
function view.Confirm()
    if ui.MenuShown() then return ui.MenuConfirm() end
    -- the detail view: Enter opens the preview row marked with Up/Down, else the first; the menu is
    -- Space's (and Right's, a right click's)
    if S.detail then
        local count = ui.detail.previewCount or 0
        if count > 0 then return view.OpenPreview(ui.detail.previewRows[ui.detail.previewMarked or 1].entry) end
        return
    end
    if view.NothingHere() then return view.SetScope(nil, true) end
    -- nothing typed, no category, no list: Enter closes, like the key again
    -- (on the start page, until a key chose one of the last entries)
    if S.query == "" and not S.scope and #S.filters == 0 and not S.linked
            and not (S.navigated and #S.results > 0) then
        return ns.Close()
    end
    -- what the keys chose, else the first result: a row under the mouse is no choice
    local chosen = S.navigated and S.keyMarked or 1
    if chosen ~= S.marked then view.Mark(chosen) end
    -- a filter only when chosen with the keys (it is no result to open; a
    -- subcategory, standing with the categories on top, opens as they do)
    local entry = S.results[S.marked]
    if entry and entry.filter and not entry.filter.subcategory and not S.navigated then return end
    view.Deeper()
end
