DGWaterRescue = DGWaterRescue or {}

local Utils = {}
DGWaterRescue.Utils = Utils

function Utils.cfg(path, fallback)
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

function Utils.debug(message)
    if not Utils.cfg('Debug', false) then
        return
    end
    print(('[dg-waterRescue] %s'):format(message))
end

function Utils.notifyFallback(message)
    -- Native chat messages are disabled; keep a debug trace for fallback cases.
    Utils.debug(('Fallback notification suppressed: %s'):format(tostring(message)))
end

function Utils.loadModel(modelName)
    local model = type(modelName) == 'number' and modelName or GetHashKey(modelName)
    if not IsModelInCdimage(model) then
        return nil
    end

    RequestModel(model)
    local timeoutAt = GetGameTimer() + 10000
    while not HasModelLoaded(model) and GetGameTimer() < timeoutAt do
        Wait(50)
    end

    if not HasModelLoaded(model) then
        return nil
    end

    return model
end

function Utils.loadAnimDict(dict)
    RequestAnimDict(dict)
    local timeoutAt = GetGameTimer() + 7000
    while not HasAnimDictLoaded(dict) and GetGameTimer() < timeoutAt do
        Wait(50)
    end
    return HasAnimDictLoaded(dict)
end

function Utils.cleanupEntities(entities)
    for _, ent in ipairs(entities) do
        if ent and ent ~= 0 and DoesEntityExist(ent) then
            DeleteEntity(ent)
        end
    end
end

function Utils.normalize2d(x, y)
    local mag = math.sqrt((x * x) + (y * y))
    if mag < 0.001 then
        return 0.0, 1.0
    end
    return x / mag, y / mag
end

function Utils.getGroundOrDefault(x, y, fallbackZ)
    local foundGround, groundZ = GetGroundZFor_3dCoord(x, y, fallbackZ + 50.0, 0)
    if foundGround then
        return groundZ
    end
    return fallbackZ
end

function Utils.getWaterOrDefault(x, y, fallbackZ)
    local isWater, waterZ = GetWaterHeight(x, y, fallbackZ + 5.0, 0.0)
    if isWater then
        return waterZ
    end
    return fallbackZ
end

function Utils.parseCoords(input, fallback)
    if type(input) == 'vector3' then
        return input
    end

    if type(input) == 'table' then
        local x = input.x or input[1]
        local y = input.y or input[2]
        local z = input.z or input[3]
        if x and y and z then
            return vector3(x, y, z)
        end
    end

    return fallback
end

function Utils.seatPlayerInBoat(ped, boat)
    for seat = 0, GetVehicleMaxNumberOfPassengers(boat) - 1 do
        if IsVehicleSeatFree(boat, seat) then
            TaskWarpPedIntoVehicle(ped, boat, seat)
            return true
        end
    end
    return false
end

function Utils.setVehicleFuelFull(vehicle)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
        return
    end

    SetVehicleFuelLevel(vehicle, 100.0)

    -- Compatibility with common fuel systems that read decor/state values.
    if DecorIsRegisteredAsType('_FUEL_LEVEL', 1) then
        DecorSetFloat(vehicle, '_FUEL_LEVEL', 100.0)
    end

    local okEntity, ent = pcall(function()
        return Entity(vehicle)
    end)
    if okEntity and ent and ent.state then
        pcall(function()
            ent.state:set('fuel', 100.0, true)
            ent.state:set('fuelLevel', 100.0, true)
            ent.state:set('_FUEL_LEVEL', 100.0, true)
        end)
    end
end

function Utils.driveBoatToPoint(driver, boat, target, speed, timeoutMs, threshold)
    local deadline = GetGameTimer() + timeoutMs
    local reissueAt = 0
    local driveStyle = 1074528293
    local navRefreshMs = 1800
    local stallWindowMs = 5200
    local minProgressPerTick = 0.18
    local lastDist = nil
    local stalledSince = 0
    local recoveries = 0
    local detourSign = 1.0

    local function missionTo(x, y, z, missionSpeed)
        TaskBoatMission(driver, boat, 0, 0, x, y, z, 4, missionSpeed, driveStyle, 0.0, 0.0)
    end

    while GetGameTimer() < deadline do
        if not DoesEntityExist(driver) or IsPedDeadOrDying(driver, true) then
            return false, GetEntityCoords(boat)
        end

        Utils.setVehicleFuelFull(boat)

        SetBoatAnchor(boat, false)
        SetVehicleUndriveable(boat, false)
        SetVehicleEngineOn(boat, true, true, true)

        local b = GetEntityCoords(boat)
        local dist = Vdist(b.x, b.y, b.z, target.x, target.y, target.z)
        if dist <= threshold then
            return true, b
        end

        if GetGameTimer() >= reissueAt then
            local dirX, dirY = Utils.normalize2d(target.x - b.x, target.y - b.y)
            local navX, navY, navZ

            if dist <= 60.0 then
                navX = target.x
                navY = target.y
                navZ = Utils.getWaterOrDefault(target.x, target.y, target.z) + 0.7
            else
                local lookAhead = math.min(55.0, math.max(20.0, dist * 0.50))
                navX = b.x + (dirX * lookAhead)
                navY = b.y + (dirY * lookAhead)
                navZ = Utils.getWaterOrDefault(navX, navY, target.z) + 0.7
            end

            missionTo(navX, navY, navZ, speed)
            reissueAt = GetGameTimer() + navRefreshMs
        end

        if lastDist ~= nil then
            local progress = lastDist - dist
            if progress < minProgressPerTick then
                if stalledSince == 0 then
                    stalledSince = GetGameTimer()
                end
            else
                stalledSince = 0
                recoveries = 0
            end
        end

        if stalledSince > 0 and (GetGameTimer() - stalledSince) >= stallWindowMs then
            recoveries = recoveries + 1
            stalledSince = GetGameTimer()

            if recoveries >= 2 then
                ClearPedTasks(driver)
            end
            SetBoatAnchor(boat, false)
            SetVehicleUndriveable(boat, false)
            SetVehicleEngineOn(boat, true, true, true)
            local dirX, dirY = Utils.normalize2d(target.x - b.x, target.y - b.y)
            local perpX, perpY = -dirY, dirX

            local detourForward = math.min(26.0, math.max(10.0, dist * 0.35))
            local detourSide = 10.0 * detourSign
            local detourX = b.x + (dirX * detourForward) + (perpX * detourSide)
            local detourY = b.y + (dirY * detourForward) + (perpY * detourSide)
            local detourZ = Utils.getWaterOrDefault(detourX, detourY, target.z) + 0.7

            missionTo(detourX, detourY, detourZ, speed + 2.0)
            if recoveries >= 2 then
                SetVehicleForwardSpeed(boat, speed * 0.35)
            end
            reissueAt = GetGameTimer() + 1200
            detourSign = detourSign * -1.0

            if recoveries >= 5 then
                local dx = target.x - b.x
                local dy = target.y - b.y
                local mag = math.sqrt((dx * dx) + (dy * dy))
                if mag > 0.001 then
                    local step = math.min(18.0, mag * 0.4)
                    local nx = b.x + (dx / mag) * step
                    local ny = b.y + (dy / mag) * step
                    local waterZ = Utils.getWaterOrDefault(nx, ny, target.z)
                    SetEntityCoordsNoOffset(boat, nx, ny, waterZ + 0.9, false, false, false)
                    SetVehicleForwardSpeed(boat, speed * 0.45)
                    recoveries = 0
                end
            end
        end

        lastDist = dist

        Wait(200)
    end

    return false, GetEntityCoords(boat)
end
