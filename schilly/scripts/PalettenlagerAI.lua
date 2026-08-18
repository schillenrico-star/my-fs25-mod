-- schilly/scripts/PalettenlagerAI.lua
-- Enhanced Pallet Storage AI manager with save/load, network transfer and objectStorage integration

PalettenlagerAI = PalettenlagerAI or {}
PalettenlagerAI.placeables = PalettenlagerAI.placeables or {}
PalettenlagerAI.xmlNamePattern = "PalletStorage.xml" -- detect placeables by XML filename
PalettenlagerAI.saveKey = "palettenlagerAI"

local function safeGetOwnerFarmId(placeable)
    if placeable == nil then return nil end
    if placeable.ownerFarmId ~= nil then return placeable.ownerFarmId end
    if placeable.getOwnerFarmId ~= nil and type(placeable.getOwnerFarmId) == "function" then
        local ok, v = pcall(placeable.getOwnerFarmId, placeable)
        if ok then return v end
    end
    if placeable.farmId ~= nil then return placeable.farmId end
    return nil
end

local function tryCall(obj, methodNames, ...)
    if obj == nil then return nil end
    for _,name in ipairs(methodNames) do
        local f = obj[name]
        if type(f) == "function" then
            local ok, res1, res2 = pcall(f, obj, ...)
            if ok then return res1, res2 end
        end
    end
    return nil
end

function PalettenlagerAI.registerPlaceable(placeable)
    if not placeable then return end

    local xmlFilename = tostring(placeable.xmlFilename or placeable.configFileName or "")
    if xmlFilename == "" then
        if placeable.configFileName then xmlFilename = placeable.configFileName end
    end

    if string.find(xmlFilename, PalettenlagerAI.xmlNamePattern) then
        local id = tostring(placeable.node or placeable.configFileName or math.random())
        if PalettenlagerAI.placeables[id] == nil then
            PalettenlagerAI.placeables[id] = {
                placeable = placeable,
                capacity = (placeable.objectStorage and placeable.objectStorage.capacity) or 0,
                current = 0,
                ownerFarmId = safeGetOwnerFarmId(placeable)
            }
            print(string.format("[PalettenlagerAI] Registered Palettenlager: %s (id=%s capacity=%d ownerFarm=%s)", xmlFilename, id, PalettenlagerAI.placeables[id].capacity or 0, tostring(PalettenlagerAI.placeables[id].ownerFarmId)))
        end
    end
end

function PalettenlagerAI.findAndRegisterAll()
    if g_currentMission == nil or g_currentMission.placeableSystem == nil then
        print("[PalettenlagerAI] Mission/placeableSystem not yet available")
        return
    end

    for _,p in ipairs(g_currentMission.placeableSystem.placeables) do
        local ok, err = pcall(PalettenlagerAI.registerPlaceable, p)
        if not ok then
            print("[PalettenlagerAI] Error registering placeable: ", err)
        end
    end
end

-- Utility: attempt to read actual stored count from placeable.objectStorage using known method names
function PalettenlagerAI.getCurrentFill(id)
    local entry = PalettenlagerAI.placeables[id]
    if not entry then return 0 end
    local p = entry.placeable
    if p and p.objectStorage then
        -- try common method names
        local tryNames = {"getStoredObjectCount", "getNumStoredObjects", "getNumObjects", "getFillLevel", "getFillUnits", "getStoredObjectsCount"}
        for _,name in ipairs(tryNames) do
            local f = p.objectStorage[name]
            if type(f) == "function" then
                local ok, res = pcall(f, p.objectStorage)
                if ok and type(res) == "number" then
                    entry.current = res
                    return res
                end
            end
        end
        -- some implementations store objects table
        if p.objectStorage.storedObjects and type(p.objectStorage.storedObjects) == "table" then
            entry.current = #p.objectStorage.storedObjects
            return entry.current
        end
    end
    -- fallback to internal counter
    return entry.current or 0
end

-- Attempt to call placeable.objectStorage's add/store methods, fallback to internal counter
function PalettenlagerAI._objectStorageAdd(entry, amount)
    local p = entry.placeable
    if p and p.objectStorage then
        local tryNames = {"storeObject", "addObject", "addToStorage", "spawnObject", "insertObject", "store"}
        for _,name in ipairs(tryNames) do
            local f = p.objectStorage[name]
            if type(f) == "function" then
                local ok, res = pcall(f, p.objectStorage, amount)
                if ok then
                    -- res may be number stored
                    return true, (type(res) == "number" and res) or amount
                end
            end
        end
    end
    return false
end

function PalettenlagerAI._objectStorageRemove(entry, amount)
    local p = entry.placeable
    if p and p.objectStorage then
        local tryNames = {"withdrawObject", "removeObject", "takeFromStorage", "popObject", "withdraw"}
        for _,name in ipairs(tryNames) do
            local f = p.objectStorage[name]
            if type(f) == "function" then
                local ok, res = pcall(f, p.objectStorage, amount)
                if ok then
                    return true, (type(res) == "number" and res) or amount
                end
            end
        end
    end
    return false
end

-- Basic local actions (use objectStorage if available)
function PalettenlagerAI.store(id, amount)
    local entry = PalettenlagerAI.placeables[id]
    if not entry then return false, "not found" end
    amount = tonumber(amount) or 0

    -- try to add via objectStorage
    local addedOk, added = PalettenlagerAI._objectStorageAdd(entry, amount)
    if addedOk then
        -- refresh current
        PalettenlagerAI.getCurrentFill(id)
        return true, added
    end

    -- fallback to counter
    local can = math.max(0, (entry.capacity or 0) - (entry.current or 0))
    local toStore = math.min(can, amount)
    entry.current = (entry.current or 0) + toStore
    return true, toStore
end

function PalettenlagerAI.withdraw(id, amount)
    local entry = PalettenlagerAI.placeables[id]
    if not entry then return false, "not found" end
    amount = tonumber(amount) or 0

    -- try to remove via objectStorage
    local removedOk, removed = PalettenlagerAI._objectStorageRemove(entry, amount)
    if removedOk then
        PalettenlagerAI.getCurrentFill(id)
        return true, removed
    end

    -- fallback
    local toWithdraw = math.min(entry.current or 0, amount)
    entry.current = (entry.current or 0) - toWithdraw
    return true, toWithdraw
end

function PalettenlagerAI.sell(id, amount, pricePerUnit)
    local ok, n = PalettenlagerAI.withdraw(id, amount)
    if not ok then return false, n end
    local money = (pricePerUnit or 0) * n
    if g_currentMission ~= nil and g_currentMission:addMoney ~= nil then
        local entry = PalettenlagerAI.placeables[id]
        local farmId = (entry and entry.ownerFarmId) or (g_currentMission.player and g_currentMission.player.farmId)
        g_currentMission:addMoney(money, "sale", farmId)
    end
    return true, n, money
end

-- Local transfer
function PalettenlagerAI.transfer(fromId, toId, amount)
    local ok, n = PalettenlagerAI.withdraw(fromId, amount)
    if not ok then return false, n end
    local ok2, stored = PalettenlagerAI.store(toId, n)
    return ok2, stored
end

-- Transfer to a farm: will attempt to find local placeable of targetFarmId, otherwise send network event
function PalettenlagerAI.transferToFarm(fromId, targetFarmId, amount)
    local ok, withdrawn = PalettenlagerAI.withdraw(fromId, amount)
    if not ok then return false, "withdraw failed" end

    -- look for local target
    for id,entry in pairs(PalettenlagerAI.placeables) do
        if tostring(entry.ownerFarmId) == tostring(targetFarmId) then
            local ok2, stored = PalettenlagerAI.store(id, withdrawn)
            if ok2 then
                print(string.format("[PalettenlagerAI] Transferred %d units from %s to local placeable %s of farm %s", stored, fromId, id, tostring(targetFarmId)))
                return true, stored
            end
        end
    end

    -- remote: send event to server/clients
    if g_server ~= nil or g_client ~= nil then
        if PalettenlagerTransferEvent ~= nil then
            PalettenlagerTransferEvent.send(fromId, targetFarmId, withdrawn)
            print("[PalettenlagerAI] Sent transfer event for remote farm (best-effort)")
            return true, withdrawn
        end
    end

    -- fallback: refund
    PalettenlagerAI.store(fromId, withdrawn)
    return false, "network not available"
end

-- Distribute to multiple targets
function PalettenlagerAI.distribute(fromId, targetFilter, amountPerTarget)
    local results = {}
    for id,entry in pairs(PalettenlagerAI.placeables) do
        if id ~= fromId then
            local accept = true
            if targetFilter and type(targetFilter) == "function" then
                accept = targetFilter(entry)
            end
            if accept then
                local ok, n = PalettenlagerAI.withdraw(fromId, amountPerTarget)
                if not ok or n == 0 then break end
                local ok2, stored = PalettenlagerAI.store(id, n)
                results[id] = stored or 0
            end
        end
    end
    return results
end

function PalettenlagerAI.findPlaceablesByPattern(pattern)
    local found = {}
    for id,entry in pairs(PalettenlagerAI.placeables) do
        local xml = tostring(entry.placeable.xmlFilename or "")
        if string.find(xml, pattern) then
            table.insert(found, { id = id, entry = entry })
        end
    end
    return found
end

-- Save/load
function PalettenlagerAI.saveToSavegame(savegame)
    if savegame == nil then return end
    local mapKey = savegame.mapKey or (g_currentMission and g_currentMission.missionInfo and g_currentMission.missionInfo.savegameIndex) or "default"
    local key = string.format("%s_%s", PalettenlagerAI.saveKey, tostring(mapKey))
    local xmlFile = key .. ".xml"
    local xml = createXMLFile(key, xmlFile)
    local i = 0
    for id,entry in pairs(PalettenlagerAI.placeables) do
        setXMLString(xml, string.format("palettenlager.placeable(%d)##id", i), id)
        setXMLInt(xml, string.format("palettenlager.placeable(%d)##current", i), entry.current or 0)
        i = i + 1
    end
    saveXMLFile(xml)
    delete(xml)
    print("[PalettenlagerAI] Saved " .. tostring(i) .. " placeables to savegame")
end

function PalettenlagerAI.loadFromSavegame(savegame)
    if savegame == nil then return end
    local mapKey = savegame.mapKey or (g_currentMission and g_currentMission.missionInfo and g_currentMission.missionInfo.savegameIndex) or "default"
    local key = string.format("%s_%s", PalettenlagerAI.saveKey, tostring(mapKey))
    local xmlFile = key .. ".xml"
    if not fileExists(xmlFile) then
        return
    end
    local xml = loadXMLFile(key, xmlFile)
    if xml == nil then return end
    local i = 0
    while true do
        local id = getXMLString(xml, string.format("palettenlager.placeable(%d)##id", i))
        if id == nil then break end
        local current = getXMLInt(xml, string.format("palettenlager.placeable(%d)##current", i)) or 0
        if PalettenlagerAI.placeables[id] ~= nil then
            PalettenlagerAI.placeables[id].current = current
        end
        i = i + 1
    end
    delete(xml)
    print("[PalettenlagerAI] Loaded saved data for " .. tostring(i) .. " placeables")
end

function PalettenlagerAI.debugDump()
    print("[PalettenlagerAI] Dumping registered palettenlager:")
    for id,e in pairs(PalettenlagerAI.placeables) do
        print(string.format("  id=%s xml=%s capacity=%d current=%d ownerFarm=%s", id, tostring(e.placeable.xmlFilename), e.capacity or 0, e.current or 0, tostring(e.ownerFarmId)))
    end
end

-- Auto register on load if possible
if g_currentMission ~= nil and g_currentMission.placeableSystem ~= nil then
    PalettenlagerAI.findAndRegisterAll()
end

-- Hook into mission save/load events if available
if g_messageCenter ~= nil and MessageType ~= nil then
    if MessageType.SAVEGAME_SAVED then
        g_messageCenter:subscribe(MessageType.SAVEGAME_SAVED, {
            onSavegameSaved = function(_, savegame) PalettenlagerAI.saveToSavegame(savegame) end
        })
    end
    if MessageType.MISSION_LOAD_FINISHED then
        g_messageCenter:subscribe(MessageType.MISSION_LOAD_FINISHED, {
            onMissionLoadFinished = function() PalettenlagerAI.findAndRegisterAll(); PalettenlagerAI.loadFromSavegame({ mapKey = (g_currentMission and g_currentMission.missionInfo and g_currentMission.missionInfo.savegameIndex) or "default" }) end
        })
    end
end

return PalettenlagerAI
