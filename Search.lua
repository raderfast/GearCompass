local _, FG = ...
local api = C_Item or _G
local itemCache, instantCache = {}, {}
local active

function FG.CancelSearch()
    if FG.ticker then FG.ticker:Cancel(); FG.ticker = nil end
    if active and active.events then active.events:UnregisterAllEvents() end
    active = nil
end

local function matches(loc, class, subclass, options)
    if class and class ~= 2 and class ~= 4 then return false end
    if loc and loc ~= "" and options.slot ~= "ALL" and loc ~= options.slot then return false end
    if class == 4 and options.armor > 0 and subclass and subclass >= 1 and subclass <= 4 and subclass ~= options.armor then return false end
    return true
end

function FG.Search(options, callback, onProgress)
    FG.CancelSearch()
    local catalog, skipped, warning = FG.Provider.Load()
    if not catalog then callback(nil, skipped); return end
    local queue, results = {}, {}
    for _, entry in pairs(catalog) do queue[#queue + 1] = entry end
    local total, index, started = #queue, 1, GetTime()
    local pending, requested, queued, retryQueue = {}, {}, {}, {}
    local pendingCount, failed, retryIndex = 0, 0, 1
    local lastPoll, lastPublish, dirty = started, started, false
    local state = {}; active = state
    local sourceFilter = options.source:lower()

    local function resolve(entry)
        local meta = instantCache[entry.id]
        if not meta and api.GetItemInfoInstant then
            local _, _, _, loc, _, class, subclass = api.GetItemInfoInstant(entry.id)
            if class then
                meta = {loc = loc, class = class, subclass = subclass}
                instantCache[entry.id] = meta
            end
        end
        if meta and not matches(meta.loc, meta.class, meta.subclass, options) then return true end
        -- Resolve source paths only for potential gear, and before server requests.
        local source = FG.Provider.ResolveSources(entry)
        if not source or (sourceFilter ~= "" and not source:lower():find(sourceFilter, 1, true)) then return true end
        local data = itemCache[entry.id]
        if not data then
            local name, link, _, _, level, _, _, _, loc, _, _, class, subclass = api.GetItemInfo(entry.id)
            if not name or not link then
                if not requested[entry.id] then
                    requested[entry.id] = true
                    if api.RequestLoadItemDataByID then api.RequestLoadItemDataByID(entry.id) end
                end
                return false
            end
            if not loc or loc == "" or not matches(loc, class, subclass, options) or (level or 0) > options.level then return true end
            local stats = api.GetItemStats(link)
            if not stats then return false end
            data = {name = name, link = link, level = level or 0, loc = loc, class = class, subclass = subclass, stats = stats}
            itemCache[entry.id] = data
        end
        if data.level > options.level or not matches(data.loc, data.class, data.subclass, options) then return true end
        results[#results + 1] = {id = entry.id, link = data.link, name = data.name, stats = data.stats,
            score = FG.Score(data.stats, options.weights), source = source, slot = data.loc}
        dirty = true
        return true
    end
    local function enqueue(id)
        if pending[id] and not queued[id] then
            queued[id] = true; retryQueue[#retryQueue + 1] = id
        end
    end
    if CreateFrame then
        state.events = CreateFrame("Frame")
        state.events:RegisterEvent("ITEM_DATA_LOAD_RESULT")
        state.events:SetScript("OnEvent", function(_, _, id, success)
            if active ~= state or not pending[id] then return end
            if success == false then
                pending[id] = nil; pendingCount = pendingCount - 1; failed = failed + 1
            else enqueue(id) end
        end)
    end
    local function publish(final)
        local snapshot = {}
        for i, item in ipairs(results) do snapshot[i] = item end
        table.sort(snapshot, function(a, b) return FG.Compare(a, b, options.priority) end)
        local message = string.format("Найдено: %d. Проверено: %d/%d. Не загружено: %d. %.2f сек.%s",
            #results, math.min(index - 1, total), total, pendingCount + failed, GetTime() - started,
            final and "" or " Загрузка…")
        if warning and warning ~= "" then message = message .. " " .. warning end
        if final then FG.CancelSearch(); callback(snapshot, message)
        elseif onProgress then onProgress(snapshot, message) end
        dirty, lastPublish = false, GetTime()
    end
    FG.ticker = C_Timer.NewTicker(0.01, function()
        if active ~= state then return end
        local now, count = GetTime(), 0
        local frameStart = debugprofilestop and debugprofilestop()
        -- Events are the main retry path. A slow fallback covers missing events
        -- and item stats which become available after the item-info event.
        if now - lastPoll >= 1 and retryIndex > #retryQueue then
            retryQueue, retryIndex = {}, 1
            for id in pairs(pending) do enqueue(id) end
            lastPoll = now
        end
        while count < 400 do
            local entry, retryID
            if index <= total then entry = queue[index]; index = index + 1
            elseif retryIndex <= #retryQueue then
                retryID = retryQueue[retryIndex]; retryIndex = retryIndex + 1
                queued[retryID] = nil; entry = pending[retryID]
            else break end
            if entry then
                if resolve(entry) then
                    if pending[entry.id] then pending[entry.id] = nil; pendingCount = pendingCount - 1 end
                elseif not pending[entry.id] then
                    pending[entry.id] = entry; pendingCount = pendingCount + 1
                end
            end
            count = count + 1
            if frameStart and debugprofilestop() - frameStart >= 3 then break end
        end
        if index > total and (pendingCount == 0 or now - started >= 8) then publish(true); return end
        if onProgress and now - lastPublish >= 0.15 and (dirty or index <= total) then publish(false) end
    end)
end
