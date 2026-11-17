local _, GC = ...
GC.Pawn = {}

local function ready()
    for _, name in ipairs({"PawnIsReady", "PawnGetAllScalesEx", "PawnGetScaleTag", "PawnGetItemData", "PawnGetSingleValueFromItem"}) do
        if type(_G[name]) ~= "function" then return nil, "Установите и включите Pawn для Forever (нужен совместимый API)." end
    end
    local ok, value = pcall(PawnIsReady)
    if not ok or not value then return nil, "Pawn ещё не готов. Дождитесь загрузки и повторите поиск." end
    return true
end

function GC.Pawn.Scales()
    local ok, err = ready()
    if not ok then return nil, err end
    local success, scales = pcall(PawnGetAllScalesEx)
    if not success or type(scales) ~= "table" then return nil, "Не удалось получить шкалы Pawn." end
    local result = {}
    for _, scale in ipairs(scales) do
        if type(scale) == "table" and type(scale.Name) == "string" then
            result[#result + 1] = {name = scale.Name, label = scale.LocalizedName or scale.Name}
        end
    end
    return result
end

local function signature(name)
    local scales, err = GC.Pawn.Scales()
    if not scales then return nil, err end
    local found
    for _, scale in ipairs(scales) do if scale.name == name then found = true; break end end
    if not found then return nil, "Шкала Pawn удалена или недоступна. Выберите шкалу заново." end
    local ok, tag = pcall(PawnGetScaleTag, name)
    if not ok or type(tag) ~= "string" then return nil, "Не удалось прочитать настройки шкалы Pawn." end
    -- Pawn's export tag omits normalization. Read that one setting without
    -- modifying Pawn's tables so a change cannot mix two score units in a scan.
    local scale = PawnCommon and PawnCommon.Scales and PawnCommon.Scales[name]
    return tag .. "|" .. tostring(scale and scale.NormalizationFactor)
end

function GC.Pawn.CreateScorer(name)
    if type(name) ~= "string" or name == "" then return nil, "Выберите шкалу Pawn." end
    local initial, err = signature(name)
    if not initial then return nil, err end
    local scorer = {}
    function scorer.Validate()
        local current, message = signature(name)
        if not current then return nil, message end
        if current ~= initial then return nil, "Настройки шкалы Pawn изменились. Повторите поиск." end
        return true
    end
    function scorer.Score(link)
        local ok, item = pcall(PawnGetItemData, link)
        if not ok then return nil, "error", "Ошибка чтения предмета в Pawn: " .. tostring(item) end
        if type(item) ~= "table" or type(item.UnenchantedStats) ~= "table" or not next(item.UnenchantedStats) then return nil, "pending" end
        if item.CanEquip == false then return nil, "skip" end
        -- Pawn's own Compare tab uses the second (unenchanted/base) value.
        local success, currentValue, value = pcall(PawnGetSingleValueFromItem, item, name)
        if not success then return nil, "error", "Ошибка оценки предмета в Pawn: " .. tostring(currentValue) end
        if value == nil then return nil, "pending" end
        if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
            return nil, "error", "Pawn вернул некорректную оценку предмета."
        end
        return value, "ok", type(item.UnknownLines) == "table" and next(item.UnknownLines) ~= nil
    end
    return scorer
end
