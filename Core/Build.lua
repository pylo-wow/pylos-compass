local _, D = ...

-- Builds the domains' entry lists and runs the one background queue all addons share.
-- A built list is never mutated: a rebuild makes a new one, so a host's index made from the old list stays valid.
-- Small domains are built at once behind the loading screen, big ones in the background.


-- Stable merge sort of values by keys, in pausable steps (table.sort cannot be interrupted).
function D.SortSideBySide(keys, values, Pause)
    local n = #keys
    local fromK, fromV, toK, toV = keys, values, {}, {}
    local width = 1
    while width < n do
        local i = 1
        while i <= n do
            local middle, stop = math.min(i + width, n + 1), math.min(i + 2 * width, n + 1)
            local a, b = i, middle
            for k = i, stop - 1 do
                if a < middle and (b >= stop or fromK[a] <= fromK[b]) then
                    toK[k], toV[k], a = fromK[a], fromV[a], a + 1
                else
                    toK[k], toV[k], b = fromK[b], fromV[b], b + 1
                end
                if k % 64 == 0 then Pause() end
            end
            i = stop
        end
        fromK, toK = toK, fromK
        fromV, toV = toV, fromV
        width = width * 2
    end
    if fromK ~= keys then
        for i = 1, n do
            keys[i], values[i] = fromK[i], fromV[i]
            if i % 256 == 0 then Pause() end
        end
    end
end

-- A domain was built or dropped: bump its state and "data" (D.version mirrors "data" for old readers).
local function Changed(key)
    D.BumpState("data:" .. key)
    D.BumpState("data")
    D.version = D.State("data")
end

local function BuildDomain(domain, Pause)
    -- dropped meanwhile (D.Drop): discard the result
    local generation = domain.generation
    if domain.signature then domain.builtSignature = domain.signature() end
    local entries = {}
    domain.collect(entries, Pause)
    local keys = {}
    for i, entry in ipairs(entries) do
        entry.key = D.SearchKey(entry.name)
        keys[i] = entry.key
        if i % 32 == 0 then Pause() end
    end
    D.SortSideBySide(keys, entries, Pause)
    local byItem, byNPC, byEntryID = {}, {}, {}
    for i, entry in ipairs(entries) do
        if entry.itemID then
            byItem[entry.itemID] = entry
        elseif entry.npcID then
            byNPC[entry.npcID] = entry
        else
            local id = D.EntryID(entry)
            if id then byEntryID[id] = entry end
        end
        if i % 64 == 0 then Pause() end
    end
    if domain.generation ~= generation then
        -- a D.Need made while this stale job ran saw it as "waiting" and would never be built
        if D.Needed(domain.key) then D.Rebuild(domain.key) end
        return
    end
    domain.list, domain.byItem, domain.byNPC, domain.byEntryID = entries, byItem, byNPC, byEntryID
    Changed(domain.key)
    D.Announce(domain.key, entries)
end

-- Background
-- A coroutine runs queued jobs (function(Pause)) for BUDGET ms per frame, paused in combat.
-- GetTimePreciseSec because debugprofilestop restarts whenever any addon calls debugprofilestart.
local BUDGET = 3
local function Now() return GetTimePreciseSec() * 1000 end
local queue = {}  -- { job, name } waiting, in order
local running     -- the job's name running right now
local builder, ticker
local sliceStart = 0

local function Pause()
    local elapsed = Now() - sliceStart
    if elapsed < 0 then sliceStart = Now() return end -- the clock started over
    if elapsed > BUDGET then coroutine.yield() end
end

-- No pcall around jobs: WoW's Lua 5.1 cannot yield across it (seen in game). A job error ends the coroutine.
local function Work()
    while #queue > 0 do
        local item = table.remove(queue, 1)
        running = item.name
        item.job(Pause)
        running = nil
    end
end

local function Start()
    builder = coroutine.create(Work)
    ticker = C_Timer.NewTicker(0, function()
        if InCombatLockdown() then return end
        sliceStart = Now()
        local co = builder
        local ok, err = coroutine.resume(co)
        if ok and coroutine.status(co) ~= "dead" then return end
        ticker:Cancel()
        builder = nil
        if not ok then
            -- log with the coroutine's own stack; only the failed job is dropped, the rest continue
            local _, stack = pcall(debugstack, co)
            geterrorhandler()(tostring(err) .. "\n" .. (type(stack) == "string" and stack or ""))
            running = nil
            if #queue > 0 then Start() end
        end
    end)
end

-- Queues a job once per name; urgent runs next after the current one.
function D.Background(name, job, urgent)
    for _, waiting in ipairs(queue) do
        if waiting.name == name then return end
    end
    local item = { name = name, job = job }
    if urgent then table.insert(queue, 1, item) else queue[#queue + 1] = item end
    if not builder then Start() end
end

function D.Idle() return builder == nil and #queue == 0 end
function D.Waiting(name)
    if running == name then return true end
    for _, waiting in ipairs(queue) do
        if waiting.name == name then return true end
    end
    return false
end

-- Building

local function NoPause() end

-- rebuild in the background; the old list stays until then
function D.Rebuild(key)
    local domain = D.domains[key]
    if not domain then return end
    D.Background("domain:" .. key, function(P) BuildDomain(domain, P) end)
end

-- Builds needed domains that are missing: small ones at once, big ones in the background.
function D.BuildMissing()
    for _, domain in ipairs(D.order) do
        if not domain.list and D.Needed(domain.key) and not D.Waiting("domain:" .. domain.key) then
            if domain.background then
                D.Rebuild(domain.key)
            else
                BuildDomain(domain, NoPause)
            end
        end
    end
end

-- TEST/hosts: build at once; refuses while the background builder runs.
function D.BuildNow(key)
    if builder then return false end
    BuildDomain(D.domains[key], NoPause)
    return true
end

-- Frees a domain's list; a queued build is removed, a running one discards its result (generation).
function D.Drop(key)
    local domain = D.domains[key]
    domain.generation = (domain.generation or 0) + 1
    for i = #queue, 1, -1 do
        if queue[i].name == "domain:" .. key then table.remove(queue, i) end
    end
    if not domain.list then return end
    domain.list, domain.byItem, domain.byNPC, domain.byEntryID = nil, nil, nil, nil
    Changed(key)
end

-- Changes
-- Events come in bursts (every skill point fires SKILL_LINES_CHANGED; the professions signature asks 2,666 spells):
-- check once, CHANGE_DELAY after the last one, not in combat.
local CHANGE_DELAY = 2
local changing = {} -- domain -> true while its check waits
local function Check(domain)
    if InCombatLockdown() then
        C_Timer.After(CHANGE_DELAY, function() Check(domain) end)
        return
    end
    changing[domain] = nil
    if not domain.list then return end
    if domain.signature and domain.signature() == domain.builtSignature then return end
    D.Rebuild(domain.key)
end
-- Also asked when a host opens: the skill window's data is not ready behind the loading screen.
-- Skipped while a build is queued/running (it would overwrite this list with an older one).
function D.CheckNow(key)
    local domain = D.domains[key]
    if domain and domain.list and domain.signature and not D.Waiting("domain:" .. key)
            and domain.signature() ~= domain.builtSignature then
        BuildDomain(domain, NoPause)
    end
end

local domainsFor = {} -- event -> domains it may change
local function Changes(event)
    for _, domain in ipairs(domainsFor[event] or {}) do
        if not changing[domain] and domain.list then
            changing[domain] = true
            C_Timer.After(CHANGE_DELAY, function() Check(domain) end)
        end
    end
end
D.On("PLAYER_LOGIN", function()
    -- all domains are registered by now; D.On skips events the client does not know
    for _, domain in ipairs(D.order) do
        for _, name in ipairs(domain.events or {}) do
            if not domainsFor[name] and D.On(name, Changes) then domainsFor[name] = {} end
            if domainsFor[name] then table.insert(domainsFor[name], domain) end
        end
    end
end)
-- small domains are built here, behind the loading screen
D.On("PLAYER_ENTERING_WORLD", function() D.BuildMissing() end)
