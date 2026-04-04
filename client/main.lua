DGWaterRescue = DGWaterRescue or {}

local Utils = DGWaterRescue.Utils
local Rescue = DGWaterRescue.Rescue
local Framework = DGWaterRescue.Framework

local function syncModules()
    Utils = Utils or DGWaterRescue.Utils
    Rescue = Rescue or DGWaterRescue.Rescue
    Framework = Framework or DGWaterRescue.Framework
end

local function cfg(path, fallback)
    local node = Config
    for part in string.gmatch(tostring(path or ''), '[^%.]+') do
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

local function ensureModules(requireRescue)
    syncModules()
    if not Utils then
        return false
    end
    if requireRescue and not Rescue then
        return false
    end
    return true
end

local lastAutoRescueAt = 0
local dispatchPending = false
local dispatchRequestedAt = 0
local dispatchRequestedCoords = nil
local qbCoreObject = nil
local qbCoreLookupAttempted = false

local function getQbCoreObject()
    if qbCoreObject then
        return qbCoreObject
    end

    if GetResourceState('qb-core') ~= 'started' then
        return nil
    end

    if qbCoreLookupAttempted then
        return nil
    end

    qbCoreLookupAttempted = true
    local ok, core = pcall(function()
        return exports['qb-core']:GetCoreObject()
    end)

    if ok and core then
        qbCoreObject = core
        return qbCoreObject
    end

    return nil
end

local function isPlayerDownedOrDead(ped)
    if IsPedDeadOrDying(ped, true) then
        return true
    end

    local stateBag = LocalPlayer and LocalPlayer.state
    if stateBag and (stateBag.isdead or stateBag.isDead or stateBag.dead or stateBag.inlaststand or stateBag.laststand) then
        return true
    end

    local qbCore = getQbCoreObject()
    if not qbCore or not qbCore.Functions or not qbCore.Functions.GetPlayerData then
        return false
    end

    local ok, playerData = pcall(function()
        return qbCore.Functions.GetPlayerData()
    end)

    local metadata = ok and playerData and playerData.metadata
    if metadata and (metadata.isdead or metadata.inlaststand) then
        return true
    end

    return false
end

local function createEmsRescueBlip(coords)
    if not ensureModules(false) then
        return
    end

    local alertCfg = Utils.cfg('Dispatch.alertBlip', {})
    if not alertCfg.enabled then
        return
    end

    local c = Utils.parseCoords(coords, nil)
    if not c then
        return
    end

    local blip = AddBlipForCoord(c.x, c.y, c.z)
    SetBlipSprite(blip, tonumber(alertCfg.sprite) or 153)
    SetBlipColour(blip, tonumber(alertCfg.color) or 1)
    SetBlipScale(blip, tonumber(alertCfg.scale) or 1.0)
    SetBlipAsShortRange(blip, false)
    SetBlipRoute(blip, alertCfg.route ~= false)

    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(tostring(alertCfg.label or 'Water Rescue Call'))
    EndTextCommandSetBlipName(blip)

    local ttlMs = (tonumber(alertCfg.durationSeconds) or 180) * 1000
    CreateThread(function()
        Wait(ttlMs)
        if blip and DoesBlipExist(blip) then
            RemoveBlip(blip)
        end
    end)
end

local function requestDispatch(reason, coords)
    if dispatchPending then
        return
    end

    dispatchPending = true
    dispatchRequestedAt = GetGameTimer()
    dispatchRequestedCoords = coords
    TriggerServerEvent('dg-waterRescue:server:requestDispatch', coords, reason)
end

local function tryAutoRescue(reason, coords)
    if not ensureModules(true) then
        return
    end

    if Rescue.isActive and Rescue.isActive() then
        return
    end

    local ped = PlayerPedId()
    if not isPlayerDownedOrDead(ped) then
        return
    end

    if cfg('Trigger.onlyDeadInWater', true) and not IsEntityInWater(ped) then
        return
    end

    local now = GetGameTimer()
    if now - lastAutoRescueAt < 10000 then
        return
    end

    lastAutoRescueAt = now
    Utils.debug(('Auto rescue dispatch requested via %s'):format(reason))
    requestDispatch(reason, coords or GetEntityCoords(ped))
end

AddEventHandler('baseevents:onPlayerDied', function(_, coords)
    tryAutoRescue('baseevents:onPlayerDied', coords)
end)

CreateThread(function()
    while true do
        Wait(1500)
        tryAutoRescue('fallback_death_monitor')
    end
end)

if cfg('Trigger.allowManualEvent', true) then
    RegisterNetEvent('dg-waterRescue:beginRescue', function(coords)
        if not ensureModules(true) then
            return
        end

        local ped = PlayerPedId()
        local at = Utils.parseCoords(coords, GetEntityCoords(ped))
        Rescue.begin(at)
    end)
end

RegisterCommand('waterrescuetest', function()
    if not ensureModules(true) then
        return
    end

    local ped = PlayerPedId()
    if not IsEntityInWater(ped) then
        if Framework and Framework.notify then
            Framework.notify('You must be in water to test water rescue.', 'low')
        else
            Utils.notifyFallback('You must be in water to test water rescue.')
        end
        return
    end

    if Framework and Framework.notify then
        Framework.notify('Manual water rescue test started.', 'medium')
    end
    Rescue.begin(GetEntityCoords(ped))
end, false)

RegisterNetEvent('dg-waterRescue:client:billingNotice', function(message, severity)
    syncModules()
    if DGWaterRescue.Framework and DGWaterRescue.Framework.notify then
        DGWaterRescue.Framework.notify(message, severity or 'low')
    elseif Utils and Utils.notifyFallback then
        Utils.notifyFallback(message)
    else
        print(('[dg-waterRescue] %s'):format(tostring(message)))
    end
end)

RegisterNetEvent('dg-waterRescue:client:dispatchDecision', function(decision, coords)
    if not ensureModules(true) then
        dispatchPending = false
        dispatchRequestedAt = 0
        dispatchRequestedCoords = nil
        return
    end

    dispatchPending = false
    dispatchRequestedAt = 0
    dispatchRequestedCoords = nil

    local payload = type(decision) == 'table' and decision or {}
    local useAI = payload.useAI ~= false
    local useAiAmbulance = payload.useAiAmbulance ~= false

    if useAI then
        local ped = PlayerPedId()
        local at = Utils.parseCoords(coords, GetEntityCoords(ped))
        Rescue.begin(at, {
            useAiAmbulance = useAiAmbulance
        })

        if payload.message and Framework and Framework.notify then
            Framework.notify(payload.message, 'medium')
        end
        return
    end

    local msg = payload.message or 'Real EMS have been notified.'
    if Framework and Framework.notify then
        Framework.notify(msg, 'medium', 'Await responder assistance')
    else
        Utils.notifyFallback(msg)
    end
end)

RegisterNetEvent('dg-waterRescue:client:emsRescueAlert', function(data)
    local payload = type(data) == 'table' and data or {}
    createEmsRescueBlip(payload.coords)
end)

CreateThread(function()
    while true do
        Wait(1000)
        if not dispatchPending then
            goto continue
        end

        local now = GetGameTimer()
        if dispatchRequestedAt > 0 and (now - dispatchRequestedAt) >= 12000 then
            dispatchPending = false
            dispatchRequestedAt = 0

            local ped = PlayerPedId()
            if isPlayerDownedOrDead(ped) then
                if not ensureModules(true) then
                    dispatchRequestedCoords = nil
                    goto continue
                end
                local at = Utils.parseCoords(dispatchRequestedCoords, GetEntityCoords(ped))
                Rescue.begin(at, {
                    useAiAmbulance = true
                })
            end

            dispatchRequestedCoords = nil
        end

        ::continue::
    end
end)
