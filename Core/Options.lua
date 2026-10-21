local _, D = ...

-- The last file: the options page of Pylos Compass (head, switches, minimap button, the rows of the search and of
-- the recommendations) and the global API. Kit\Kit.lua builds the page at ADDON_LOADED from D.options.
local L = D.L
local search, advice = D.search, D.advice

BINDING_NAME_PYLOSCOMPASS_WINDOW = L["Open recommendations"]

-- every row of a part is grayed out while its switch is off (a row with a switch of its own too: both count)
local function Under(entries, switch)
    for _, entry in ipairs(entries) do
        if entry.type ~= "header" and entry.type ~= "text" then
            if entry.dependsOn == nil then
                entry.dependsOn, entry.enabledWhen = switch, true
            elseif entry.dependsOn ~= switch then
                local own = entry.enabledIf
                entry.enabledIf = function() return D.db ~= nil and D.db[switch] ~= false and (not own or own()) end
            end
        end
    end
    return entries
end

local defaults = {}
for _, part in ipairs({ search.options, advice.options }) do
    for key, value in pairs(part.defaults) do defaults[key] = value end
end

-- the switches act at once: what is open closes, what was built is let go
local function SearchSwitched(on)
    if on then
        search.index.BuildMissing()
    else
        search.Close(true)
        for _, source in ipairs(search.sources) do search.index.Drop(source) end
    end
end
local function AdviceSwitched(on)
    if on then
        advice.push.Evaluate("switch")
    else
        advice.CloseWindow()
        advice.push.Interrupt()
        if D.SetAlert then D.SetAlert(false) end
    end
end

local function BothOff()
    print(("|cffffd100Pylos Compass|r: %s"):format(
        L["the search and the recommendations are switched off (right-click the minimap button for the options)."]))
end

-- what a click or a key does while the search is off
local function SearchOff()
    if D.db.adviceOn ~= false then return advice.ToggleWindow() end
    BothOff()
end

-- ... and while the recommendations are off
local function AdviceOff()
    if D.db.searchOn ~= false then return search.ButtonClicked(true) end
    BothOff()
end

local options = {
    savedVariable = "PylosCompassDB",
    schema = { version = 2 },
    title = "Pylos Compass",
    intro = L["Search for anything in the game and see what is worth doing next."],
    icon = "Interface\\AddOns\\PylosCompass\\Button.tga",
    slash = "/pcompass",
    slashLeftClick = true, -- /pcompass acts like a left click (the recommendations), /pcompass options opens the options
    defaults = defaults,
    onLeftClick = function()
        if D.db.adviceOn == false then return AdviceOff() end
        advice.LeftClick() -- a quiet nudge that glows is shown first
    end,
    leftClickText = L["open the recommendations"],
    onMiddleClick = function()
        if D.db.searchOn == false then return SearchOff() end
        search.ButtonClicked(true)
    end,
    middleClickText = L["open the search"],
    onTooltip = function(tooltip)
        if advice.push.Glowing() then tooltip:AddLine(L["A new hint: left-click shows it."], 1, 0.82, 0) end
    end,
    onLoad = function(db)
        search.options.onLoad(db)
        advice.options.onLoad(db)
    end,

    { type = "checkbox", key = "searchOn", label = L["Enable search"], default = true, onChange = SearchSwitched,
      -- the shared game data is built either way (the recommendations need it too)
      tooltip = L["The search bar: a key opens it, type a few letters, Enter opens a result, Ctrl+Enter uses it. " ..
          "Switched off, the bar stays closed and its lists are dropped; the game data stays loaded."] },
    { type = "checkbox", key = "adviceOn", label = L["Enable recommendations"], default = true,
      onChange = AdviceSwitched,
      tooltip = L["The window with what is worth doing next, and the hints. Switched off, the window and hints " ..
          "do not appear; the game data stays loaded."] },
}
local function Add(entries)
    for _, entry in ipairs(entries) do options[#options + 1] = entry end
end
local function Header(label) options[#options + 1] = { type = "header", label = label } end
local function Percent(value) return ("%d %%"):format(value) end
local function ApplyAdviceScale()
    advice.ApplyScale()
    advice.push.ApplyScale()
end

-- the page: the two switches, Display, Behaviour; then the subpages (the settings list shows them below Pylos
-- Compass): Nudges, Learning
Header(L["Display"])
options[#options + 1] = search.rows.background -- both windows wear it
options[#options + 1] = { type = "slider", key = "searchScale", label = L["Search size"], default = 100,
    min = 70, max = 150, step = 5, format = Percent, tooltip = L["The size of the search bar and its lists."],
    onChange = function() search.ui.ApplyScale() end }
options[#options + 1] = { type = "slider", key = "adviceScale", label = L["Recommendations size"], default = 100,
    min = 70, max = 150, step = 5, format = Percent,
    tooltip = L["The size of the recommendations window and the hint messages."],
    onChange = ApplyAdviceScale }
Add(Under({ { type = "button", label = L["Recommendations window"], text = L["Reset position"],
    tooltip = L["Move the recommendations window back to where it opens by default, next to the minimap button."],
    func = function() advice.ResetPosition() end } }, "adviceOn"))
Add(Under({ search.rows.showCategories }, "searchOn"))

Header(L["Behaviour"])
Add(Under({ search.rows.key }, "searchOn"))
options[#options + 1] = { type = "keybinding", command = "PYLOSCOMPASS_WINDOW", dependsOn = "adviceOn",
    enabledWhen = true }
Add(Under({ search.rows.clickOutside }, "searchOn"))
options[#options + 1] = { type = "minimap" }

Under(advice.rows.nudges.entries, "adviceOn")
options[#options + 1] = advice.rows.nudges

options[#options + 1] = { type = "page", label = L["Learning"], entries = {
    { type = "text", height = 40,
      text = L["What you choose and do is remembered only on this computer, to tune the search and the " ..
          "recommendations."] },
    { type = "checkbox", key = "learn", label = L["Learn from what I do"], default = true,
      tooltip = L["Remember what you choose in the search, what you cast, use, buy and turn in, and how you answer " ..
          "suggestions. Switched off, none of this is remembered any more; what is remembered stays until you " ..
          "reset it. Facts about the game learned while playing (where NPCs stand, what a trainer teaches) and " ..
          "the items and zones you have seen are not part of this."] },
    Under({ search.rows.weighting }, "searchOn")[1],
    Under({ advice.rows.reset }, "adviceOn")[1],
} }
D.options = options

-- the global API, for key bindings and macros
PylosCompass.Show = search.Show             -- Show(id, name): the search's detail view of a Pylos entry ID ("q:176")
PylosCompass.ToggleSearch = function()
    if D.db and D.db.searchOn == false then return SearchOff() end
    search.Toggle()
end
PylosCompass.ToggleWindow = advice.ToggleWindow

-- the compass art sits a bit up and left of the button's ring at the kit's spot: moved by half a unit
D.On("PLAYER_LOGIN", function()
    local icon = D.minimapButton and D.minimapButton.icon
    if icon then
        icon:ClearAllPoints()
        icon:SetPoint("CENTER", 0.5, 0.5)
    end
end)
