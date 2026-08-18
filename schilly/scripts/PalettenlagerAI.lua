-- schilly/scripts/PalettenlagerAI.lua
-- Simple Pallet Storage AI manager
-- Provides registration and basic actions: store, withdraw, sell, transfer

PalettenlagerAI = PalettenlagerAI or {}
PalettenlagerAI.placeables = PalettenlagerAI.placeables or {}
PalettenlagerAI.xmlNamePattern = "PalletStorage.xml" -- detect placeables by XML filename

function PalettenlagerAI.registerPlaceable(placeable)
    if not placeable or not placeable.xmlFilename then
        return
    end

    if string.find(placeable.xmlFilename, PalettenlagerAI.xmlNamePattern) then
        local id = tostring(placeable.node or placeable.modName or math.random())
        PalettenlagerAI.placeables[id] = {
            placeable = placeable,
            capacity = (placeable.objectStorage and placeable.objectStorage.capacity) or 0,
            current = 0 -- we'll try to read actual storage if available
        }
        print(string.format("[PalettenlagerAI] Registered Palettenlager: %s (capacity=%d)", placeable.xmlFilename, PalettenlagerAI.placeables[id].capacity))

        -- Try to read actual fill level from objectStorage if present
        if placeable.objectStorage and placeable.objectStorage.capacity then
            -- objectStorage keeps items via fillTypes, but exact API varies per FS version/mod
            -- We'll attempt to approximate current fill by summing stored objects if available
            if placeable.objectStorage.updateObjectStorage then
                -- noop: placeholder for more advanced integrations
            end
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

-- Basic actions (these will be expanded and used by GUI / external scripts)
function PalettenlagerAI.store(id, amount)
    local entry = PalettenlagerAI.placeables[id]
    if not entry then return false, "not found" end
    local can = math.max(0, entry.capacity - entry.current)
    local toStore = math.min(can, amount)
    entry.current = entry.current + toStore
    return true, toStore
end

function PalettenlagerAI.withdraw(id, amount)
    local entry = PalettenlagerAI.placeables[id]
    if not entry then return false, "not found" end
    local toWithdraw = math.min(entry.current, amount)
    entry.current = entry.current - toWithdraw
    return true, toWithdraw
end

function PalettenlagerAI.sell(id, amount, pricePerUnit)
    local ok, n = PalettenlagerAI.withdraw(id, amount)
    if not ok then return false, n end
    local money = (pricePerUnit or 0) * n
    -- give money to farm (multiplayer aware)
    if g_currentMission ~= nil and g_currentMission:addMoney ~= nil then
        g_currentMission:addMoney(money, "sale")
    end
    return true, n, money
end

function PalettenlagerAI.transfer(fromId, toId, amount)
    -- transfer without extra fees as requested
    local ok, n = PalettenlagerAI.withdraw(fromId, amount)
    if not ok then return false, n end
    local ok2, stored = PalettenlagerAI.store(toId, n)
    return ok2, stored
end

-- Simple debug dump
function PalettenlagerAI.debugDump()
    print("[PalettenlagerAI] Dumping registered palettenlager:")
    for id,e in pairs(PalettenlagerAI.placeables) do
        print(string.format("  id=%s xml=%s capacity=%d current=%d", id, tostring(e.placeable.xmlFilename), e.capacity or 0, e.current or 0))
    end
end

-- Auto-run on script load: try to register existing placeables
if g_currentMission ~= nil and g_currentMission.placeableSystem ~= nil then
    PalettenlagerAI.findAndRegisterAll()
else
    -- try to wait until mission is loaded by subscribing to an event if available
    if g_messageCenter ~= nil and MessageType ~= nil then
        -- subscribe to missionLoaded-like event if exists
        -- This is best-effort: message types differ across versions
        -- Fallback: a timer that will try again later isn't available here, so we rely on other integration stubs
    end
end

return PalettenlagerAI
