local _, FG = ...
_G.GearCompass = FG

FG.stats = {
    {"STR", "ITEM_MOD_STRENGTH_SHORT", "Сила"},
    {"AGI", "ITEM_MOD_AGILITY_SHORT", "Ловкость"},
    {"STA", "ITEM_MOD_STAMINA_SHORT", "Выносливость"},
    {"INT", "ITEM_MOD_INTELLECT_SHORT", "Интеллект"},
    {"SPI", "ITEM_MOD_SPIRIT_SHORT", "Дух"},
    {"AP", "ITEM_MOD_ATTACK_POWER_SHORT", "Сила атаки"},
    {"SP", "ITEM_MOD_SPELL_POWER_SHORT", "Сила заклинаний"},
    {"CRIT", "ITEM_MOD_CRIT_RATING_SHORT", "Крит (рейтинг)"},
    {"HIT", "ITEM_MOD_HIT_RATING_SHORT", "Меткость (рейтинг)"},
    {"HASTE", "ITEM_MOD_HASTE_RATING_SHORT", "Скорость (рейтинг)"},
    {"MASTERY", "ITEM_MOD_MASTERY_RATING_SHORT", "Искусность"},
    {"VERS", "ITEM_MOD_VERSATILITY", "Универсальность"},
    {"ARMOR", "RESISTANCE0_NAME", "Броня"},
    {"DEF", "ITEM_MOD_DEFENSE_SKILL_RATING_SHORT", "Защита (рейтинг)"},
    {"DODGE", "ITEM_MOD_DODGE_RATING_SHORT", "Уклонение (рейтинг)"},
    {"PARRY", "ITEM_MOD_PARRY_RATING_SHORT", "Парирование (рейтинг)"},
    {"BLOCK", "ITEM_MOD_BLOCK_RATING_SHORT", "Блок (рейтинг)"},
    {"MP5", "ITEM_MOD_MANA_REGENERATION_SHORT", "Мана / 5 сек."},
}
FG.byKey = {}
for _, stat in ipairs(FG.stats) do FG.byKey[stat[1]] = stat[2] end

function FG.ParseWeights(text)
    local weights = {}
    for line in text:gmatch("[^\r\n]+") do
        local key, value = line:match("^%s*(%w+)%s*=%s*([%+%-]?[%d%.,]+)%s*$")
        key = key and key:upper()
        value = value and tonumber((value:gsub(",", ".")))
        if not key or not FG.byKey[key] or not value or value ~= value or math.abs(value) > 1000000 then
            return nil, "Некорректный вес: " .. line
        end
        weights[key] = value
    end
    return weights
end

function FG.ParsePriority(text)
    local result, seen = {}, {}
    if text:match("^%s*$") then return result end
    if not text:match("^%s*%w+[%w%s>]*$") or text:match(">%s*>") or text:match(">%s*$") then
        return nil, "Приоритет: INT > SP > CRIT"
    end
    for part in (text:upper() .. ">"):gmatch("(.-)>") do
        local key = part:match("^%s*(%w+)%s*$")
        if not key then return nil, "Разделяйте приоритеты знаком >." end
        if not FG.byKey[key] or seen[key] then return nil, "Неизвестный или повторный стат: " .. key end
        seen[key] = true
        result[#result + 1] = key
    end
    return result
end

function FG.Score(stats, weights)
    local score = 0
    for key, weight in pairs(weights) do score = score + (stats[FG.byKey[key]] or 0) * weight end
    return score
end

function FG.Compare(a, b, priority)
    for _, key in ipairs(priority or {}) do
        local av, bv = a.stats[FG.byKey[key]] or 0, b.stats[FG.byKey[key]] or 0
        if av ~= bv then return av > bv end
    end
    if a.score ~= b.score then return a.score > b.score end
    return a.id < b.id
end

function FG.Print(message) print("|cff55ccffGearCompass:|r " .. message) end
