-- Stub object construction; use real data tables from the ATT release.
local app = {IsForever=true, handlers={}, categories={}, Settings={}, cache={}}
app.OnTooltipDB=setmetatable({}, {__index=function() return function() end end})
app.OnUpdateDB=app.OnTooltipDB
app.ResolveQuestData=function(t) return t end
app.L=setmetatable({}, {__index=function(_,key) return key end})
app.asset=function(path) return path end
app.ClassIndex=1; app.RaceIndex=1
function app.AddEventHandler(event, fn)
    if event == "OnBuildDataCache" then app.handlers[#app.handlers+1]=fn end
end
function app.CreateItem(id, data) data=data or {}; data.itemID=id; return data end
function app.CreateItemSource(sourceID, id, data) data=data or {}; data.itemID=id; return data end
local fields = {CreateQuest="questID",CreateNPC="npcID",CreateInstance="instanceID",CreateCustomHeader="headerID",CreateProfession="professionID"}
setmetatable(app, {__index=function(t,key)
    if key:match("^Create") then
        local constructor=function(id, data)
            data=type(data)=="table" and data or {}
            data[fields[key] or "testID"]=id
            return data
        end
        rawset(t,key,constructor); return constructor
    end
end})
function app.index()
    local function visit(group,parent)
        if type(group)~="table" then return end
        group.parent=parent
        if group.itemID then
            app.cache[group.itemID]=app.cache[group.itemID] or {}
            table.insert(app.cache[group.itemID],group)
        end
        for _,child in ipairs(group.g or group) do visit(child,group) end
    end
    for _,group in pairs(app.categories) do visit(group) end
end
function app.GetRawFieldContainer(field) assert(field=="itemID"); return app.cache end
return app
