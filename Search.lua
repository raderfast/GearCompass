local _, FG = ...
local api = C_Item or _G
local itemCache, instantCache = {}, {}
local active

-- Inventory slots an item of each equip location would replace. Several slots
-- (rings, trinkets) compare against the weaker piece, the natural upgrade target.
-- One-handers compare with the main hand only: the off hand may hold a shield.
FG.slotIDs = {
    INVTYPE_HEAD={1}, INVTYPE_NECK={2}, INVTYPE_SHOULDER={3}, INVTYPE_CHEST={5}, INVTYPE_ROBE={5},
    INVTYPE_WAIST={6}, INVTYPE_LEGS={7}, INVTYPE_FEET={8}, INVTYPE_WRIST={9}, INVTYPE_HAND={10},
    INVTYPE_FINGER={11, 12}, INVTYPE_TRINKET={13, 14}, INVTYPE_CLOAK={15},
    INVTYPE_WEAPON={16}, INVTYPE_2HWEAPON={16}, INVTYPE_WEAPONMAINHAND={16},
    INVTYPE_WEAPONOFFHAND={17}, INVTYPE_SHIELD={17}, INVTYPE_HOLDABLE={17},
    INVTYPE_RANGED={18}, INVTYPE_RANGEDRIGHT={18}, INVTYPE_THROWN={18}, INVTYPE_RELIC={18},
}

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
    local scorer
    if options.scoring == "pawn" then
        local err
        scorer, err = FG.Pawn.CreateScorer(options.pawnScale)
        if not scorer then callback(nil, err); return end
    end
    local priority = scorer and {} or options.priority
    local catalog, skipped, warning = FG.Provider.Load()
    if not catalog then callback(nil, skipped); return end
    local queue, results = {}, {}
    for _, entry in pairs(catalog) do queue[#queue + 1] = entry end
    local total, index, started = #queue, 1, GetTime()
    local pending, requested, queued, retryQueue = {}, {}, {}, {}
    local pendingCount, failed, retryIndex, uncertain = 0, 0, 1, 0
    local fatal
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
            data = {name = name, link = link, level = level or 0, loc = loc, class = class, subclass = subclass}
            itemCache[entry.id] = data
        end
        if data.level > options.level or not matches(data.loc, data.class, data.subclass, options) then return true end
        local score, approximate
        if scorer then
            local status
            score, status, approximate = scorer.Score(data.link)
            if status == "error" then fatal = approximate; return true end
            if status == "skip" then return true end
            if status == "pending" then return false end
        else
            if not data.stats then data.stats = api.GetItemStats(data.link) end
            if not data.stats then return false end
            score = FG.Score(data.stats, options.weights)
        end
        if approximate then uncertain = uncertain + 1 end
        results[#results + 1] = {id = entry.id, link = data.link, name = data.name, stats = data.stats,
            score = score, source = source, slot = data.loc, approximate = approximate}
        dirty = true
        return true
    end
    -- Score of the equipped piece for an equip location; nil while data loads.
    -- Resolved values are cached for the whole search, missing ones are retried.
    local equippedCache = {}
    local function equipped(loc)
        if equippedCache[loc] then return equippedCache[loc] end
        local ids = FG.slotIDs[loc]
        if not ids or not GetInventoryItemLink then return nil end
        local worst
        for _, slotID in ipairs(ids) do
            local link = GetInventoryItemLink("player", slotID)
            local info = {link = link, slotID = slotID, score = 0}
            if link and scorer then
                local score, status, approximate = scorer.Score(link)
                if status ~= "ok" then return nil end
                info.score, info.approximate = score, approximate
            elseif link then
                info.stats = api.GetItemStats(link)
                if not info.stats then return nil end
                info.score = FG.Score(info.stats, options.weights)
            end
            if not worst or info.score < worst.score then worst = info end
        end
        equippedCache[loc] = worst
        return worst
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
        if scorer then
            local valid, err = scorer.Validate()
            if not valid then FG.CancelSearch(); callback(nil, err); return end
        end
        local snapshot = {}
        for i, item in ipairs(results) do
            local current = equipped(item.slot)
            item.delta = current and item.score - current.score or nil
            snapshot[i] = item
        end
        if options.slot ~= "ALL" then snapshot.equipped = equipped(options.slot) end
        local progress = total > 0 and math.min(index - 1, total) / total or 1
        table.sort(snapshot, function(a, b) return FG.Compare(a, b, priority) end)
        local message = string.format("Найдено: %d. Проверено: %d/%d. Не загружено: %d. %.2f сек.%s",
            #results, math.min(index - 1, total), total, pendingCount + failed, GetTime() - started,
            final and "" or " Загрузка…")
        if warning and warning ~= "" then message = message .. " " .. warning end
        if scorer then message = message .. " Pawn: " .. (options.pawnLabel or options.pawnScale) .. ". С оговорками (*): " .. uncertain end
        if final then FG.CancelSearch(); callback(snapshot, message, 1)
        elseif onProgress then onProgress(snapshot, message, progress) end
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
            if fatal then FG.CancelSearch(); callback(nil, fatal); return end
            count = count + 1
            if frameStart and debugprofilestop() - frameStart >= 3 then break end
        end
        if index > total and (pendingCount == 0 or now - started >= 8) then publish(true); return end
        if onProgress and now - lastPublish >= 0.15 and (dirty or index <= total) then publish(false) end
    end)
end
