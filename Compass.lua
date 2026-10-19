local _, D = ...

-- The last file: the options page of Pylos Compass (head, switches, minimap button, the rows of the search and of
-- the recommendations) and the global API. Kit\Kit.lua builds the page at ADDON_LOADED from D.options.
local L = D.L
local search, advice = D.search, D.advice

BINDING_NAME_PYLOSCOMPASS_WINDOW = L["Open recommendations"]

-- every row of a part is grayed out while its switch is off
local function Under(entries, switch)
    for _, entry in ipairs(entries) do
        if entry.dependsOn == nil and entry.type ~= "header" and entry.type ~= "text" then
            entry.dependsOn, entry.enabledWhen = switch, true
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
        if advice.push.Interrupt then advice.push.Interrupt() end
        if D.SetAlert then D.SetAlert(false) end
    end
end

-- what a click or a key does while the search is off
local function SearchOff()
    if D.db.adviceOn ~= false then return advice.ToggleWindow() end
    print(("|cffffd100Pylos Compass|r: %s"):format(L["the search and the recommendations are switched off (right-click the minimap button for the options)."]))
end

local options = {
    savedVariable = "PylosCompassDB",
    title = "Pylos Compass",
    intro = L["Search for anything in the game and see what is worth doing next."],
    icon = "Interface\\Icons\\INV_Misc_Spyglass_02",
    slash = "/pcompass",
    slashLeftClick = true, -- /pcompass opens the search, /pcompass options the options
    defaults = defaults,
    onLeftClick = function()
        if D.db.searchOn == false then return SearchOff() end
        search.ButtonClicked(true)
    end,
    leftClickText = L["open the search"],
    onMiddleClick = function() advice.ToggleWindow() end,
    middleClickText = L["open the recommendations"],
    onLoad = function(db)
        search.options.onLoad(db)
        advice.options.onLoad(db)
    end,

    { type = "checkbox", key = "searchOn", label = L["Enable the search"], default = true, onChange = SearchSwitched,
      -- the shared game data is built either way (the recommendations need it too)
      tooltip = L["The search bar: a key opens it, type a few letters, Enter uses the result. Switched off, the bar stays closed and its lists are dropped; the game data stays loaded."] },
    { type = "checkbox", key = "adviceOn", label = L["Enable the recommendations"], default = true, onChange = AdviceSwitched,
      tooltip = L["The window with what is worth doing next, and the nudges. Switched off, the window and nudges stay away; the game data stays loaded."] },
    { type = "minimap" },
    { type = "header", label = L["Search settings"] },
}
local function Add(entries)
    for _, entry in ipairs(entries) do options[#options + 1] = entry end
end
Add(Under(search.options, "searchOn"))
options[#options + 1] = { type = "header", label = L["Recommendation settings"] }
options[#options + 1] = { type = "keybinding", command = "PYLOSCOMPASS_WINDOW", dependsOn = "adviceOn", enabledWhen = true }
Add(Under(advice.options, "adviceOn"))
D.options = options

-- for key bindings and other addons
PylosCompass.Show = search.Show             -- Show(id, name): the search's detail view of a Pylos entry ID ("q:176")
PylosCompass.ToggleSearch = function()
    if D.db and D.db.searchOn == false then return SearchOff() end
    search.Toggle()
end
PylosCompass.ToggleWindow = advice.ToggleWindow
