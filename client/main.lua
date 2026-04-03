DGWaterRescue = DGWaterRescue or {}

local Utils = DGWaterRescue.Utils
local Rescue = DGWaterRescue.Rescue

AddEventHandler('baseevents:onPlayerDied', function(_, coords)
    local ped = PlayerPedId()

    if Utils.cfg('Trigger.onlyDeadInWater', true) and not IsEntityInWater(ped) then
        return
    end

    Rescue.begin(coords or GetEntityCoords(ped))
end)

if Utils.cfg('Trigger.allowManualEvent', true) then
    RegisterNetEvent('dg-waterRescue:beginRescue', function(coords)
        local ped = PlayerPedId()
        local at = Utils.parseCoords(coords, GetEntityCoords(ped))
        Rescue.begin(at)
    end)
end

RegisterNetEvent('dg-waterRescue:client:billingNotice', function(message, severity)
    if DGWaterRescue.Framework and DGWaterRescue.Framework.notify then
        DGWaterRescue.Framework.notify(message, severity or 'low')
    else
        Utils.notifyFallback(message)
    end
end)
