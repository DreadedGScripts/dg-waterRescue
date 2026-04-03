DGWaterRescue = DGWaterRescue or {}

local Rescue = {}
DGWaterRescue.Rescue = Rescue

local Utils = DGWaterRescue.Utils
local Routing = DGWaterRescue.Routing
local Framework = DGWaterRescue.Framework

local state = 'IDLE'
local rescueActive = false
local lastRescueStartAt = 0

local function forcePlayerExitBoat(ped, boat, timeoutMs)
    if not DoesEntityExist(boat) then
        return true
    end

    if not IsPedInVehicle(ped, boat, false) then
        return true
    end

    ClearPedTasksImmediately(ped)
    TaskLeaveVehicle(ped, boat, 16)

    local deadline = GetGameTimer() + (timeoutMs or 3000)
    while GetGameTimer() < deadline do
        if not IsPedInVehicle(ped, boat, false) then
            return true
        end
        Wait(150)
    end

    -- Fallback: force-seat exit when task-based leave does not complete.
    if IsPedInVehicle(ped, boat, false) then
        TaskWarpPedOutOfVehicle(ped, boat)
        Wait(100)
    end

    return not IsPedInVehicle(ped, boat, false)
end

local function seatPedInBoat(ped, boat, preferredSeats)
    if type(preferredSeats) == 'table' then
        for _, seat in ipairs(preferredSeats) do
            if IsVehicleSeatFree(boat, seat) then
                TaskWarpPedIntoVehicle(ped, boat, seat)
                if IsPedInVehicle(ped, boat, false) then
                    return true
                end
            end
        end
    end

    for seat = 0, GetVehicleMaxNumberOfPassengers(boat) - 1 do
        if IsVehicleSeatFree(boat, seat) then
            TaskWarpPedIntoVehicle(ped, boat, seat)
            if IsPedInVehicle(ped, boat, false) then
                return true
            end
        end
    end

    return false
end

local function formatRuntimeError(err)
    local text = tostring(err or 'unknown error')
    text = text:gsub('^.-client[/\\]rescue.lua:', '')
    if #text > 120 then
        text = text:sub(1, 120)
    end
    return text
end

local function runWaterPickup(swimmer, ped, boat, targetPos)
    local waterZ = Utils.getWaterOrDefault(targetPos.x, targetPos.y, targetPos.z)
    local swimmerStart = vector3(targetPos.x + 1.4, targetPos.y + 1.1, waterZ + 0.15)
    local patientPickup = vector3(targetPos.x + 0.2, targetPos.y + 0.2, waterZ + 0.15)

    TaskLeaveVehicle(swimmer, boat, 16)
    Wait(900)

    if IsPedInVehicle(swimmer, boat, false) then
        TaskWarpPedOutOfVehicle(swimmer, boat)
        Wait(100)
    end

    SetEntityCoords(swimmer, swimmerStart.x, swimmerStart.y, swimmerStart.z, false, false, false, true)
    TaskGoStraightToCoord(swimmer, patientPickup.x, patientPickup.y, patientPickup.z, 1.25, -1, 0.0, 0.0)

    local swimDeadline = GetGameTimer() + 2500
    while GetGameTimer() < swimDeadline do
        local swimmerPos = GetEntityCoords(swimmer)
        if Vdist(swimmerPos.x, swimmerPos.y, swimmerPos.z, patientPickup.x, patientPickup.y, patientPickup.z) <= 1.3 then
            break
        end
        Wait(150)
    end

    if IsPedDeadOrDying(ped, true) then
        NetworkResurrectLocalPlayer(patientPickup.x, patientPickup.y, patientPickup.z, GetEntityHeading(ped), true, false)
        Wait(350)
    end

    SetEntityCoords(ped, patientPickup.x, patientPickup.y, patientPickup.z, false, false, false, true)
    ClearPedTasksImmediately(ped)
    ClearPedTasksImmediately(swimmer)

    local boatBoardPos = GetEntityCoords(boat)
    SetEntityCoords(swimmer, boatBoardPos.x + 0.7, boatBoardPos.y + 0.3, boatBoardPos.z + 0.4, false, false, false, true)
    SetEntityCoords(ped, boatBoardPos.x - 0.4, boatBoardPos.y - 0.2, boatBoardPos.z + 0.4, false, false, false, true)

    if not seatPedInBoat(swimmer, boat, { 0, 2, 1 }) then
        return false
    end

    if not seatPedInBoat(ped, boat, { 1, 2, 0 }) then
        return false
    end

    return true
end

local function placePlayerAtHandoffPoint(ped, boat, handoffPoint)
    forcePlayerExitBoat(ped, boat, 3500)

    if IsPedInAnyVehicle(ped, false) then
        local vehicle = GetVehiclePedIsIn(ped, false)
        if vehicle and vehicle ~= 0 then
            TaskWarpPedOutOfVehicle(ped, vehicle)
            Wait(100)
        end
    end

    ClearPedTasksImmediately(ped)

    local target = Utils.parseCoords(handoffPoint, GetEntityCoords(ped))
    local groundZ = Utils.getGroundOrDefault(target.x, target.y, target.z)
    SetEntityCoords(ped, target.x, target.y, groundZ + 0.15, false, false, false, true)
end

local function seatRearMedicInAmbulance(medic, ambulance)
    for _, seat in ipairs({ 1, 2, 0 }) do
        if IsVehicleSeatFree(ambulance, seat) then
            TaskWarpPedIntoVehicle(medic, ambulance, seat)
            if IsPedInVehicle(medic, ambulance, false) then
                return true
            end
        end
    end

    return false
end

local function getAmbulanceRearPositions(ambulance)
    local patientBase = GetOffsetFromEntityInWorldCoords(ambulance, 0.0, -4.5, 0.0)
    local medicBase = GetOffsetFromEntityInWorldCoords(ambulance, 0.9, -3.4, 0.0)

    local patientGround = Utils.getGroundOrDefault(patientBase.x, patientBase.y, patientBase.z)
    local medicGround = Utils.getGroundOrDefault(medicBase.x, medicBase.y, medicBase.z)

    return vector3(patientBase.x, patientBase.y, patientGround + 0.1), vector3(medicBase.x, medicBase.y, medicGround + 0.1)
end

local function carryPatientToAmbulanceRear(medic, ped, ambulance)
    local rearPatientPos, rearMedicPos = getAmbulanceRearPositions(ambulance)
    local carryDict = 'missfinale_c2mcs_1'
    local hasCarryAnim = Utils.loadAnimDict(carryDict)

    ClearPedTasksImmediately(medic)
    ClearPedTasksImmediately(ped)

    if hasCarryAnim then
        TaskPlayAnim(medic, carryDict, 'fin_c2_mcs_1_camman', 8.0, -8.0, -1, 49, 0.0, false, false, false)
        TaskPlayAnim(ped, carryDict, 'fin_c2_mcs_1_camman_p', 8.0, -8.0, -1, 33, 0.0, false, false, false)
    end

    SetEntityCollision(ped, false, false)
    AttachEntityToEntity(ped, medic, GetPedBoneIndex(medic, 11816), 0.27, 0.15, 0.63, 0.5, 0.5, 180.0, false, false, false, false, 2, false)

    TaskGoStraightToCoord(medic, rearMedicPos.x, rearMedicPos.y, rearMedicPos.z, 1.0, -1, GetEntityHeading(ambulance), 0.0)

    local deadline = GetGameTimer() + 12000
    while GetGameTimer() < deadline do
        local medicPos = GetEntityCoords(medic)
        if Vdist(medicPos.x, medicPos.y, medicPos.z, rearMedicPos.x, rearMedicPos.y, rearMedicPos.z) <= 1.5 then
            break
        end
        Wait(150)
    end

    DetachEntity(ped, true, true)
    SetEntityCollision(ped, true, true)
    ClearPedTasksImmediately(medic)
    ClearPedTasksImmediately(ped)

    SetEntityCoords(ped, rearPatientPos.x, rearPatientPos.y, rearPatientPos.z, false, false, false, true)
    SetEntityCoords(medic, rearMedicPos.x, rearMedicPos.y, rearMedicPos.z, false, false, false, true)
    SetEntityHeading(medic, GetEntityHeading(ambulance))
end

local function playCprSequence(medic, ped, durationMs)
    local duration = durationMs or 6200
    local playedAnim = false

    if IsPedInAnyVehicle(ped, false) then
        local veh = GetVehiclePedIsIn(ped, false)
        if veh and veh ~= 0 then
            TaskLeaveVehicle(ped, veh, 16)
            Wait(300)
            if IsPedInAnyVehicle(ped, false) then
                TaskWarpPedOutOfVehicle(ped, veh)
            end
        end
    end

    local pedPos = GetEntityCoords(ped)
    local medicPos = GetEntityCoords(medic)
    local faceHeading = GetHeadingFromVector_2d(pedPos.x - medicPos.x, pedPos.y - medicPos.y)

    ClearPedTasksImmediately(medic)
    ClearPedTasksImmediately(ped)
    SetEntityHeading(medic, faceHeading)
    SetEntityVelocity(ped, 0.0, 0.0, 0.0)
    FreezeEntityPosition(medic, true)
    FreezeEntityPosition(ped, true)

    local medicDict = 'mini@cpr@char_a@cpr_def'
    local patientDict = 'mini@cpr@char_b@cpr_def'

    if Utils.loadAnimDict(medicDict) and Utils.loadAnimDict(patientDict) then
        TaskPlayAnim(medic, medicDict, 'cpr_pumpchest', 8.0, -8.0, duration, 1, 0, false, false, false)
        TaskPlayAnim(ped, patientDict, 'cpr_pumpchest', 8.0, -8.0, duration, 1, 0, false, false, false)
        playedAnim = true
    end

    if not playedAnim then
        ClearPedTasksImmediately(medic)
        TaskStartScenarioInPlace(medic, 'CODE_HUMAN_MEDIC_KNEEL', 0, true)
        ClearPedTasksImmediately(ped)
        TaskStartScenarioInPlace(ped, 'WORLD_HUMAN_SUNBATHE_BACK', 0, true)
    end

    Wait(duration)
    FreezeEntityPosition(medic, false)
    FreezeEntityPosition(ped, false)
    ClearPedTasks(medic)
    ClearPedTasks(ped)
end

local function setState(nextState)
    state = nextState
    Utils.debug(('STATE => %s'):format(nextState))
    Framework.requestBillingAndCooldown(nextState)
end

local function spawnRescueBoatNear(targetPos, heading)
    local model = Utils.loadModel(Utils.cfg('Models.boat', 'dinghy'))
    if not model then return nil end

    local attempts = Utils.cfg('Search.rescueBoatSpawnAttempts', 14)
    local dist = Utils.cfg('Search.rescueBoatSpawnDistance', 90.0)

    for _ = 1, attempts do
        local angle = math.rad(math.random(0, 359))
        local bx = targetPos.x + math.cos(angle) * dist
        local by = targetPos.y + math.sin(angle) * dist
        local isWater, wz = GetWaterHeight(bx, by, targetPos.z + 10.0, 0.0)
        if isWater and wz then
            local boat = CreateVehicle(model, bx, by, wz + 1.1, heading, true, false)
            if boat and DoesEntityExist(boat) then
                SetEntityAsMissionEntity(boat, true, true)
                SetBoatAnchor(boat, false)
                SetVehicleEngineOn(boat, true, true, true)
                return boat
            end
        end
    end

    return nil
end

local function runSequence(rawCoords, rescueOptions)
    if rescueActive then
        return
    end

    local options = type(rescueOptions) == 'table' and rescueOptions or {}
    local useAiAmbulance = options.useAiAmbulance ~= false

    if Utils.cfg('Cooldown.enabled', true) then
        local cooldownSeconds = Utils.cfg('Cooldown.seconds', 240)
        local elapsedMs = GetGameTimer() - lastRescueStartAt
        local cooldownMs = cooldownSeconds * 1000
        if lastRescueStartAt > 0 and elapsedMs < cooldownMs then
            local remaining = math.ceil((cooldownMs - elapsedMs) / 1000)
            Framework.notify(('Rescue unavailable for %ds due to cooldown.'):format(remaining), 'low')
            return
        end
    end

    rescueActive = true
    lastRescueStartAt = GetGameTimer()
    setState('DISPATCHED')

    local entities = {}
    local function track(ent)
        if ent and ent ~= 0 then
            table.insert(entities, ent)
        end
        return ent
    end

    local ok, err = pcall(function()
        local ped = PlayerPedId()
        local deathPos = Utils.parseCoords(rawCoords, GetEntityCoords(ped))

        if IsPedInAnyVehicle(ped, false) then
            Framework.notify('Rescue cancelled: you are already in a vehicle.', 'low')
            return
        end

        if not IsEntityInWater(ped) then
            Utils.debug('Rescue cancelled: not in water')
            return
        end

        Framework.notify('Lifeguard boat dispatched. Stay calm.', 'medium', 'Rescue team en route')

        local shore, waterline = Routing.findSafeShore(deathPos)
        local dirSeaX, dirSeaY = Utils.normalize2d(deathPos.x - shore.x, deathPos.y - shore.y)
        local perpX, perpY = -dirSeaY, dirSeaX

        local boatBeachInlandOffset = Utils.cfg('Search.boatBeachInlandOffset', 3.0)
        local beachPoint = vector3(
            shore.x - (dirSeaX * boatBeachInlandOffset),
            shore.y - (dirSeaY * boatBeachInlandOffset),
            Utils.getGroundOrDefault(shore.x, shore.y, shore.z) + 0.2
        )

        local rendezvous = vector3(
            shore.x - (dirSeaX * Utils.cfg('Search.patientDropInlandOffset', 4.0)),
            shore.y - (dirSeaY * Utils.cfg('Search.patientDropInlandOffset', 4.0)),
            Utils.getGroundOrDefault(shore.x, shore.y, shore.z) + 0.2
        )

        local ambulanceSpawn = vector3(
            shore.x - (dirSeaX * Utils.cfg('Search.ambulanceInlandDistance', 28.0)) + (perpX * Utils.cfg('Search.ambulanceSideOffset', 4.0)),
            shore.y - (dirSeaY * Utils.cfg('Search.ambulanceInlandDistance', 28.0)) + (perpY * Utils.cfg('Search.ambulanceSideOffset', 4.0)),
            shore.z
        )
        ambulanceSpawn = vector3(
            ambulanceSpawn.x,
            ambulanceSpawn.y,
            Utils.getGroundOrDefault(ambulanceSpawn.x, ambulanceSpawn.y, ambulanceSpawn.z)
        )

        local driverModel = Utils.loadModel(Utils.cfg('Models.rescueDriver', 's_m_y_baywatch_01'))
        local ambulanceModel = nil
        local medicModel = nil

        if useAiAmbulance then
            ambulanceModel = Utils.loadModel(Utils.cfg('Models.ambulance', 'ambulance'))
            medicModel = Utils.loadModel(Utils.cfg('Models.paramedic', 's_m_m_paramedic_01'))
        end

        if not driverModel or (useAiAmbulance and (not ambulanceModel or not medicModel)) then
            Framework.notify('Rescue unavailable (model load failed).', 'critical')
            return
        end

        local headingToSea = GetHeadingFromVector_2d(dirSeaX, dirSeaY)

        local ambulance = nil
        local ambulanceDriver = nil
        local medic = nil

        if useAiAmbulance then
            ambulance = track(CreateVehicle(ambulanceModel, ambulanceSpawn.x, ambulanceSpawn.y, ambulanceSpawn.z, headingToSea, true, false))
            ambulanceDriver = track(CreatePedInsideVehicle(ambulance, 26, medicModel, -1, true, false))
            medic = track(CreatePed(26, medicModel, ambulanceSpawn.x, ambulanceSpawn.y, ambulanceSpawn.z + 0.2, headingToSea, true, false))

            if not DoesEntityExist(ambulance) or not DoesEntityExist(ambulanceDriver) or not DoesEntityExist(medic) then
                Framework.notify('Rescue unavailable (ambulance team failed to spawn).', 'critical')
                return
            end

            seatRearMedicInAmbulance(medic, ambulance)

            SetEntityAsMissionEntity(ambulance, true, true)
            SetVehicleSiren(ambulance, true)
            SetVehicleHasMutedSirens(ambulance, false)

            SetEntityAsMissionEntity(ambulanceDriver, true, true)
            SetEntityInvincible(ambulanceDriver, true)
            SetBlockingOfNonTemporaryEvents(ambulanceDriver, true)

            SetEntityAsMissionEntity(medic, true, true)
            SetEntityInvincible(medic, true)
            SetBlockingOfNonTemporaryEvents(medic, true)
        end

        local boat = track(spawnRescueBoatNear(deathPos, headingToSea))
        if not boat then
            Framework.notify('Rescue failed to find safe boat spawn.', 'critical')
            return
        end

        local driver = track(CreatePedInsideVehicle(boat, 26, driverModel, -1, true, false))
        local swimmer = track(CreatePed(26, driverModel, deathPos.x, deathPos.y, deathPos.z + 1.0, headingToSea, true, false))
        if not DoesEntityExist(driver) or not DoesEntityExist(swimmer) then
            Framework.notify('Rescue failed to deploy lifeguard crew.', 'critical')
            return
        end

        if not seatPedInBoat(swimmer, boat, { 0, 1, 2 }) then
            Framework.notify('Rescue failed to seat the swimmer lifeguard.', 'critical')
            return
        end

        SetEntityAsMissionEntity(driver, true, true)
        SetEntityInvincible(driver, true)
        SetBlockingOfNonTemporaryEvents(driver, true)
        SetPedCanBeDraggedOut(driver, false)
        SetPedStayInVehicleWhenJacked(driver, true)

        SetEntityAsMissionEntity(swimmer, true, true)
        SetEntityInvincible(swimmer, true)
        SetBlockingOfNonTemporaryEvents(swimmer, true)
        SetPedCanBeDraggedOut(swimmer, false)
        SetPedStayInVehicleWhenJacked(swimmer, true)

        setState('PICKUP')

        local pickedUp, boatPos = Utils.driveBoatToPoint(
            driver,
            boat,
            vector3(deathPos.x, deathPos.y, Utils.getWaterOrDefault(deathPos.x, deathPos.y, deathPos.z) + 0.6),
            Utils.cfg('Navigation.boatPickupSpeed', 34.0),
            Utils.cfg('TimeoutsMs.boatPickup', 45000),
            Utils.cfg('Navigation.boatPickupDistance', 14.0)
        )

        if not pickedUp then
            Framework.notify('Rescue boat could not reach you in time.', 'critical')
            setState('FAILED')
            return
        end

        if not runWaterPickup(swimmer, ped, boat, deathPos) then
            Framework.notify('Rescue boat crew could not complete water pickup.', 'critical')
            setState('FAILED')
            return
        end

        Framework.notify('Boat pickup complete. Heading to shore.', 'medium')
        setState('SHORE_TRANSIT')

        Utils.driveBoatToPoint(
            driver,
            boat,
            waterline,
            Utils.cfg('Navigation.boatShoreSpeed', 36.0),
            Utils.cfg('TimeoutsMs.boatToShore', 42000),
            Utils.cfg('Navigation.boatShoreApproachThreshold', 10.0)
        )

        local beached, finalBoatPos = Utils.driveBoatToPoint(
            driver,
            boat,
            beachPoint,
            Utils.cfg('Navigation.boatBeachSpeed', 44.0),
            Utils.cfg('TimeoutsMs.boatBeach', 22000),
            Utils.cfg('Navigation.boatBeachStopDistance', 11.0)
        )

        if not beached then
            SetEntityCoordsNoOffset(boat, beachPoint.x, beachPoint.y, beachPoint.z + 0.2, false, false, false)
            finalBoatPos = GetEntityCoords(boat)
        end

        SetBoatAnchor(boat, true)
        SetVehicleEngineOn(boat, false, true, true)
        SetVehicleUndriveable(boat, true)
        ClearPedTasksImmediately(driver)

        setState('BEACH_HANDOFF')

        local handoffPoint = vector3(
            finalBoatPos.x + (perpX * 2.6) - (dirSeaX * 1.1),
            finalBoatPos.y + (perpY * 2.6) - (dirSeaY * 1.1),
            Utils.getGroundOrDefault(finalBoatPos.x + (perpX * 2.6) - (dirSeaX * 1.1), finalBoatPos.y + (perpY * 2.6) - (dirSeaY * 1.1), finalBoatPos.z)
        )

        if not useAiAmbulance then
            placePlayerAtHandoffPoint(ped, boat, handoffPoint)
            Framework.notify('Boat handoff complete. Real EMS have your rescue location.', 'medium', 'Await medical responders on shore')
            setState('CLEANUP')
            return
        end

        TaskVehicleDriveToCoord(
            ambulanceDriver,
            ambulance,
            rendezvous.x,
            rendezvous.y,
            rendezvous.z,
            Utils.cfg('Navigation.ambulanceResponseSpeed', 24.0),
            0,
            GetEntityModel(ambulance),
            786603,
            1.0,
            true
        )

        placePlayerAtHandoffPoint(ped, boat, handoffPoint)

        local ambDeadline = GetGameTimer() + Utils.cfg('TimeoutsMs.ambulanceArrival', 20000)
        while GetGameTimer() < ambDeadline do
            local ambPos = GetEntityCoords(ambulance)
            if Vdist(ambPos.x, ambPos.y, ambPos.z, rendezvous.x, rendezvous.y, rendezvous.z) <= 14.0 then
                break
            end
            Wait(250)
        end

        TaskLeaveVehicle(medic, ambulance, 0)
        Wait(900)

        local rearPatientPos, rearMedicPos = getAmbulanceRearPositions(ambulance)
        SetEntityCoords(medic, rearMedicPos.x, rearMedicPos.y, rearMedicPos.z, false, false, false, true)
        SetEntityHeading(medic, GetEntityHeading(ambulance))

        local patientPos = GetEntityCoords(ped)
        if IsPedInAnyVehicle(ped, false) then
            local boatPos = GetEntityCoords(boat)
            patientPos = vector3(boatPos.x, boatPos.y, boatPos.z)
        end
        TaskGoStraightToCoord(medic, patientPos.x, patientPos.y, patientPos.z, 2.0, -1, 0.0, 0.0)

        local walkDeadline = GetGameTimer() + Utils.cfg('TimeoutsMs.walkToPatient', 12000)
        while GetGameTimer() < walkDeadline do
            local mPos = GetEntityCoords(medic)
            if Vdist(mPos.x, mPos.y, mPos.z, patientPos.x, patientPos.y, patientPos.z) <= 2.5 then
                break
            end
            Wait(250)
        end

        carryPatientToAmbulanceRear(medic, ped, ambulance)
        SetEntityCoords(ped, rearPatientPos.x, rearPatientPos.y, rearPatientPos.z, false, false, false, true)
        SetEntityCoords(medic, rearMedicPos.x, rearMedicPos.y, rearMedicPos.z, false, false, false, true)

        setState('CPR')

        playCprSequence(medic, ped, Utils.cfg('Medical.cprDurationMs', 6200))

        Framework.reviveWithFallback(ped)

        setState('REVIVED')
        Framework.notify('CPR complete. You were revived with critical condition.', 'success', 'Seek treatment immediately')

        local departPos = vector3(
            ambulanceSpawn.x + math.random(55, 85),
            ambulanceSpawn.y + math.random(55, 85),
            ambulanceSpawn.z
        )

        TaskEnterVehicle(medic, ambulance, 3000, 0, 1.5, 1, 0)
        Wait(2200)
        TaskVehicleDriveToCoord(ambulanceDriver, ambulance, departPos.x, departPos.y, departPos.z, 22.0, 0, GetEntityModel(ambulance), 524863, 1.0, true)

        Wait(Utils.cfg('TimeoutsMs.postReviveCleanup', 10000))

        setState('CLEANUP')
    end)

    if not ok then
        Utils.debug(('Rescue error: %s'):format(err))
        Framework.notify(('Rescue sequence failed: %s'):format(formatRuntimeError(err)), 'critical')
        Framework.notify('Rescue sequence failed and was reset.', 'critical')
        setState('FAILED')
    end

    Utils.cleanupEntities(entities)
    rescueActive = false
    setState('IDLE')
end

function Rescue.begin(coords, rescueOptions)
    runSequence(coords, rescueOptions)
end

function Rescue.isActive()
    return rescueActive
end
