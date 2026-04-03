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
    TriggerEvent('chat:addMessage', { args = { '^2Water Rescue:', message } })
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

function Utils.driveBoatToPoint(driver, boat, target, speed, timeoutMs, threshold)
    local deadline = GetGameTimer() + timeoutMs
    local reissueAt = 0

    while GetGameTimer() < deadline do
        if not DoesEntityExist(driver) or IsPedDeadOrDying(driver, true) then
            return false, GetEntityCoords(boat)
        end

        if GetGameTimer() >= reissueAt then
            TaskBoatMission(driver, boat, 0, 0, target.x, target.y, target.z, 4, speed, 1074528293, 0.0, 0.0)
            reissueAt = GetGameTimer() + 850
        end

        local b = GetEntityCoords(boat)
        local dist = Vdist(b.x, b.y, b.z, target.x, target.y, target.z)
        if dist <= threshold then
            return true, b
        end

        Wait(200)
    end

    return false, GetEntityCoords(boat)
end
