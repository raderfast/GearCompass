local widgets={}
local methods={}
local function widget()
    local w={scripts={},shown=true,disabled=false,text=""}
    setmetatable(w,{__index=function(_,key)
        if methods[key] then return methods[key] end
        if key:match("^[A-Z]") then return function() end end
    end})
    widgets[#widgets+1]=w
    return w
end
function methods:SetText(value) self.text=value end
function methods:GetText() return self.text end
function methods:SetScript(name,fn) self.scripts[name]=fn end
function methods:RegisterEvent(event) self.event=event end
function methods:Show() self.shown=true end
function methods:Hide() self.shown=false end
function methods:IsShown() return self.shown end
function methods:SetShown(value) self.shown=value end
function methods:Enable() self.disabled=false end
function methods:Disable() self.disabled=true end
function methods:EnableKeyboard(value) self.keyboard=value end
function methods:CreateFontString() return widget() end
function methods:CreateTexture() return widget() end
CreateFrame=function() local w=widget(); w.TitleText=widget(); return w end
UIParent={}; UISpecialFrames={}; SlashCmdList={}; tinsert=table.insert
UnitLevel=function() return 60 end
PawnIsReady=function() return true end
PawnGetAllScalesEx=function() return {{Name="A",LocalizedName="My Pawn scale"}} end
PawnGetItemData=function() end
PawnGetSingleValueFromItem=function() end
PawnGetScaleTag=function() return "A" end
local function click(text)
    for _,w in ipairs(widgets) do
        if w.text==text and w.scripts.OnClick and w.shown and not w.disabled then w.scripts.OnClick(w); return end
    end
    error("Button not found: "..text)
end
function runUITest(gc)
    for _,w in ipairs(widgets) do if w.event=="ADDON_LOADED" then w.scripts.OnEvent(w,"ADDON_LOADED","GearCompass") end end
    local searched
    gc.Search=function(options,callback) searched=options; callback({},"Done") end
    gc.Open()
    local count=#widgets
    click("Шкала Pawn")
    click("My Pawn scale")
    assert(GearCompassDB.scoring=="pawn" and GearCompassDB.pawnScale=="A")
    click("Найти")
    assert(searched.scoring=="pawn" and searched.pawnScale=="A" and #searched.priority==0)
    click("Свои веса"); click("Шкала Pawn"); click("Свои веса")
    assert(#widgets==count, "Switching scoring modes must reuse widgets")
    assert(GearCompassDB.scoring=="custom")
    -- All-zero custom profile is still rejected after leaving Pawn mode.
    searched=nil; click("Найти"); assert(not searched)
    -- Armor dropdown: the choice list is built once and reused.
    click("Любая броня"); click("Кольчуга")
    count=#widgets
    click("Кольчуга"); click("Латы")
    assert(#widgets==count, "Reopening a dropdown must reuse its widgets")
    -- Every stat has its own weight box; the first one is STR.
    local boxes={}
    for _,w in ipairs(widgets) do if w.scripts.OnTabPressed then boxes[#boxes+1]=w end end
    assert(#boxes==#gc.stats, "All stats must be shown at once")
    boxes[1]:SetText("1,5")
    click("Найти")
    assert(searched and searched.scoring=="custom" and searched.weights.STR==1.5 and searched.armor==4)
    assert(GearCompassDB.weights:find("STR=1,5",1,true) and GearCompassDB.weights:find("MP5=0",1,true))
    print("PASS: UI scoring modes, Pawn scale, dropdowns, full weight list and persistence")
end
