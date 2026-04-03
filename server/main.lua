local lastRescueAt = {}

local function cfg(path, fallback)
    local node = Config
    for part in string.gmatch(path, '[^%.]+') do
        if type(node) ~= 'table' then
            return fallback
        end
        node = node[part]
    end
    if node == nil then
        return fallback
    end
    return node
end

local function getPlayerKey(src)
    if GetResourceState('dg-bridge') == 'started' then
        local ok, identifier = pcall(function()
            return exports['dg-bridge']:getIdentifier(src, 'license')
        end)
        if ok and identifier then
            return identifier
        end
    end
    return ('src:%s'):format(src)
end

local function isResourceStarted(name)
    return GetResourceState(name) == 'started'
end

local function collectOnlineQbEms()
    if not isResourceStarted('qb-core') then
        return {}
    end

    local okCore, qbCore = pcall(function()
        return exports['qb-core']:GetCoreObject()
    end)

    if not okCore or not qbCore or not qbCore.Functions or not qbCore.Functions.GetPlayer then
        return {}
    end

    local emsList = {}
    local jobName = cfg('Dispatch.qbEmsJobName', 'ambulance')
    local requireOnDuty = cfg('Dispatch.requireOnDuty', true)

    for _, id in ipairs(GetPlayers()) do
        local src = tonumber(id)
        local player = qbCore.Functions.GetPlayer(src)
        local job = player and player.PlayerData and player.PlayerData.job
        if job and job.name == jobName and (not requireOnDuty or job.onduty) then
            table.insert(emsList, src)
        end
    end

    return emsList
end

local function normalizeCoords(coords)
    if type(coords) ~= 'table' then
        return nil
    end

    local x = tonumber(coords.x or coords[1])
    local y = tonumber(coords.y or coords[2])
    local z = tonumber(coords.z or coords[3])
    if not x or not y or not z then
        return nil
    end

    return { x = x, y = y, z = z }
end

local function tryChargePlayer(src)
    if not cfg('Billing.enabled', true) then
        return true, nil
    end

    if GetResourceState('dg-bridge') ~= 'started' then
        return true, nil
    end

    local amount = cfg('Billing.amount', 850)
    local moneyType = cfg('Billing.moneyType', 'bank')

    local okRemove = pcall(function()
        return exports['dg-bridge']:removeMoney(src, moneyType, amount)
    end)

    if okRemove then
        return true, nil
    end

    if cfg('Billing.requirePaymentToRevive', false) then
        return false, ('Insufficient %s funds for water rescue bill of $%d.'):format(moneyType, amount)
    end

    return true, ('Water rescue bill could not be charged (%s $%d).'):format(moneyType, amount)
end

RegisterNetEvent('dg-waterRescue:server:rescueState', function(stateName)
    local src = source

    if stateName == 'DISPATCHED' then
        if cfg('Cooldown.enabled', true) then
            local key = getPlayerKey(src)
            local cdSeconds = cfg('Cooldown.seconds', 240)
            local now = os.time()
            local remaining = (lastRescueAt[key] or 0) + cdSeconds - now
            if remaining > 0 then
                TriggerClientEvent('dg-waterRescue:client:billingNotice', src, ('Rescue cooldown active (%ds remaining).'):format(remaining), 'low')
                return
            end
            lastRescueAt[key] = now
        end
        return
    end

    if stateName == 'REVIVED' then
        local ok, message = tryChargePlayer(src)
        if message then
            TriggerClientEvent('dg-waterRescue:client:billingNotice', src, message, ok and 'low' or 'critical')
        end
    end
end)

RegisterNetEvent('dg-waterRescue:server:requestDispatch', function(coords, reason)
    local src = source
    local safeCoords = normalizeCoords(coords)
    local preferRealEms = cfg('Dispatch.preferRealEMS', true)

    if not preferRealEms or not safeCoords then
        TriggerClientEvent('dg-waterRescue:client:dispatchDecision', src, {
            useAI = true,
            useAiAmbulance = true
        }, safeCoords)
        return
    end

    local onlineEms = collectOnlineQbEms()
    if #onlineEms == 0 then
        TriggerClientEvent('dg-waterRescue:client:dispatchDecision', src, {
            useAI = true,
            useAiAmbulance = true,
            reason = 'no_ems_online'
        }, safeCoords)
        return
    end

    local rescueId = ('waterrescue:%s:%s'):format(src, os.time())
    local victimName = GetPlayerName(src) or ('Player %s'):format(src)
    local dispatchReason = tostring(reason or 'water_emergency')

    for _, emsSrc in ipairs(onlineEms) do
        TriggerClientEvent('dg-waterRescue:client:emsRescueAlert', emsSrc, {
            rescueId = rescueId,
            coords = safeCoords,
            victimId = src,
            victimName = victimName,
            reason = dispatchReason
        })

        TriggerClientEvent('dg-notifications:client:dispatch', emsSrc, {
            message = 'Incoming water rescue emergency',
            description = ('Victim: %s (ID %s)'):format(victimName, src),
            severity = 'critical',
            theme = 'dispatch',
            tag = 'EMS Dispatch',
            metrics = {
                { label = 'Type', value = 'Water Rescue' },
                { label = 'Victim ID', value = tostring(src) }
            }
        })
    end

    TriggerClientEvent('dg-waterRescue:client:dispatchDecision', src, {
        useAI = true,
        useAiAmbulance = false,
        reason = 'ems_notified',
        emsCount = #onlineEms,
        message = 'Real EMS have been dispatched. AI boat rescue is inbound.'
    }, safeCoords)
end)
