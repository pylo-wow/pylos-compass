local addonName, D = ...

-- Pylos Compass: Data (Core, You, World, Data, Engine), the search (Search) and the recommendations (Advice) in one
-- addon. D is the root namespace; Kit\Kit.lua (first in the TOC) has given it L, kit and, once the options are
-- built, db and the minimap button.
--   D.search   the search's namespace   D.advice   the recommendations' namespace
-- A part reads the kit's names from the root and, for the recommendations, the engine's names as its own.

PylosCompass = { API = 1, internal = D } -- Compass.lua fills it; Bindings.xml calls it; internal: the whole namespace, for Pylos Dev only

local KIT = { L = true, db = true, kit = true, widgets = true, SetOption = true, minimapButton = true,
    SetAlert = true, GetColor = true, IsModifierHeld = true }

local function Part(fallback)
    return setmetatable({ data = D }, { __index = function(_, key)
        if KIT[key] then return D[key] end
        if key == "engine" then return D.engine end
        if fallback then return fallback(key) end
    end })
end

D.search = Part()
D.advice = Part(function(key)
    local engine = D.engine
    return engine and engine[key]
end)
