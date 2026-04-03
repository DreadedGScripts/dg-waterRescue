DGWaterRescue = DGWaterRescue or {}

local Rescue = {}
DGWaterRescue.Rescue = Rescue

local Utils = DGWaterRescue.Utils
local Routing = DGWaterRescue.Routing
local Framework = DGWaterRescue.Framework

local state = 'IDLE'
local rescueActive = false
local lastRescueStartAt = 0

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

local function runSequence(rawCoords)
    if rescueActive then
        return
    end

    if Utils.cfg('Cooldown.enabled', true) then
        local cooldownSeconds = Utils.cfg('Cooldown.seconds', 240)
        local elapsed = os.time() - lastRescueStartAt
        if lastRescueStartAt > 0 and elapsed < cooldownSeconds then
            local remaining = cooldownSeconds - elapsed
            Framework.notify(('Rescue unavailable for %ds due to cooldown.'):format(remaining), 'low')
            return
        end
    end

    rescueActive = true
    lastRescueStartAt = os.time()
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

        local beachPoint = vector3(
            shore.x - (dirSeaX * Utils.cfg('Search.beachInlandDistance', 10.0)),
            shore.y - (dirSeaY * Utils.cfg('Search.beachInlandDistance', 10.0)),
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

        local ambulanceModel = Utils.loadModel(Utils.cfg('Models.ambulance', 'ambulance'))
        local medicModel = Utils.loadModel(Utils.cfg('Models.paramedic', 's_m_m_paramedic_01'))
        local driverModel = Utils.loadModel(Utils.cfg('Models.rescueDriver', 's_m_y_baywatch_01'))

        if not ambulanceModel or not medicModel or not driverModel then
            Framework.notify('Rescue unavailable (model load failed).', 'critical')
            return
        end

        local headingToSea = GetHeadingFromVector_2d(dirSeaX, dirSeaY)

        local ambulance = track(CreateVehicle(ambulanceModel, ambulanceSpawn.x, ambulanceSpawn.y, ambulanceSpawn.z, headingToSea, true, false))
        local medic = track(CreatePedInsideVehicle(ambulance, 26, medicModel, -1, true, false))

        if not DoesEntityExist(ambulance) or not DoesEntityExist(medic) then
            Framework.notify('Rescue unavailable (ambulance team failed to spawn).', 'critical')
            return
        end

        SetEntityAsMissionEntity(ambulance, true, true)
        SetVehicleSiren(ambulance, true)
        SetVehicleHasMutedSirens(ambulance, false)

        SetEntityAsMissionEntity(medic, true, true)
        SetEntityInvincible(medic, true)
        SetBlockingOfNonTemporaryEvents(medic, true)

        local boat = track(spawnRescueBoatNear(deathPos, headingToSea))
        if not boat then
            Framework.notify('Rescue failed to find safe boat spawn.', 'critical')
            return
        end

        local driver = track(CreatePedInsideVehicle(boat, 26, driverModel, -1, true, false))
        if not DoesEntityExist(driver) then
            Framework.notify('Rescue failed to deploy lifeguard driver.', 'critical')
            return
        end

        SetEntityAsMissionEntity(driver, true, true)
        SetEntityInvincible(driver, true)
        SetBlockingOfNonTemporaryEvents(driver, true)
        SetPedCanBeDraggedOut(driver, false)
        SetPedStayInVehicleWhenJacked(driver, true)

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

        if IsPedDeadOrDying(ped, true) then
            NetworkResurrectLocalPlayer(boatPos.x, boatPos.y, boatPos.z + 1.0, GetEntityHeading(ped), true, false)
            Wait(350)
        end

        SetEntityCoords(ped, boatPos.x, boatPos.y, boatPos.z + 1.0, false, false, false, true)
        ClearPedTasksImmediately(ped)

        if not Utils.seatPlayerInBoat(ped, boat) then
            Framework.notify('Rescue boat is full and cannot board you.', 'critical')
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

        TaskVehicleDriveToCoord(
            medic,
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

        TaskLeaveVehicle(ped, boat, 16)
        Wait(900)
        SetEntityCoords(ped, rendezvous.x, rendezvous.y, rendezvous.z, false, false, false, true)

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

        local patientPos = GetEntityCoords(ped)
        TaskGoStraightToCoord(medic, patientPos.x, patientPos.y, patientPos.z, 2.0, -1, 0.0, 0.0)

        local walkDeadline = GetGameTimer() + Utils.cfg('TimeoutsMs.walkToPatient', 12000)
        while GetGameTimer() < walkDeadline do
            local mPos = GetEntityCoords(medic)
            if Vdist(mPos.x, mPos.y, mPos.z, patientPos.x, patientPos.y, patientPos.z) <= 2.5 then
                break
            end
            Wait(250)
        end

        setState('CPR')

        local medicDict = 'mini@cpr@char_a@cpr_def'
        local patientDict = 'mini@cpr@char_b@cpr_def'

        if Utils.loadAnimDict(medicDict) then
            TaskPlayAnim(medic, medicDict, 'cpr_pumpchest', 8.0, -8.0, Utils.cfg('Medical.cprDurationMs', 6200), 1, 0, false, false, false)
        end

        if Utils.loadAnimDict(patientDict) then
            TaskPlayAnim(ped, patientDict, 'cpr_pumpchest', 8.0, -8.0, Utils.cfg('Medical.cprDurationMs', 6200), 1, 0, false, false, false)
        end

        Wait(Utils.cfg('Medical.cprDurationMs', 6200))
        ClearPedTasks(ped)
        ClearPedTasks(medic)

        Framework.reviveWithFallback(ped)

        local boatExit = finalBoatPos or GetEntityCoords(boat)
        SetEntityCoords(ped, boatExit.x, boatExit.y, boatExit.z + 0.2, false, false, false, true)

        setState('REVIVED')
        Framework.notify('CPR complete. You were revived with critical condition.', 'success', 'Seek treatment immediately')

        local departPos = vector3(
            ambulanceSpawn.x + math.random(55, 85),
            ambulanceSpawn.y + math.random(55, 85),
            ambulanceSpawn.z
        )

        TaskEnterVehicle(medic, ambulance, 3000, -1, 1.5, 1, 0)
        Wait(2200)
        TaskVehicleDriveToCoord(medic, ambulance, departPos.x, departPos.y, departPos.z, 22.0, 0, GetEntityModel(ambulance), 524863, 1.0, true)

        Wait(Utils.cfg('TimeoutsMs.postReviveCleanup', 10000))

        setState('CLEANUP')
    end)

    if not ok then
        Utils.debug(('Rescue error: %s'):format(err))
        Framework.notify('Rescue sequence failed and was reset.', 'critical')
        setState('FAILED')
    end

    Utils.cleanupEntities(entities)
    rescueActive = false
    setState('IDLE')
end

function Rescue.begin(coords)
    runSequence(coords)
end

function Rescue.isActive()
    return rescueActive
end
