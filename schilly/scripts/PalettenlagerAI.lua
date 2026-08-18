-- schilly/scripts/PalettenlagerAI.lua
-- Enhanced Pallet Storage AI manager with save/load and network transfer

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

-- Basic local actions
function PalettenlagerAI.store(id, amount)
    local entry = PalettenlagerAI.placeables[id]
    if not entry then return false, "not found" end
    local can = math.max(0, (entry.capacity or 0) - (entry.current or 0))
    local toStore = math.min(can, amount)
    entry.current = (entry.current or 0) + toStore
    return true, toStore
end

function PalettenlagerAI.withdraw(id, amount)
    local entry = PalettenlagerAI.placeables[id]
    if not entry then return false, "not found" end
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
    if g_server ~= nil then
        -- server: broadcast to clients
        if g_eventManager ~= nil then
            local event = PalettenlagerTransferEvent:new(fromId, targetFarmId, withdrawn)
            g_eventManager:raise(event)
            print("[PalettenlagerAI] Broadcasted transfer event for remote farm")
            -- wait for remote confirmation in event handling; for now return placeholder
            return true, withdrawn
        end
    else
        -- client: send to server via event system
        if g_eventManager ~= nil then
            local event = PalettenlagerTransferEvent:new(fromId, targetFarmId, withdrawn)
            g_eventManager:raise(event)
            print("[PalettenlagerAI] Sent transfer event to server for remote farm")
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
    local xml = createXMLFile(key, "", "palettenlager")
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
        -- nothing saved yet
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
    -- attempt to listen for save and mission loaded
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
