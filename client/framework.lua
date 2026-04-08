DGWaterRescue = DGWaterRescue or {}

local Framework = {}
DGWaterRescue.Framework = Framework

local Utils = DGWaterRescue.Utils

local function hasResource(name)
    return GetResourceState(name) == 'started'
end

local function toQbNotifyType(severity)
    if severity == 'critical' then
        return 'error'
    end
    if severity == 'success' then
        return 'success'
    end
    return 'primary'
end

function Framework.notify(message, severity, subText, theme, notifyOptions)
    if hasResource('dg-notifications') then
        local chosenTheme = tostring(theme or 'waterrescue')
        local payload = {
            mainText = message,
            subText = subText or '',
            tag = 'Water Rescue',
            timestamp = string.format('%02d:%02d', GetClockHours(), GetClockMinutes()),
            theme = chosenTheme
        }

        if type(notifyOptions) == 'table' then
            for key, value in pairs(notifyOptions) do
                payload[key] = value
            end
        end

        TriggerEvent('dg-notifications:client:ems', payload)
        return
    end

    if hasResource('qb-core') then
        local qbType = toQbNotifyType(severity)
        local text = message
        if subText and subText ~= '' then
            text = ('%s | %s'):format(message, subText)
        end
        TriggerEvent('QBCore:Notify', text, qbType, 4500)
        return
    end

    if hasResource('dg-bridge') then
        TriggerEvent('dg-bridge:notify', message, severity == 'critical' and 'error' or 'info', 4500)
        return
    end

    Utils.notifyFallback(message)
end

function Framework.reviveWithFallback(ped)
    local localPed = PlayerPedId()
    print("[DGWaterRescue] reviveWithFallback called. ped:", ped, "localPed:", localPed)

    if hasResource('dg-bridge') then
        print("[DGWaterRescue] Triggering dg-bridge:revive event...")
        TriggerEvent('dg-bridge:revive')
        Wait(1200)
    end

    if IsPedDeadOrDying(localPed, true) then
        print("[DGWaterRescue] Still dead after dg-bridge, triggering hospital:client:Revive...")
        TriggerEvent('hospital:client:Revive')
        Wait(1200)
    end

    print("[DGWaterRescue] Forcing native revive with NetworkResurrectLocalPlayer...")
    local p = GetEntityCoords(localPed)
    NetworkResurrectLocalPlayer(p.x, p.y, p.z, GetEntityHeading(localPed), true, false)

    local maxHealth = GetEntityMaxHealth(localPed)
    local target = math.min(maxHealth, Utils.cfg('Medical.partialReviveHealth', 130))
    print("[DGWaterRescue] Setting health to", target)
    SetEntityHealth(localPed, target)
    ClearPedBloodDamage(localPed)
    ClearPedTasksImmediately(localPed)
end

function Framework.requestBillingAndCooldown(stateName)
    TriggerServerEvent('dg-waterRescue:server:rescueState', stateName)
end
