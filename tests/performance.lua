local FG = ...
local time, tick, eventHandler, registered = 0, nil, nil, false
local infoCalls, statCalls, requests, instantCalls = 0, 0, {}, 0
local ready = {}
GetTime = function() return time end
CreateFrame = function()
    return {
        RegisterEvent=function(_, event) assert(event == "ITEM_DATA_LOAD_RESULT"); registered=true end,
        SetScript=function(_, script, fn) assert(script=="OnEvent"); eventHandler=fn end,
        UnregisterAllEvents=function() registered=false end,
    }
end
C_Timer.NewTicker = function(_, fn) tick=fn; return {Cancel=function() tick=nil end} end
local catalog = {}
for id=1,14116 do catalog[id]={id=id,sources={Dungeon=true}} end
FG.Provider.Load=function() return catalog,0,"" end
GetItemInfoInstant=function(id)
    instantCalls=instantCalls+1
    return id,nil,nil,"INVTYPE_HEAD",nil,4,1
end
GetItemInfo=function(id)
    infoCalls=infoCalls+1
    if id==1 and not ready[1] then return nil end
    return "Item"..id,"item:"..id,3,50,10,nil,nil,1,"INVTYPE_HEAD",nil,0,4,1
end
GetItemStats=function() statCalls=statCalls+1; return {ITEM_MOD_INTELLECT_SHORT=10} end
RequestLoadItemDataByID=function(id) requests[id]=(requests[id] or 0)+1 end
local options={weights={INT=1},priority={},slot="ALL",armor=1,level=60,source=""}
local final, progress, completions
local function advance(n)
    for i=1,n do if not tick then break end; time=time+0.01; tick() end
end
completions=0
FG.Search(options,function(r) final=r; completions=completions+1 end,function(r) progress=r end)
advance(60)
assert(progress and #progress==14115 and not final, "Known results must be visible before unknown items finish")
assert(requests[1]==1 and registered)
ready[1]=true
eventHandler(nil,"ITEM_DATA_LOAD_RESULT",1,true)
advance(2)
assert(final and #final==14116 and completions==1 and not registered)
assert(time<1, "Large cached catalog should not have a 17-second artificial delay")
local previousInfo, previousStats, previousInstant=infoCalls,statCalls,instantCalls
final=nil; options.weights.INT=2
FG.Search(options,function(r) final=r end)
advance(60)
assert(final and #final==14116 and final[1].score==20)
assert(infoCalls==previousInfo and statCalls==previousStats and instantCalls==previousInstant, "Warm search should reuse item metadata and recalculate only scores")

-- Source filtering precedes expensive server queries.
catalog={[20000]={id=20000,sources={Other=true}}}
options.source="Dungeon"; final=nil
FG.Search(options,function(r) final=r end)
advance(2)
assert(final and #final==0 and not requests[20000] and infoCalls==previousInfo)

-- Cancellation must ignore queued events from a superseded search.
options.source=""; ready[1]=false
catalog={[30000]={id=30000,sources={Dungeon=true}}}
GetItemInfo=function() infoCalls=infoCalls+1; return nil end
final=nil
FG.Search(options,function() error("Cancelled search published results") end)
advance(2)
local oldHandler=eventHandler
FG.CancelSearch()
oldHandler(nil,"ITEM_DATA_LOAD_RESULT",30000,true)
assert(not tick and not registered)

-- Unavailable IDs are requested once, and fallback checks are bounded.
FG.Search(options,function(r) final=r end)
local before=infoCalls
advance(810)
assert(final and #final==0 and infoCalls-before<=9)
assert(requests[30000]==2 and not registered)
print("PASS: 14,116 IDs; progressive results <1 simulated second; warm item API calls=0; event completion, cancellation and bounded retries")
