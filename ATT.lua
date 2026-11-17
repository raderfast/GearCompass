local _, FG = ...
FG.Provider = {}

local function textFor(group)
    local ok, value = pcall(function() return group.text or group.name end)
    if ok and type(value) == "string" and value ~= "" then
        return value:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    end
    for _, field in ipairs({"questID", "npcID", "creatureID", "instanceID", "mapID", "professionID", "headerID"}) do
        local id = rawget(group, field)
        if id then return field .. ":" .. tostring(id) end
    end
end

local function sourceFor(group)
    local parts, seen, current, available = {}, {}, group, true
    for depth = 1, 32 do
        if type(current) ~= "table" or seen[current] then break end
        seen[current] = true
        -- ATT's InGame filter uses u <= 2 for content not in the game.
        local u = rawget(current, "u")
        if type(u) == "number" and u <= 2 then available = false end
        if depth > 1 then
            local text = textFor(current)
            if text then table.insert(parts, 1, text) end
        end
        current = rawget(current, "parent") or rawget(current, "sourceParent")
    end
    -- ATT's root window node adds nothing to a path; keep only real categories.
    if #parts > 1 and parts[1]:upper() == "ALL THE THINGS" then table.remove(parts, 1) end
    if #parts == 0 then parts[1] = "ALL THE THINGS: источник не указан" end
    return table.concat(parts, " / "), available
end

function FG.Provider.ResolveSources(entry)
    if entry.sourceText then return entry.sourceText end
    local sources = entry.sources or {}
    for _, group in ipairs(entry.references or {}) do
        if type(group) == "table" then
            local source, available = sourceFor(group)
            if available then sources[source] = true end
        end
    end
    local sorted = {}
    for source in pairs(sources) do sorted[#sorted + 1] = source end
    if #sorted == 0 then return nil end
    table.sort(sorted)
    entry.sourceText = table.concat(sorted, "; ")
    return entry.sourceText
end

function FG.Provider.Collect(att, lazy)
    if type(att.GetRawFieldContainer) ~= "function" then
        return nil, "Версия ATT не поддерживается: нет GetRawFieldContainer."
    end
    if not att.IsForever then return nil, "Нужна база ALL THE THINGS для клиента Forever." end
    -- Use the default database index, not the filtered UI and not all caches:
    -- ATT stores NeverImplemented and other hidden content in separate caches.
    local cache = att.GetRawFieldContainer("itemID")
    if type(cache) ~= "table" or not next(cache) then
        return nil, "ATT ещё загружает базу. Дождитесь загрузки и повторите поиск."
    end
    local items, skipped = {}, 0
    for id, references in pairs(cache) do
        if type(id) == "number" and id > 0 and id % 1 == 0 and type(references) == "table" then
            if lazy then
                items[id] = {id = id, references = references}
            else
            for _, group in ipairs(references) do
                if type(group) == "table" then
                    local source, available = sourceFor(group)
                    if available then
                        local entry = items[id] or {id = id, sources = {}}
                        entry.sources[source] = true
                        items[id] = entry
                    else skipped = skipped + 1 end
                end
            end
            end
        end
    end
    return items, skipped
end

local cachedATT, cachedIndex, cachedItems, cachedSkipped, hookedATT
function FG.Provider.Invalidate()
    cachedATT, cachedIndex, cachedItems, cachedSkipped = nil, nil, nil, nil
end

function FG.Provider.Load()
    if InCombatLockdown() then return nil, "Откройте поиск вне боя." end
    local att = _G.AllTheThings
    if not att then return nil, "Установите и включите ALL THE THINGS для Forever." end
    local index = att.GetRawFieldContainer and att.GetRawFieldContainer("itemID")
    if cachedATT == att and cachedIndex == index and cachedItems then
        return cachedItems, cachedSkipped, ""
    end
    if hookedATT ~= att and att.AddEventHandler then
        att.AddEventHandler("OnDataCached", FG.Provider.Invalidate)
        att.AddEventHandler("OnReady", FG.Provider.Invalidate)
        hookedATT = att
    end
    local items, skipped = FG.Provider.Collect(att, true)
    if not items then return nil, skipped end
    cachedATT, cachedIndex, cachedItems, cachedSkipped = att, index, items, skipped
    return items, skipped, ""
end
