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
