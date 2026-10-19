local ns = select(2, ...).search
if ns.off then return end
local L = ns.L

-- Data's recommendation engine (service "engine") behind ns.rec. the search is a search, so
-- it asks only for reasons of kind "know": what you would want to look up now (target, fresh
-- loot, a new zone, your quests' items, your lookups). What to do next is the recommendations' window.

local R = ns.engine
local rec = {}
ns.rec = rec

local KIND = "know"

-- recompute reasons only when the game's state changed (Data's D.State; R.Refresh); they do not
-- depend on the search text or filters. R.Prepare redid everything each frame (~2 ms, 290 KB per open).
rec.Prepare = R.Refresh or R.Prepare
-- an entry's worth to look up now (0: no reason)
rec.Fit = function(entry) return R.Fit(entry, KIND) end
-- its row's note: a text or { icon, count, tip }
rec.Note = function(entry) return R.Note(entry, KIND) end
rec.Explain = function(entry) return R.Explain(entry, KIND) end
rec.Sort = function(list, tiebreak) return R.Sort(list, tiebreak, KIND) end
rec.Relevant = function(limit, perDomain, domains) return R.Relevant(limit, perDomain, domains, KIND) end
-- the start page showed it: the recommendations watch whether you follow it
rec.Shown = function(entry) return R.Shown and R.Shown(entry, KIND) end
rec.UsedNow = R.UsedNow
rec.UsedIDs = R.UsedIDs
rec.Chose = R.Chose
rec.PassedOver = R.PassedOver         -- a suggestion above the chosen one was passed over
rec.Feedback = function(entry, good) return R.Feedback(entry, good, KIND) end
rec.Hide = R.Hide
rec.IsHidden = R.IsHidden
rec.Knows = R.Knows
rec.Forget = R.Forget
rec.Log = function(...) return R.Log(...) end -- Dev replaces R.Log, so look it up at run time
-- an item that is an upgrade for you: "+14 %" or "Free slot"; nil if none (a row's state)
rec.Upgrade = function(itemID)
    local r = R.UpgradeOf and itemID and R.UpgradeOf(itemID)
    if not r then return nil end
    if r.free then return L["Free slot"] end
    return r.percent and ("+%d %%"):format(r.percent + 0.5) or L["Better"]
end

-- A suggestion's reason as its row's text (UI\List.lua): the strongest reason's note, name first
-- ("Your target", "Quest 0/8"). The tooltip's Why lists every reason.
function rec.Mark(entry)
    local note = rec.Note(entry)
    if type(note) == "table" then return note.text or note.tip end
    return note
end
