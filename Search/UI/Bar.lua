local ns = select(2, ...).search
local L = ns.L
local D = ns.data

-- The bar's contents: symbol, back arrow, label, text, hint, cursor, filter tokens and filter button;
-- RenderBar draws it for the state. Opening and closing.

local S = ns.state
local W = ns.widgets
local ui = ns.ui
local bar, tip = ui.bar, ui.tip
local WIDTH = W.WIDTH
local Clamp, EaseOutCubic, EaseOutBack = W.Clamp, W.EaseOutCubic, ns.EaseOutBack

-- the symbol at the left: what kind of view this is (see RenderBar)
bar.symbol = bar:CreateTexture(nil, "ARTWORK")
bar.symbol:SetPoint("LEFT", 20, -1)

-- Back for the mouse: the spell book's page arrow at the left of the bar, where there is a way back (no tooltip)
bar.back = CreateFrame("Button", nil, bar)
bar.back:SetSize(26, 26)
bar.back:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up")
bar.back:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Down")
bar.back:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
bar.back:RegisterForClicks("LeftButtonUp")
bar.back:Hide()
bar.back:SetPoint("LEFT", 10, -1)
bar.back:SetScript("OnClick", function() ns.view.Back() end)

-- The filter button at the bar's right end (the game's dropdown button): a click opens the filter window
-- (Filters.lua). A red × at its corner clears the filters set.
bar.filter = CreateFrame("Button", nil, bar)
bar.filter:SetSize(24, 24)
bar.filter:SetPoint("RIGHT", -16, 0)
bar.filter.icon = bar.filter:CreateTexture(nil, "ARTWORK")
bar.filter.icon:SetAllPoints()
-- the look: the game's dropdown button (as in the world map's quest log), open while the filter window is;
-- the first atlas the client has (atlas names from the tables can be missing at run time)
local BUTTONS = { "common-dropdown-a-button-c60", "common-dropdown-a-button", "map-filter-button" }
local BUTTONS_OPEN = { "common-dropdown-a-button-open-c60", "common-dropdown-a-button-open", "map-filter-button-down" }
local function Funnel(open)
    for _, name in ipairs(open and BUTTONS_OPEN or BUTTONS) do
        if W.Atlas(bar.filter.icon, name) then return end
    end
    if open then return Funnel(false) end
    bar.filter.icon:SetTexture("Interface\\Icons\\INV_Misc_Spyglass_02")
end
Funnel(false)
bar.filter.hover = bar.filter:CreateTexture(nil, "HIGHLIGHT")
bar.filter.hover:SetAllPoints()
if not (W.Atlas(bar.filter.hover, "common-dropdown-a-button-hover-c60")
        or W.Atlas(bar.filter.hover, "common-dropdown-a-button-hover")) then
    bar.filter.hover:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
    bar.filter.hover:SetBlendMode("ADD")
end
-- red × at its corner while filters are set (as on the game's filter dropdowns): a click clears them; a subcategory stays
bar.filter.reset = CreateFrame("Button", nil, bar.filter)
bar.filter.reset:SetSize(18, 18)
bar.filter.reset:SetPoint("CENTER", bar.filter, "TOPRIGHT", -1, -1)
bar.filter.reset:SetFrameLevel(bar.filter:GetFrameLevel() + 2)
bar.filter.reset.icon = bar.filter.reset:CreateTexture(nil, "ARTWORK")
bar.filter.reset.icon:SetAllPoints()
if not W.Atlas(bar.filter.reset.icon, "auctionhouse-ui-filter-redx") then
    bar.filter.reset.icon:SetTexture("Interface\\Buttons\\UI-StopButton")
end
-- hovering lights the × itself up (a square glow drew a blue frame)
local RESET_GLOW = 0.5
bar.filter.reset.glow = bar.filter.reset:CreateTexture(nil, "HIGHLIGHT")
bar.filter.reset.glow:SetAllPoints()
if W.Atlas(bar.filter.reset.glow, "auctionhouse-ui-filter-redx") then
    bar.filter.reset.glow:SetBlendMode("ADD")
    bar.filter.reset.glow:SetAlpha(RESET_GLOW)
end
bar.filter.reset:SetScript("OnClick", function() ns.view.ClearFilters() end)
bar.filter.reset:Hide()

bar.filter:SetScript("OnClick", function()
    ui.filterOpen = not ui.filterOpen
    -- everything again: the list grows with the window; the tooltip stays and slides aside (Tooltip.lua ui.MoveTip)
    ns.view.Refresh({ marked = S.marked, top = S.top })
end)
bar.filter:SetScript("OnEnter", function(self) W.ControlTip(tip, self, "ANCHOR_BOTTOM", L["Filter"]) end)
bar.filter:SetScript("OnLeave", function() tip:Hide() end)

-- The × that empties the text, as the game's search boxes have it: category and filters stay, the keyboard
-- goes to the bar. Shown while there is text (RenderBar).
bar.clear = CreateFrame("Button", nil, bar)
bar.clear:SetSize(16, 16)
bar.clear:SetNormalTexture("Interface\\FriendsFrame\\ClearBroadcastIcon")
bar.clear:GetNormalTexture():SetAlpha(0.6)
bar.clear:SetHighlightTexture("Interface\\FriendsFrame\\ClearBroadcastIcon", "ADD")
bar.clear:RegisterForClicks("LeftButtonUp")
bar.clear:Hide()
bar.clear:SetScript("OnClick", function()
    S.query = ""
    ns.view.Refresh()
    ns.input.Focus()
end)
bar.clear:SetScript("OnEnter", function(self) W.ControlTip(tip, self, "ANCHOR_BOTTOM", L["Clear"]) end)
bar.clear:SetScript("OnLeave", function() tip:Hide() end)

bar.label = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
bar.label:SetPoint("LEFT", bar.symbol, "RIGHT", 10, 1)
bar.label:SetWordWrap(false)
local LABEL_ROOM = WIDTH - 80 -- a longer label is cut off with "..."

bar.text = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
bar.text:SetJustifyH("LEFT")

bar.hint = bar:CreateFontString(nil, "OVERLAY", "GameFontDisableLarge")
-- a little right of where the text starts: the cursor stands there (else it cut into the first letter)
bar.hint:SetPoint("LEFT", bar.text, "LEFT", 6, 0)
bar.hint:SetTextColor(W.PLACEHOLDER[1], W.PLACEHOLDER[2], W.PLACEHOLDER[3])

-- the blinking cursor after the text: shown BLINK_ON of every second, by a timer while wanted (not per frame)
local CURSOR_ALPHA = 0.9
local BLINK_ON = 0.55
bar.cursor = ui.Fill(bar, "OVERLAY", W.WHITE[1], W.WHITE[2], W.WHITE[3], CURSOR_ALPHA)
bar.cursor:SetSize(2, 20)
bar.cursor:SetPoint("LEFT", bar.text, "RIGHT", 1, 0)
bar.cursor:Hide()
local blinking = false
local function Blink()
    if not bar:IsShown() or not bar.cursorWanted then
        blinking = false
        bar.cursor:Hide()
        return
    end
    local phase = GetTime() % 1
    local on = phase < BLINK_ON
    bar.cursor:SetShown(on)
    C_Timer.After((on and BLINK_ON or 1) - phase, Blink)
end
-- the cursor blinks once the bar is half open, not in a detail view (no text there) and not without the keyboard
local function WantCursor()
    bar.cursorWanted = bar.halfOpen and not S.detail and not S.unfocused
    if not bar.cursorWanted then
        bar.cursor:Hide()
    elseif not blinking then
        blinking = true
        Blink()
    end
end

-- Filter tokens: small framed labels between the label and the text, one per set filter, in the filter's colour; a click removes one.
local TOKEN_HEIGHT, TOKEN_PAD = 22, 16
local TOKEN_GROUND = { 0.12, 0.09, 0.05, 0.85 }
local tokens = {}

local function Token(i)
    local token = tokens[i]
    if token then return token end
    token = CreateFrame("Button", nil, bar)
    token:SetHeight(TOKEN_HEIGHT)
    token.bg = ui.Fill(token, "BACKGROUND", TOKEN_GROUND[1], TOKEN_GROUND[2], TOKEN_GROUND[3], TOKEN_GROUND[4])
    token.bg:SetAllPoints()
    ui.Border(token, "BORDER")
    token.text = token:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    token.text:SetPoint("CENTER", 0, 0)
    token:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    token:RegisterForClicks("LeftButtonUp")
    token:SetScript("OnClick", function(self) ns.view.RemoveFilter(self.index) end)
    tokens[i] = token
    return token
end

-- places the tokens after anchor (a subcategory is no token: its tab shows it); returns what the text follows
local function PlaceTokens(anchor, show)
    local count = 0
    for i, f in ipairs(show and S.filters or {}) do
        if not f.subcategory then
            count = count + 1
            local token = Token(count)
            token.index = i
            token.text:SetText(ui.ColoredName(f))
            token:SetWidth(token.text:GetStringWidth() + TOKEN_PAD)
            token:ClearAllPoints()
            token:SetPoint("LEFT", anchor, "RIGHT", count == 1 and 10 or 6, 0)
            token:Show()
            anchor = token
        end
    end
    for i = count + 1, #tokens do tokens[i]:Hide() end
    return anchor, count > 0
end

-- Draws the bar for the state: the symbol (lens for every search, also in a category; "i" for a detail view,
-- the link's icon for a link's list), label, text, hint, tabs. The detail view is no search: its entry's name
-- (an item in its quality colour and with its English name), no text, no cursor.
local ENGLISH = "|cff9d9d9d" -- an English name in brackets: the game's grey
function ui.RenderBar()
    local symbol, isIcon = "Interface\\Common\\UI-Searchbox-Icon", false
    local label = ""
    if S.detail then
        symbol = "Interface\\FriendsFrame\\InformationIcon"
        local entry = S.detail
        label = entry.name
        if entry.itemID then
            local quality = C_Item.GetItemQualityByID(entry.itemID)
            local hex = quality and select(4, C_Item.GetItemQualityColor(quality))
            if hex then label = "|c" .. hex .. label .. "|r" end
            local english = D.NameEN("item", entry.itemID)
            if english and english ~= entry.name then label = label .. " " .. ENGLISH .. "(" .. english .. ")|r" end
        elseif entry.npcID then
            local english = D.NameEN("npc", entry.npcID)
            if english and english ~= entry.name then label = label .. " " .. ENGLISH .. "(" .. english .. ")|r" end
        end
    elseif S.linked then
        symbol, isIcon = S.linked.link.icon, true
        label = S.linked.link.title:format("|cffffffff" .. S.linked.entry.name .. "|r")
    end
    -- searching in a category: no label; the lit tabs are the path and the hint names where the search
    -- looks ("Search in Arms"); a path in the bar doubled the tabs
    bar.symbol:SetTexture(symbol)
    bar.symbol:SetTexCoord(isIcon and 0.08 or 0, isIcon and 0.92 or 1, isIcon and 0.08 or 0, isIcon and 0.92 or 1)
    local size = (isIcon or S.detail) and 18 or 16
    bar.symbol:SetSize(size, size)
    local shade = (isIcon or S.detail) and 1 or 0.9
    bar.symbol:SetVertexColor(shade, shade, shade)

    bar.label:SetText(label)
    bar.label:SetWidth(0)
    if bar.label:GetStringWidth() > LABEL_ROOM then bar.label:SetWidth(LABEL_ROOM) end
    bar.text:ClearAllPoints()
    -- the search's filter tokens after the label (not in detail views and lists)
    local anchor, hasTokens = PlaceTokens(label ~= "" and bar.label or bar.symbol, not S.detail and not S.linked)
    if hasTokens then
        bar.text:SetPoint("LEFT", anchor, "RIGHT", 8, 0)
    elseif label ~= "" then
        bar.text:SetPoint("LEFT", bar.label, "RIGHT", 8, 0)
    else
        bar.text:SetPoint("LEFT", bar.symbol, "RIGHT", 10, 1)
    end
    bar.text:SetText(S.detail and "" or S.query:gsub("|", "||"))
    local deepest = ns.view.Subcategory() or S.scope
    if S.scope then
        bar.hint:SetText(L["Search in %s"]:format(deepest.name))
    else
        bar.hint:SetText(hasTokens and L["Type a name"] or L["Search everything"])
    end
    local empty = S.query == "" and not S.linked and not S.detail
    -- without the keyboard: the hint says how to get it back, also over a detail view or a list; the typed text dims
    if S.unfocused then
        bar.hint:SetText(L["Click here to type"])
        bar.hint:SetShown(S.query == "")
        bar.text:SetAlpha(0.5)
        bar.label:SetAlpha(0.6)
    else
        bar.hint:SetShown(empty)
        bar.text:SetAlpha(1)
        bar.label:SetAlpha(1)
    end
    WantCursor()

    -- the filter button where filters fit (not in detail views and lists), with the red × while filters are set
    local fits, count = false, 0
    if not S.detail and not S.linked then
        for _, f in ipairs(ns.filters) do
            if not f.subcategory and (not S.scope or ns.filter.AppliesTo(f, S.scope)) then fits = true end
        end
        for _, f in ipairs(S.filters) do
            if not f.subcategory then count = count + 1 end
        end
    end
    bar.filter:SetShown(fits)
    -- (not while the bar opens: it comes with the list)
    ui.RenderFilterPanel(ui.filterOpen and fits and not S.detail and not S.linked and bar.settled)
    bar.filter.reset:SetShown(count > 0)
    bar.clear:ClearAllPoints()
    if fits then bar.clear:SetPoint("RIGHT", bar.filter, "LEFT", -8, 0) else bar.clear:SetPoint("RIGHT", -18, 0) end
    bar.clear:SetShown(S.query ~= "" and not S.detail and not S.linked)
    Funnel(ui.filterOpen and fits)

    local canBack = #S.history > 0 or not empty or S.scope ~= nil or #S.filters > 0
    bar.back:SetShown(canBack)
    bar.symbol:ClearAllPoints()
    if canBack then
        bar.symbol:SetPoint("LEFT", bar.back, "RIGHT", 4, 0)
    else
        bar.symbol:SetPoint("LEFT", 20, -1)
    end

    ui.PlaceChips()
    ui.ShowSubTabs()
    local sub = ns.view.Subcategory()
    ui.SetArt(sub and sub.background)
end

-- Opening and closing
-- Opening: the bar pops in from the middle, stretching from 70 % of its width with a little overshoot while
-- it fades in; symbol and text follow a moment later; the category tabs rise one after another (Tabs.lua).
-- Rows slide in from the right (List.lua) and stay hidden until the growing list reaches them. Closing: a quick fade.
local OPEN_TIME, CONTENT_DELAY, OPEN_FROM = 0.3, 0.08, 0.7
local BAR_TOP = 0.22 -- its resting place: this share of the screen below the top
local CONTENT = { bar.symbol, bar.label, bar.text, bar.hint }

local function PlaceBar(width)
    bar:ClearAllPoints()
    bar:SetPoint("TOP", UIParent, "TOP", 0, S.barTop)
    bar:SetWidth(width)
end

-- the bar stands: the list folds open from nothing, the filter window comes (Base.lua opening order)
local function Settle()
    bar.settled = true
    ui.Finished("bar")
    local list = ui.list
    if list.pending then
        list.pending = nil
        list.height = 1
        list:SetHeight(1)
        list:Show()
        ui.RenderBar()
        ui.ShowTooltip(S.results[S.marked])
        ui.FitList()
        ui.PlaceRows()
    end
    ui.CheckList()
end

local function Grow(_, p)
    bar:SetAlpha(EaseOutCubic(Clamp(p * 2)))
    PlaceBar(WIDTH * (OPEN_FROM + (1 - OPEN_FROM) * EaseOutBack(p)))
    local content = EaseOutCubic(Clamp((p * OPEN_TIME - CONTENT_DELAY) / (OPEN_TIME - CONTENT_DELAY)))
    for _, part in ipairs(CONTENT) do part:SetAlpha(content) end
    if p >= 0.5 and not bar.halfOpen then
        bar.halfOpen = true
        WantCursor()
    end
end
local opening = { duration = OPEN_TIME, ease = false, apply = Grow, done = Settle }
local closing = { duration = W.CLOSE_TIME,
    apply = function(_, value) bar:SetAlpha(1 - value) end,
    done = function()
        S.closingAt = nil
        bar:Hide()
    end,
}

function ui.StartOpening()
    S.barTop = -UIParent:GetHeight() * BAR_TOP
    S.openedAt, S.closingAt, bar.settled, bar.halfOpen = GetTime(), nil, false, false
    -- the windows below start hidden, so the list folds open again after the bar (hiding the bar left them
    -- shown inside it, so only the first opening did)
    ui.list:Hide()
    ui.list.pending = nil
    ui.detail:Hide()
    ui.ResetFilterPanel()
    ui.RestartOrder()
    ui.Finished("start")
    -- the filter window starts as the option says (closed by default); the tooltip starts where it will stand
    ui.filterOpen = ns.db and ns.db.filtersOpen == true
    ui.filterWanted = false
    ui.MoveTip(true)
    ui.RaiseChips()
    W.Tween(bar, "open", opening)
    WantCursor()
    bar:Show()
end

function ui.StartClosing(instantly)
    tip:Hide()
    if instantly then
        S.closingAt = nil
        W.Tween(bar, "open", nil)
        bar:Hide()
    else
        S.closingAt = GetTime()
        PlaceBar(WIDTH)
        W.Tween(bar, "open", closing)
    end
end
