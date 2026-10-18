-- Pylos Kit 1.0.0 (copied from pylos-dev\shared; do not edit here)
local addonName, ns = ...

-- Settings, saved data, minimap button and slash command of one Pylos addon, built from
-- its ns.options at its ADDON_LOADED. Every addon carries its own copy: no global, nothing
-- shared with other addons at run time.
--
-- ns.options = {
--     savedVariable = "MyAddonDB",          -- name from the TOC
--     title = "My Addon",                   -- optional display name, default addonName
--     intro = "One sentence what the addon does.",
--     icon = "Interface\\Icons\\...",       -- minimap button
--     slash = "/myaddon",                   -- opens the options
--     slashLeftClick = true,                -- optional: "/myaddon" acts like a left-click,
--                                           -- "/myaddon options" opens the options, else help
--     defaults = { list = {} },             -- optional stored values without a menu entry
--     schema = { version = 2, migrations = { [2] = function(db) end } }, -- optional (ns.kit.Saved)
--     onLoad = function(db) end,            -- optional, after the menu is built
--     onLeftClick = function() end,         -- optional, replaces the master toggle
--     leftClickText = "...",                -- tooltip line for onLeftClick
--     onMiddleClick = function() end,       -- optional: middle-click on the minimap button
--     middleClickText = "...",              -- tooltip line for onMiddleClick
--     onTooltip = function(tooltip) end,    -- optional extra lines in the button tooltip
--     alertDims = true,                     -- optional: icon gray while there is no alert (ns.SetAlert)
--     { type = "checkbox", key = "enabled", label = "...", default = true,
--       master = true, toggleText = "..." }, -- master switch
--     { type = "header", label = "..." },
--     { type = "checkbox", key = "...", label = "...", default = false, tooltip = "..." },
--     { type = "dropdown", key = "...", label = "...", default = "a",
--       values = { { "a", "Text A" }, { "b", "Text B" } } },
--     { type = "color", key = "...", label = "...", default = "lightgray" },
--     { type = "modifier", key = "...", label = "...", default = "none" },
--     { type = "slider", key = "...", label = "...", default = 100, min = 50, max = 150,
--       step = 5, format = function(value) return value .. "%" end },
--     { type = "button", label = "...", text = "Button text", func = function() end, tooltip = "..." },
--     { type = "keybinding", command = "MYADDON_ACTION" }, -- key from Bindings.xml
--     { type = "minimap" },                 -- "Show minimap button"
--     { type = "text", text = "...", height = 24 }, -- plain string, height in pixels (default 24)
--     { type = "page", label = "...", init = function(frame) end }, -- own subpage
-- }
-- A row of any other type is left out and named in chat.
-- keybinding: a button that takes the next key pressed for a command from the
-- addon's Bindings.xml (right-click unbinds); the label is the command's BINDING_NAME_ text.
-- page: a subpage below the addon for content too tall for a row. init(frame) runs on
-- every show; frame is the area below the page title.
-- Entries with a key, and minimap, may have onChange = function(value) end.
-- dependsOn = "otherKey", enabledWhen = value: grayed out unless that option has
-- that value. enabledIf = function() -> bool: grayed out while false.
-- visibleWhen = { "otherKey", value } (any entry): listed only while that option has that value.
-- The master switch is also toggled by left-clicking the minimap button
-- (toggleText is used in the chat line and tooltip); all other options except
-- minimap are grayed out while it is off.
--
-- Set on ns: L (texts), kit = { version, Saved, NewLocale }; once the options are built
-- db, minimapButton (.icon), SetOption(key, value), GetColor(key), IsModifierHeld(key),
-- SetAlert(on). A field the addon set itself is kept (db excepted). ns.off set by the
-- addon before its ADDON_LOADED: nothing is built.
--
-- Page layout: intro; general switches without header (master first, minimap
-- last); "Display"; further sections. A section needs at least three entries.
--
-- Saved keys no option names any more are kept; only a schema migration removes them.
--
-- Every page is a canvas page with its own controls, not a page of Blizzard's settings
-- list: that list is shared by all pages, and Blizzard's Audio page calls a restricted
-- function in it (C_Discord.IsUserOAuthed), so any trace an addon page leaves there gets
-- the addon blamed for a blocked action.

local VERSION = "1.0.0"
local CHAT_NAME = "|cffffd100%s|r"

-- rawget: an ns may have an __index
local function Offer(key, value)
    if rawget(ns, key) == nil then ns[key] = value end
end

-- Texts: English, each its own key

local function NewLocale()
    return setmetatable({}, { __index = function(_, key) return key end })
end
Offer("L", NewLocale())
local L = ns.L

-- Saved data

local function Copy(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for k, v in pairs(value) do copy[k] = Copy(v) end
    return copy
end

-- Sets up the SavedVariable `name` (call in or after the addon's ADDON_LOADED) and returns it.
--   spec.defaults    key -> value, put in where the key is nil (tables copied)
--   spec.version     current data shape (number, default 1)
--   spec.migrations  [n] = function(db): brings shape n - 1 to n
-- db._schema holds the stored shape: a new table starts at spec.version, one from
-- before shapes were counted is 0. Newer-shape data is left as is, unknown keys are kept.
local function Saved(name, spec)
    spec = spec or {}
    local version = spec.version or 1
    local db = _G[name]
    if type(db) ~= "table" then
        db = { _schema = version }
        _G[name] = db
    end
    local from = tonumber(db._schema) or 0
    if from < version then
        for n = from + 1, version do
            local migrate = spec.migrations and spec.migrations[n]
            if migrate then migrate(db) end
            db._schema = n -- if a later migration fails, this one does not run again
        end
    end
    for key, value in pairs(spec.defaults or {}) do
        if db[key] == nil then db[key] = Copy(value) end
    end
    return db
end

Offer("kit", { version = VERSION, Saved = Saved, NewLocale = NewLocale })

local function Problem(text)
    print(CHAT_NAME:format(ns.options and ns.options.title or addonName) .. ": " .. text)
end

-- Colors

-- key, menu label, r, g, b; the order is the order in the dropdown
local COLOR_LIST = {
    { "gray", "Gray", 0.62, 0.62, 0.62 },
    { "lightgray", "Light gray", 0.8, 0.8, 0.8 },
    { "white", "White", 1, 1, 1 },
    { "yellow", "Yellow", 1, 0.82, 0 },
    { "orange", "Orange", 1, 0.6, 0.2 },
    { "red", "Red", 1, 0.4, 0.4 },
    { "pink", "Pink", 1, 0.6, 0.8 },
    { "purple", "Purple", 0.75, 0.55, 1 },
    { "blue", "Light blue", 0.5, 0.8, 1 },
    { "turquoise", "Turquoise", 0.3, 0.9, 0.8 },
    { "green", "Green", 0.4, 1, 0.4 },
}
local COLORS = {} -- key -> { r, g, b }
for _, entry in ipairs(COLOR_LIST) do
    COLORS[entry[1]] = { entry[3], entry[4], entry[5] }
end

local function GetColor(key)
    return COLORS[key] or COLORS.white
end

local function ColorCode(key)
    local color = GetColor(key)
    return ("|cff%02x%02x%02x"):format(color[1] * 255, color[2] * 255, color[3] * 255)
end

local MODIFIERS = { shift = IsShiftKeyDown, ctrl = IsControlKeyDown, alt = IsAltKeyDown }

-- true if the chosen "modifier" key is held (always for "none")
local function IsModifierHeld(key)
    local isHeld = MODIFIERS[key]
    return not isHeld or isHeld()
end

local PRESETS = {
    color = function()
        local values = {}
        for i, entry in ipairs(COLOR_LIST) do
            values[i] = { entry[1], ColorCode(entry[1]) .. L[entry[2]] .. "|r" } -- label in its color
        end
        return values
    end,
    modifier = function()
        return { { "none", L["Always"] }, { "shift", L["Only with Shift"] }, { "ctrl", L["Only with Ctrl"] }, { "alt", L["Only with Alt"] } }
    end,
}

local TYPES = { checkbox = true, minimap = true, header = true, text = true, button = true, page = true,
    keybinding = true, slider = true, dropdown = true, color = true, modifier = true }

local LABEL_X = 37
local ROW_HEIGHT = 32

-- Pages

-- A page: its title on top, rows from top to bottom in a scroll area. page.Layout places the
-- rows that are listed, refreshes them and runs on every show and option change.
local function NewPage(title)
    local panel = CreateFrame("Frame")
    local heading = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightHuge")
    heading:SetPoint("TOPLEFT", 7, -22)
    heading:SetText(title)
    local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 0, -56)
    scroll:SetPoint("BOTTOMRIGHT", -30, 10)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1)
    scroll:SetScrollChild(content)

    local page = { panel = panel, content = content, rows = {} }
    function page.Layout()
        content:SetWidth(scroll:GetWidth())
        local y = 0
        for _, row in ipairs(page.rows) do
            local shown = not row.visible or row.visible()
            row.frame:SetShown(shown)
            if shown then
                row.frame:ClearAllPoints()
                row.frame:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
                row.frame:SetPoint("RIGHT", content, "RIGHT")
                row.frame:SetHeight(row.height)
                if row.refresh then row.refresh() end
                y = y + row.height
            end
        end
        content:SetHeight(math.max(y, 1))
    end
    -- Blizzard calls OnRefresh on every display; OnShow misses the first one right after another
    -- canvas page (a frame without parent already counts as shown)
    panel.OnRefresh = page.Layout
    return page
end

-- a row of the page, with a label on its left if one is given
local function AddPageRow(page, height, label)
    local frame = CreateFrame("Frame", nil, page.content)
    local row = { frame = frame, height = height }
    if label then
        row.label = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        row.label:SetPoint("LEFT", LABEL_X, 0)
        row.label:SetPoint("RIGHT", frame, "CENTER", -90, 0)
        row.label:SetJustifyH("LEFT")
        row.label:SetText(label)
    end
    page.rows[#page.rows + 1] = row
    return row
end

-- color: optional color key; height in pixels
local function AddTextRow(page, height, text, color)
    local row = AddPageRow(page, height)
    local fontString = row.frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    fontString:SetPoint("TOPLEFT", LABEL_X, -4)
    fontString:SetPoint("TOPRIGHT", -20, -4) -- full row width, wraps only when needed
    fontString:SetJustifyH("LEFT")
    local rgb = color and GetColor(color) or { 1, 1, 1 }
    fontString:SetTextColor(rgb[1], rgb[2], rgb[3])
    fontString:SetText(text)
    row.text = fontString
    return row
end

-- tooltip on the row and its control
local function AddTooltip(row, title, text)
    local function Show(owner)
        GameTooltip:SetOwner(owner, "ANCHOR_TOPLEFT")
        GameTooltip:SetText(title)
        GameTooltip:AddLine(text, 1, 1, 1, true)
        GameTooltip:Show()
    end
    row.frame:EnableMouse(true)
    for _, frame in ipairs({ row.frame, row.control }) do
        frame:HookScript("OnEnter", Show)
        frame:HookScript("OnLeave", GameTooltip_Hide)
    end
end

-- a button that binds the next key pressed to command; right-click unbinds
local function KeyBindingButton(row, command)
    local button = CreateFrame("Button", nil, row.frame, "UIPanelButtonTemplate")
    local function Show()
        local key = GetBindingKey(command)
        button:SetText(key and GetBindingText(key) or L["Not bound"])
    end
    local function Unbind()
        local key = GetBindingKey(command)
        while key do
            SetBinding(key)
            key = GetBindingKey(command)
        end
    end
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:SetScript("OnClick", function(self, mouseButton)
        if InCombatLockdown() then return end -- bindings change only out of combat
        if mouseButton == "RightButton" then
            Unbind()
            SaveBindings(GetCurrentBindingSet())
            Show()
        else
            self:SetText(L["Press a key (Esc: cancel)"])
            self:EnableKeyboard(true)
        end
    end)
    button:SetScript("OnKeyDown", function(self, key)
        if IsMetaKey(key) then return end -- Shift, Ctrl, Alt: wait for the key they go with
        self:EnableKeyboard(false)
        if key ~= "ESCAPE" and not InCombatLockdown() then
            Unbind()
            SetBinding(CreateKeyChordStringUsingMetaKeyState(key), command)
            SaveBindings(GetCurrentBindingSet())
        end
        Show()
    end)
    button:SetScript("OnHide", function(self) self:EnableKeyboard(false) end)
    return button, Show
end

local function Build()
    Offer("GetColor", GetColor)
    Offer("IsModifierHeld", IsModifierHeld)
    local options -- ns.options
    local entries = {} -- the entries of ns.options of a known type
    local db
    local category
    local page
    local minimapButton
    local master -- entry of the master switch, if any
    local title -- display name
    local changeHandlers = {} -- key -> list of handlers, called with the new value

    local function OpenOptions()
        Settings.OpenToCategory(category:GetID())
    end

    -- Changes an option the way the menu would: its handlers run and the page follows
    local function SetOption(key, value)
        db[key] = value
        for _, handler in ipairs(changeHandlers[key] or {}) do handler(value) end
        if page then page.Layout() end
    end
    Offer("SetOption", SetOption)

    local function OnChange(key, handler)
        changeHandlers[key] = changeHandlers[key] or {}
        table.insert(changeHandlers[key], handler)
    end

    local alert = false -- ns.SetAlert's state; kept while the button is hidden
    local alertFrame

    local function UpdateButtonState()
        -- gray while the master switch is off, with alertDims also while no alert
        if master or options.alertDims then
            local off = master and not db[master.key]
            local idle = options.alertDims and not alert
            minimapButton.icon:SetDesaturated(off or idle or false)
        end
    end

    -- on a hidden button only the state changes (the alert frame is its child)
    local function SetAlert(on)
        alert = on and true or false
        alertFrame:SetShown(alert)
        UpdateButtonState()
    end

    local function LeftClick()
        if options.onLeftClick then
            options.onLeftClick()
        elseif master then
            SetOption(master.key, not db[master.key])
            print(L[db[master.key] and "%s: %s on" or "%s: %s off"]:format(CHAT_NAME:format(title), master.toggleText))
        else
            OpenOptions()
        end
    end

    local function CreateMinimapButton()
        local button = CreateFrame("Button", addonName .. "MinimapButton", Minimap)
        button:SetSize(31, 31)
        button:SetFrameStrata("MEDIUM")
        button:SetFrameLevel(8)
        button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

        local background = button:CreateTexture(nil, "BACKGROUND")
        background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
        background:SetSize(24, 24)
        background:SetPoint("CENTER", 0, 1)

        local icon = button:CreateTexture(nil, "ARTWORK")
        icon:SetTexture(options.icon)
        icon:SetSize(18, 18)
        icon:SetPoint("CENTER", 0, 1)
        button.icon = icon

        local border = button:CreateTexture(nil, "OVERLAY")
        border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
        border:SetSize(50, 50)
        border:SetPoint("TOPLEFT")

        -- alert: highlight ring plus additive copy of the border, pulsing
        alertFrame = CreateFrame("Frame", nil, button)
        alertFrame:SetAllPoints()
        local ring = alertFrame:CreateTexture(nil, "OVERLAY")
        ring:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
        ring:SetBlendMode("ADD")
        ring:SetAllPoints()
        local rim = alertFrame:CreateTexture(nil, "OVERLAY")
        rim:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
        rim:SetBlendMode("ADD")
        rim:SetSize(50, 50)
        rim:SetPoint("TOPLEFT")
        local pulse = alertFrame:CreateAnimationGroup()
        pulse:SetLooping("BOUNCE")
        local fade = pulse:CreateAnimation("Alpha")
        fade:SetFromAlpha(0.15)
        fade:SetToAlpha(1)
        fade:SetDuration(0.6)
        fade:SetSmoothing("IN_OUT")
        -- OnShow, not SetAlert: the animation would stop after the minimap was hidden
        alertFrame:SetScript("OnShow", function() pulse:Play() end)
        alertFrame:SetScript("OnHide", function() pulse:Stop() end)
        alertFrame:Hide()

        local function UpdatePosition()
            local angle = math.rad(db.minimapAngle)
            local radius = Minimap:GetWidth() / 2 + 5
            button:ClearAllPoints()
            button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
        end

        button:RegisterForDrag("LeftButton")
        button:SetScript("OnDragStart", function(self)
            self:SetScript("OnUpdate", function()
                local centerX, centerY = Minimap:GetCenter()
                local cursorX, cursorY = GetCursorPosition()
                local scale = Minimap:GetEffectiveScale()
                db.minimapAngle = math.deg(math.atan2(cursorY / scale - centerY, cursorX / scale - centerX))
                UpdatePosition()
            end)
        end)
        button:SetScript("OnDragStop", function(self)
            self:SetScript("OnUpdate", nil)
        end)

        button:RegisterForClicks("LeftButtonUp", "RightButtonUp", "MiddleButtonUp")
        button:SetScript("OnClick", function(_, mouseButton)
            if mouseButton == "RightButton" then
                OpenOptions()
            elseif mouseButton == "MiddleButton" then
                if options.onMiddleClick then options.onMiddleClick() end
            else
                LeftClick()
            end
        end)
        button:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:SetText(title)
            if options.onTooltip then options.onTooltip(GameTooltip) end
            local leftClick = options.leftClickText or (master and L["%s on/off"]:format(master.toggleText))
            if leftClick then
                GameTooltip:AddLine(L["Left-click: %s"]:format(leftClick), 1, 1, 1)
            end
            GameTooltip:AddLine(L["Right-click: options"], 1, 1, 1)
            if options.onMiddleClick and options.middleClickText then
                GameTooltip:AddLine(L["Middle-click: %s"]:format(options.middleClickText), 1, 1, 1)
            end
            GameTooltip:AddLine(L["Drag: move button"], 1, 1, 1)
            GameTooltip:Show()
        end)
        button:SetScript("OnLeave", GameTooltip_Hide)

        minimapButton = button
        Offer("minimapButton", button)
        Offer("SetAlert", SetAlert)
        UpdatePosition()
        UpdateButtonState()
        button:SetShown(db.minimap)
    end

    local function AddPage(entry)
        local panel = CreateFrame("Frame")
        local heading = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightHuge")
        heading:SetPoint("TOPLEFT", 7, -22)
        heading:SetText(entry.label)
        local content = CreateFrame("Frame", nil, panel)
        content:SetPoint("TOPLEFT", 0, -56)
        content:SetPoint("BOTTOMRIGHT")
        -- Blizzard also refreshes every canvas when the window opens; only the shown one has a parent
        panel.OnRefresh = function() if panel:GetParent() then entry.init(content) end end
        Settings.RegisterCanvasLayoutSubcategory(category, panel, entry.label)
    end

    -- grayed out: by enabledIf, by the option it depends on, or (after the master switch) by
    -- the master switch; the master switch and minimap only by enabledIf
    local function EnabledTest(entry, afterMaster)
        return function()
            if entry.enabledIf and not entry.enabledIf() then return false end
            if entry.dependsOn then
                return (not master or db[master.key]) and db[entry.dependsOn] == entry.enabledWhen
            end
            return not afterMaster or db[master.key]
        end
    end

    -- one row of a known type (page: a subpage, no row); returns the row
    local function AddEntry(entry)
        local kind = entry.type
        local row
        if kind == "header" then
            row = AddPageRow(page, 45)
            local text = row.frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightLarge")
            text:SetPoint("BOTTOMLEFT", 7, 8)
            text:SetText(entry.label)
        elseif kind == "text" then
            row = AddTextRow(page, entry.height or 24, entry.text)
        elseif kind == "page" then
            AddPage(entry)
        elseif kind == "checkbox" or kind == "minimap" then
            local key = entry.key or "minimap"
            row = AddPageRow(page, ROW_HEIGHT, kind == "minimap" and L["Show minimap button"] or entry.label)
            local box = CreateFrame("CheckButton", nil, row.frame, "SettingsCheckboxTemplate")
            box:SetPoint("LEFT", row.frame, "CENTER", -80, 0)
            box:SetScript("OnClick", function(self) SetOption(key, self:GetChecked() and true or false) end)
            row.control = box
            row.refresh = function() box:SetChecked(db[key] and true or false) end
        elseif kind == "dropdown" or PRESETS[kind] then -- color and modifier: dropdowns with ready values
            local values = PRESETS[kind] and PRESETS[kind]() or entry.values
            row = AddPageRow(page, ROW_HEIGHT, entry.label)
            local dropdown = CreateFrame("DropdownButton", nil, row.frame, "WowStyle1DropdownTemplate")
            dropdown:SetPoint("LEFT", row.frame, "CENTER", -80, 0)
            dropdown:SetWidth(200)
            dropdown:SetupMenu(function(_, root)
                for _, value in ipairs(values) do
                    root:CreateRadio(value[2], function() return db[entry.key] == value[1] end,
                        function() SetOption(entry.key, value[1]) end, value[1])
                end
            end)
            row.control = dropdown
            row.refresh = function() dropdown:GenerateMenu() end -- shows the chosen value
        elseif kind == "slider" then
            row = AddPageRow(page, ROW_HEIGHT, entry.label)
            local slider = CreateFrame("Frame", nil, row.frame, "MinimalSliderWithSteppersTemplate")
            slider:SetPoint("LEFT", row.frame, "CENTER", -80, 0)
            slider:SetWidth(250)
            slider:Init(db[entry.key], entry.min, entry.max, (entry.max - entry.min) / (entry.step or 1),
                { [MinimalSliderWithSteppersMixin.Label.Right] = entry.format or tostring })
            slider:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, value)
                if db[entry.key] ~= value then SetOption(entry.key, value) end
            end, slider)
            row.control = slider
            row.refresh = function() slider:SetValue(db[entry.key]) end
        elseif kind == "button" then
            row = AddPageRow(page, ROW_HEIGHT, entry.label)
            local button = CreateFrame("Button", nil, row.frame, "UIPanelButtonTemplate")
            button:SetPoint("LEFT", row.frame, "CENTER", -80, 0)
            button:SetSize(200, 22)
            button:SetText(entry.text)
            button:SetScript("OnClick", function() entry.func() end)
            row.control = button
        elseif kind == "keybinding" then
            row = AddPageRow(page, ROW_HEIGHT, _G["BINDING_NAME_" .. entry.command] or entry.command)
            local button, show = KeyBindingButton(row, entry.command)
            button:SetPoint("LEFT", row.frame, "CENTER", -80, 0)
            button:SetSize(200, 22)
            row.control = button
            row.refresh = show
        end
        return row
    end

    local function BuildMenu()
        page = NewPage(title)
        ns.kit.page = page -- for the tests
        -- a top-level entry of its own in the game's AddOns settings
        category = Settings.RegisterCanvasLayoutCategory(page.panel, title)
        if options.intro then AddTextRow(page, 32, options.intro) end

        local afterMaster = false
        for _, entry in ipairs(entries) do
            local row = AddEntry(entry)
            if row then
                row.key = entry.key or (entry.type == "minimap" and "minimap" or nil)
                if entry.visibleWhen then
                    local key, value = entry.visibleWhen[1], entry.visibleWhen[2]
                    row.visible = function() return db[key] == value end
                end
                if row.control then
                    local enabled = EnabledTest(entry, afterMaster and not entry.master and entry.type ~= "minimap")
                    local refresh = row.refresh
                    row.refresh = function()
                        if refresh then refresh() end
                        local on = enabled() and true or false
                        row.control:SetEnabled(on)
                        if row.label then row.label:SetFontObject(on and "GameFontNormal" or "GameFontDisable") end
                    end
                    local tooltip = entry.tooltip
                        or (entry.type == "keybinding" and L["Click, then press a key. Right-click: unbind."])
                    if tooltip then AddTooltip(row, row.label and row.label:GetText() or "", tooltip) end
                end
            end
            if entry.master then afterMaster = true end

            if entry.type == "minimap" then
                OnChange("minimap", function(shown)
                    minimapButton:SetShown(shown)
                    if entry.onChange then entry.onChange(shown) end
                end)
            elseif entry.master or entry.onChange then
                OnChange(entry.key, function(value)
                    if entry.master then UpdateButtonState() end
                    if entry.onChange then entry.onChange(value) end
                end)
            end
        end
        -- after the subpages (page entries) so they hang below it
        Settings.RegisterAddOnCategory(category)
        page.Layout()
    end

    options = ns.options
    title = options.title or addonName
    if type(options.savedVariable) ~= "string" then
        Problem(L["its options name no savedVariable, they are not built."])
        return
    end
    for _, entry in ipairs(options) do
        if TYPES[entry.type] then
            entries[#entries + 1] = entry
        else
            Problem(L["the option type \"%s\" is unknown, its row is left out."]:format(tostring(entry.type)))
        end
    end

    local defaults = { minimap = true, minimapAngle = 200 }
    for key, value in pairs(options.defaults or {}) do defaults[key] = value end
    for _, entry in ipairs(entries) do
        if entry.key then defaults[entry.key] = entry.default end
        if entry.master then master = entry end
    end

    local schema = options.schema or {}
    db = Saved(options.savedVariable, { defaults = defaults, version = schema.version, migrations = schema.migrations })
    ns.db = db -- even when set: some addons hold false here until now

    CreateMinimapButton()
    BuildMenu()

    if options.slash then
        local name = addonName:upper()
        _G["SLASH_" .. name .. "1"] = options.slash
        if options.slashLeftClick then
            SlashCmdList[name] = function(text)
                local command = strtrim(text):lower()
                if command == "" then
                    LeftClick()
                elseif command == "options" then
                    OpenOptions()
                else
                    print(CHAT_NAME:format(title) .. ":")
                    print(("  %s - %s"):format(options.slash, options.leftClickText or L["same as left-clicking the minimap button"]))
                    print("  " .. L["%s options - open the options"]:format(options.slash))
                end
            end
        else
            SlashCmdList[name] = OpenOptions
        end
    end

    if options.onLoad then options.onLoad(db) end
end

-- Built at the addon's own ADDON_LOADED: its saved variables are there, its files have run
local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(self, _, name)
    if name ~= addonName then return end
    self:UnregisterEvent("ADDON_LOADED")
    if ns.off or not ns.options then return end
    -- an error in the options (or onLoad/migration) is reported, the addon's other code keeps running
    if not xpcall(Build, geterrorhandler()) then
        Problem(L["building its options failed (see the Lua error)."])
    end
end)
