DGWaterRescue = DGWaterRescue or {}

local Framework = {}
DGWaterRescue.Framework = Framework

local Utils = DGWaterRescue.Utils

local function hasResource(name)
    return GetResourceState(name) == 'started'
end

function Framework.notify(message, severity, subText)
    if hasResource('dg-notifications') then
        TriggerEvent('dg-notifications:client:notify', {
            mainText = message,
            subText = subText or '',
            tag = 'Water Rescue',
            severity = severity or 'medium',
            timestamp = string.format('%02d:%02d', GetClockHours(), GetClockMinutes())
        })
        return
    end

    if hasResource('dg-bridge') then
        TriggerEvent('dg-bridge:notify', {
            message = message,
            type = severity == 'critical' and 'error' or 'info',
            duration = 4500
        })
        return
    end

    Utils.notifyFallback(message)
end

function Framework.reviveWithFallback(ped)
    if hasResource('dg-bridge') then
        TriggerEvent('dg-bridge:revive')
        Wait(1200)
    end

    if IsPedDeadOrDying(ped, true) then
        TriggerEvent('hospital:client:Revive')
        Wait(1200)
    end

    if IsPedDeadOrDying(ped, true) then
        local p = GetEntityCoords(ped)
        NetworkResurrectLocalPlayer(p.x, p.y, p.z, GetEntityHeading(ped), true, false)
    end

    local maxHealth = GetEntityMaxHealth(ped)
    local target = math.min(maxHealth, Utils.cfg('Medical.partialReviveHealth', 130))
    SetEntityHealth(ped, target)
    ClearPedBloodDamage(ped)
    ClearPedTasksImmediately(ped)
end

function Framework.requestBillingAndCooldown(stateName)
    TriggerServerEvent('dg-waterRescue:server:rescueState', stateName)
end
