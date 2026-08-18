-- schilly/scripts/PalettenlagerAI.lua
-- Enhanced Pallet Storage AI manager
-- Adds: cross‑farm transfer (free), distribution to other storages and factories

PalettenlagerAI = PalettenlagerAI or {}
PalettenlagerAI.placeables = PalettenlagerAI.placeables or {}
PalettenlagerAI.xmlNamePattern = "PalletStorage.xml" -- detect placeables by XML filename

local function safeGetOwnerFarmId(placeable)
    if placeable == nil then return nil end
    -- Try common fields / methods used by various mods/FS versions
    if placeable.ownerFarmId ~= nil then return placeable.ownerFarmId end
    if placeable:getOwnerFarmId ~= nil and type(placeable.getOwnerFarmId) == "function" then
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
        -- try to infer from placeable.metadata
        if placeable.configFileName then xmlFilename = placeable.configFileName end
    end

    if string.find(xmlFilename, PalettenlagerAI.xmlNamePattern) then
        local id = tostring(placeable.node or placeable.configFileName or math.random())
        PalettenlagerAI.placeables[id] = {
            placeable = placeable,
            capacity = (placeable.objectStorage and placeable.objectStorage.capacity) or 0,
            current = 0,
            ownerFarmId = safeGetOwnerFarmId(placeable)
        }
        print(string.format("[PalettenlagerAI] Registered Palettenlager: %s (id=%s capacity=%d ownerFarm=%s)", xmlFilename, id, PalettenlagerAI.placeables[id].capacity or 0, tostring(PalettenlagerAI.placeables[id].ownerFarmId)))
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
        -- give money to farm owner if known, otherwise to player farm
        local entry = PalettenlagerAI.placeables[id]
        local farmId = entry and entry.ownerFarmId or g_currentMission.player.farmId
        g_currentMission:addMoney(money, "sale", farmId)
    end
    return true, n, money
end

-- Transfer without additional fees between storages on the same server
-- If target placeable is known locally, simply move stock
function PalettenlagerAI.transfer(fromId, toId, amount)
    local ok, n = PalettenlagerAI.withdraw(fromId, amount)
    if not ok then return false, n end
    local ok2, stored = PalettenlagerAI.store(toId, n)
    return ok2, stored
end

-- Cross‑farm transfer (free): move amount from a local registered storage to a storage owned by another farm
-- This function will try to locate a target placeable that belongs to targetFarmId. If not found locally, it will queue a remote transfer (placeholder) or fail gracefully.
function PalettenlagerAI.transferToFarm(fromId, targetFarmId, amount)
    -- withdraw from source
    local ok, withdrawn = PalettenlagerAI.withdraw(fromId, amount)
    if not ok then return false, "withdraw failed" end

    -- look for a registered placeable with ownerFarmId == targetFarmId
    for id,entry in pairs(PalettenlagerAI.placeables) do
        if tostring(entry.ownerFarmId) == tostring(targetFarmId) then
            -- try to store here (local)
            local ok2, stored = PalettenlagerAI.store(id, withdrawn)
            if ok2 then
                print(string.format("[PalettenlagerAI] Transferred %d units from %s to local placeable %s of farm %s", stored, fromId, id, tostring(targetFarmId)))
                return true, stored
            end
        end
    end

    -- If we didn't find a local placeable for the farm, attempt to notify remote (multiplayer) or schedule transfer
    -- Placeholder: real cross‑farm transfer requires network RPCs and a remote receiver implementing an API.
    -- We'll implement a best-effort log and return success=false so the caller can handle remote transfer via CoursePlay/other mods.
    print(string.format("[PalettenlagerAI] No local placeable found for farm %s — remote transfer required (placeholder)", tostring(targetFarmId)))
    -- For now: refund withdrawn amount back to the source to avoid loss
    PalettenlagerAI.store(fromId, withdrawn)
    return false, "remoteNotImplemented"
end

-- Distribute items from a source storage to multiple targets (other palettenlager or factories)
-- targetFilter: function(entry) -> boolean  (if nil, will try to use xmlNamePattern to match storages),
-- returns table of results { targetId = storedAmount }
function PalettenlagerAI.distribute(fromId, targetFilter, amountPerTarget)
    local results = {}
    -- collect potential targets (exclude the source)
    for id,entry in pairs(PalettenlagerAI.placeables) do
        if id ~= fromId then
            local accept = true
            if targetFilter and type(targetFilter) == "function" then
                accept = targetFilter(entry)
            end
            if accept then
                -- attempt to transfer amountPerTarget
                local ok, n = PalettenlagerAI.withdraw(fromId, amountPerTarget)
                if not ok or n == 0 then break end
                local ok2, stored = PalettenlagerAI.store(id, n)
                results[id] = stored or 0
            end
        end
    end
    return results
end

-- Utility: find placeables by xml name pattern (helpful to find factories or other storages)
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

-- Debug dump
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

return PalettenlagerAI
