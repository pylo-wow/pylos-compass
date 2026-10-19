local ns = select(2, ...).search

-- Filter machinery (the filters are in Filters\*.lua, registered with ns.RegisterFilter).
-- Index.lua asks here before a search: which sources to search, which entries pass, whether a
-- small pool can stand in for the index, and which filters to suggest for a text.

local filter = {}
ns.filter = filter

local function AppliesTo(f, source)
    return not f.sources or tContains(f.sources, source.key)
end

filter.AppliesTo = AppliesTo

-- the set filters by group: filters of one group are alternatives
local function Groups(filters)
    local groups, byName = {}, {}
    for _, f in ipairs(filters) do
        local name = f.group or f.key
        local group = byName[name]
        if not group then
            group = {}
            byName[name] = group
            groups[#groups + 1] = group
        end
        group[#group + 1] = f
    end
    return groups
end

-- Gets the set filters ready for one search. Returns:
--   passes(entry)   true if the entry passes every group (nil: no filters)
--   searches(src)   true if the source can hold passing entries
--   pool            the only entries that can pass, if a group consists of
--                   filters with pools (else nil)
--   reveal          true if a filter asks for hidden entries
function filter.Prepare(filters)
    if #filters == 0 then return nil, function() return true end, nil, false end
    local reveal = false
    for _, f in ipairs(filters) do
        if f.prepare then f.prepare() end
        if f.reveals then reveal = true end
    end
    local groups = Groups(filters)

    local function passes(entry)
        for _, group in ipairs(groups) do
            local ok = false
            for _, f in ipairs(group) do
                if AppliesTo(f, entry.source) and f.test(entry) then
                    ok = true
                    break
                end
            end
            if not ok then return false end
        end
        return true
    end

    local function searches(source)
        for _, group in ipairs(groups) do
            local ok = false
            for _, f in ipairs(group) do
                if AppliesTo(f, source) then ok = true end
            end
            if not ok then return false end
        end
        return true
    end

    -- the smallest group whose filters all have pools stands in for the index
    local pool
    for _, group in ipairs(groups) do
        local list, complete = {}, true
        if #group == 1 and group[1].pool then
            list = group[1].pool() -- one filter's pool as it is, not copied
        else
            for _, f in ipairs(group) do
                if not f.pool then
                    complete = false
                    break
                end
                for _, entry in ipairs(f.pool()) do list[#list + 1] = entry end
            end
        end
        if complete and (not pool or #list < #pool) then pool = list end
    end
    return passes, searches, pool, reveal
end

-- Adds to out the filters a typed text asks for. Subcategories first: their name starts with the
-- text (2 characters inside their category, 3 elsewhere; offered ones only). Then the other
-- filters: "#" alone all, "#text" those whose name or words start with every typed word
-- ("#not ba" -> "Not on bars"), 3+ characters those whose name starts with it. Set filters and
-- ones not fitting the category are left out.
function filter.Suggest(query, filters, scope, out)
    local hash = query:sub(1, 1) == "#"
    if hash then query = strtrim(query:sub(2)) end
    local set = {}
    for _, f in ipairs(filters) do set[f] = true end
    if not hash and #query >= (scope and 2 or 3) then
        for _, source in ipairs(scope and { scope } or ns.ActiveSources()) do
            for _, f in ipairs(ns.Subcategories(source)) do
                if not set[f] and f.entry.key:sub(1, #query) == query then out[#out + 1] = f.entry end
            end
        end
    end
    if not hash and #query < 3 then return false end
    for _, f in ipairs(ns.filters) do
        if not f.subcategory and not set[f] and (not scope or AppliesTo(f, scope)) then
            local fits = f.entry.key:sub(1, #query) == query
            if hash then
                fits = true
                for word in query:gmatch("%S+") do
                    if not (" " .. f.find):find(" " .. word, 1, true) then
                        fits = false
                        break
                    end
                end
            end
            if fits then out[#out + 1] = f.entry end
        end
    end
    return hash -- "#": only filters, no search
end
