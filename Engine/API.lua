local _, D = ...
if D.off then return end
local ns = D.engine

-- The names the search and the recommendations call on the engine (D.engine); the rest of the engine is internal.
-- Entries are Data's; IDs are its entry IDs ("i:2589", "n:1234", ...).
-- Calls about a suggestion (Fit ... Feedback, Hide, Hidden) take the entry (the single calls Shown, Feedback, Hide,
-- Hidden also its ID); calls about memory (Chose ... Forget) take the ID (or the entry).
-- kind (optional, last): "do" (default: what to do next) or "know" (what you would want to look up now: target,
-- loot, a new zone's NPCs, quest items, lookups; a search's start page).
--   API                        1
--   Prepare()                  gets everything ready; once per frame however often called (call before asking)
--   Refresh()                  same, but only when the game's state changed (D.State, plus your choices); earlier work is
--                              kept and Relevant/RelevantByTopic give their lists again. For a reopened view or tab.
--   Fit(entry, kind)           what an entry is worth now (0: no reason)
--   Weighed(entry, id, kind)   the fit as the lists weigh it (id may be nil; passed over, just done, what stands with it)
--   Test(key, entry)           one reason's strength, nil if none
--   Note(entry, kind)          its row's note: a text or { icon, count, tip }, and the key of the reason it is from
--   Explain(entry, kind)       its reasons as sentences (tooltip lines)
--   Sort(list, tiebreak, kind) sorts a list as suggestions, in place
--   Relevant(limit, perDomain, domains, kind)  most relevant entries now: list of { entry, id, score, fit, used, carries };
--                              domains: set of domain keys (nil: all); carries (doing): the entries this row stands for
--                              (an upgrade's quest rewards, a restock at its vendor, a quest's other rewards).
--                              Do not change the list.
--   RelevantByTopic(limit, perDomain)  the same per topic: { all = list, class = list, gear = list, ... } (the window's
--                              tabs; only "all" merges into the row it is got at, every list carries a quest's other rewards)
--   Shown(entry, kind, rank)   a host showed it as a suggestion (rank: its row, 1 the top; for the log); Learning
--                              watches whether you follow it (only what was shown counts)
--   Feedback(entry, good, kind)  your word on a suggestion
--   Hide(entry, hidden)        "Don't suggest" (hidden false: again)
--   Hidden(entry)              is it hidden; it comes back when its reasons have something new (a trainer's new spell)
--   IsHidden(id)               the same by ID, without that (an old name)
--   Chose(id, amount, text)    you chose an entry in a host (1, or 0.5 for only looking; text: what was typed)
--   PassedOver(id, kind)       a suggestion above the chosen one was passed over; kind "know" if not given
--   UsedNow() / Used(id)       how much you use something, 0..1 (UsedNow: a function(id), for many)
--   Recent()                   IDs chosen lately, newest first
--   UsedIDs(prefix)            list of IDs chosen or done with that prefix ("n:")
--   RunningLow()               item ID -> how many left, of what you buy regularly
--   Knows(id), Forget(id)      the memory of an entry
--   Reset()                    forgets every choice and what the learning learned
--   Log(kind, ...)             the activity log, if there and switched on
--   ItemValue                  item valuer module (ItemValue\Value.lua): ItemValue.Compare(itemID or link) -> how much
--                              better for you; .Value, .Total, .Profile, .Weights
--   UpgradeOf(itemID)          an upgrade for you (your class and armour, the suggestions' threshold): the comparison, or nil

ns.API = 1

local reasons, memory, learning = ns.reasons, ns.memory, ns.learning

-- an entry from an entry or its ID; an ID from an ID or its entry
local function Entry(x) return type(x) == "table" and x or D.EntryByID(x) end
local function ID(x) return type(x) == "table" and D.EntryID(x) or x end

ns.Prepare = reasons.Prepare
ns.Refresh = reasons.Refresh
ns.Fit = reasons.Fit
ns.Weighed = reasons.Weighed
ns.Test = reasons.Test
ns.Note = reasons.Note
ns.Explain = reasons.Explain
ns.Sort = reasons.Sort
ns.UsedNow = memory.UsedNow
ns.Recent = memory.Recent
ns.UsedIDs = memory.IDs
ns.RunningLow = memory.RunningLow
ns.Reset = memory.Reset

function ns.Used(x) return memory.Used(ID(x)) end
function ns.Knows(x) return memory.Knows(ID(x)) end
function ns.Forget(x) return memory.Forget(ID(x)) end
function ns.IsHidden(x) return memory.Hidden(ID(x)) end

function ns.Hidden(x)
    local entry = Entry(x)
    return entry ~= nil and reasons.Hidden(entry)
end

function ns.Shown(x, kind, rank)
    local entry = Entry(x)
    if entry then learning.Shown(entry, kind, rank) end
end

function ns.Feedback(x, good, kind)
    local entry = Entry(x)
    if entry then learning.Feedback(entry, good, kind) end
end

function ns.Chose(x, amount, text)
    local id = ID(x)
    memory.Chose(id, amount)
    ns.Log("chose", id, text or "", amount or 1)
end

function ns.PassedOver(x, kind)
    memory.Skipped(ID(x), nil, kind or "know")
end

function ns.Hide(x, hidden)
    local entry = Entry(x)
    if not entry then return end
    memory.Hide(D.EntryID(entry), hidden, hidden ~= false and reasons.Renew(entry) or nil)
end

