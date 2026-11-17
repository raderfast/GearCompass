local PawnIsInitialized=true
local sort,format,tinsert,strlower=table.sort,string.format,table.insert,string.lower
local PawnScaleTotals={}
local PawnScaleBestGems={A={},B={}}
PawnIgnoreStatValue=-1000000
PawnCurrentScaleVersion=1
PawnLocal={VisibleScalesHeader="%s",HiddenScalesHeader="Hidden"}
VgerCore={Assert=function(value,message) assert(value,message) end,Fail=error}
UnitName=function() return "Tester" end
PawnIsScaleVisible=function() return false end
PawnCommon={Scales={A={Values={Strength=2,Stamina=0.2}},B={Values={Intellect=3}}}}
PawnGetItemData=function()
    return {Stats={Strength=999},UnenchantedStats={Strength=10,Stamina=5},Level=60,CanEquip=true}
end
