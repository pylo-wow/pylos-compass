local ns = select(2, ...).advice
if ns.off then return end
local D = ns.data

-- Nudges: unprompted alerts with a rule set of their own (Pushes.lua), on the same facts as the window (reasons, reach, memory).
-- A wrong nudge costs more trust than a right one earns. Every candidate passes a chain of gates:
--   big (large gain), missable (now much cheaper than later), sure (hard facts only, no unchecked 1.12 data),
--   new (not nudged for this situation, not just done, not "Don't suggest"),
--   moment (a pause: after combat/loot/landing, new zone, resting, loading screen; never in combat, on a flight, in an instance group),
--   budget (medium at most every MEDIUM_EVERY, loud every LOUD_EVERY; a rule may own its budget)
-- Levels (Toast.lua): 1 quiet (button glow, tab dot), 2 medium (short note, at a moment), 3 loud (note and sound until answered, out of combat).
-- A rule gives its highest level; one lower when 2 of the last 3 were ignored/"Later", by options (a level switched off gives the one below), quiet over budget.
-- "Never for this" switches the rule off. Every decision, near miss (one gate failed) and outcome goes to ns.Log (Log.lua, dev build).
--   ns.RegisterPush(rule): rule = { key, label, level, topic (tab for the dot, or nil), states (Data states to re-evaluate on), ownBudget, candidates(add) }
--   add(c): c = { situation (identity: nudges once per AGAIN seconds), entry, title, text, icon, level,
--   action = { kind = "item" | "macro" | "waypoint", value, name }, big/missable/sure = { ok, words } }

local push = {}
ns.push = push

local QUIET, MEDIUM, LOUD = 1, 2, 3
push.QUIET, push.MEDIUM, push.LOUD = QUIET, MEDIUM, LOUD
local LEVEL_NAMES = { "quiet", "medium", "loud" }
push.LEVEL_NAMES = LEVEL_NAMES
local MEDIUM_EVERY, LOUD_EVERY = 15 * 60, 60 * 60
local AGAIN = 24 * 3600     -- seconds before the same situation may nudge again
local LATER = 10 * 60       -- seconds "Later" holds
local FOLLOW = 30 * 60      -- seconds a shown nudge waits to be followed
local MOMENT = 30           -- seconds a pause lasts after its event
local JUST_DONE = 30 * 60   -- an entry acted on within this is not new
local HISTORY = 80          -- decisions kept for the debug window

local rules, byKey = {}, {}
push.rules = rules
local pushedAt = {}   -- situation -> time() nudged (also saved per character)
local laterUntil = {} -- situation -> time() before which "Later" holds
local nearLogged = {} -- situation -> true once a near miss is logged
local waiting = {}    -- situation -> { c, rule, level }: waits for a moment
local quiet = {}      -- situation -> { topic, rule key, at }
push.quiet = quiet    -- shared with Toast.lua; do not replace
local shown = {}      -- nudges shown, watched for being followed
local lastAt = { [MEDIUM] = 0, [LOUD] = 0 }
push.history = {}     -- the latest decisions, newest first (Debug.lua)

function ns.RegisterPush(rule)
    rules[#rules + 1] = rule
    byKey[rule.key] = rule
end

local function Enabled(rule)
    return ns.db and ns.db.push ~= false and ns.db["push_" .. rule.key] ~= false
end

-- Log and history

local function Gates(c, moment)
    local parts = {}
    for _, gate in ipairs({ "big", "missable", "sure" }) do
        local g = c[gate] or { false, "?" }
        parts[#parts + 1] = ("%s=%s %s"):format(gate, tostring(g[2] or ""), g[1] and "ok" or "NO")
    end
    if c.new ~= nil then parts[#parts + 1] = ("new=%s %s"):format(c.newWords or "", c.new and "ok" or "NO") end
    if moment ~= nil then parts[#parts + 1] = "moment=" .. (moment and "ok" or "wait") end
    return table.concat(parts, " ")
end

local function Note(outcome, rule, c, level, moment, extra)
    local id = c and c.entry and D.EntryID(c.entry) or "-"
    local gates = c and Gates(c, moment) or ""
    ns.Log("push", outcome, rule.key, id, level and LEVEL_NAMES[level] or "-", gates,
        c and c.situation or "-", extra or "")
    table.insert(push.history, 1, { at = time(), outcome = outcome, rule = rule.key, name = c and (c.entry and c.entry.name or c.title) or "",
        level = level, gates = gates, extra = extra })
    push.history[HISTORY + 1] = nil
end
push.Note = Note

-- Saved per character: situations nudged (time) and the last outcomes per rule
local function Saved()
    local db = ns.db
    if not db then return nil end
    local key = ns.Character()
    if not key then return nil end
    db.pushes[key] = db.pushes[key] or { at = {}, outcomes = {} }
    return db.pushes[key]
end

local function Outcomes(ruleKey)
    local saved = Saved()
    if not saved then return {} end
    saved.outcomes[ruleKey] = saved.outcomes[ruleKey] or {}
    return saved.outcomes[ruleKey]
end

-- keeps the last three outcomes per rule
local function Remember(ruleKey, outcome)
    local list = Outcomes(ruleKey)
    table.insert(list, 1, outcome)
    list[4] = nil
end

-- two of the last three waved away: a level lower
local function Damped(ruleKey)
    local away = 0
    for _, outcome in ipairs(Outcomes(ruleKey)) do
        if outcome == "ignored" or outcome == "later" then away = away + 1 end
    end
    return away >= 2
end

-- Moments

local momentUntil = 0
local function Blocked()
    if InCombatLockdown() then return "combat" end
    if UnitOnTaxi and UnitOnTaxi("player") then return "flight" end
    if IsInInstance() and IsInGroup() then return "group instance" end
    return nil
end
function push.Moment()
    return GetTime() < momentUntil and Blocked() == nil
end

local Evaluate
local pauseDue, pauseTimer -- when the pause evaluation is due; whether its timer runs
local function Pause(delay)
    pauseDue = math.max(pauseDue or 0, GetTime() + (delay or 0))
    if pauseTimer then return end
    local function Fire()
        local wait = pauseDue - GetTime()
        if wait > 0.001 then return C_Timer.After(wait, Fire) end
        pauseTimer, pauseDue = false, nil
        momentUntil = GetTime() + MOMENT
        Evaluate("moment")
    end
    pauseTimer = true
    C_Timer.After(delay or 0, Fire)
end
ns.On("PLAYER_REGEN_ENABLED", function() Pause(2) end)
ns.On("LOOT_CLOSED", function() Pause(0.5) end)
ns.On("PLAYER_CONTROL_GAINED", function() Pause(1) end) -- landed after a flight
ns.On("ZONE_CHANGED_NEW_AREA", function() Pause(1) end)
ns.On("ZONE_CHANGED", function() Pause(1) end)
ns.On("PLAYER_UPDATE_RESTING", function() Pause(1) end)
ns.On("PLAYER_ENTERING_WORLD", function() Pause(3) end)
-- combat: hide the note (its secure button cannot stay)
ns.On("PLAYER_REGEN_DISABLED", function()
    momentUntil = 0
    if push.Interrupt then push.Interrupt() end
end)

-- Quiet

-- topic has a quiet nudge (tab dot)
function push.QuietTopic(topic)
    for _, q in pairs(quiet) do
        if q.topic == topic then return true end
    end
    return false
end
function push.HasQuiet() return next(quiet) ~= nil end
-- Window opened or tab looked at: clears the dots. Returns the entries of the quiet nudges seen (entry -> true); the window shows them first, with the dot (Window.lua).
function push.SeenTopic(topic)
    local entries = {}
    for situation, q in pairs(quiet) do
        if q.topic == topic or topic == nil then
            if q.entry then entries[q.entry] = true end
            quiet[situation] = nil
        end
    end
    if push.QuietChanged then push.QuietChanged() end
    return entries
end
-- topic of the newest quiet nudge newer than since (last window open): the window opens there
function push.NewestQuietTopic(since)
    local best
    for _, q in pairs(quiet) do
        if q.topic and q.at > since and (not best or q.at > best.at) then best = q end
    end
    return best and best.topic
end

-- Deciding

local function New(c)
    local saved = Saved()
    local at = pushedAt[c.situation] or (saved and saved.at[c.situation])
    if at and time() - at < (c.again or AGAIN) then return false, "nudged before" end
    if laterUntil[c.situation] and time() < laterUntil[c.situation] then return false, "later" end
    local entry = c.entry
    if entry then
        local id = D.EntryID(entry)
        if id and ns.reasons.Hidden(entry, id) then return false, "don't suggest" end
        if not c.anyway then
            local since = id and ns.memory.SinceActed(id)
            if since and since < JUST_DONE then return false, "just done" end
            -- another NPC of the same errand counts as done (Reasons.lua Satisfied)
            if entry.npcID and ns.reasons.Satisfied(id, entry) < 0.5 then return false, "errand done" end
        end
    end
    return true, "yes"
end

-- level of a candidate: its rule's or its own, one lower when waved away, then by options
local function Level(rule, c)
    local level = math.min(rule.level, c.level or rule.level)
    if Damped(rule.key) then level = level - 1 end
    local db = ns.db
    if level == LOUD and db.pushLoud == false then level = MEDIUM end
    if level == MEDIUM and db.pushMedium == false then level = QUIET end
    if level == QUIET and db.pushQuiet == false then level = 0 end
    return level
end

local function Show(rule, c, level)
    pushedAt[c.situation] = time()
    local saved = Saved()
    if saved then saved.at[c.situation] = time() end
    waiting[c.situation] = nil
    if level == QUIET then
        quiet[c.situation] = { topic = rule.topic, rule = rule.key, at = time(), entry = c.entry }
        if push.QuietChanged then push.QuietChanged() end
    else
        if not rule.ownBudget then lastAt[level] = time() end
        push.Toast(rule, c, level)
    end
    shown[#shown + 1] = { rule = rule, c = c, level = level, at = time(),
        id = c.entry and D.EntryID(c.entry) or nil }
    Note("shown", rule, c, level, level == QUIET or push.Moment())
end

local function Decide(rule, c, present)
    present[c.situation] = true
    local new, words = New(c)
    c.new, c.newWords = new, words
    local failed, failedGate = 0, nil
    for _, gate in ipairs({ "big", "missable", "sure", "new" }) do
        local ok = gate == "new" and new or (c[gate] and c[gate][1])
        if not ok then
            failed = failed + 1
            failedGate = gate
        end
    end
    if failed > 0 then
        -- near miss: one gate short (except "nudged before")
        if failed == 1 and not (failedGate == "new" and words == "nudged before") and not nearLogged[c.situation] then
            nearLogged[c.situation] = true
            Note("near", rule, c, nil, nil, failedGate)
        end
        return
    end
    local level = Level(rule, c)
    if level <= 0 then return end
    -- over the budget: quiet instead
    if level > QUIET and not rule.ownBudget and time() - lastAt[level] < (level == LOUD and LOUD_EVERY or MEDIUM_EVERY) then
        Note("budget", rule, c, level)
        level = QUIET
    end
    -- medium waits for a pause; loud only for the fight to end; one note at a time
    local blocked = Blocked()
    local ready = level == QUIET or (level == LOUD and blocked ~= "combat" and blocked ~= "flight")
        or (level == MEDIUM and push.Moment())
    if ready and level > QUIET and push.Busy and push.Busy(level) then ready = false end
    if not ready then
        if not waiting[c.situation] then
            waiting[c.situation] = { c = c, rule = rule, level = level }
            Note("waited", rule, c, level, false, blocked or "no pause")
        end
        return
    end
    Show(rule, c, level)
end

-- followed (entry acted on since) or gone (reason went away); also prunes waiting and quiet
local function Watch(present)
    local now = time()
    for i = #shown, 1, -1 do
        local s = shown[i]
        local since = s.id and ns.memory.SinceActed(s.id)
        if since and since <= now - s.at then
            Note("followed", s.rule, s.c, s.level, nil, ("%d s"):format(now - s.at))
            Remember(s.rule.key, "followed")
            table.remove(shown, i)
        elseif not present[s.c.situation] then
            Note("gone", s.rule, s.c, s.level, nil, ("%d s"):format(now - s.at))
            if push.Gone then push.Gone(s.c.situation) end
            table.remove(shown, i)
        elseif now - s.at > FOLLOW then
            table.remove(shown, i)
        end
    end
    for situation, w in pairs(waiting) do
        if not present[situation] then
            Note("dropped", w.rule, w.c, w.level)
            waiting[situation] = nil
        end
    end
    for situation in pairs(quiet) do
        if not present[situation] then quiet[situation] = nil end
    end
end

local running = false
function Evaluate(why)
    if running or not ns.db or ns.db.push == false or ns.db.adviceOn == false or InCombatLockdown() then return end
    running = true
    local present = {}
    local ok, problem = pcall(function()
        D.RefreshOwned()
        ns.reasons.Refresh() -- rules read current reasons
    end)
    if ok then
        local allRan = true
        for _, rule in ipairs(rules) do
            if Enabled(rule) then
                local done, err = pcall(rule.candidates, function(c) Decide(rule, c, present) end)
                if not done then
                    allRan = false
                    geterrorhandler()(err)
                end
            end
        end
        if allRan then
            ok, problem = pcall(function()
                Watch(present)
                if push.QuietChanged then push.QuietChanged() end
            end)
        end
    end
    running = false
    if not ok then geterrorhandler()(problem) end
end
push.Evaluate = Evaluate

-- re-evaluate once shortly after rule states change (batches changes)
local due = false
local function Soon()
    if due then return end
    due = true
    C_Timer.After(1, function()
        due = false
        Evaluate("state")
    end)
end
-- Call after the rules are registered (end of Pushes.lua); Data has loaded, so its D.OnLoaded is past.
function push.Start()
    local states, seen = {}, {}
    for _, rule in ipairs(rules) do
        for _, state in ipairs(rule.states or {}) do
            if not seen[state] then
                seen[state] = true
                states[#states + 1] = state
            end
        end
    end
    if #states > 0 then D.OnState(states, Soon) end
end

-- Answers from the note (Toast.lua)

function push.Answer(rule, c, level, answer)
    if answer == "later" then
        laterUntil[c.situation] = time() + LATER
        pushedAt[c.situation] = nil
        local saved = Saved()
        if saved then saved.at[c.situation] = nil end
    elseif answer == "never" then
        ns.db["push_" .. rule.key] = false
    elseif answer == "interrupted" or answer == "replaced" then
        -- combat or a louder note: may come again later
        pushedAt[c.situation] = nil
        local saved = Saved()
        if saved then saved.at[c.situation] = nil end
    end
    -- only real answers count for the level, not samples
    if not rule.sample and (answer == "ignored" or answer == "later" or answer == "clicked" or answer == "never") then
        Remember(rule.key, answer)
    end
    -- answered: no longer watched (no second log line for clicked)
    for i = #shown, 1, -1 do
        if shown[i].c == c then table.remove(shown, i) end
    end
    Note(answer, rule, c, level)
end

-- drop saved situations older than AGAIN (at load)
function push.Prune()
    local now = time()
    for _, saved in pairs(ns.db.pushes) do
        for situation, at in pairs(saved.at or {}) do
            if now - at > AGAIN then saved.at[situation] = nil end
        end
    end
end
