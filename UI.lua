local _, FG = ...
local slots = {
    {"ALL", "Все слоты"}, {"INVTYPE_HEAD", "Голова"}, {"INVTYPE_NECK", "Шея"},
    {"INVTYPE_SHOULDER", "Плечи"}, {"INVTYPE_CHEST", "Грудь"}, {"INVTYPE_ROBE", "Одеяние"},
    {"INVTYPE_CLOAK", "Плащ"}, {"INVTYPE_WRIST", "Запястья"}, {"INVTYPE_HAND", "Кисти рук"},
    {"INVTYPE_WAIST", "Пояс"}, {"INVTYPE_LEGS", "Ноги"}, {"INVTYPE_FEET", "Ступни"},
    {"INVTYPE_FINGER", "Кольцо"}, {"INVTYPE_TRINKET", "Аксессуар"},
    {"INVTYPE_WEAPON", "Одноручное"}, {"INVTYPE_2HWEAPON", "Двуручное"},
    {"INVTYPE_WEAPONMAINHAND", "Правая рука"}, {"INVTYPE_WEAPONOFFHAND", "Левая рука"},
    {"INVTYPE_SHIELD", "Щит"}, {"INVTYPE_HOLDABLE", "Предмет в левой руке"},
    {"INVTYPE_RANGED", "Дальний бой"}, {"INVTYPE_RANGEDRIGHT", "Жезл / стрелковое"}, {"INVTYPE_RELIC", "Реликвия"},
}
local armor = {"Любая броня", "Ткань", "Кожа", "Кольчуга", "Латы"}

local function label(parent, text, x, y)
    local f = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f:SetPoint("TOPLEFT", x, y); f:SetText(text)
    return f
end
local function edit(parent, x, y, w, h, multi)
    local e = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    e:SetPoint("TOPLEFT", x, y); e:SetSize(w, h); e:SetAutoFocus(false)
    e:SetFontObject(ChatFontNormal); e:SetMultiLine(multi or false)
    e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    return e
end
local function button(parent, text, x, y, w, action)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetPoint("TOPLEFT", x, y); b:SetSize(w, 24); b:SetText(text); b:SetScript("OnClick", action)
    return b
end

function FG.Open()
    if FG.window then FG.window:SetShown(not FG.window:IsShown()); return end
    local db = GearCompassDB
    local f = CreateFrame("Frame", "GearCompassWindow", UIParent, "BasicFrameTemplateWithInset")
    FG.window = f
    f:SetSize(940, 650); f:SetPoint("CENTER"); f:SetMovable(true); f:EnableMouse(true)
    f:RegisterForDrag("LeftButton"); f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true); f.TitleText:SetText("GearCompass — подбор экипировки · ALL THE THINGS")
    tinsert(UISpecialFrames, "GearCompassWindow")
    label(f, "Веса: очки за единицу стата", 18, -40)
    local weights = edit(f, 24, -65, 230, 345, true)
    weights:SetMaxLetters(2000); weights:SetText(db.weights)
    label(f, "Строгий приоритет (или пусто)", 18, -420)
    local priority = edit(f, 24, -443, 230, 26)
    priority:SetMaxLetters(300); priority:SetText(db.priority)
    label(f, "Например: INT > SP > CRIT", 18, -476)
    local help = label(f, "", 18, -506)
    help:SetFontObject("GameFontHighlightSmall"); help:SetWidth(235); help:SetJustifyH("LEFT")
    help:SetText("STR сила · AGI ловкость · STA выносл.\nINT интеллект · SPI дух · AP атака\nSP заклинания · CRIT крит · HIT меткость\nHASTE скорость · ARMOR броня\nDEF защита · DODGE уклонение\nPARRY парирование · BLOCK блок\nMP5 мана/5 · MASTERY · VERS")
    local si, ai = db.slot or 1, db.armor or 1
    if not slots[si] then si = 1 end
    if not armor[ai] then ai = 1 end
    button(f, slots[si][2], 280, -38, 170, function(self)
        si = si % #slots + 1; self:SetText(slots[si][2])
    end)
    button(f, armor[ai], 460, -38, 145, function(self)
        ai = ai % #armor + 1; self:SetText(armor[ai])
    end)
    label(f, "Макс. уровень:", 620, -44)
    local level = edit(f, 733, -38, 45, 24)
    level:SetMaxLetters(3); level:SetText(tostring(db.level or UnitLevel("player")))
    label(f, "Источник содержит:", 280, -80)
    local source = edit(f, 432, -73, 330, 26)
    source:SetMaxLetters(120); source:SetText(db.source or "")
    local status = label(f, "Задайте веса и нажмите «Найти».", 280, -113)
    status:SetWidth(635); status:SetJustifyH("LEFT"); status:SetFontObject("GameFontHighlightSmall")
    local rows, results, page = {}, {}, 1
    local pageText = label(f, "", 530, -608)
    local function draw()
        for n, row in ipairs(rows) do
            local item = results[(page - 1) * 10 + n]
            row.item = item; row:SetShown(item ~= nil)
            if item then
                row.title:SetText(string.format("%s   |cffffffff%.2f|r", item.link or item.name, item.score))
                row.source:SetText(item.source)
            end
        end
        pageText:SetText(page .. " / " .. math.max(1, math.ceil(#results / 10)))
    end
    for n = 1, 10 do
        local row = CreateFrame("Button", nil, f)
        row:SetPoint("TOPLEFT", 280, -150 - (n - 1) * 44); row:SetSize(630, 42)
        row.title = label(row, "", 0, 0); row.title:SetWidth(630); row.title:SetJustifyH("LEFT")
        row.source = label(row, "", 0, -19); row.source:SetFontObject("GameFontHighlightSmall")
        row.source:SetWidth(630); row.source:SetJustifyH("LEFT"); row.source:SetWordWrap(false)
        row:SetScript("OnEnter", function(self)
            if not self.item then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetHyperlink(self.item.link)
            GameTooltip:AddLine("Источник: " .. self.item.source, 1, 1, 1, true)
            GameTooltip:AddLine("Класс, фракцию и требования проверьте в подсказке.", 1, 0.7, 0, true)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        row:SetScript("OnClick", function(self)
            if self.item and IsModifiedClick("CHATLINK") then ChatEdit_InsertLink(self.item.link) end
        end)
        rows[n] = row; row:Hide()
    end
    button(f, "Назад", 280, -602, 90, function() page = math.max(1, page - 1); draw() end)
    button(f, "Далее", 810, -602, 90, function() page = math.min(math.max(1, math.ceil(#results / 10)), page + 1); draw() end)
    button(f, "Найти", 795, -38, 105, function(self)
        local parsed, err = FG.ParseWeights(weights:GetText())
        if not parsed then status:SetText(err); return end
        local priorities; priorities, err = FG.ParsePriority(priority:GetText())
        if not priorities then status:SetText(err); return end
        local hasWeight = false
        for _, value in pairs(parsed) do if value ~= 0 then hasWeight = true end end
        if not hasWeight and #priorities == 0 then status:SetText("Задайте ненулевой вес или порядок приоритетов."); return end
        local maxLevel = tonumber(level:GetText())
        if not maxLevel or maxLevel < 1 or maxLevel > 999 or maxLevel % 1 ~= 0 then status:SetText("Уровень: целое число 1–999."); return end
        db.weights, db.priority = weights:GetText(), priority:GetText()
        db.slot, db.armor, db.level, db.source = si, ai, maxLevel, source:GetText()
        self:Disable(); status:SetText("Поиск… найденные предметы появятся сразу.")
        FG.Search({weights = parsed, priority = priorities, slot = slots[si][1], armor = ai - 1, level = maxLevel, source = db.source}, function(found, message)
            self:Enable(); status:SetText(message)
            results, page = found or {}, 1; draw()
        end, function(found, message)
            status:SetText(message)
            results = found; draw()
        end)
    end)
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(_, _, name)
    if name ~= "GearCompass" then return end
    GearCompassDB = GearCompassDB or {}
    -- Neutral starting profile: the player chooses meaningful weights.
    if not GearCompassDB.weights then
        local lines = {}
        for _, stat in ipairs(FG.stats) do lines[#lines + 1] = stat[1] .. "=0" end
        GearCompassDB.weights = table.concat(lines, "\n")
    end
    GearCompassDB.priority = GearCompassDB.priority or ""
    SLASH_GEARCOMPASS1 = "/gc"
    SLASH_GEARCOMPASS2 = "/gearcompass"
    SlashCmdList.GEARCOMPASS = FG.Open
end)
