local ns = select(2, ...).search
local L = ns.L
local D = ns.data

-- The list below the bar: the results' rows (or the overview, Overview.lua),
-- a scroll bar, the list's height.

local S = ns.state
local W = ns.widgets
local ui = ns.ui
local bar = ui.bar
local ROW_HEIGHT, DOT = W.ROW_HEIGHT, W.DOT
local Clamp = W.Clamp

local WINDOW_GAP = ui.WINDOW_GAP
local list = CreateFrame("Frame", nil, bar)
list:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -WINDOW_GAP)
list:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", 0, -WINDOW_GAP)
list:Hide()
W.Panel(list)
ui.Art(list)
ui.CatchMouse(list)
ui.list = list

list.empty = W.Empty(list)
list.empty:SetText(L["Nothing found"])

local rows = {}
ui.rows = rows
-- Rows slide in from the right (ROW_SHIFT px, with a fade); a row that only
-- gets a new entry moves ROW_NUDGE px and brightens from ROW_DIM
local ROW_TIME, ROW_STAGGER, ROW_SHIFT = 0.18, 0.03, 12
local ROW_NUDGE, ROW_DIM = 5, 0.35

-- Dragging an entry onto the action bars: spells and items are put on the cursor like from the spell book
-- or the bags. A link's list entry stands for its item. (Also used by the detail icon and the menu.)
function ui.Pickup(entry)
    entry = entry and (entry.target or entry)
    if not entry or entry.scope or entry.filter then return end
    if entry.itemID then
        C_Item.PickupItem(entry.itemID)
        return
    end
    local spellID = entry.type == "spell" and entry.value
    if not spellID or C_Spell.IsSpellPassive(spellID) then return end
    C_Spell.PickupSpell(spellID)
end

-- A row: icon, name and a grey line of details on the left; state for you and the reason on the right; the icon
-- shows the count you carry (from 2) and the quality frame. A heading (entry.header) is a narrow gap with its label.
local HEADER_HEIGHT = 22
local HEADING = { 0.75, 0.68, 0.52 } -- a heading's label in the list
local NAME_X = W.NAME_X

local function HoverRow(row)
    S.hovered = true -- the mark shows (no choice for Enter: View.lua, view.Confirm)
    ns.view.Mark(S.top + row.index)
end

-- A row's parts, shared by the list and the detail view's previews (Detail.lua): W.RowParts (icon, quality
-- frame, count, reason symbol, status, name, line below) plus the round mask and the reason's text
function ui.RowParts(row, height)
    W.RowParts(row, height)
    -- an NPC's portrait is round, as the game shows portraits, without the square frame of an action button
    row.round = row:CreateMaskTexture()
    row.round:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask",
        "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    row.round:SetAllPoints(row.icon)
    -- the reason a suggestion has (as text), or a link's info: right, on the line of details, under the state
    row.why = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.why:SetJustifyH("RIGHT")
    row.why:SetWordWrap(false)
    row.why:SetTextColor(W.SUB[1], W.SUB[2], W.SUB[3])
end

local function Row(i)
    local row = rows[i]
    if row then return row end
    row = CreateFrame("Button", nil, list)
    row.index = i
    row:SetHeight(ROW_HEIGHT)
    row.offset = 6 + (i - 1) * ROW_HEIGHT
    row.ease = 1
    ui.RowParts(row, ROW_HEIGHT)
    row.heading = CreateFrame("Frame", nil, row)
    row.heading:SetAllPoints()
    row.heading.label = row.heading:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.heading.label:SetPoint("CENTER", 0, -1)
    row.heading.label:SetTextColor(HEADING[1], HEADING[2], HEADING[3])
    local BRONZE, RULE = W.BRONZE, W.BRONZE_RULE
    local left = ui.Fill(row.heading, "ARTWORK", BRONZE[1], BRONZE[2], BRONZE[3], RULE)
    left:SetHeight(1)
    left:SetPoint("LEFT", 6, -1)
    left:SetPoint("RIGHT", row.heading.label, "LEFT", -10, 0)
    local right = ui.Fill(row.heading, "ARTWORK", BRONZE[1], BRONZE[2], BRONZE[3], RULE)
    right:SetHeight(1)
    right:SetPoint("LEFT", row.heading.label, "RIGHT", 10, 0)
    right:SetPoint("RIGHT", -6, -1)
    row.heading:Hide()
    row:SetScript("OnEnter", function(self)
        if self.entry and self.entry.header then return end
        ui.Hover(self, HoverRow)
    end)
    row:SetScript("OnLeave", ui.Unhover)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetScript("OnClick", function(self, button)
        if GetCursorInfo() then return end
        if self.entry and self.entry.header then return end
        if button == "RightButton" then return ui.ShowMenu(self.entry) end
        ns.view.Mark(S.top + i)
        ns.view.Deeper()
    end)
    row:RegisterForDrag("LeftButton")
    row:SetScript("OnDragStart", function(self)
        if not self.entry.header then ui.Pickup(self.entry) end
    end)
    rows[i] = row
    return row
end

-- icon and subtype of an item, fetched the first time it is shown (entries of a link come without)
function ui.ItemDetails(entry)
    if entry.itemID and not entry.icon then
        local _, _, subType, _, icon = C_Item.GetItemInfoInstant(entry.itemID)
        entry.icon, entry.category = icon, entry.category or subType
    end
end

-- The grey line below a name: what its category says of it (source.describe), else its category; parts joined
-- with dots (W.DOT), the open subcategory left out. A link's list row stands for its target (Links\Common.lua);
-- the link's own info (a drop chance, a count) is its reason, below on the right.
local function Real(entry) return entry.target or entry end
local function FilterSources(filter)
    local names = {}
    for _, key in ipairs(filter.sources or {}) do
        local source = ns.sourceByKey[key]
        if source then names[#names + 1] = source.name end
    end
    return table.concat(names, ", ")
end
-- In a list of mixed kinds (the start page, a search in all, a link's list of quests and items) the line
-- starts with the entry's kind, a little lighter, so that the item type "Quest" is not taken for a quest; in
-- a list of one kind (a category) the tab says it already
local KINDS = { items = L["Item"], npcs = L["NPC"], quests = L["Quest"], spells = L["Spell"],
    professions = L["Recipe"], dungeons = L["Dungeon"] }
local KIND_COLOR = ("|cff%02x%02x%02x"):format(W.LIGHT[1] * 255, W.LIGHT[2] * 255, W.LIGHT[3] * 255)
local function Mixed()
    local first
    for _, entry in ipairs(S.results) do
        local domain = not entry.header and Real(entry).domain
        if domain then
            if first and domain ~= first then return true end
            first = first or domain
        end
    end
    return false
end

local function Describe(entry, linked, mixed)
    local parts
    local real = Real(entry)
    if real.source and real.source.describe then
        parts = real.source.describe(real)
    elseif entry.filter then
        parts = { entry.category, FilterSources(entry.filter) }
    elseif entry.details then
        -- a row with texts of its own (a zone in a link's list, Links\More.lua)
        parts = { entry.details }
    else
        parts = { not linked and entry.category or nil }
    end
    local sub = ns.view.Subcategory()
    local kind = mixed and KINDS[real.domain]
    local text = ""
    for i = 1, 4 do
        local part = parts[i]
        if part and part ~= "" and not (sub and part == sub.name) and part ~= kind then
            text = text == "" and part or text .. DOT .. part
        end
    end
    if kind then text = KIND_COLOR .. kind .. "|r" .. (text ~= "" and (DOT .. text) or "") end
    return text
end

-- Scroll bar for lists longer than the rows shown: a thin track with a bronze thumb; clicking or dragging scrolls,
-- the mouse wheel scrolls the list itself. The mark only moves along when it would leave the shown rows.
local SCROLL_WIDTH = 6
local SCROLL_ROOM = SCROLL_WIDTH + 8 -- what the rows leave free for it
ui.SCROLL_ROOM = SCROLL_ROOM
local TRACK_ALPHA, THUMB, THUMB_MIN = 0.45, { 0.78, 0.62, 0.36, 0.9 }, 16
local scroll = CreateFrame("Frame", nil, list)
scroll:SetWidth(SCROLL_WIDTH + 6)
scroll:SetPoint("TOPRIGHT", -4, -8)
scroll:SetPoint("BOTTOMRIGHT", -4, 8)
scroll:EnableMouse(true)
scroll.track = ui.Fill(scroll, "BACKGROUND", 0, 0, 0, TRACK_ALPHA)
scroll.track:SetWidth(SCROLL_WIDTH)
scroll.track:SetPoint("TOP")
scroll.track:SetPoint("BOTTOM")
scroll.thumb = ui.Fill(scroll, "ARTWORK", THUMB[1], THUMB[2], THUMB[3], THUMB[4])
scroll.thumb:SetWidth(SCROLL_WIDTH)
scroll:Hide()

-- A row in its place: sliding in (row.ease 0-1, see RenderRows), and shown
-- only as far as the growing list reaches it
local function PlaceRow(row)
    local ease = row.ease
    local shift = (row.animFull and ROW_SHIFT or ROW_NUDGE) * (1 - ease)
    local alpha = row.animFull and ease or ROW_DIM + (1 - ROW_DIM) * ease
    local right = scroll:IsShown() and SCROLL_ROOM or 0
    row:SetAlpha(alpha * Clamp((list:GetHeight() - row.offset) / row:GetHeight()))
    row:SetPoint("TOPLEFT", 6 + shift, -row.offset)
    row:SetPoint("TOPRIGHT", -6 + shift - right, -row.offset)
end
local function Slide(row, value)
    row.ease = value
    PlaceRow(row)
end
local sliding = { duration = ROW_TIME, apply = Slide }

-- what scrolls: total, shown at once, first shown (0-based); the overview by lines of cells, the list by rows
local function ScrollState()
    local overview = ui.overview
    if overview and overview:IsShown() then return overview.lines, ui.OVERVIEW_LINES, overview.top end
    return #S.results, ui.Rows(), S.top
end

local function PlaceThumb()
    if not scroll:IsShown() then return end
    local height = scroll:GetHeight()
    local total, visible, top = ScrollState()
    local size = math.max(height * visible / math.max(total, 1), THUMB_MIN)
    local offset = (height - size) * top / math.max(total - visible, 1)
    scroll.thumb:SetHeight(size)
    scroll.thumb:ClearAllPoints()
    scroll.thumb:SetPoint("TOP", scroll.track, "TOP", 0, -offset)
end
ui.PlaceThumb = PlaceThumb

function ui.PlaceRows()
    for _, row in ipairs(rows) do
        if row:IsShown() then PlaceRow(row) end
    end
    PlaceThumb()
end

-- Fills the rows with the shown part of the results. A row that appears slides in, a row that only gets a new
-- entry fades it in briefly. A row still animating keeps going, so fast typing does not cut it short; rows
-- changed at once follow one another. Each entry animates once per list: scrolling back shows seen entries at once.
local seen = {} -- entries of the current results shown already

-- The right side of a row, two lines like the left:
--   state   on the name's line: what it is for you now, a word or a number (source.state: text and tone);
--           a hotkey is no state, the tooltip says it (UI\Tooltip.lua)
--   reason  on the line of details: why a suggestion is listed (the recommendations' reason as text), grey
-- One meaning per place, nothing pushes the other out. Tones (ns.TONES): good (can be done now), active
-- (going on), done (of no use to you), no (not possible yet), plain (a fact: a distance); or a color of its own
-- (a recipe's skill color). The symbol is grey where the tone is done or no.
local TONES = ns.TONES
-- a recipe item of no use right now in a link's list (D.RecipeState); items' own rows: Sources\Items.lua
local RECIPE_STATES = ns.RECIPE_STATES
local function StateOf(entry)
    local real = Real(entry)
    if real.source and real.source.state then return real.source.state(real) end
    if entry.stateText then return entry.stateText, entry.stateTone end -- (a row of its own, a zone)
    local recipe = RECIPE_STATES[entry.recipeState]
    if recipe then return recipe[1], recipe[2] end
    return nil
end

-- A row's texts for an entry, as ui.FillRow shows them (also the detail view's head): the line of details,
-- the state and its color, the reason (opts as ui.FillRow's), and whether it is dimmed
function ui.RowTexts(entry, opts)
    local state, tone = StateOf(entry)
    local color = TONES[tone] or type(tone) == "table" and tone or nil
    local dimmed = tone == "no" or tone == "done" or (type(tone) == "table" and tone.dim == true)
        or (entry.hidden == true and tone ~= "good") or entry.knownRecipe == true
    local why = opts.note or (opts.linked and entry.category ~= "" and entry.category) or nil
    return Describe(entry, opts.linked, opts.mixed), state or "", color, why, dimmed
end

-- A row's content for an entry, the same in the list and in the detail view's previews: icon, name's color,
-- details, state on the right and the reason (or a link's info) below it. The row is one of W.RowParts' with
-- a why font string. opts: linked (a link's list: its info below on the right), mixed (the kind first in the
-- details), note (a suggestion's reason).
function ui.FillRow(row, entry, opts)
    -- an item's data is requested as soon as its row shows, so its tooltip is complete when marked
    if entry.itemID and not C_Item.IsItemDataCachedByID(entry.itemID) then
        C_Item.RequestLoadItemDataByID(entry.itemID)
    end
    if row.entry ~= entry then
        ui.ItemDetails(entry)
        row.entry = entry
        W.ShowIcon(row.icon, entry, ROW_HEIGHT - 10)
        local round = Real(entry).domain == "npcs"
        if round ~= row.isRound then
            if round then row.icon:AddMaskTexture(row.round) else row.icon:RemoveMaskTexture(row.round) end
            row.isRound = round
        end
        row.icon.frame:SetShown(not round)
        local tint = entry.iconColor
        row.icon:SetVertexColor(tint and tint[1] or 1, tint and tint[2] or 1, tint and tint[3] or 1)
        W.ShowQuality(row.quality, entry)
    end
    -- its texts (ui.RowTexts): the state for you (the source's, asked on every draw: it changes with bags,
    -- level, log) and its color; grey when not possible yet, of no use, or not learned and not learnable now
    local details, state, color, why, dimmed = ui.RowTexts(entry, opts)
    row.tone, row.dimmed = color, dimmed
    row.icon:SetDesaturated(row.dimmed)

    local count = entry.itemID and not opts.linked and C_Item.GetItemCount(entry.itemID) or 0
    row.count:SetText(count > 1 and count or "")
    row.count:SetShown(count > 1)
    row.reason:Hide()
    row.reasonText:SetText("")
    row.state = state
    -- below on the right: a suggestion's reason or a link's info ("25 %", "collect 6")
    row.why:SetText(why or "")
    local twoLines = details ~= "" or why ~= nil
    local right = -10
    row.status:ClearAllPoints()
    if twoLines then
        row.status:SetPoint("BOTTOMRIGHT", row, "RIGHT", right, 1)
    else
        row.status:SetPoint("RIGHT", row, "RIGHT", right, 0)
    end
    row.why:ClearAllPoints()
    row.why:SetPoint("TOPRIGHT", row, "RIGHT", right, -3)
    row.sub:SetText(details)
    row.sub:SetPoint("RIGHT", row, "RIGHT", right, 0)
    if why then row.sub:SetPoint("RIGHT", row.why, "LEFT", -12, 0) end
    row.name:ClearAllPoints()
    if twoLines then
        row.name:SetPoint("BOTTOMLEFT", row, "LEFT", NAME_X, 1)
    else
        row.name:SetPoint("LEFT", row, "LEFT", NAME_X, 0)
    end
    row.name:SetPoint("RIGHT", row.status, "LEFT", -12, 0)
end

local rowOpts = {}
function ui.RenderRows()
    local now, changed = GetTime(), 0
    local shown = math.max(math.min(#S.results - S.top, ui.Rows()), 0)
    local offset = 6
    local mixed = Mixed()
    ui.NoteCursor()
    for i = 1, shown do
        local entry = S.results[S.top + i]
        local row = Row(i)
        row.offset = offset
        row:SetHeight(entry.header and HEADER_HEIGHT or ROW_HEIGHT)
        offset = offset + (entry.header and HEADER_HEIGHT or ROW_HEIGHT)
        local appears = not row:IsShown() or not list:IsShown()
        if row.entry ~= entry and seen[entry] and not appears then
            row.animStart = nil -- seen before: at once, without animation
            W.Tween(row, "slide", nil)
            row.ease = 1
        elseif row.entry ~= entry or appears then
            local running = row.animStart and now - row.animStart < ROW_TIME
            if appears or not running then
                row.animStart = now + changed * ROW_STAGGER
                row.animFull = appears or row.animFull and running
                sliding.delay = changed * ROW_STAGGER
                W.Tween(row, "slide", sliding)
                changed = changed + 1
            end
        end
        seen[entry] = true
        local header = entry.header == true
        row.heading:SetShown(header)
        row.parts = row.parts or { row.icon, row.icon.frame, row.name, row.sub, row.status, row.reason,
            row.reasonText, row.why }
        for _, part in ipairs(row.parts) do part:SetShown(not header) end
        row.icon.frame:SetShown(not header and not row.isRound)
        if header then
            row.entry = entry
            row.heading.label:SetText(entry.name)
            row.quality:Hide()
            row.count:Hide()
            row.highlight:Hide()
        else
            rowOpts.linked, rowOpts.mixed = S.linked ~= nil, mixed
            rowOpts.note = not S.linked and ns.index.noted[entry] or nil
            ui.FillRow(row, entry, rowOpts)
        end
        row:Show()
    end
    for i = shown + 1, #rows do rows[i]:Hide() end
    ui.PlaceRows()
    ui.MarkRows()
end

-- The typed part of a name in an accent color: gold on the light names, white on the marked gold one.
local function ColorHex(color)
    return ("ff%02x%02x%02x"):format(color[1] * 255, color[2] * 255, color[3] * 255)
end
local ACCENT, ACCENT_MARKED = ColorHex(W.GOLD), ColorHex(W.WHITE)
local function Highlighted(name, on)
    local typed = ns.SearchKey(S.query)
    local key, map = D.SearchKey(name, true)
    local from, to = key:find(typed, 1, true)
    if typed == "" or not from then return name end
    from, to = map[from], map[to]
    local color = on and ACCENT_MARKED or ACCENT
    return name:sub(1, from - 1) .. "|c" .. color .. name:sub(from, to) .. "|r" .. name:sub(to + 1)
end

-- shows which row is marked: the selection bar, the name in gold; the others light (dimmed: not learned yet),
-- icons a little dimmed
function ui.MarkRows()
    for i, row in ipairs(rows) do
        local entry = row.entry
        local on = S.top + i == S.marked and entry and not entry.header and ui.MarkVisible()
        row.highlight:SetShown(on and true or false)
        if entry and not entry.header then
            -- the name only when entry, text or mark changed: marking runs on every key and hover, and
            -- Highlighted makes two search keys, a map table and four strings per row
            on = on and true or false
            if row.namedEntry ~= entry or row.namedQuery ~= S.query or row.namedOn ~= on then
                row.namedEntry, row.namedQuery, row.namedOn = entry, S.query, on
                row.name:SetText(Highlighted(entry.name, on))
            end
            row.status:SetText(row.state or "")
            W.MarkRow(row, on, row.dimmed)
            local tone = row.tone
            if tone then row.status:SetTextColor(tone[1], tone[2], tone[3]) end
        end
    end
end

local function Scrolls()
    local total, visible = ScrollState()
    return total > visible
end

local function ScrollTo(newTop)
    local total, visible, top = ScrollState()
    newTop = math.min(math.max(newTop, 0), total - visible)
    if newTop == top then return end
    if ui.overview:IsShown() then return ui.ScrollOverview(newTop) end
    S.top = newTop
    ui.RenderRows()
    ui.FitList()
    -- the mark stays inside the shown rows; at an edge a heading there is
    -- passed over inwards
    local first, last = S.top + 1, math.min(S.top + ui.Rows(), #S.results)
    local index, step = S.marked, 1
    if index < first then index, step = first, 1 end
    if index > last then index, step = last, -1 end
    ns.view.Mark(index, step, true)
end

-- dragging: the cursor's place on the track picks the shown part (every frame while held)
local function ScrollToCursor()
    local _, y = GetCursorPosition()
    local total, visible = ScrollState()
    local fraction = (scroll:GetTop() - y / scroll:GetEffectiveScale()) / scroll:GetHeight()
    ScrollTo(math.floor(fraction * (total - visible) + 0.5))
end

scroll:SetScript("OnMouseDown", function(self)
    self:SetScript("OnUpdate", ScrollToCursor)
    ScrollToCursor()
end)
scroll:SetScript("OnMouseUp", function(self) self:SetScript("OnUpdate", nil) end)
scroll:SetScript("OnHide", function(self) self:SetScript("OnUpdate", nil) end)

list:EnableMouseWheel(true)
list:SetScript("OnMouseWheel", function(_, delta)
    if not Scrolls() then return end
    local _, _, top = ScrollState()
    ScrollTo(top - delta)
end)

-- The list's height: it follows its target (W.Follow); rows, the overview's cells and the subcategory tabs
-- show as it reaches them, the filter window beside it is at least as tall.
local function Grow(self, height, arrived)
    self:SetHeight(height)
    ui.PlaceRows()
    ui.FadeCells()
    ui.PlaceTabs()
    ui.FitFilterHeight()
    if arrived then ui.CheckList() end
end

-- The list's height for the rows shown now (a heading is a narrow row, so it changes with scrolling);
-- overviewHeight: the overview's instead
function ui.FitList(overviewHeight)
    if overviewHeight == nil then overviewHeight = list.overviewHeight end
    local rowsHeight = 0
    for i = S.top + 1, math.min(S.top + ui.Rows(), #S.results) do
        rowsHeight = rowsHeight + (S.results[i].header and HEADER_HEIGHT or ROW_HEIGHT)
    end
    list.target = overviewHeight or math.max(rowsHeight, ROW_HEIGHT) + 12
    list.target = math.max(list.target, ui.tabsHeight or 0, ui.filterHeight or 0)
    -- with a background picture always full height, so the picture shows
    if list.artInfo and not overviewHeight then list.target = math.max(list.target, ui.Rows() * ROW_HEIGHT + 12) end
    if list:IsShown() then W.Follow(list, "height", list.target, Grow) end
    ui.CheckList()
end

-- Opening order: the step "list" is done when the list stands at its full height (or the detail view shows)
function ui.CheckList()
    if ui.Since("bar") and not ui.Since("list") and not list.pending
        and (not list:IsShown() or (list.target and math.abs(list.target - (list.height or 0)) < 1)) then
        ui.Finished("list")
    end
end

-- Shows the list for the state (or hides it): rows, empty note, scroll bar, or a category's overview. It
-- grows and shrinks smoothly towards its new height; it starts one row high when it first shows.
function ui.RenderList(show, overviewEntries)
    ui.detail:Hide()
    ui.HideMenu()
    wipe(seen) -- new results: their entries animate again
    ui.RenderRows()
    local overviewHeight = ui.RenderOverview(overviewEntries)
    list.empty:SetShown(show and #S.results == 0 and (not overviewEntries or ui.overview.count == 0))
    -- a category still being built (in the background after logging in) says so, not "nothing found"
    local hint = S.scope and S.query == "" and (ns.index.browsed and ns.index.browseHint
        or #S.filters == 0 and S.scope.emptyHint)
    if not S.scope and not S.linked and S.query == "" and #S.filters == 0 then
        hint = L["Nothing to suggest right now. Type to search."]
    end
    -- text typed and nothing in this category: Enter looks in all
    local elsewhere = S.scope and S.scope.index and ns.view.NothingHere()
        and L["Nothing found in %s. Enter: search in all"]:format(S.scope.name)
    list.empty:SetText(S.scope and not S.scope.index and L["Loading..."] or elsewhere or hint or L["Nothing found"])
    -- while the bar opens, the list waits and then folds open below it (see Bar.lua)
    list.pending = show and not list:IsShown() and not bar.settled or nil
    if list.pending then show = false end
    if show and not list:IsShown() then
        list.height = ROW_HEIGHT + 12
        list:SetHeight(list.height)
    end
    list.overviewHeight = overviewHeight
    list:SetShown(show)
    scroll:SetShown(Scrolls())
    ui.FitList(overviewHeight)
    ui.PlaceRows()
    ui.PlaceTabs()
end
