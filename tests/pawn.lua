local GC = ...
assert(not GC.Pawn.Scales())
assert(not GC.Pawn.CreateScorer("A"))
local isReady, tag = false, "Strength=1"
PawnIsReady=function() return isReady end
PawnCommon={Scales={A={NormalizationFactor=1}}}
PawnGetAllScalesEx=function() return {{Name="A",LocalizedName="My profile"},{Name="B",LocalizedName="Other"}} end
PawnGetScaleTag=function(name) return tag..name end
local item={UnenchantedStats={Strength=10},CanEquip=true}
local baseValue, currentValue = 10, 999
PawnGetItemData=function() return item end
PawnGetSingleValueFromItem=function() return currentValue,baseValue end
assert(not GC.Pawn.Scales())
isReady=true
assert(#GC.Pawn.Scales()==2)
assert(not GC.Pawn.CreateScorer("missing"))
local scorer=assert(GC.Pawn.CreateScorer("A"))
assert(scorer.Score("item:1")==10, "Must use base value, not enchanted value")
baseValue=0; assert(scorer.Score("item:1")==0, "Zero is a valid score")
baseValue=nil; local value,status=scorer.Score("item:1"); assert(not value and status=="pending")
baseValue=0/0; value,status=scorer.Score("item:1"); assert(not value and status=="error")
baseValue=10; item.UnknownLines={proc=true}
local approximate; value,status,approximate=scorer.Score("item:1"); assert(value==10 and approximate)
item.CanEquip=false; value,status=scorer.Score("item:1"); assert(not value and status=="skip")
item.CanEquip=true
PawnGetItemData=function() error("API failure") end
value,status=scorer.Score("item:1"); assert(not value and status=="error")
PawnGetItemData=function() return item end
tag="Strength=2"; assert(not scorer.Validate())
scorer=assert(GC.Pawn.CreateScorer("A")); PawnCommon.Scales.A.NormalizationFactor=2
assert(not scorer.Validate())

-- Full search must not depend on the limited C_Item.GetItemStats in Pawn mode.
local tick,time,handler= nil,0,nil
GetTime=function() return time end
InCombatLockdown=function() return false end
C_Timer={NewTicker=function(_,fn) tick=fn; return {Cancel=function() tick=nil end} end}
CreateFrame=function() return {RegisterEvent=function() end,UnregisterAllEvents=function() end,SetScript=function(_,_,fn) handler=fn end} end
local catalog={}
for id=1,3 do catalog[id]={id=id,sources={Dungeon=true}} end
GC.Provider.Load=function() return catalog,0,"" end
GetItemInfoInstant=function(id) return id,nil,nil,"INVTYPE_HEAD",nil,4,1 end
GetItemInfo=function(id) return "Item"..id,"item:"..id,3,50,10,nil,nil,1,"INVTYPE_HEAD",nil,0,4,1 end
GetItemStats=function() error("Pawn mode must not require GetItemStats") end
local thirdReady=false
PawnGetItemData=function(link)
    local id=tonumber(link:match("%d+"))
    if id==3 and not thirdReady then return nil end
    return {id=id,UnenchantedStats={Strength=id},UnknownLines=id==2 and {proc=true} or nil}
end
PawnGetSingleValueFromItem=function(data,name)
    return 999, data.id*(name=="A" and 10 or 100)
end
local options={scoring="pawn",pawnScale="A",priority={"INT"},weights={},slot="ALL",armor=1,level=60,source=""}
local results,message
local function run(frames)
    for i=1,frames do if not tick then break end; time=time+0.01; tick() end
end
GC.Search(options,function(r,m) results,message=r,m end)
run(2); assert(not results)
thirdReady=true; handler(nil,"ITEM_DATA_LOAD_RESULT",3,true); run(2)
assert(results and #results==3 and results[1].id==3 and results[1].score==30)
assert(results[2].approximate and not results[1].approximate)
options.pawnScale="B"; results=nil
GC.Search(options,function(r,m) results,message=r,m end); run(2)
assert(results and results[1].score==300, "Changing scales must rescore cached metadata")

-- Changing settings mid-search aborts instead of publishing mixed scores.
options.pawnScale="A"; thirdReady=false; results="waiting"
GC.Search(options,function(r,m) results,message=r,m end); run(2)
tag="Strength=3"; thirdReady=true; handler(nil,"ITEM_DATA_LOAD_RESULT",3,true); run(2)
assert(results==nil and message:find("Pawn",1,true) and not tick)

-- Missing Pawn is an explicit error, never a silent custom-score fallback.
PawnIsReady=nil; results="waiting"
GC.Search(options,function(r,m) results,message=r,m end)
assert(results==nil and not tick and message:find("Pawn",1,true))

-- Expensive tooltip parsing must yield between frames, including warm searches.
PawnIsReady=function() return true end
thirdReady=true; catalog={}
for id=100,199 do catalog[id]={id=id,sources={Dungeon=true}} end
local cpu, parsed = 0, 0
debugprofilestop=function() return cpu end
PawnGetItemData=function(link)
    cpu=cpu+2; parsed=parsed+1
    return {id=tonumber(link:match("%d+")),UnenchantedStats={Strength=1}}
end
results=nil
GC.Search(options,function(r,m) results,message=r,m end)
run(1); assert(parsed==2 and not results, "Pawn parsing must obey the per-frame work budget")
run(60); assert(results and #results==100)
print("PASS: Pawn optional API, base/zero/missing scores, scale changes, errors, unknown lines and asynchronous search")
