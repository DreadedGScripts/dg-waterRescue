DGWaterRescue = DGWaterRescue or {}

local Rescue = {}
DGWaterRescue.Rescue = Rescue

local Utils = DGWaterRescue.Utils
local Routing = DGWaterRescue.Routing
local Framework = DGWaterRescue.Framework

local state = 'IDLE'
local rescueActive = false
local lastRescueStartAt = 0
local SHOULDER_CARRY_DICT = 'missfinale_c2mcs_1'
local SHOULDER_CARRY_MEDIC_ANIM = 'fin_c2_mcs_1_camman'
local SHOULDER_CARRY_PATIENT_ANIM = 'firemans_carry'
local SHOULDER_CARRY_PATIENT_FALLBACK_ANIM = 'fin_c2_mcs_1_camman_p'

local function playPatientCarryAnimation(ped)
    TaskPlayAnim(ped, SHOULDER_CARRY_DICT, SHOULDER_CARRY_PATIENT_ANIM, 8.0, -8.0, -1, 33, 0.0, false, false, false)
    Wait(50)

    if not IsEntityPlayingAnim(ped, SHOULDER_CARRY_DICT, SHOULDER_CARRY_PATIENT_ANIM, 3) then
        TaskPlayAnim(ped, SHOULDER_CARRY_DICT, SHOULDER_CARRY_PATIENT_FALLBACK_ANIM, 8.0, -8.0, -1, 33, 0.0, false, false, false)
    end
end

local function pickRescueDriverModelName()
    local candidates = Utils.cfg('Models.rescueDrivers', nil)
    if type(candidates) ~= 'table' or #candidates == 0 then
        return Utils.cfg('Models.rescueDriver', 's_m_y_baywatch_01')
    end

    local pool = {}
    for _, name in ipairs(candidates) do
        if type(name) == 'string' and name ~= '' then
            pool[#pool + 1] = name
        end
    end

    if #pool == 0 then
        return Utils.cfg('Models.rescueDriver', 's_m_y_baywatch_01')
    end

    return pool[math.random(1, #pool)]
end

local function driveBoatForPickup(driver, boat, deathPos)
    local timeoutMs = Utils.cfg('TimeoutsMs.boatPickup', 45000)
    local forcePickupDistance = Utils.cfg('Navigation.boatPickupGraceDistance', 28.0)
    local deepWaterPickupDistance = forcePickupDistance + 18.0
    local deadline = GetGameTimer() + timeoutMs
    local reissueAt = 0

    while GetGameTimer() < deadline do
        if not DoesEntityExist(driver) or IsPedDeadOrDying(driver, true) or not DoesEntityExist(boat) then
            return false, GetEntityCoords(boat)
        end

        Utils.setVehicleFuelFull(boat)
        SetBoatAnchor(boat, false)
        SetVehicleUndriveable(boat, false)
        SetVehicleEngineOn(boat, true, true, true)

        local boatPos = GetEntityCoords(boat)
        local dx = boatPos.x - deathPos.x
        local dy = boatPos.y - deathPos.y
        local horizontalDist = math.sqrt((dx * dx) + (dy * dy))

        local victimWaterZ = Utils.getWaterOrDefault(deathPos.x, deathPos.y, deathPos.z)
        local victimDepth = victimWaterZ - deathPos.z
        local isDeepUnderwater = victimDepth >= 6.0

        if horizontalDist <= forcePickupDistance then
            return true, boatPos
        end

        if isDeepUnderwater and horizontalDist <= deepWaterPickupDistance then
            Utils.debug(('Deep-water pickup fallback engaged at %.2fm horizontal distance'):format(horizontalDist))
            return true, boatPos
        end

        if GetGameTimer() >= reissueAt then
            TaskBoatMission(
                driver,
                boat,
                0,
                0,
                deathPos.x,
                deathPos.y,
                Utils.getWaterOrDefault(deathPos.x, deathPos.y, deathPos.z) + 0.7,
                4,
                Utils.cfg('Navigation.boatPickupSpeed', 34.0),
                1074528293,
                0.0,
                0.0
            )
            reissueAt = GetGameTimer() + 2200
        end

        if GetEntitySpeed(boat) < 1.1 and horizontalDist <= (forcePickupDistance + 12.0) then
            return true, boatPos
        end

        Wait(200)
    end

    local finalPos = GetEntityCoords(boat)
    local fdx = finalPos.x - deathPos.x
    local fdy = finalPos.y - deathPos.y
    local finalHorizontalDist = math.sqrt((fdx * fdx) + (fdy * fdy))
    if finalHorizontalDist <= (deepWaterPickupDistance + 8.0) then
        return true, finalPos
    end

    return false, finalPos
end

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

local function formatRuntimeError(err)
    local text = tostring(err or 'unknown error')
    text = text:gsub('^.-client[/\\]rescue.lua:', '')
    if #text > 120 then
        text = text:sub(1, 120)
    end
    return text
end

local function placePlayerAtHandoffPoint(ped, boat, handoffPoint)
    if DoesEntityExist(boat) and IsEntityAttachedToEntity(ped, boat) then
        DetachEntity(ped, true, true)
        SetEntityCollision(ped, true, true)
    end

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

local function boardPlayerForWaterTransit(ped, boat)
    if not DoesEntityExist(boat) then
        return nil
    end

    ClearPedTasksImmediately(ped)

    if Utils.seatPlayerInBoat(ped, boat) and IsPedInVehicle(ped, boat, false) then
        return 'seat'
    end

    -- Fallback for one-seat craft: attach patient to craft so transit can continue.
    SetEntityCollision(ped, false, false)
    AttachEntityToEntity(ped, boat, 0, 0.0, -0.6, 0.55, 0.0, 0.0, 180.0, false, false, false, false, 2, true)
    Wait(100)

    if IsEntityAttachedToEntity(ped, boat) then
        return 'attached'
    end

    SetEntityCollision(ped, true, true)
    return nil
end

local function getAmbulanceLoadPosition(ambulance)
    local loadBase = GetOffsetFromEntityInWorldCoords(ambulance, 1.2, -2.6, 0.0)
    local loadGround = Utils.getGroundOrDefault(loadBase.x, loadBase.y, loadBase.z)
    return vector3(loadBase.x, loadBase.y, loadGround + 0.1)
end

local function setAmbulanceRearDoorsOpen(ambulance, isOpen)
    if not DoesEntityExist(ambulance) then
        return
    end

    for _, doorIndex in ipairs({ 2, 3 }) do
        if isOpen then
            SetVehicleDoorOpen(ambulance, doorIndex, false, false)
        else
            SetVehicleDoorShut(ambulance, doorIndex, false)
        end
    end
end

local function getAmbulancePatientSeat(ambulance)
    for _, seat in ipairs({ 1, 2, 0 }) do
        if IsVehicleSeatFree(ambulance, seat) then
            return seat
        end
    end

    return nil
end

local function getAmbulanceRearSeat(ambulance)
    for _, seat in ipairs({ 1, 2 }) do
        if IsVehicleSeatFree(ambulance, seat) then
            return seat
        end
    end

    return nil
end

local function placeMedicInRearSeat(medic, ambulance)
    local rearSeat = getAmbulanceRearSeat(ambulance)
    if rearSeat == nil then
        return false
    end

    TaskWarpPedIntoVehicle(medic, ambulance, rearSeat)
    Wait(100)
    return IsPedInVehicle(medic, ambulance, false)
end

local function boardMedicInAmbulance(medic, ambulance, reservedSeat)
    for _, seat in ipairs({ 2, 1, 0 }) do
        if seat ~= reservedSeat and IsVehicleSeatFree(ambulance, seat) then
            TaskWarpPedIntoVehicle(medic, ambulance, seat)
            if IsPedInVehicle(medic, ambulance, false) then
                return true
            end
        end
    end

    return false
end

local function prepPatientForCarry(ped)
    if IsEntityAttached(ped) then
        DetachEntity(ped, true, true)
    end

    local pedPos = GetEntityCoords(ped)
    if IsPedDeadOrDying(ped, true) then
        NetworkResurrectLocalPlayer(pedPos.x, pedPos.y, pedPos.z, GetEntityHeading(ped), true, false)
        Wait(100)
    end

    ClearPedSecondaryTask(ped)
    ClearPedTasksImmediately(ped)
    FreezeEntityPosition(ped, false)
    SetEntityInvincible(ped, true)
    SetPedCanRagdoll(ped, false)
    SetEntityHealth(ped, math.max(101, math.min(GetEntityMaxHealth(ped), 110)))
end

local function startShoulderCarry(medic, ped, resetTasks)
    local hasCarryAnim = Utils.loadAnimDict(SHOULDER_CARRY_DICT)

    if resetTasks ~= false then
        ClearPedTasksImmediately(medic)
        ClearPedTasksImmediately(ped)
    end

    if hasCarryAnim then
        TaskPlayAnim(medic, SHOULDER_CARRY_DICT, SHOULDER_CARRY_MEDIC_ANIM, 8.0, -8.0, -1, 49, 0.0, false, false, false)
        playPatientCarryAnimation(ped)
    end

    SetEntityCollision(ped, false, false)
    AttachEntityToEntity(ped, medic, GetPedBoneIndex(medic, 24818), 0.18, 0.16, 0.52, 75.0, 82.0, 182.0, false, false, false, false, 2, true)
end

local function ensureShoulderCarryAnimation(medic, ped)
    if not Utils.loadAnimDict(SHOULDER_CARRY_DICT) then
        return
    end

    if not IsEntityPlayingAnim(medic, SHOULDER_CARRY_DICT, SHOULDER_CARRY_MEDIC_ANIM, 3) then
        TaskPlayAnim(medic, SHOULDER_CARRY_DICT, SHOULDER_CARRY_MEDIC_ANIM, 8.0, -8.0, -1, 49, 0.0, false, false, false)
    end

    if not IsEntityPlayingAnim(ped, SHOULDER_CARRY_DICT, SHOULDER_CARRY_PATIENT_ANIM, 3)
        and not IsEntityPlayingAnim(ped, SHOULDER_CARRY_DICT, SHOULDER_CARRY_PATIENT_FALLBACK_ANIM, 3) then
        playPatientCarryAnimation(ped)
    end
end

local function stopShoulderCarry(medic, ped)
    if IsEntityAttachedToEntity(ped, medic) then
        DetachEntity(ped, true, true)
    end

    SetEntityCollision(ped, true, true)
    SetPedCanRagdoll(ped, true)
    SetEntityInvincible(ped, false)
    ClearPedSecondaryTask(ped)
    ClearPedTasksImmediately(medic)
    ClearPedTasksImmediately(ped)
end

local function carryPatientIntoAmbulance(medic, ped, ambulance)
    local loadPos = getAmbulanceLoadPosition(ambulance)
    local patientSeat = getAmbulancePatientSeat(ambulance)
    if patientSeat == nil then
        return false, nil
    end

    prepPatientForCarry(ped)
    startShoulderCarry(medic, ped)
    SetPedKeepTask(medic, true)
    SetPedMoveRateOverride(medic, 10.0)
    SetPedMaxMoveBlendRatio(medic, 3.0)
    TaskGoToCoordAnyMeans(medic, loadPos.x, loadPos.y, loadPos.z, 6.0, 0, false, 786603, 0.0)

    local deadline = GetGameTimer() + 9000
    while GetGameTimer() < deadline do
        local medicPos = GetEntityCoords(medic)
        if Vdist(medicPos.x, medicPos.y, medicPos.z, loadPos.x, loadPos.y, loadPos.z) <= 1.6 then
            break
        end

        if not IsEntityAttachedToEntity(ped, medic) then
            startShoulderCarry(medic, ped, false)
        end

        ensureShoulderCarryAnimation(medic, ped)

        Wait(150)
    end

    stopShoulderCarry(medic, ped)

    TaskWarpPedIntoVehicle(ped, ambulance, patientSeat)
    Wait(150)

    if not IsPedInVehicle(ped, ambulance, false) then
        return false, nil
    end

    return true, patientSeat
end

local function revivePatientInsideAmbulance(ped, ambulance, patientSeat)
    if not DoesEntityExist(ambulance) then
        return false
    end

    TriggerServerEvent('dg-waterRescue:server:preparePatientRevive')
    Wait(250)

    if not IsPedInVehicle(ped, ambulance, false) then
        TaskWarpPedIntoVehicle(ped, ambulance, patientSeat or 1)
        Wait(150)
    end

    if IsPedDeadOrDying(ped, true) then
        local p = GetEntityCoords(ped)
        NetworkResurrectLocalPlayer(p.x, p.y, p.z, GetEntityHeading(ambulance), true, false)
        Wait(100)
    end

    local maxHealth = GetEntityMaxHealth(ped)
    local target = math.min(maxHealth, Utils.cfg('Medical.partialReviveHealth', 130))
    SetEntityHealth(ped, target)
    ClearPedBloodDamage(ped)
    ClearPedSecondaryTask(ped)
    ClearPedTasksImmediately(ped)

    if not IsPedInVehicle(ped, ambulance, false) then
        TaskWarpPedIntoVehicle(ped, ambulance, patientSeat or 1)
        Wait(150)
    end

    return IsPedInVehicle(ped, ambulance, false)
end

local function releasePatientFromAmbulance(ped, ambulance)
    if not DoesEntityExist(ambulance) then
        return false
    end

    local dropPos = GetOffsetFromEntityInWorldCoords(ambulance, 1.4, -4.2, 0.0)
    local dropZ = Utils.getGroundOrDefault(dropPos.x, dropPos.y, dropPos.z)

    if IsPedInAnyVehicle(ped, false) then
        TaskWarpPedOutOfVehicle(ped, ambulance)
        Wait(100)
    end

    ClearPedTasksImmediately(ped)
    SetEntityCoords(ped, dropPos.x, dropPos.y, dropZ + 0.1, false, false, false, true)
    SetEntityHeading(ped, GetEntityHeading(ambulance))
    SetEntityInvincible(ped, false)
    SetPedCanRagdoll(ped, true)
    return true
end

local function choosePatientOutcomeInAmbulance()
    if not Utils.cfg('PatientChoice.enabled', true) then
        return 'revive'
    end

    local timeoutSeconds = Utils.cfg('PatientChoice.timeoutSeconds', 12)
    local defaultChoice = Utils.cfg('PatientChoice.defaultChoice', 'dropoff')
    local reviveControl = Utils.cfg('PatientChoice.reviveControl', 38)
    local dropoffControl = Utils.cfg('PatientChoice.dropoffControl', 47)
    local deadline = GetGameTimer() + (timeoutSeconds * 1000)

    while GetGameTimer() < deadline do
        local secondsLeft = math.max(1, math.ceil((deadline - GetGameTimer()) / 1000))
        local message = ('Press ~INPUT_CONTEXT~ to revive in ambulance ($%s) or ~INPUT_DETONATE~ to be dropped off without revive. Auto: %s in %ss'):format(
            tostring(Utils.cfg('Billing.amount', 850)),
            tostring(defaultChoice),
            secondsLeft
        )

        BeginTextCommandDisplayHelp('STRING')
        AddTextComponentSubstringPlayerName(message)
        EndTextCommandDisplayHelp(0, false, false, 1)

        if IsControlJustPressed(0, reviveControl) then
            return 'revive'
        end

        if IsControlJustPressed(0, dropoffControl) then
            return 'dropoff'
        end

        Wait(0)
    end

    return defaultChoice
end

local function sendRescueUnitsAway(boat, driver, seaExitPoint, ambulance, ambulanceDriver, medic, ambulanceExitPoint)
    if DoesEntityExist(boat) and DoesEntityExist(driver) and seaExitPoint then
        SetBoatAnchor(boat, false)
        SetVehicleUndriveable(boat, false)
        SetVehicleEngineOn(boat, true, true, true)
        Utils.setVehicleFuelFull(boat)
        TaskBoatMission(driver, boat, 0, 0, seaExitPoint.x, seaExitPoint.y, seaExitPoint.z, 4, 26.0, 1074528293, 0.0, 0.0)
    end

    if DoesEntityExist(ambulance) and DoesEntityExist(ambulanceDriver) and ambulanceExitPoint then
        FreezeEntityPosition(ambulance, false)
        SetVehicleUndriveable(ambulance, false)
        SetVehicleEngineOn(ambulance, true, true, true)
        setAmbulanceRearDoorsOpen(ambulance, false)

        if DoesEntityExist(medic) and not IsPedInVehicle(medic, ambulance, false) then
            boardMedicInAmbulance(medic, ambulance, nil)
        end

        TaskVehicleDriveToCoord(ambulanceDriver, ambulance, ambulanceExitPoint.x, ambulanceExitPoint.y, ambulanceExitPoint.z, 22.0, 0, GetEntityModel(ambulance), 524863, 1.0, true)
    end
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
                Utils.setVehicleFuelFull(boat)
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

        local driverModelName = pickRescueDriverModelName()
        local driverModel = Utils.loadModel(driverModelName)
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
            local rearSeat = getAmbulanceRearSeat(ambulance)
            if rearSeat ~= nil then
                medic = track(CreatePedInsideVehicle(ambulance, 26, medicModel, rearSeat, true, false))
            end

            if not medic or not DoesEntityExist(medic) then
                medic = track(CreatePed(26, medicModel, ambulanceSpawn.x, ambulanceSpawn.y, ambulanceSpawn.z + 0.2, headingToSea, true, false))
            end

            if not DoesEntityExist(ambulance) or not DoesEntityExist(ambulanceDriver) or not DoesEntityExist(medic) then
                Framework.notify('Rescue unavailable (ambulance team failed to spawn).', 'critical')
                return
            end

            if not IsPedInVehicle(medic, ambulance, false) then
                placeMedicInRearSeat(medic, ambulance)
            end

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

        local pickedUp, boatPos = driveBoatForPickup(driver, boat, deathPos)

        if not pickedUp then
            local nearPos = boatPos or GetEntityCoords(boat)
            local nearDist = Vdist(nearPos.x, nearPos.y, nearPos.z, deathPos.x, deathPos.y, deathPos.z)
            local graceDistance = Utils.cfg('Navigation.boatPickupGraceDistance', 28.0)
            if nearDist <= graceDistance then
                Utils.debug(('Pickup grace fallback engaged at %.2fm'):format(nearDist))
                pickedUp = true
            end
        end

        if not pickedUp then
            Framework.notify('Rescue boat could not reach you in time.', 'critical')
            setState('FAILED')
            return
        end

        if IsPedDeadOrDying(ped, true) then
            NetworkResurrectLocalPlayer(deathPos.x, deathPos.y, deathPos.z, GetEntityHeading(ped), true, false)
            Wait(350)
        end

        local boardingMode = boardPlayerForWaterTransit(ped, boat)
        if not boardingMode then
            Framework.notify('Pickup failed: unable to secure patient on rescue craft.', 'critical')
            setState('FAILED')
            return
        end

        Wait(120)

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

        FreezeEntityPosition(ambulance, true)
        SetVehicleEngineOn(ambulance, false, true, true)

        TaskLeaveVehicle(medic, ambulance, 0)
        Wait(1200)
        setAmbulanceRearDoorsOpen(ambulance, true)

        local patientPos = GetEntityCoords(ped)
        SetPedKeepTask(medic, true)
        SetPedMoveRateOverride(medic, 10.0)
        SetPedMaxMoveBlendRatio(medic, 3.0)
        TaskGoToCoordAnyMeans(medic, patientPos.x, patientPos.y, patientPos.z, 6.0, 0, false, 786603, 0.0)

        local walkDeadline = GetGameTimer() + Utils.cfg('TimeoutsMs.walkToPatient', 12000)
        while GetGameTimer() < walkDeadline do
            local mPos = GetEntityCoords(medic)
            if Vdist(mPos.x, mPos.y, mPos.z, patientPos.x, patientPos.y, patientPos.z) <= 2.2 then
                break
            end
            Wait(250)
        end

        local loaded, patientSeat = carryPatientIntoAmbulance(medic, ped, ambulance)
        if not loaded then
            Framework.notify('Medical handoff failed: unable to load patient into ambulance.', 'critical')
            setState('FAILED')
            return
        end

        boardMedicInAmbulance(medic, ambulance, patientSeat)
        Wait(350)

        local patientChoice = choosePatientOutcomeInAmbulance()

        if patientChoice == 'revive' then
            setState('CPR')

            if not revivePatientInsideAmbulance(ped, ambulance, patientSeat) then
                Framework.notify('Medical handoff failed: unable to revive patient in ambulance.', 'critical')
                setState('FAILED')
                return
            end

            Wait(1000)
            releasePatientFromAmbulance(ped, ambulance)

            setState('REVIVED')
            Framework.notify('You were revived in the ambulance and released at the scene.', 'success', 'Seek treatment immediately')
        else
            releasePatientFromAmbulance(ped, ambulance)
            SetEntityHealth(ped, math.max(101, math.min(GetEntityMaxHealth(ped), 110)))
            Framework.notify('You were dropped off without ambulance revival. No rescue bill was charged.', 'medium', 'Seek medical help when ready')
        end

        local seaExitPoint = vector3(
            waterline.x + (dirSeaX * 140.0),
            waterline.y + (dirSeaY * 140.0),
            Utils.getWaterOrDefault(waterline.x + (dirSeaX * 140.0), waterline.y + (dirSeaY * 140.0), waterline.z) + 0.8
        )

        local ambulanceExitPoint = vector3(
            ambulanceSpawn.x + math.random(60, 95),
            ambulanceSpawn.y + math.random(60, 95),
            ambulanceSpawn.z
        )

        sendRescueUnitsAway(boat, driver, seaExitPoint, ambulance, ambulanceDriver, medic, ambulanceExitPoint)

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
