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

-- Layout (window 1100x680): settings on the left, filters and result table on the right.
local RX, RW = 288, 790          -- right area x and width
local PAGE, ROW_H = 9, 44
local STAT_COLS, STAT_W = 4, 48
local DELTA_W, SCORE_W = 66, 124
local SCORE_X = RW - DELTA_W - 8 - SCORE_W
local STAT_X = SCORE_X - 8 - STAT_COLS * STAT_W
local NAME_X = 66
local BAR_W = 90
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"

local function label(parent, text, x, y, font)
    local f = parent:CreateFontString(nil, "OVERLAY", font or "GameFontNormal")
    f:SetPoint("TOPLEFT", x, y); f:SetText(text); f:SetJustifyH("LEFT")
    return f
end
local function edit(parent, x, y, w, h)
    local e = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    e:SetPoint("TOPLEFT", x, y); e:SetSize(w, h); e:SetAutoFocus(false)
    e:SetFontObject(ChatFontNormal)
    e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    e:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    return e
end
local function button(parent, text, x, y, w, action, h)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetPoint("TOPLEFT", x, y); b:SetSize(w, h or 24); b:SetText(text)
    if action then b:SetScript("OnClick", action) end
    return b
end
local function rect(parent, layer, r, g, b, a)
    local t = parent:CreateTexture(nil, layer or "BACKGROUND")
    t:SetColorTexture(r, g, b, a or 1)
    return t
end
local function number(value)
    if value == nil then return "—" end
    if value % 1 == 0 then return tostring(value) end
    return string.format("%.1f", value)
end
local function itemIcon(id)
    local get = (C_Item and C_Item.GetItemIconByID) or GetItemIcon
    return id and get and get(id) or QUESTION
end

-- Columns of the result table: strict priorities first, then the heaviest weights.
local function statColumns(priorities, weights)
    local cols, seen, rest = {}, {}, {}
    for _, key in ipairs(priorities) do
        if #cols < STAT_COLS and not seen[key] then cols[#cols + 1] = key; seen[key] = true end
    end
    for key, value in pairs(weights) do
        if value ~= 0 and not seen[key] then rest[#rest + 1] = key end
    end
    table.sort(rest, function(a, b)
        local x, y = math.abs(weights[a]), math.abs(weights[b])
        if x ~= y then return x > y end
        return a < b
    end)
    for _, key in ipairs(rest) do
        if #cols >= STAT_COLS then break end
        cols[#cols + 1] = key
    end
    return cols
end

-- A button that opens a grid of choices. The choice frame is built once and reused.
local openPopup
local function dropdown(parent, x, y, w, caption, items, getIndex, setIndex, columns, itemW)
    label(parent, caption, x + 2, y, "GameFontNormalSmall")
    local b = button(parent, "", x, y - 14, w, nil, 26)
    local arrow = b:CreateTexture(nil, "OVERLAY")
    arrow:SetTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up")
    arrow:SetSize(18, 18); arrow:SetPoint("RIGHT", -4, 0)
    local popup
    function b.Refresh() b:SetText(items[getIndex()]) end
    function b.Close() if popup then popup:Hide() end end
    b:SetScript("OnClick", function()
        if popup and popup:IsShown() then popup:Hide(); return end
        if openPopup and openPopup ~= popup then openPopup:Hide() end
        if not popup then
            columns, itemW = columns or 1, itemW or w
            local rows = math.ceil(#items / columns)
            popup = CreateFrame("Frame", nil, parent, "BackdropTemplate")
            popup:SetPoint("TOPLEFT", b, "BOTTOMLEFT", 0, -2)
            popup:SetSize(columns * (itemW + 4) + 6, rows * 24 + 8)
            popup:SetFrameStrata("DIALOG"); popup:EnableMouse(true)
            popup:SetBackdrop({bgFile = "Interface/Tooltips/UI-Tooltip-Background",
                edgeFile = "Interface/Tooltips/UI-Tooltip-Border", edgeSize = 12,
                insets = {left = 3, right = 3, top = 3, bottom = 3}})
            popup:SetBackdropColor(0.06, 0.05, 0.04, 0.97)
            for i, text in ipairs(items) do
                local col, row = (i - 1) % columns, math.floor((i - 1) / columns)
                button(popup, text, 5 + col * (itemW + 4), -4 - row * 24, itemW, function()
                    setIndex(i); b.Refresh(); popup:Hide()
                end, 22)
            end
        end
        popup:Show(); openPopup = popup
    end)
    b.Refresh()
    return b
end

-- One table row: rank, icon, name/source, stat columns, score bar, delta to equipped.
local function createRow(parent, y)
    local row = CreateFrame("Button", nil, parent)
    row:SetPoint("TOPLEFT", RX, y); row:SetSize(RW, ROW_H)
    row.bg = rect(row, "BACKGROUND", 0.11, 0.09, 0.07, 1); row.bg:SetAllPoints()
    row.rank = label(row, "", 0, -15, "GameFontDisableSmall")
    row.rank:SetWidth(22); row.rank:SetJustifyH("RIGHT")
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetPoint("TOPLEFT", 28, -6); row.icon:SetSize(32, 32)
    row.title = label(row, "", NAME_X, -7)
    row.title:SetWordWrap(false)
    row.source = label(row, "", NAME_X, -25, "GameFontDisableSmall")
    row.source:SetWordWrap(false)
    row.stats = {}
    for i = 1, STAT_COLS do
        local s = label(row, "", STAT_X + (i - 1) * STAT_W, -15, "GameFontHighlightSmall")
        s:SetWidth(STAT_W - 4); s:SetJustifyH("RIGHT")
        row.stats[i] = s
    end
    row.barBg = rect(row, "ARTWORK", 0.04, 0.03, 0.02, 1)
    row.barBg:SetPoint("TOPLEFT", SCORE_X, -18); row.barBg:SetSize(66, 8)
    row.bar = rect(row, "OVERLAY", 0.82, 0.63, 0.25, 1)
    row.bar:SetPoint("TOPLEFT", SCORE_X, -18); row.bar:SetSize(66, 8)
    row.score = label(row, "", SCORE_X + 70, -15, "GameFontHighlight")
    row.score:SetWidth(SCORE_W - 70); row.score:SetJustifyH("RIGHT")
    row.delta = label(row, "", RW - DELTA_W, -15)
    row.delta:SetWidth(DELTA_W - 4); row.delta:SetJustifyH("RIGHT")
    return row
end

local function setNameWidth(row, hasStats)
    local width = (hasStats and STAT_X or SCORE_X) - NAME_X - 8
    row.title:SetWidth(width); row.source:SetWidth(width)
end

local function fillStats(row, columns, stats)
    for i, cell in ipairs(row.stats) do
        local key = columns[i]
        cell:SetShown(key ~= nil)
        if key then
            local value = stats and stats[FG.byKey[key]]
            cell:SetText(value and number(value) or "—")
        end
    end
end

local function setDelta(row, delta)
    if delta == nil then
        row.delta:SetText("—"); row.delta:SetTextColor(0.6, 0.57, 0.5)
    elseif math.abs(delta) < 0.05 then
        row.delta:SetText("0.0"); row.delta:SetTextColor(0.75, 0.71, 0.63)
    else
        row.delta:SetText(string.format("%+.1f", delta))
        if delta > 0 then row.delta:SetTextColor(0.5, 0.82, 0.5)
        else row.delta:SetTextColor(0.88, 0.5, 0.42) end
    end
end

function FG.Open()
    if FG.window then FG.window:SetShown(not FG.window:IsShown()); return end
    local db = GearCompassDB
    local f = CreateFrame("Frame", "GearCompassWindow", UIParent, "BasicFrameTemplateWithInset")
    FG.window = f
    f:SetSize(1100, 680); f:SetPoint("CENTER"); f:SetMovable(true); f:EnableMouse(true)
    f:RegisterForDrag("LeftButton"); f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true); f.TitleText:SetText("GearCompass — подбор экипировки по данным ALL THE THINGS")
    f:SetScript("OnHide", function() if openPopup then openPopup:Hide() end end)
    tinsert(UISpecialFrames, "GearCompassWindow")

    local status, progress
    local scoring, pawnScale = db.scoring or "custom", db.pawnScale
    local lockables = {}

    ---------------------------------------------------------------- left: scoring model
    local divider = rect(f, "ARTWORK", 0.23, 0.19, 0.14, 1)
    divider:SetPoint("TOPLEFT", 274, -28); divider:SetSize(1, 642)
    label(f, "Модель оценки", 16, -34)
    local customButton, pawnButton
    local customPanel = CreateFrame("Frame", nil, f)
    customPanel:SetPoint("TOPLEFT", 0, -88); customPanel:SetSize(272, 580)
    local pawnPanel = CreateFrame("Frame", nil, f)
    pawnPanel:SetPoint("TOPLEFT", 0, -88); pawnPanel:SetSize(272, 580)

    -- Custom weights: every stat at once, scrollable.
    label(customPanel, "Веса", 16, 0)
    local weightsHint = label(customPanel, "очки за 1 ед.", 170, -2, "GameFontDisableSmall")
    weightsHint:SetWidth(80); weightsHint:SetJustifyH("RIGHT")
    local scroll = CreateFrame("ScrollFrame", "GearCompassWeightsScroll", customPanel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 12, -20); scroll:SetSize(222, 392)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(222, #FG.stats * 26 + 4); scroll:SetScrollChild(content)
    local initial = FG.ParseWeights(db.weights or "") or {}
    local weightRows = {}
    local function updateBars()
        local values, max = {}, 0
        for i, row in ipairs(weightRows) do
            local value = tonumber((row.box:GetText():gsub(",", "."))) or 0
            values[i] = value; max = math.max(max, math.abs(value))
        end
        for i, row in ipairs(weightRows) do
            local value = values[i]
            local width = max > 0 and math.abs(value) / max * BAR_W or 0
            row.fill:SetShown(width > 0)
            if width > 0 then row.fill:SetWidth(width) end
            if value < 0 then row.fill:SetColorTexture(0.75, 0.33, 0.25, 1) else row.fill:SetColorTexture(0.82, 0.63, 0.25, 1) end
            row.code:SetAlpha(value == 0 and 0.55 or 1)
        end
    end
    for i, stat in ipairs(FG.stats) do
        local y = -4 - (i - 1) * 26
        local row = {key = stat[1]}
        row.code = label(content, stat[1], 4, y - 5, "GameFontHighlightSmall")
        local hover = CreateFrame("Frame", nil, content)
        hover:SetPoint("TOPLEFT", 0, y); hover:SetSize(158, 22); hover:EnableMouse(true)
        hover:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText(stat[3]); GameTooltip:Show()
        end)
        hover:SetScript("OnLeave", function() GameTooltip:Hide() end)
        local barBg = rect(content, "ARTWORK", 0.04, 0.03, 0.02, 1)
        barBg:SetPoint("TOPLEFT", 64, y - 8); barBg:SetSize(BAR_W, 6)
        row.fill = rect(content, "OVERLAY", 0.82, 0.63, 0.25, 1)
        row.fill:SetPoint("TOPLEFT", 64, y - 8); row.fill:SetSize(BAR_W, 6)
        row.box = edit(content, 168, y, 46, 22)
        row.box:SetMaxLetters(12); row.box:SetJustifyH("RIGHT")
        row.box:SetText(tostring(initial[stat[1]] or 0))
        row.box:SetScript("OnTextChanged", updateBars)
        row.box:SetScript("OnTabPressed", function()
            weightRows[i % #FG.stats + 1].box:SetFocus()
        end)
        weightRows[i] = row
    end
    updateBars()
    local function weightsText()
        local lines = {}
        for _, row in ipairs(weightRows) do
            local text = row.box:GetText():match("^%s*(.-)%s*$")
            lines[#lines + 1] = row.key .. "=" .. (text == "" and "0" or text)
        end
        return table.concat(lines, "\n")
    end

    label(customPanel, "Строгий приоритет", 16, -424)
    local priority = edit(customPanel, 22, -442, 228, 24)
    priority:SetMaxLetters(300); priority:SetText(db.priority or "")
    local priorityHint = label(customPanel, "Например: INT > SP > CRIT.\nПусто — только сумма весов; веса решают ничью.", 16, -472, "GameFontDisableSmall")
    priorityHint:SetWidth(244)

    -- Pawn scales: a paged list of the scales Pawn reports.
    label(pawnPanel, "Шкала Pawn", 16, 0)
    local scaleButtons, choices, offset = {}, {}, 1
    local pawnNote = label(pawnPanel, "Базовая оценка Pawn без текущих чар, как на вкладке Compare. Свои веса и приоритет сохранены, но сейчас не используются.", 16, -380, "GameFontDisableSmall")
    pawnNote:SetWidth(244)
    local function redrawScales()
        for i, b in ipairs(scaleButtons) do
            b.choice = choices[offset + i - 1]; b:SetShown(b.choice ~= nil)
            if b.choice then
                b:SetText(b.choice.label)
                if b.choice.name == pawnScale then b:LockHighlight() else b:UnlockHighlight() end
            end
        end
    end
    for i = 1, 12 do
        scaleButtons[i] = button(pawnPanel, "", 16, -20 - (i - 1) * 27, 240, function(b)
            pawnScale = b.choice.name
            db.scoring, db.pawnScale = "pawn", pawnScale
            redrawScales()
            status:SetText("Оценка Pawn: «" .. b.choice.label .. "», без текущих чар.")
        end)
        lockables[#lockables + 1] = scaleButtons[i]
    end
    button(pawnPanel, "Назад", 16, -348, 80, function() offset = math.max(1, offset - 12); redrawScales() end)
    button(pawnPanel, "Далее", 176, -348, 80, function() if offset + 12 <= #choices then offset = offset + 12 end; redrawScales() end)
    local function loadScales()
        local scales, err = FG.Pawn.Scales()
        choices = {}
        for _, scale in ipairs(scales or {}) do choices[#choices + 1] = {label = scale.label, name = scale.name} end
        offset = 1; redrawScales()
        return err
    end

    local function setMode(mode)
        scoring = mode; db.scoring = mode
        local isPawn = mode == "pawn"
        customPanel:SetShown(not isPawn); pawnPanel:SetShown(isPawn)
        if isPawn then customButton:UnlockHighlight(); pawnButton:LockHighlight()
        else pawnButton:UnlockHighlight(); customButton:LockHighlight() end
        for _, row in ipairs(weightRows) do row.box:ClearFocus() end
        priority:ClearFocus()
        if isPawn then
            local err = loadScales()
            if err then return err end
            if not pawnScale then return "Выберите шкалу Pawn в списке слева." end
            return "Оценка Pawn без текущих чар. Свои веса не используются."
        end
        return "Оценка по своим весам и приоритетам."
    end
    customButton = button(f, "Свои веса", 16, -52, 120, function() status:SetText(setMode("custom")) end, 26)
    pawnButton = button(f, "Шкала Pawn", 138, -52, 120, function() status:SetText(setMode("pawn")) end, 26)
    lockables[#lockables + 1] = customButton; lockables[#lockables + 1] = pawnButton

    ---------------------------------------------------------------- right: filters
    local si, ai = db.slot or 1, db.armor or 1
    if not slots[si] then si = 1 end
    if not armor[ai] then ai = 1 end
    local slotNames = {}
    for i, slot in ipairs(slots) do slotNames[i] = slot[2] end
    local slotDrop = dropdown(f, RX, -32, 160, "Слот", slotNames,
        function() return si end, function(i) si = i end, 3, 150)
    local armorDrop = dropdown(f, RX + 168, -32, 130, "Броня", armor,
        function() return ai end, function(i) ai = i end, 1, 130)
    label(f, "Макс. ур.", RX + 308, -32, "GameFontNormalSmall")
    local level = edit(f, RX + 314, -46, 44, 26)
    level:SetMaxLetters(3); level:SetNumeric(true); level:SetJustifyH("CENTER")
    level:SetText(tostring(db.level or UnitLevel("player")))
    label(f, "Источник содержит", RX + 370, -32, "GameFontNormalSmall")
    local source = edit(f, RX + 376, -46, 290, 26)
    source:SetMaxLetters(120); source:SetText(db.source or "")
    local searchButton

    progress = CreateFrame("StatusBar", nil, f)
    progress:SetPoint("TOPLEFT", RX, -86); progress:SetSize(160, 8)
    progress:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    progress:SetStatusBarColor(0.82, 0.63, 0.25); progress:SetMinMaxValues(0, 1); progress:SetValue(0)
    local progressBg = rect(progress, "BACKGROUND", 0.04, 0.03, 0.02, 1); progressBg:SetAllPoints()
    status = label(f, "Задайте веса и нажмите «Найти».", RX + 172, -84, "GameFontHighlightSmall")
    status:SetWidth(RW - 172); status:SetWordWrap(false)

    ---------------------------------------------------------------- right: table
    local equippedRow = createRow(f, -104)
    equippedRow.bg:SetColorTexture(0.06, 0.05, 0.04, 1)
    equippedRow.rank:SetText("")
    local header = CreateFrame("Frame", nil, f)
    header:SetPoint("TOPLEFT", RX, -152); header:SetSize(RW, 20)
    local headerLine = rect(header, "ARTWORK", 0.23, 0.19, 0.14, 1)
    headerLine:SetPoint("BOTTOMLEFT"); headerLine:SetSize(RW, 1)
    local hRank = label(header, "#", 0, -4, "GameFontNormalSmall"); hRank:SetWidth(22); hRank:SetJustifyH("RIGHT")
    label(header, "Предмет и источник", NAME_X, -4, "GameFontNormalSmall")
    local hStats = {}
    for i = 1, STAT_COLS do
        hStats[i] = label(header, "", STAT_X + (i - 1) * STAT_W, -4, "GameFontNormalSmall")
        hStats[i]:SetWidth(STAT_W - 4); hStats[i]:SetJustifyH("RIGHT")
    end
    local hScore = label(header, "Оценка", SCORE_X, -4, "GameFontNormalSmall")
    hScore:SetWidth(SCORE_W); hScore:SetJustifyH("RIGHT")
    local hDelta = label(header, "К надетому", RW - DELTA_W - 10, -4, "GameFontNormalSmall")
    hDelta:SetWidth(DELTA_W + 6); hDelta:SetJustifyH("RIGHT")

    local rows, results, page, columns = {}, {}, 1, {}
    local pageText = label(f, "", RX + RW - 118, -600, "GameFontHighlightSmall")
    pageText:SetWidth(60); pageText:SetJustifyH("CENTER")
    local footer = label(f, "Shift+клик — ссылка в чат. «К надетому» — разница с надетым предметом этого слота.", RX, -600, "GameFontDisableSmall")
    footer:SetWidth(RW - 200)

    local function showTooltip(self)
        local item = self.item
        if not item or not item.link then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetHyperlink(item.link)
        if item.source then GameTooltip:AddLine("Источник: " .. item.source, 1, 1, 1, true) end
        if item.delta then GameTooltip:AddLine(string.format("Относительно надетого: %+.2f", item.delta), 0.5, 0.82, 0.5, true) end
        if item.approximate then GameTooltip:AddLine("Pawn: есть нераспознанные строки. Оценка может не учитывать часть свойств.", 1, 0.7, 0, true) end
        if item.source then GameTooltip:AddLine("Класс, фракцию и требования проверьте в подсказке.", 1, 0.7, 0, true) end
        GameTooltip:Show()
    end
    equippedRow:SetScript("OnEnter", showTooltip)
    equippedRow:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local function drawEquipped()
        local slot = slots[si][1]
        local info = results.equipped
        local hasStats = #columns > 0
        setNameWidth(equippedRow, hasStats)
        equippedRow.bar:Hide(); equippedRow.barBg:Hide()
        setDelta(equippedRow, nil)
        equippedRow.item = nil
        if slot == "ALL" then
            equippedRow.icon:SetTexture(QUESTION)
            equippedRow.title:SetText("|cffbfb6a0Надето сейчас|r  —  для «Все слоты» разница считается к слоту каждого предмета")
            equippedRow.source:SetText(""); equippedRow.score:SetText(""); fillStats(equippedRow, {}, nil)
            return
        end
        if not info then
            equippedRow.icon:SetTexture(QUESTION)
            equippedRow.title:SetText("|cffbfb6a0Надето сейчас|r  —  нажмите «Найти», чтобы сравнить")
            equippedRow.source:SetText(slots[si][2]); equippedRow.score:SetText(""); fillStats(equippedRow, {}, nil)
            return
        end
        equippedRow.item = info.link and {link = info.link, approximate = info.approximate} or nil
        equippedRow.icon:SetTexture(info.link and GetInventoryItemTexture and GetInventoryItemTexture("player", info.slotID) or QUESTION)
        equippedRow.title:SetText("|cffbfb6a0Надето сейчас|r  " .. (info.link or "пусто"))
        equippedRow.source:SetText(slots[si][2])
        equippedRow.score:SetText(string.format("%.2f%s", info.score, info.approximate and " *" or ""))
        fillStats(equippedRow, columns, info.stats)
    end

    local function draw()
        local hasStats = #columns > 0
        for i, cell in ipairs(hStats) do cell:SetText(columns[i] or "") end
        hScore:SetText(scoring == "pawn" and "Оценка Pawn" or "Оценка")
        local best = 0
        for _, item in ipairs(results) do if item.score > best then best = item.score end end
        for n, row in ipairs(rows) do
            local index = (page - 1) * PAGE + n
            local item = results[index]
            row.item = item; row:SetShown(item ~= nil)
            if item then
                setNameWidth(row, hasStats)
                row.rank:SetText(index)
                row.icon:SetTexture(itemIcon(item.id))
                row.title:SetText(item.link or item.name)
                row.source:SetText(item.source or "")
                fillStats(row, columns, item.stats)
                local width = best > 0 and math.max(0, item.score) / best * 66 or 0
                row.bar:SetShown(width > 0)
                if width > 0 then row.bar:SetWidth(width) end
                row.score:SetText(string.format("%.2f%s", item.score, item.approximate and " *" or ""))
                setDelta(row, item.delta)
            end
        end
        pageText:SetText(page .. " / " .. math.max(1, math.ceil(#results / PAGE)))
        drawEquipped()
    end
    for n = 1, PAGE do
        local row = createRow(f, -176 - (n - 1) * (ROW_H + 2))
        if n % 2 == 0 then row.bg:SetColorTexture(0.09, 0.075, 0.055, 1) end
        row:SetScript("OnEnter", showTooltip)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        row:SetScript("OnClick", function(self)
            if self.item and IsModifiedClick("CHATLINK") then ChatEdit_InsertLink(self.item.link) end
        end)
        rows[n] = row; row:Hide()
    end
    button(f, "<", RX + RW - 150, -594, 32, function() page = math.max(1, page - 1); draw() end)
    button(f, ">", RX + RW - 54, -594, 32, function()
        page = math.min(math.max(1, math.ceil(#results / PAGE)), page + 1); draw()
    end)

    local function setLocked(locked)
        for _, b in ipairs(lockables) do if locked then b:Disable() else b:Enable() end end
        if locked then searchButton:Disable() else searchButton:Enable() end
    end
    searchButton = button(f, "Найти", RX + 682, -46, 108, function()
        local parsed, priorities, err = {}, {}
        if scoring ~= "pawn" then
            parsed, err = FG.ParseWeights(weightsText())
            if not parsed then status:SetText(err); return end
            priorities, err = FG.ParsePriority(priority:GetText())
            if not priorities then status:SetText(err); return end
            local hasWeight = false
            for _, value in pairs(parsed) do if value ~= 0 then hasWeight = true end end
            if not hasWeight and #priorities == 0 then status:SetText("Задайте ненулевой вес или порядок приоритетов."); return end
        end
        local maxLevel = tonumber(level:GetText())
        if not maxLevel or maxLevel < 1 or maxLevel > 999 or maxLevel % 1 ~= 0 then status:SetText("Уровень: целое число 1–999."); return end
        db.weights, db.priority = weightsText(), priority:GetText()
        db.slot, db.armor, db.level, db.source = si, ai, maxLevel, source:GetText()
        if openPopup then openPopup:Hide() end
        columns = scoring == "pawn" and {} or statColumns(priorities, parsed)
        setLocked(true); progress:SetValue(0)
        status:SetText("Поиск… найденные предметы появятся сразу.")
        local pawnLabel
        for _, choice in ipairs(choices) do if choice.name == pawnScale then pawnLabel = choice.label end end
        FG.Search({scoring = scoring, pawnScale = pawnScale, pawnLabel = pawnLabel, weights = parsed, priority = priorities,
            slot = slots[si][1], armor = ai - 1, level = maxLevel, source = db.source},
        function(found, message)
            setLocked(false); status:SetText(message); progress:SetValue(found and 1 or 0)
            results, page = found or {}, 1; draw()
        end, function(found, message, fraction)
            status:SetText(message); progress:SetValue(fraction or 0)
            results = found; draw()
        end)
    end, 28)

    status:SetText(setMode(scoring))
    if scoring ~= "pawn" then status:SetText("Задайте веса и нажмите «Найти».") end
    slotDrop.Refresh(); armorDrop.Refresh()
    draw()
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
