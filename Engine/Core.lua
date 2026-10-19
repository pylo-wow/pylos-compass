local _, D = ...

-- The engine on the data layer's entries: what to do or look up next, from your situation and what you do.
-- No interface; the search (Search\) and the recommendations (Advice\) show it. D.engine is this whole table.
-- Files (Engine\): Core.lua (saved data, needed domains, helpers), Memory.lua (what you do), Reach.lua (how easily you
-- can act now), Reasons.lua + Reasons\*.lua (why something is worth doing), Learning.lua + Learning\*.lua (personal
-- reason weights), ItemValue\Weights.lua + ItemValue\Value.lua (item valuer), Relevant.lua (most relevant across
-- domains), API.lua (public interface).
-- Saved data: PylosCompassEngineDB (chosen, did, bought, skipped, hidden, reasonStats, upgradesJudged, seenItems,
-- seenZones).
local ns = { data = D, L = D.L, DOT = D.DOT }
D.engine = ns

-- Helpers
-- Small ones live in the data layer (D.CharacterKey, D.ItemIDFromLink, D.Decay, D.YardsMinutes, D.Secret, D.On).

ns.Character = D.CharacterKey

-- A client format ("%s dies, you gain %d experience.") as a Lua pattern catching its texts in order;
-- numbers: catch the numbers too (else only matched); whole: the text must end there.
function ns.FormatPattern(format, numbers, whole)
    if type(format) ~= "string" then return nil end
    local pattern = format:gsub("%%%d?%$?s", "\1"):gsub("%%%d?%$?d", "\2")
    pattern = pattern:gsub("[%(%)%.%+%-%*%?%[%]%^%$%%]", "%%%0")
    pattern = pattern:gsub("\1", "(.+)"):gsub("\2", numbers and "(%%d+)" or "%%d+")
    return "^" .. pattern .. (whole and "$" or "")
end

-- Activity log hook: does nothing unless something replaces it.
ns.Log = function() end

-- Game events through the one frame of D.On: fn(event, ...); UNIT_ events only for the player.
-- Prefer a D.OnState state where there is one.
function ns.On(event, fn)
    if event:find("^UNIT_") then
        return D.On(event, function(name, unit, ...)
            if unit == "player" then return fn(name, unit, ...) end
        end)
    end
    return D.On(event, fn)
end

ns.RECENT = 40 -- recent choices looked at (Relevant.lua, Reasons\LookedUp.lua)

-- How fresh a record stamped with time() is: 1 right after, 0 after window seconds; nil without a stamp. A faded one
-- is dropped from store[key].
function ns.Fade(store, key, at, window)
    if not at then return nil end
    local share = 1 - (time() - at) / window
    if share <= 0 then
        store[key] = nil
        return nil
    end
    return share
end

-- the engine looks at every domain
for _, key in ipairs({ "spells", "items", "professions", "npcs", "dungeons", "zones", "quests" }) do
    D.Need(key, "engine", true)
end

-- Saved data

local DEFAULTS = {
    chosen = {},
    did = {},
    bought = {},
    -- per kind of suggestion ("do": the window, "know": a search; Memory.lua, Learning.lua)
    skipped = { ["do"] = {}, know = {} },
    hidden = {},
    reasonStats = { ["do"] = {}, know = {} },
    upgradesJudged = {},  -- per character: the upgrades already learned from (Learning\Upgrades.lua)
    seenItems = {},       -- per character: the items ever had (Reasons\Looted.lua)
    seenZones = {},       -- per character: the zones ever been in (Reasons\NewHere.lua)
}
-- what has faded goes
local function Ready()
    ns.memory.Prune()
    ns.learning.PruneJudged()
end

D.OnLoaded(function()
    ns.db = D.kit.Saved("PylosCompassEngineDB", { defaults = DEFAULTS, version = 1 })
    Ready()
end)
