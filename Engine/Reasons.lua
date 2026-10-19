local _, D = ...
local ns = D.engine
local L = ns.L

-- Reasons: why an entry is worth something to you now. Each reason is a small file in Reasons\, registered with
-- ns.RegisterReason. This file holds the stages of need and their worth (STAGES), an entry's fit (Fit), its note
-- (symbol or text of its strongest reason), list order (Sort) and what is kept until something changes (Prepare,
-- Refresh).
--
-- Each reason has a value (weight x strength) and a reach (how easily you can act on it now, Reach.lua): something
-- small you can do right now beats something big far away, unless that is far more important.
--
-- The stage decides first: each stage is worth twice the next (STAGES); a reason's weight within its stage lies
-- between LIGHTEST and HEAVIEST (0.7 to 1.4, at most twice another), so at equal reach and strength a lower stage never
-- beats a higher one:
--   play          repair, bags, what you run out of; grows with how bad it is; distance hurts less the worse it is
--                 ("urgent")
--   progress      quests, trainers, spells, clear upgrades
--   professions   skill ups, recipes
--   opportunity   consumables for your level, dungeons
-- A strength says how much of it there is (1 a plain case); it counts at most MOST (twice plain), so the strongest
-- case of a stage only reaches the plain case of the stage above. Growing amounts flatten (reasons.Grow). Other things
-- that move a value: reach, urgency, your personal weight (x0.5 to x1.5, Learning.lua), FOCUS (x1.5 for professions
-- while you work on them), what stands right there (BUNDLE) and further reasons (MORE). Using something often is no
-- reason (it only breaks ties: Sort, Relevant.lua); what you just did steps back (SATISFIED).
--
-- Two kinds of reasons, one engine:
--   do     what to do next (default): the recommendations window
--   know   what you would want to look up now (the search's start page): target, what you looted, a new zone, lookups;
--          own scale, reach counts only as its square root
--   both   a reason of both
-- Fit, Weighed, Note, Explain, Keys, Errand, Sort and Each take the kind as last argument ("do" if not given);
-- Topics, Covered, Via and bundling are about doing only.
--
-- A reason (fields in this order in the files of Reasons\):
--   key         unique
--   stage       a STAGES key ("play", "progress", "professions", "opportunity"; knowing: "know"); required
--   weight      within its stage, 1 a plain one, LIGHTEST to HEAVIEST; default 1
--   label       a readable name; default: the key
--   learn       false: not learned from being followed (Learning.lua), only from your word and choices
--   kind        "do" (default), "know" or "both"
--   sources     the domains it applies to
--   depends     the states (Core\State.lua; DEPENDS below) its prepare and test read; strengths are kept while they
--               stay the same (default: all of DEPENDS). "rec:chosen" only for a knowing reason that reads the entry's
--               own choices: a choice recomputes just the chosen entries
--   topic       a key of reasons.TOPICS (the tabs of Window.lua), or function(entry) -> one
--   prepare     function(): once whenever its states changed
--   candidates  function(add): entries it brings itself (knowing: what you looted, your target); optional
--   test        function(entry) -> strength (1 a plain case, more for more, at most MOST), or nil/false/0: none
--   reach       function(entry, strength) -> factor, words; optional (an NPC: its distance; else 1)
--   urgent      how little distance counts, 0 (default: in full) to 1 (not at all), or function(entry, strength) ->
--               that
--   profession  true or function(entry) -> true: counts for FOCUS
--   covered     function(entry) -> true: another row stands for it (a spell to learn: its trainer); an entry whose
--               reasons are all covered is left out of the lists
--   via         function(entry) -> entry ID of the row that stands for getting it (an upgrade: the quest of your log
--               rewarding it; something to restock: its vendor); the "All" list shows that row only, carrying it
--               (Relevant.lua)
--   group       function(entry) -> key, nil if none: entries of one key are one errand (an upgrade: the quest rewarding
--               it); a list shows the best and it carries the others (Relevant.lua); doing only
--   offers      function(entry) -> entry IDs it offers right there (a trainer: the spells), watched with it
--               (Learning.lua)
--   renew       function(entry) -> list of what it has (a trainer: spells to learn); an entry hidden with "Don't
--               suggest" comes back once there is something new
--   affordable  function(entry) -> how many of what it offers you can pay (the nudges, Pushes.lua)
--   errand      false: the note does not name an errand, so two NPCs with it are not one errand (reasons.Errand)
--   note        function(entry, strength) -> what the row shows: a text ("Free slot") or { icon, count, tip }; optional
--   why         function(entry, strength) -> a tooltip sentence, for a reason without a note or whose note says too
--               little; optional
-- The tooltip lists every reason an entry has with its reach (reasons.Explain). A new reason is a file in Reasons\ (in
-- the TOC).

local reasons = {}
ns.reasons = reasons

-- what a plain reason (strength 1, right here, weight 1) of each stage is worth; each stage twice the next; know has
-- its own scale
local STAGES = { play = 80, progress = 40, professions = 20, opportunity = 10, know = 40 }
reasons.STAGES = STAGES
-- a reason's weight within its stage: at most twice another's, so the stage decides first
local LIGHTEST, HEAVIEST = 0.7, 1.4
local MOST = 2
reasons.MOST = MOST
-- What reasons are about, in the order of the recommendations window's tabs (Window.lua). A reason's topic must be
-- listed here, else it is worked out and never shown.
-- here, else it is worked out and never shown.
reasons.TOPICS = {
    { key = "class", name = L["Class"] },
    { key = "gear", name = L["Gear"] },
    { key = "professions", name = L["Professions"] },
    { key = "quests", name = L["Quests"] },
    { key = "supplies", name = L["Supplies"] },
    { key = "dungeons", name = L["Dungeons"] },
    { key = "zones", name = L["Zones"] },
}
local TOPIC = {}
for _, topic in ipairs(reasons.TOPICS) do TOPIC[topic.key] = topic end

-- a strength that grows with an amount but flattens: 1 at plain, +0.5 per doubling (2x: 1.5, 4x: 2 = MOST), never
-- below 0
function reasons.Grow(amount, plain)
    if amount <= 0 then return 0 end
    return math.min(MOST, math.max(0, 1 + 0.5 * math.log(amount / plain) / math.log(2)))
end
local TIRED = 0.6
-- what you just did has its reasons fulfilled for a while: right after it they count 1 - SATISFIED, returning with
-- half-life SATISFIED_HALF (seen in game: crafting the last meat left the recipe on top); your use of it stays
local SATISFIED, SATISFIED_HALF = 0.8, 20 * 60
local FOCUS, FOCUS_WINDOW = 1.5, 20 * 60
-- what stands within a few steps of an NPC adds BUNDLE of its value (Reach.lua: reach.Neighbours), only from neighbours
-- worth less than the NPC itself: the errand is the bigger one, the smaller comes along
local BUNDLE = 0.3
local MORE = 0.3
reasons.TIRED, reasons.MORE, reasons.BUNDLE = TIRED, MORE, BUNDLE

-- An NPC you went to stands for its errand: other NPCs of the same errand count as gone to as well. Per kind: errand ->
-- seconds since the latest NPC of it was gone to (within ERRAND_WINDOW); made when first asked after a wipe.
local ERRAND_WINDOW = 4 * SATISFIED_HALF
local actedErrands = { ["do"] = false, know = false }
local function ErrandSince(entry, kind)
    if not entry.npcID then return nil end
    local list = actedErrands[kind]
    if not list then
        list = {}
        actedErrands[kind] = list
        for _, id in ipairs(ns.memory.DoneSince(ERRAND_WINDOW)) do
            local other = id:sub(1, 2) == "n:" and D.EntryByID(id)
            local errand = other and reasons.Errand(other, kind)
            local since = errand and ns.memory.SinceActed(id)
            if since and (not list[errand] or since < list[errand]) then list[errand] = since end
        end
    end
    local errand = reasons.Errand(entry, kind)
    return errand and list[errand]
end

-- A recipe you can still make is not done with one (skilling up repeats it); once the materials run out its reasons
-- fall by themselves.
local function Satisfied(id, entry, kind)
    if entry and entry.domain == "professions" and D.CraftTimes(entry) > 0 then return 1 end
    local since = id and ns.memory.SinceActed(id)
    local errandSince = entry and ErrandSince(entry, kind or "do")
    if errandSince and (not since or errandSince < since) then since = errandSince end
    if not since then return 1 end
    return 1 - D.Decay(SATISFIED, since, SATISFIED_HALF)
end
reasons.Satisfied = Satisfied

local all, bySource = {}, { ["do"] = {}, know = {} }
local NONE = {}
local KINDS = { ["do"] = { "do" }, know = { "know" }, both = { "do", "know" } }

function ns.RegisterReason(reason)
    -- fail loudly: a forgotten weight or stage would be a silent 0
    local stage = STAGES[reason.stage]
    if not stage then error(("reason %s: unknown stage %s"):format(tostring(reason.key), tostring(reason.stage)), 2) end
    local weight = reason.weight or 1
    if weight < LIGHTEST or weight > HEAVIEST then
        error(("reason %s: weight %s outside %s to %s (the stage decides first)"):format(reason.key, tostring(weight),
            LIGHTEST, HEAVIEST), 2)
    end
    if type(reason.topic) == "string" and not TOPIC[reason.topic] then
        error(("reason %s: unknown topic %s (reasons.TOPICS)"):format(reason.key, reason.topic), 2)
    end
    reason.weight = stage * weight
    reason.label = reason.label or reason.key
    reason.kind = reason.kind or "do"
    all[#all + 1] = reason
    all[reason.key] = reason
    for _, kind in ipairs(KINDS[reason.kind]) do
        for _, key in ipairs(reason.sources) do
            bySource[kind][key] = bySource[kind][key] or {}
            table.insert(bySource[kind][key], reason)
        end
    end
    return reason
end

local function Of(entry, kind)
    return entry.domain and bySource[kind or "do"][entry.domain] or NONE
end

local tests = {}       -- reason -> entry -> strength or false
local reaches = {}     -- reason -> entry -> { factor, words }
local fits = { ["do"] = {}, know = {} }      -- kind -> entry -> fit
local strongest = { ["do"] = {}, know = {} } -- kind -> entry -> { reason, strength } of the strongest
local bundles = {}     -- entry -> what else is right there (Bundle below)
local errands = { ["do"] = {}, know = {} }   -- kind -> entry -> errand text or false (reasons.Errand)
local focus = 1

local function Personal(key, kind)
    return ns.learning.Multiplier(key, kind)
end
reasons.Personal = Personal

local function Focus()
    for _, id in ipairs(ns.memory.DoneSince(FOCUS_WINDOW)) do
        local spellID = tonumber(id:match("^s:(%d+)"))
        if spellID and D.Recipe(spellID) then return FOCUS end
    end
    return 1
end

-- What results depend on: states of Core\State.lua and the engine's own: "rec:chosen" (a choice in the search),
-- "rec:memory" (did, bought, passed over: Memory.lua), "rec:hidden" ("Don't suggest"), "rec:linked" (a chat link,
-- Reasons\Linked.lua), "rec:rare" (a rare near you came up or died: Reasons\RareNearby.lua), "rec:learning" (personal
-- weights), "rec:weights" (item valuer, ItemValue\). STATES is also what the recommendations window follows
-- (Window.lua: recomputed soon after a change). WHERE is what changes as you walk or look about, including every
-- name plate
-- ("rec:nearby"), chat link and error message ("rec:blocked"): for the start page only (the window would work all the
-- time). Results kept with these stay valid while none changed; STALE seconds at most, for what changes with time
-- alone (what you just did fades, a hearthstone gets ready). "ratings" is left out: it changes with every buff.
reasons.STATES = { "bags", "gear", "durability", "level", "money", "prices", "zone", "quests", "spells", "skills",
    "talents", "travel", "npcs", "drops", "data", "group", "events", "rec:chosen", "rec:memory", "rec:hidden",
    "rec:learning", "rec:rare", "rec:weights" }
local WHERE = { "position", "target", "rec:nearby", "rec:linked", "rec:blocked" }
-- A choice ("rec:chosen") changes only the chosen entry: its use and tiredness, the recent choices (candidates), and
-- its strength for reasons naming "rec:chosen" in depends (Looked up). So a choice alone recomputes just the chosen
-- entries and keeps the rest (WipeChosen).
local DEPENDS, OTHERS = {}, {}
for _, list in ipairs({ reasons.STATES, WHERE }) do
    for _, name in ipairs(list) do
        DEPENDS[#DEPENDS + 1] = name
        if name ~= "rec:chosen" then OTHERS[#OTHERS + 1] = name end
    end
end
local STALE = 30
local states = D.Cache(DEPENDS, STALE)
local others = D.Cache(OTHERS, STALE) -- all but the choices: did anything else change
local thisFrame = D.Cache({ "frame" })
reasons.generation = 0 -- grows whenever the results are thrown away (Relevant.lua keeps its lists by it)

local Run, Renewed

-- a reason's own states (its depends, without "rec:chosen": a choice is handled per entry, DropChosen); true if they
-- changed: its strengths go
local function Renew(reason, everything)
    if not reason.states then
        local depends = {}
        for _, name in ipairs(reason.depends or OTHERS) do
            if name == "rec:chosen" then reason.byChoice = true else depends[#depends + 1] = name end
        end
        reason.states = D.Cache(depends, STALE)
    end
    local _, changed = reason.states.Get()
    if everything or changed or not tests[reason] then
        if reason.prepare then reason.prepare() end
        tests[reason] = tests[reason] and wipe(tests[reason]) or {}
        return true
    end
    return false
end
local function DropChosen(reason, chosen)
    if not reason.byChoice then return end
    for _, entry in ipairs(chosen) do
        tests[reason][entry] = nil
        if reaches[reason] then reaches[reason][entry] = nil end
    end
end
-- entries chosen since the last wipe (memory.TakeChosen); trainer: one is a trainer (Reach.lua breaks ties between
-- trainers by use, so every spell's reach may change)
local function TakeChosen()
    local chosen, trainer = {}, false
    for _, id in ipairs(ns.memory.TakeChosen()) do
        local entry = D.EntryByID(id)
        if entry then chosen[#chosen + 1] = entry end
        local npcID = tonumber(id:match("^n:(%d+)$"))
        if npcID and D.npcTrainers and D.npcTrainers[npcID] then trainer = true end
    end
    return chosen, trainer
end

-- everything: every reason's strengths go (else only those whose own
-- states changed, and the chosen entries' ones of a reason that reads
-- choices); chosen: those entries (else taken from the memory)
local function Wipe(everything, chosen)
    reasons.generation = reasons.generation + 1
    others.Get() -- (seen now: WipeChosen asks whether anything else changed since)
    chosen = chosen or TakeChosen()
    ns.learning.Refresh()
    focus = Focus()
    for _, reason in ipairs(all) do
        if not Renew(reason, everything) then DropChosen(reason, chosen) end
        reaches[reason] = reaches[reason] and wipe(reaches[reason]) or {}
    end
    wipe(fits["do"])
    wipe(fits.know)
    wipe(strongest["do"])
    wipe(strongest.know)
    wipe(errands["do"])
    wipe(errands.know)
    actedErrands["do"], actedErrands.know = false, false
    wipe(bundles)
    -- a hidden entry with something new comes back: unhidden here, not while its fit is worked out (a side effect on
    -- memory)
    local back
    for id, renew in pairs(ns.memory.AllHidden()) do
        if type(renew) == "string" then
            local entry = D.EntryByID(id)
            if entry and Renewed(entry, renew) then
                back = back or {}
                back[#back + 1] = id
            end
        end
    end
    for _, id in ipairs(back or NONE) do ns.memory.Hide(id, false) end
end

-- Only choices changed since the last wipe: a new generation (lists are mixed again: used, tired, recent choices) and
-- the chosen entries are recomputed (fits, and strengths for reasons that read choices); the rest stays. If anything
-- else changed too, or a trainer was chosen: Wipe. Returns false where Refresh has to Wipe itself.
local function WipeChosen()
    local _, other = others.Get()
    if other then return false end
    local chosen, trainer = TakeChosen()
    local renewed = trainer
    for _, reason in ipairs(all) do
        if Renew(reason) then renewed = true else DropChosen(reason, chosen) end
    end
    if renewed then
        Wipe(false, chosen)
        return true
    end
    reasons.generation = reasons.generation + 1
    for _, entry in ipairs(chosen) do
        for _, kind in ipairs({ "do", "know" }) do
            fits[kind][entry], strongest[kind][entry], errands[kind][entry] = nil, nil, nil
        end
    end
    return true
end

-- gets every reason ready; once per frame however often asked
function reasons.Prepare()
    states.Get() -- (a Refresh in this frame keeps what this works out)
    local _, newFrame = thisFrame.Get()
    if newFrame then Wipe(true) end
end

-- gets every reason ready only if something they depend on changed (DEPENDS): tabs opened again where you stand keep
-- their work
function reasons.Refresh()
    local _, renewed = states.Get()
    if renewed then
        thisFrame.Get() -- (a Prepare in this frame keeps it)
        if not WipeChosen() then Wipe() end
    end
end

function Run(reason, entry)
    local cache = tests[reason]
    if not cache then
        reasons.Prepare()
        cache = tests[reason]
    end
    local strength = cache[entry]
    if strength == nil then
        strength = reason.test(entry)
        if strength == true then strength = 1 end
        if type(strength) ~= "number" or strength <= 0 then
            strength = false
        elseif strength > MOST then
            strength = MOST
        end
        cache[entry] = strength
    end
    return strength or nil
end

local function Reach(reason, entry, strength)
    local cache = reaches[reason]
    local known = cache[entry]
    if not known then
        local factor, words
        if reason.reach then
            factor, words = reason.reach(entry, strength)
        elseif entry.npcID then
            factor, words = ns.reach.NPC(entry)
        end
        known = { factor or 1, words }
        cache[entry] = known
    end
    return known[1], known[2]
end

local function ForProfession(reason, entry)
    local profession = reason.profession
    if type(profession) == "function" then return profession(entry) end
    return profession == true
end

-- How much distance counts: the reach to the power of 1 - urgency (0: in full, 0.5: its square root, 0.9: hardly).
-- Knowing counts it at most as the square root; an urgent reason known about not twice.
local function Urgency(reason, entry, strength)
    local urgent = reason.urgent
    if type(urgent) == "function" then urgent = urgent(entry, strength) end
    return urgent or 0
end

-- one reason's value for an entry and its parts: value, personal, reach factor, words, focus. Knowing needs no way
-- there: reach counts only as its square root, no focus
local function Value(reason, entry, strength, kind)
    local personal = Personal(reason.key, kind)
    local factor, words = Reach(reason, entry, strength)
    local exponent = 1 - Urgency(reason, entry, strength)
    local focused = 1
    if kind == "know" then
        exponent = math.min(exponent, 0.5)
    elseif ForProfession(reason, entry) then
        focused = focus
    end
    factor = factor ^ exponent
    return reason.weight * personal * strength * factor * focused, personal, factor, words, focused
end

-- every reason of a kind an entry has: fn(reason, strength, value, personal, reach factor, words, focus) (the tooltip
-- takes the words; the other parts tell how the value came about)
function reasons.Each(entry, kind, fn)
    kind = kind or "do"
    for _, reason in ipairs(Of(entry, kind)) do
        local strength = Run(reason, entry)
        if strength then fn(reason, strength, Value(reason, entry, strength, kind)) end
    end
end

function reasons.Test(key, entry)
    local reason = all[key]
    if reason and entry.domain and tContains(reason.sources, entry.domain) then return Run(reason, entry) end
    return nil
end

-- What makes a hidden entry come back: what its reasons have now as text (";key:thing;key:thing;", "" if none). It
-- comes back once there is a thing that was not there (a trainer with a new spell), not when there are fewer.
function reasons.Renew(entry)
    local parts = {}
    for _, reason in ipairs(Of(entry)) do
        if reason.renew and Run(reason, entry) then
            for _, thing in ipairs(reason.renew(entry)) do parts[#parts + 1] = reason.key .. ":" .. tostring(thing) end
        end
    end
    return #parts > 0 and (";" .. table.concat(parts, ";") .. ";") or ""
end
function Renewed(entry, hiddenAs)
    for _, reason in ipairs(Of(entry)) do
        if reason.renew and Run(reason, entry) then
            for _, thing in ipairs(reason.renew(entry)) do
                if not hiddenAs:find(";" .. reason.key .. ":" .. tostring(thing) .. ";", 1, true) then return true end
            end
        end
    end
    return false
end

function reasons.Hidden(entry, id)
    id = id or D.EntryID(entry)
    local hidden = ns.memory.HiddenAs(id)
    if not hidden then return false end
    return not (type(hidden) == "string" and Renewed(entry, hidden))
end

-- an entry's fit: its reasons' values (0: none, also if hidden); kind "do" (default) or "know"
function reasons.Fit(entry, kind)
    kind = kind or "do"
    local fit = fits[kind][entry]
    if fit then return fit end
    fit = 0
    -- 0 also for an NPC or quest of a world event not running now (D.EventAway) and a dungeon of the other side only
    -- (entry.side)
    local otherSide = entry.domain == "dungeons" and entry.side and entry.side ~= UnitFactionGroup("player")
    if reasons.Hidden(entry) or D.EventAway(entry) or otherSide then
        fits[kind][entry], strongest[kind][entry] = 0, false
        return 0
    end
    -- the strongest reason that has a note (one without, like skillUp, must not hide another's)
    local best, bestValue = nil, 0
    local top = 0
    for _, reason in ipairs(Of(entry, kind)) do
        local strength = Run(reason, entry)
        if strength then
            local value = Value(reason, entry, strength, kind)
            fit = fit + value
            top = math.max(top, value)
            if reason.note and value > bestValue then best, bestValue = { reason, strength }, value end
        end
    end
    -- the strongest reason counts in full, the others only MORE of theirs (adding them up would let several small ones
    -- beat one clearly better)
    fit = top + MORE * (fit - top)
    fits[kind][entry] = fit
    strongest[kind][entry] = best or false
    return fit
end

-- true if another row stands for everything an entry is suggested for
-- (the lists leave it out: Relevant.lua); only for doing
function reasons.Covered(entry, kind)
    if (kind or "do") ~= "do" or reasons.Fit(entry) <= 0 then return false end
    for _, reason in ipairs(Of(entry)) do
        if Run(reason, entry) and not (reason.covered and reason.covered(entry)) then return false end
    end
    return true
end

-- the entry ID of the row that stands for getting an entry (a reason's via), nil if none; doing only
function reasons.Via(entry)
    for _, reason in ipairs(Of(entry)) do
        if reason.via and Run(reason, entry) then
            local id = reason.via(entry)
            if id then return id end
        end
    end
    return nil
end

function reasons.Group(entry)
    for _, reason in ipairs(Of(entry)) do
        if reason.group and Run(reason, entry) then
            local key = reason.group(entry)
            if key then return key end
        end
    end
    return nil
end

function reasons.Keys(entry, kind)
    local keys = {}
    if reasons.Fit(entry, kind) <= 0 then return keys end
    for _, reason in ipairs(Of(entry, kind)) do
        if Run(reason, entry) then keys[#keys + 1] = reason.key end
    end
    return keys
end

function reasons.Topics(entry)
    local topics = {}
    if reasons.Fit(entry) <= 0 then return topics end
    for _, reason in ipairs(Of(entry)) do
        if reason.topic and Run(reason, entry) then
            local topic = type(reason.topic) == "function" and reason.topic(entry) or reason.topic
            if not TOPIC[topic] then
                error(("reason %s: unknown topic %s (reasons.TOPICS)"):format(reason.key, tostring(topic)))
            end
            topics[topic] = true
        end
    end
    return topics
end

local function NoteText(note)
    return type(note) == "table" and note.tip or type(note) == "string" and note or nil
end
reasons.NoteText = NoteText

-- the errand an entry stands for: its strongest reason with a note and what the note says ("service:Repairs: ...");
-- nil if none. A list shows one NPC per errand (Relevant.lua). Kept until the next Prepare, like the fits.
function reasons.Errand(entry, kind)
    kind = kind or "do"
    local known = errands[kind][entry]
    if known ~= nil then return known or nil end
    reasons.Fit(entry, kind)
    local best = strongest[kind][entry]
    local errand = best and best[1].errand ~= false
        and (best[1].key .. ":" .. tostring(NoteText(best[1].note(entry, best[2])))) or false
    errands[kind][entry] = errand
    return errand or nil
end

function reasons.Note(entry, kind)
    reasons.Fit(entry, kind)
    local best = strongest[kind or "do"][entry]
    if not best then return nil end
    local note = best[1].note(entry, best[2]) -- only reasons with a note are kept as strongest
    return note, best[1].key
end

local function Sentence(reason, entry, strength)
    local text = reason.why and reason.why(entry, strength)
    if not text and reason.note then text = NoteText(reason.note(entry, strength)) end
    return text
end
reasons.Sentence = Sentence

-- Bundling: what else you can do where an NPC stands: the reasons of the NPCs around it (not hidden) that it lacks
-- itself, each kind once, from the one where it is worth most (two repairers side by side are one errand).
-- List of { entry, value, reason, strength }, most worth first. Doing only.
local function Bundle(entry)
    if not entry.npcID then return NONE end
    local list = bundles[entry]
    if list then return list end
    local own = {}
    for _, reason in ipairs(Of(entry)) do
        if Run(reason, entry) then own[reason.key] = true end
    end
    local best = {}
    local fit = reasons.Fit(entry)
    for _, npcID in ipairs(ns.reach.Neighbours(entry)) do
        local other = D.EntryByID("n:" .. npcID)
        local otherFit = other and reasons.Fit(other) or 0
        if otherFit > 0 and otherFit < fit then
            for _, reason in ipairs(Of(other)) do
                local strength = not own[reason.key] and Run(reason, other)
                if strength then
                    local value = Value(reason, other, strength)
                    if not best[reason.key] or value > best[reason.key][2] then
                        best[reason.key] = { other, value, reason, strength }
                    end
                end
            end
        end
    end
    list = {}
    for _, item in pairs(best) do list[#list + 1] = item end
    table.sort(list, function(a, b) return a[2] > b[2] end)
    bundles[entry] = list
    return list
end
reasons.Bundle = Bundle

-- every reason an entry has, as sentences for its tooltip (strongest first),
-- with its reach; then what stands with it (doing)
function reasons.Explain(entry, kind)
    kind = kind or "do"
    local lines, sorted = {}, {}
    if reasons.Fit(entry, kind) <= 0 then return lines end
    -- not what the engine learned about a reason ("you seldom follow this"): puzzling in a tooltip
    reasons.Each(entry, kind, function(reason, strength, value, _, _, words)
        local text = Sentence(reason, entry, strength)
        if not text then return end
        -- the sentence, then the way to it as a detail line (AddWhy shows what follows a newline in gray)
        if words then text = text .. "\n" .. words end
        sorted[#sorted + 1] = { text, value }
    end)
    -- sorted list of pairs, not keyed by text: two reasons with the same sentence would share a value
    table.sort(sorted, function(a, b) return a[2] > b[2] end)
    for i, item in ipairs(sorted) do lines[i] = item[1] end
    if kind == "do" then
        local bundle = Bundle(entry)
        for i = 1, math.min(#bundle, 2) do
            local item = bundle[i]
            local why = Sentence(item[3], item[1], item[4])
            lines[#lines + 1] = L["Right there too: %s"]:format(item[1].name .. (why and (" (" .. why .. ")") or ""))
        end
    end
    return lines
end

function reasons.All() return all end

-- an entry's fit as the lists weigh it: plus what stands with it (an NPC, doing), less for what you passed over lately
-- or just did (id: its D.EntryID, if known)
function reasons.Weighed(entry, id, kind)
    kind = kind or "do"
    local fit = reasons.Fit(entry, kind)
    if fit <= 0 then return 0 end
    id = id or D.EntryID(entry)
    if kind == "do" then
        for _, item in ipairs(Bundle(entry)) do fit = fit + BUNDLE * item[2] end
    end
    return fit * (1 - TIRED * ns.memory.Tired(id, kind)) * Satisfied(id, entry, kind)
end

-- Sorts a list opened without text, in place: weighed fit, then how much you use it (only a tie breaker: habit is no
-- recommendation), then the source's own order (tiebreak(a, b): true, false or nil when equal), then A-Z.
function reasons.Sort(list, tiebreak, kind)
    kind = kind or "do"
    local Used = ns.memory.UsedNow()
    local score, used = {}, {}
    for _, entry in ipairs(list) do
        local id = D.EntryID(entry)
        score[entry] = reasons.Weighed(entry, id, kind)
        used[entry] = Used(id)
    end
    table.sort(list, function(a, b)
        if score[a] ~= score[b] then return score[a] > score[b] end
        if used[a] ~= used[b] then return used[a] > used[b] end
        if tiebreak then
            local order = tiebreak(a, b)
            if order ~= nil then return order end
        end
        return a.key < b.key
    end)
    return list
end

function reasons.EachCandidates(kind, add)
    for _, reason in ipairs(all) do
        if reason.candidates and (reason.kind == kind or reason.kind == "both") then reason.candidates(add) end
    end
end
