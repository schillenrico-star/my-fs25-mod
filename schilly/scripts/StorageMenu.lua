-- schilly/scripts/StorageMenu.lua
-- Binds the GUI layout to PalettenlagerAI functions (simplified)

StorageMenu = {}

function StorageMenu.onOpen()
    -- populate list with registered placeables
    local list = {}
    for id,entry in pairs(PalettenlagerAI.placeables) do
        table.insert(list, { id = id, label = string.format("%s (id=%s) - %d/%d", tostring(entry.placeable.xmlFilename or "placeable"), id, entry.current or 0, entry.capacity or 0) })
    end
    g_gui:changeElementAttributes("StorageMenu", "palList", { items = list })
    g_gui:changeElementText("StorageMenu", "lblInfo", "Select a storage to manage")
end

function StorageMenu.onClose()
    g_gui:closeGui("StorageMenu")
end

function StorageMenu.onStore()
    local sel = g_gui:getElement("StorageMenu", "palList").selected
    local amount = tonumber(g_gui:getElement("StorageMenu", "inputAmount").text) or 0
    if sel == nil then g_gui:showPopup("No storage selected") return end
    local id = sel.id
    local ok, n = PalettenlagerAI.store(id, amount)
    if ok then g_gui:changeElementText("StorageMenu", "lblInfo", string.format("Stored %d items in %s", n, id)) else g_gui:changeElementText("StorageMenu", "lblInfo", "Store failed") end
end

function StorageMenu.onWithdraw()
    local sel = g_gui:getElement("StorageMenu", "palList").selected
    local amount = tonumber(g_gui:getElement("StorageMenu", "inputAmount").text) or 0
    if sel == nil then g_gui:showPopup("No storage selected") return end
    local id = sel.id
    local ok, n = PalettenlagerAI.withdraw(id, amount)
    if ok then g_gui:changeElementText("StorageMenu", "lblInfo", string.format("Withdrew %d items from %s", n, id)) else g_gui:changeElementText("StorageMenu", "lblInfo", "Withdraw failed") end
end

function StorageMenu.onSell()
    local sel = g_gui:getElement("StorageMenu", "palList").selected
    local amount = tonumber(g_gui:getElement("StorageMenu", "inputAmount").text) or 0
    if sel == nil then g_gui:showPopup("No storage selected") return end
    local id = sel.id
    local price = 0
    -- use market price if available
    if g_currentMission ~= nil and g_currentMission.marketPrices ~= nil then
        price = 1 -- placeholder: real market lookup would consult sell price for specific items
    end
    local ok, n, money = PalettenlagerAI.sell(id, amount, price)
    if ok then g_gui:changeElementText("StorageMenu", "lblInfo", string.format("Sold %d items for %d", n, money)) else g_gui:changeElementText("StorageMenu", "lblInfo", "Sell failed") end
end

function StorageMenu.onTransferFarm()
    local sel = g_gui:getElement("StorageMenu", "palList").selected
    local amount = tonumber(g_gui:getElement("StorageMenu", "inputAmount").text) or 0
    local targetFarm = tonumber(g_gui:getElement("StorageMenu", "inputTargetFarm").text) or 0
    if sel == nil then g_gui:showPopup("No storage selected") return end
    local id = sel.id
    local ok, res = PalettenlagerAI.transferToFarm(id, targetFarm, amount)
    if ok then g_gui:changeElementText("StorageMenu", "lblInfo", string.format("Transfer requested: %d units to farm %d", res or amount, targetFarm)) else g_gui:changeElementText("StorageMenu", "lblInfo", "Transfer failed: "..tostring(res)) end
end

function StorageMenu.onDistributeStorages()
    local sel = g_gui:getElement("StorageMenu", "palList").selected
    local amount = tonumber(g_gui:getElement("StorageMenu", "inputAmount").text) or 0
    if sel == nil then g_gui:showPopup("No storage selected") return end
    local id = sel.id
    local res = PalettenlagerAI.distribute(id, function(entry) return string.find(tostring(entry.placeable.xmlFilename or ""), "PalletStorage") end, amount)
    g_gui:changeElementText("StorageMenu", "lblInfo", "Distributed to storages")
end

function StorageMenu.onDistributeFactories()
    local sel = g_gui:getElement("StorageMenu", "palList").selected
    local amount = tonumber(g_gui:getElement("StorageMenu", "inputAmount").text) or 0
    if sel == nil then g_gui:showPopup("No storage selected") return end
    local id = sel.id
    local res = PalettenlagerAI.distribute(id, function(entry) return string.find(tostring(entry.placeable.xmlFilename or ""), "Factory") end, amount)
    g_gui:changeElementText("StorageMenu", "lblInfo", "Distributed to factories")
end

return StorageMenu
