-- schilly/scripts/events/PalettenlagerTransferEvent.lua
-- Simple network event to request transfer to a farm

PalettenlagerTransferEvent = {}
PalettenlagerTransferEvent_mt = Class(PalettenlagerTransferEvent, Event)
InitEventClass(PalettenlagerTransferEvent, "PalettenlagerTransferEvent")

function PalettenlagerTransferEvent:emptyNew()
    local self = Event:new(PalettenlagerTransferEvent_mt)
    return self
end

function PalettenlagerTransferEvent:new(fromId, targetFarmId, amount)
    local self = PalettenlagerTransferEvent:emptyNew()
    self.fromId = tostring(fromId)
    self.targetFarmId = tostring(targetFarmId)
    self.amount = tonumber(amount) or 0
    return self
end

function PalettenlagerTransferEvent:readStream(streamId, connection)
    self.fromId = streamReadString(streamId)
    self.targetFarmId = streamReadString(streamId)
    self.amount = streamReadInt32(streamId)
    self:run(connection)
end

function PalettenlagerTransferEvent:writeStream(streamId, connection)
    streamWriteString(streamId, tostring(self.fromId))
    streamWriteString(streamId, tostring(self.targetFarmId))
    streamWriteInt32(streamId, tonumber(self.amount) or 0)
end

function PalettenlagerTransferEvent:run(connection)
    -- If server: broadcast to all clients (so they can check if they own the target farm)
    if g_server ~= nil and connection == nil then
        -- server: forward to clients
        g_server:broadcastEvent(self, true)
        -- also try server side
        PalettenlagerTransferEvent.processTransfer(self.fromId, self.targetFarmId, self.amount)
    else
        -- client or forwarded event: process on this instance
        PalettenlagerTransferEvent.processTransfer(self.fromId, self.targetFarmId, self.amount)
    end
end

function PalettenlagerTransferEvent.processTransfer(fromId, targetFarmId, amount)
    -- Try to find local placeable for targetFarmId
    for id,entry in pairs(PalettenlagerAI.placeables) do
        if tostring(entry.ownerFarmId) == tostring(targetFarmId) then
            local ok2, stored = PalettenlagerAI.store(id, amount)
            if ok2 then
                print(string.format("[PalettenlagerTransferEvent] Remote accepted %d units into %s (farm %s)", stored, id, tostring(targetFarmId)))
                return true, stored
            end
        end
    end
    -- not found locally
    return false, "noLocalTarget"
end

function PalettenlagerTransferEvent.send(fromId, targetFarmId, amount, noEventSend)
    if noEventSend == nil or noEventSend == false then
        if g_server ~= nil then
            -- server: broadcast event
            g_server:broadcastEvent(PalettenlagerTransferEvent:new(fromId, targetFarmId, amount))
        elseif g_client ~= nil then
            g_client:getServerConnection():sendEvent(PalettenlagerTransferEvent:new(fromId, targetFarmId, amount))
        end
    end
end
