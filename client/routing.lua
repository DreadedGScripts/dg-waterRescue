DGWaterRescue = DGWaterRescue or {}

local Routing = {}
DGWaterRescue.Routing = Routing

local Utils = DGWaterRescue.Utils

local function hasHazardObject(x, y, z)
    local avoid = Utils.cfg('Realism.avoidObjectModels', {})
    local radius = Utils.cfg('Realism.hazardScanRadius', 14.0)

    for _, modelName in ipairs(avoid) do
        local model = GetHashKey(modelName)
        local obj = GetClosestObjectOfType(x, y, z, radius, model, false, false, false)
        if obj and obj ~= 0 and DoesEntityExist(obj) then
            return true
        end
    end

    return false
end

local function hasHazardNearby(x, y, z)
    if hasHazardObject(x, y, z) then
        return true
    end

    -- Large structures (yachts/pier meshes) may not be detected at a single point.
    local largeRadius = Utils.cfg('Realism.largeHazardScanRadius', 60.0)
    local ringRadius = math.max(18.0, largeRadius * 0.55)
    for _, offset in ipairs({
        {  ringRadius,  0.0 },
        { -ringRadius,  0.0 },
        { 0.0,  ringRadius },
        { 0.0, -ringRadius },
    }) do
        if hasHazardObject(x + offset[1], y + offset[2], z) then
            return true
        end
    end

    return false
end

local function isInBlockedShoreArea(x, y, z)
    local blockedAreas = Utils.cfg('Realism.blockedShoreAreas', {})
    if type(blockedAreas) ~= 'table' then
        return false
    end

    for _, area in ipairs(blockedAreas) do
        local centerX = area.x or area[1]
        local centerY = area.y or area[2]
        local centerZ = area.z or area[3] or z
        local radius = tonumber(area.radius) or 0.0
        if centerX and centerY and radius > 0.0 then
            local dist = Vdist(x, y, z, centerX, centerY, centerZ)
            if dist <= radius then
                return true
            end
        end
    end

    return false
end

local function getRescueShorePoint(pos)
    local hutModelName = Utils.cfg('Models.lifeguardHut', 'prop_lifeguard_tower_01')
    local hutModel = GetHashKey(hutModelName)
    local handle, obj = FindFirstObject()
    local foundAny = true

    local bestDist = nil
    local bestPoint = nil

    repeat
        if DoesEntityExist(obj) and GetEntityModel(obj) == hutModel then
            local c = GetEntityCoords(obj)
            local dist = Vdist(c.x, c.y, c.z, pos.x, pos.y, pos.z)
            if not bestDist or dist < bestDist then
                bestDist = dist
                bestPoint = vector3(c.x, c.y, c.z)
            end
        end
        foundAny, obj = FindNextObject(handle)
    until not foundAny

    EndFindObject(handle)

    if bestPoint then
        return bestPoint
    end

    return vector3(-1335.0, -1690.0, 0.5)
end

function Routing.findSafeShore(origin)
    local maxRadius = Utils.cfg('Search.shoreSearchRadius', 2600.0)
    local radiusStep = Utils.cfg('Search.shoreSearchStep', 55.0)
    local angleStep = Utils.cfg('Search.shoreSearchAngleStep', 10)
    local probeForward = Utils.cfg('Search.shoreProbeForward', 10.0)
    local zoneBias = Utils.cfg('Realism.preferSandZones', true)
    local beachZones = Utils.cfg('Realism.beachZoneNames', {})
    local maxShoreHeightAboveWater = Utils.cfg('Search.maxShoreHeightAboveWater', 3.2)

    local best = nil

    local radius = 35.0
    while radius <= maxRadius do
        for angle = 0, 359, angleStep do
            local rad = math.rad(angle)
            local wx = origin.x + math.cos(rad) * radius
            local wy = origin.y + math.sin(rad) * radius

            local isWater, waterZ = GetWaterHeight(wx, wy, origin.z + 8.0, 0.0)
            if isWater and waterZ then
                local lx = wx + math.cos(rad) * probeForward
                local ly = wy + math.sin(rad) * probeForward

                local foundGround, groundZ = GetGroundZFor_3dCoord(lx, ly, waterZ + 20.0, 0)
                local stillWater, _ = GetWaterHeight(lx, ly, groundZ + 1.0, 0.0)

                if foundGround and not stillWater and groundZ > waterZ + 0.35 and groundZ <= (waterZ + maxShoreHeightAboveWater) then
                    if not hasHazardNearby(lx, ly, groundZ) and not isInBlockedShoreArea(lx, ly, groundZ) then
                        local score = radius
                        if zoneBias then
                            local zone = GetNameOfZone(lx, ly, groundZ)
                            if zone and beachZones[zone] then
                                score = score - 120.0
                            end
                        end

                        if not best or score < best.score then
                            best = {
                                shore = vector3(lx, ly, groundZ),
                                waterline = vector3(wx, wy, waterZ + 0.8),
                                score = score,
                            }
                        end
                    end
                end
            end
        end

        if best and best.score < 180.0 then
            break
        end

        radius = radius + radiusStep
    end

    if best then
        return best.shore, best.waterline
    end

    local fallback = getRescueShorePoint(origin)
    return fallback, vector3(fallback.x, fallback.y, Utils.getWaterOrDefault(fallback.x, fallback.y, fallback.z) + 0.8)
end
