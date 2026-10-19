local ns = select(2, ...).search
local L = ns.L

-- Entry points and settings of the search: opening and closing (ns.Show, ns.Toggle, ns.ButtonClicked, ns.Close),
-- the click outside the bar, the default key, the reset of the search's memory and ns.options (defaults and rows
-- of the options page). Events: GLOBAL_MOUSE_DOWN, PLAYER_REGEN_DISABLED, PLAYER_ENTERING_WORLD.

local COMMAND = "PYLOSCOMPASS" -- Bindings.xml
local DEFAULT_KEY = "ALT-SPACE" -- bound once, if neither the key nor the command is bound
BINDING_NAME_PYLOSCOMPASS = L["Open search"]
local BACKGROUND = 85 -- percent

local ui, S = ns.ui, ns.state

-- byMouse: open without keyboard focus; a click into the bar takes it.
local function Open(byMouse)
    if ns.db.searchOn == false then return end
    if InCombatLockdown() then
        ns.widgets.Error(L["The search only opens out of combat."])
        return
    end
    ns.index.BuildMissing()
    ns.rank.Prepare()
    ui.StartOpening()
    ui.ApplyLook()
    ns.input.BindKeys()
    S.unfocused = false
    ns.view.Reset()
    if byMouse then ns.input.Unfocus() end
    ns.rec.Log("open") -- the engine's activity log, if any
end

-- instantly: no fade (the bar's secure buttons must be gone before combat lockdown).
function ns.Close(instantly)
    if not ui.bar:IsShown() or (S.closingAt and not instantly) then return end

    ns.input.ClearKeys()
    ui.StartClosing(instantly)
end

local CLOSE_GUARD = 0.3 -- seconds after closing in which the button that closed it does not reopen it

local function ButtonClicked(byMouse)
    -- Closed by this same click (button closes on release, "click outside" on press): stay closed.
    if S.closingAt and GetTime() - S.closingAt < CLOSE_GUARD then return end
    if ui.bar:IsShown() and not S.closingAt then ns.Close() else Open(byMouse) end
end

function ns.Toggle()
    -- open without the keyboard: the key takes it back instead of closing
    if ui.bar:IsShown() and not S.closingAt and S.unfocused then return ns.input.Focus() end
    ButtonClicked()
end

-- Used by the recommendations window and the PylosCompass global (Core\Options.lua):
--   Show(id, name)    open the detail view of an entry ID ("q:176"); falls back to
--                     typing name if the entry is not built or switched off. Out of combat only.
--   BackgroundAlpha() window background opacity, 0-1
local function Show(id, name)
    if ns.db.searchOn == false then return end
    if InCombatLockdown() then return Open() end
    -- state is set at once; the bar is not shown yet in this frame
    if not ui.bar:IsShown() or S.closingAt then Open(true) end
    local entry = id and ns.index.EntryByID(id)
    if entry then
        ns.view.Open(entry)
    elseif name then
        ns.view.Type(name)
    end
end
ns.Show = Show
function ns.BackgroundAlpha() return (ns.db and ns.db.backgroundAlpha or BACKGROUND) / 100 end
ns.ButtonClicked = ButtonClicked

local function MouseOverSearch()
    local focus = GetMouseFoci()[1]
    while focus do
        if focus == ui.bar then return true end
        focus = focus.GetParent and focus:GetParent()
    end
    return false
end

local CLICK_GUARD = 0.2 -- seconds after opening: the click that opened it is no click outside

-- Option clickOutside: releases the keyboard or closes the search; the click still reaches the
-- game. A click into the bar takes the keyboard back. Ignored while the cursor carries something.
local function ClickedOutside()
    if not ui.bar:IsShown() or S.closingAt then return end
    if MouseOverSearch() then
        -- Keys act on the bar or the detail view (no text field: Space/Enter open its menu).
        if S.unfocused and (ui.bar:IsMouseOver() or (ui.detail:IsShown() and ui.detail:IsMouseOver())) then
            ns.input.Focus()
        end
        return
    end
    if GetTime() - (S.openedAt or 0) < CLICK_GUARD or GetCursorInfo() then return end
    -- the minimap button closes the search itself, on release
    if ns.minimapButton and ns.minimapButton:IsMouseOver() then return end
    local mode = ns.db.clickOutside
    if mode == "close" then
        ns.Close()
    elseif mode == "release" then
        ns.input.Unfocus()
    end
end
ns.data.On("GLOBAL_MOUSE_DOWN", ClickedOutside)
-- fires just before lockdown; override bindings cannot be removed after it
ns.data.On("PLAYER_REGEN_DISABLED", function() ns.Close(true) end)
ns.data.On("PLAYER_ENTERING_WORLD", function()
    -- loading screen is still up: build the small sources here, unseen
    ns.index.BuildMissing()
    if ns.db.defaultKeySet or ns.db.searchOn == false then return end
    if InCombatLockdown() then return end -- bindings change only out of combat: try again next time
    ns.db.defaultKeySet = true
    local taken = GetBindingAction(DEFAULT_KEY)
    if not GetBindingKey(COMMAND) and (taken == nil or taken == "") then
        SetBinding(DEFAULT_KEY, COMMAND)
        SaveBindings(GetCurrentBindingSet())
        print(("|cffffd100Pylos Compass|r: %s"):format(
            L["%s opens the search now; change it in the key bindings."]:format(GetBindingText(DEFAULT_KEY))))
    elseif not GetBindingKey(COMMAND) then
        print(("|cffffd100Pylos Compass|r: %s"):format(
            L["The search has no key yet: set one in the key bindings (Pylos Compass)."]))
    end
end)

local function SourcesChanged()
    for _, source in ipairs(ns.sources) do
        if ns.db["source_" .. source.key] == false then ns.index.Drop(source) end
    end
    ns.index.BuildMissing()
    -- an open search starts fresh: its category or filters may belong to the dropped source
    if ui.bar:IsShown() then ns.view.Reset() end
end

-- Reset is irreversible: confirm first. Clears only the search's own memory.
StaticPopupDialogs["PYLOSCOMPASS_RESET_WEIGHTING"] = {
    text = L["Reset the search's weighting? It forgets which results you chose for what you typed. What the " ..
        "recommendations learned stays."],
    button1 = YES,
    button2 = NO,
    OnAccept = function()
        ns.memory.Reset()
        if ui.bar:IsShown() and not S.detail and not S.linked then ns.view.Refresh() end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

-- the memory keeps only what the search knows (not Auto Shot or quest item spells)
ns.memory.accept = function(id) return ns.index.EntryByID(id) ~= nil end

-- Core\Options.lua builds the options page (head, minimap button) from this: defaults, load step and rows
ns.options = {
    -- filtersOpen: pin of the filter window
    defaults = { defaultKeySet = false, learned = {}, filtersOpen = false },
    onLoad = function()
        ns.memory.Prune()
        ui.ApplyLook()
    end,

    { type = "keybinding", command = COMMAND },
    { type = "slider", key = "backgroundAlpha", label = L["Background"], default = BACKGROUND,
      min = 0, max = 100, step = 5, format = function(value) return ("%d %%"):format(value) end,
      tooltip = L["How strongly the background covers the game. Border and text stay."],
      onChange = ui.ApplyLook },
    { type = "dropdown", key = "clickOutside", label = L["Click outside"], default = "release",
      values = {
          { "release", L["Release the keyboard"] },
          { "close", L["Close the search"] },
          { "nothing", L["Nothing"] },
      },
      tooltip = L["A click anywhere outside the search. Released, the keys go to the game (chat, walking) and a " ..
          "click into the bar takes them back. The click still works in the game."] },
    -- grayed out while Pylos GatherInfo is not loaded
    { type = "checkbox", key = "gatherInfo", label = L["Where to get it (Pylos GatherInfo)"], default = true,
      enabledIf = function() return ns.GatherInfo() ~= nil end,
      tooltip = L["The tooltips of the search say where a trade good is gathered. Needs the addon Pylos GatherInfo."] },
    { type = "button", label = L["Weighting"], text = L["Reset"],
      tooltip = L["The search forgets which results you chose for what you typed. What the recommendations learned " ..
          "stays."],
      func = function() StaticPopup_Show("PYLOSCOMPASS_RESET_WEIGHTING") end },

    { type = "header", label = L["Categories"] },
}
for _, source in ipairs(ns.sources) do
    table.insert(ns.options, { type = "checkbox", key = "source_" .. source.key, label = source.name,
        default = true, tooltip = source.hint, onChange = SourcesChanged })
end
