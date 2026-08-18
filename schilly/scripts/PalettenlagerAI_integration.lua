-- schilly/scripts/PalettenlagerAI_integration.lua
-- Integration stub: run when mission is loaded to register PalletStorage placeables

source("schilly/scripts/PalettenlagerAI.lua")

local function tryRegister()
    if g_currentMission ~= nil and g_currentMission.placeableSystem ~= nil then
        PalettenlagerAI.findAndRegisterAll()
        return true
    end
    return false
end

-- Try immediate
if not tryRegister() then
    -- If the mission isn't ready, try hooking into the mission loaded callback
    if g_messageCenter ~= nil and MessageType ~= nil and MessageType.MISSION_LOAD_FINISHED then
        g_messageCenter:subscribe(MessageType.MISSION_LOAD_FINISHED, {
            onMissionLoadFinished = function() PalettenlagerAI.findAndRegisterAll() end
        })
    else
        -- best-effort fallback: print note
        print("[PalettenlagerAI_integration] Mission not ready — Palettenlager registration deferred")
    end
end
