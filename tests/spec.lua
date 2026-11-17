local FG, searchSource = ...
local function resetSearch() assert(loadstring(searchSource))("GearCompass", FG) end
local weights = assert(FG.ParseWeights("INT=1\nSP=0,8\nSTA=-0.2"))
assert(weights.INT == 1 and weights.SP == 0.8 and weights.STA == -0.2)
assert(not FG.ParseWeights("BAD=3"))
assert(not FG.ParseWeights("INT=1.2.3"))
assert(not FG.ParseWeights("INT=1000001"))
assert(not FG.ParsePriority("INT > INT"))
assert(not FG.ParsePriority("INT >> SP"))
assert(not FG.ParsePriority("INT >"))
assert(not FG.ParsePriority("INT SP"))
local priority = assert(FG.ParsePriority("INT > SP > CRIT"))
local a = {id=1, stats={ITEM_MOD_INTELLECT_SHORT=10}, score=10}
local b = {id=2, stats={ITEM_MOD_INTELLECT_SHORT=9, ITEM_MOD_SPELL_POWER_SHORT=100}, score=89}
assert(FG.Score(b.stats, weights) == 89)
assert(FG.Compare(a, b, priority))
assert(FG.Compare(b, a, {}))
assert(not FG.Compare(a, a, priority))

-- Deduplicate references and exclude explicitly unimplemented ancestors.
local dungeon = {text="Dungeon"}
local boss = {text="Boss", parent=dungeon}
local quest = {questID=900, parent=dungeon}
local unavailable = {text="Never implemented", u=1}
local cache = {
    [101]={{itemID=101,parent=boss},{itemID=101,parent=boss},{itemID=101,parent=quest}},
    [102]={{itemID=102,parent=boss,visible=false}},
    [777]={{itemID=777,parent=unavailable}},
    spellID=888,
}
local att = {IsForever=true, GetRawFieldContainer=function(field) assert(field=="itemID"); return cache end}
local catalog, skipped = FG.Provider.Collect(att)
assert(catalog[101] and catalog[102] and not catalog[888] and not catalog[777])
assert(skipped == 1)
local n = 0; for _ in pairs(catalog[101].sources) do n=n+1 end; assert(n == 2)
assert(catalog[101].sources["Dungeon / Boss"])
assert(catalog[101].sources["Dungeon / questID:900"])
assert(not FG.Provider.Collect({}))
assert(not FG.Provider.Collect({IsForever=false,GetRawFieldContainer=att.GetRawFieldContainer}))
assert(not FG.Provider.Collect({IsForever=true,GetRawFieldContainer=function() return {} end}))
-- ATT's root node is dropped from paths, but never leaves a path empty.
local root = {text="|cffb4b4ffALL THE THINGS|r"}
local zone = {text="Zones", parent=root}
local rooted = FG.Provider.Collect({IsForever=true,GetRawFieldContainer=function()
    return {[50]={{parent=zone}}, [51]={{parent=root}}}
end})
assert(rooted[50].sources["Zones"])
assert(rooted[51].sources["ALL THE THINGS"])
local loop = {}; loop.parent=loop
local cyclic = FG.Provider.Collect({IsForever=true,GetRawFieldContainer=function() return {[42]={{parent=loop}}} end})
assert(cyclic[42])

InCombatLockdown = function() return true end
assert(not FG.Provider.Load())
InCombatLockdown = function() return false end
assert(not FG.Provider.Load())
AllTheThings=att
local lazyCatalog=FG.Provider.Load()
assert(lazyCatalog[101])
assert(not lazyCatalog[101].sourceText)
assert(FG.Provider.Load()==lazyCatalog)
assert(FG.Provider.ResolveSources(lazyCatalog[101]):find("Dungeon",1,true))
FG.Provider.Invalidate()
assert(FG.Provider.Load()~=lazyCatalog)

local time, tick, requests = 0, nil, 0
GetTime = function() return time end
C_Timer = {NewTicker=function(_, fn)
    tick=fn; return {Cancel=function() tick=nil end}
end}
FG.Provider.Load = function() return catalog, 0, "" end
-- Search.lua captured this API table when loaded (C_Item absent => _G).
RequestLoadItemDataByID = function() requests=requests+1 end
GetItemInfo = function(id)
    if id == 101 and time < 0.15 then return nil end
    return "Item"..id, "item:"..id, 3, 50, id == 102 and 60 or 10, "Armor", "Cloth", 1, "INVTYPE_HEAD", nil, 0, 4, 1
end
GetItemStats = function() return {ITEM_MOD_INTELLECT_SHORT=10} end
local result, message
FG.Search({weights=weights, priority={}, slot="INVTYPE_HEAD", armor=1, level=20, source="Dungeon"}, function(r,m) result,message=r,m end)
for i=1,100 do if not tick then break end; time=time+0.05; tick() end
assert(result and #result == 1 and result[1].id == 101 and result[1].score == 10)
assert(requests > 0 and not FG.ticker)
resetSearch()
GetItemInfo = function() return nil end
result = nil
FG.Search({weights=weights,priority={},slot="ALL",armor=0,level=60,source=""}, function(r,m) result,message=r,m end)
for i=1,500 do if not tick then break end; time=time+0.05; tick() end
assert(result and #result == 0 and message:find("2"))
assert(not FG.ticker)

-- ATT indexes non-gear too: instant metadata must prevent full server queries.
resetSearch()
GetItemInfoInstant = function(id)
    return id, nil, nil, "INVTYPE_HEAD", nil, id == 102 and 15 or 4, 1
end
GetItemInfo = function(id)
    assert(id == 101, "Non-gear should not request full item info")
    return "Item101", "item:101", 3, 50, 10, "Armor", "Cloth", 1, "INVTYPE_HEAD", nil, 0, 4, 1
end
result = nil
FG.Search({weights=weights,priority={},slot="ALL",armor=1,level=60,source=""}, function(r,m) result,message=r,m end)
for i=1,100 do if not tick then break end; time=time+0.05; tick() end
assert(result and #result == 1 and result[1].id == 101)

-- Delta to the equipped piece of the candidate's slot.
resetSearch()
GetInventoryItemLink = function(_, slot) if slot == 1 then return "item:900" end end
GetItemStats = function(link)
    if link == "item:900" then return {ITEM_MOD_INTELLECT_SHORT=4} end
    return {ITEM_MOD_INTELLECT_SHORT=10}
end
result = nil
FG.Search({weights=weights,priority={},slot="INVTYPE_HEAD",armor=1,level=60,source=""}, function(r,m) result,message=r,m end)
for i=1,100 do if not tick then break end; time=time+0.05; tick() end
assert(result and result[1].delta == 6, "Delta must compare with the equipped head")
assert(result.equipped and result.equipped.score == 4 and result.equipped.slotID == 1)
-- Rings compare with the weaker ring; an empty ring slot scores 0.
assert(FG.slotIDs.INVTYPE_FINGER[1] == 11 and FG.slotIDs.INVTYPE_FINGER[2] == 12)
resetSearch()
GetItemInfoInstant = function(id) return id, nil, nil, "INVTYPE_FINGER", nil, id == 102 and 15 or 4, 0 end
GetItemInfo = function(id)
    assert(id == 101)
    return "Ring", "item:101", 3, 50, 10, "Armor", "Misc", 1, "INVTYPE_FINGER", nil, 0, 4, 0
end
GetInventoryItemLink = function(_, slot) if slot == 11 then return "item:900" end end
result = nil
FG.Search({weights=weights,priority={},slot="INVTYPE_FINGER",armor=0,level=60,source=""}, function(r,m) result,message=r,m end)
for i=1,100 do if not tick then break end; time=time+0.05; tick() end
assert(result and result[1].delta == 10 and result.equipped.slotID == 12 and not result.equipped.link)
GetInventoryItemLink = nil
