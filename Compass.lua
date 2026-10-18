local _, D = ...
if D.off then return end

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

local options = {
    savedVariable = "PylosCompassDB",
    title = "Pylos Compass",
    intro = L["Search for anything in the game and see what is worth doing next."],
    icon = "Interface\\Icons\\INV_Misc_Spyglass_02",
    slash = "/pcompass",
    slashLeftClick = true, -- /pcompass opens the search, /pcompass options the options
    defaults = defaults,
    onLeftClick = function() search.ButtonClicked(true) end,
    leftClickText = L["open the search"],
    onMiddleClick = function() advice.ToggleWindow() end,
    middleClickText = L["open the recommendations"],
    onLoad = function(db)
        search.options.onLoad(db)
        advice.options.onLoad(db)
    end,

    { type = "checkbox", key = "searchOn", label = L["Search"], default = true,
      tooltip = L["The search bar: a key opens it, type a few letters, Enter uses the result."] },
    { type = "checkbox", key = "adviceOn", label = L["Recommendations"], default = true,
      tooltip = L["The window with what is worth doing next, and the nudges."] },
    { type = "minimap" },
    { type = "header", label = L["Search"] },
}
local function Add(entries)
    for _, entry in ipairs(entries) do options[#options + 1] = entry end
end
Add(Under(search.options, "searchOn"))
options[#options + 1] = { type = "header", label = L["Recommendations"] }
options[#options + 1] = { type = "keybinding", command = "PYLOSCOMPASS_WINDOW", dependsOn = "adviceOn", enabledWhen = true }
Add(Under(advice.options, "adviceOn"))
D.options = options

-- for key bindings and other addons
PylosCompass.Show = search.Show             -- Show(id, name): the search's detail view of a Pylos entry ID ("q:176")
PylosCompass.ToggleSearch = search.Toggle
PylosCompass.ToggleWindow = advice.ToggleWindow
