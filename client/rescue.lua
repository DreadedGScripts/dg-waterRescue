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
local BOAT_PATIENT_DEAD_ANIM_DICT = 'dead'
local BOAT_PATIENT_DEAD_ANIM_NAME = 'dead_a'

local function drawCprProgressHud(label, pct, cycleCount, cycleTarget, tint)
    local clampedPct = math.max(0.0, math.min(1.0, (tonumber(pct) or 0.0) / 100.0))
    local x = 0.5
    local y = 0.905
    local width = 0.28
    local height = 0.022
    local fillAlpha = 210

    DrawRect(x, y, width, height, 8, 14, 24, 195)
    DrawRect(x - ((width * (1.0 - clampedPct)) * 0.5), y, width * clampedPct, height - 0.005, tint.r, tint.g, tint.b, fillAlpha)

    SetTextFont(4)
    SetTextScale(0.33, 0.33)
    SetTextColour(220, 235, 255, 230)
    SetTextOutline()
    SetTextCentre(true)
    SetTextEntry('STRING')
    AddTextComponentString(('%s  %d%%  |  Compressions %d/%d'):format(label, math.floor(clampedPct * 100.0), cycleCount, cycleTarget))
    DrawText(0.5, y - 0.018)
end

local function buildCprNotifyOptions(cadence, durationMs)
    local stride = math.max(1, tonumber(cadence.pumpSoundStride) or 1)
    local pulseIntervalMs = cadence.msPerCompression * stride
    local pulseDurationMs = math.max(80, math.min(2000, tonumber(Utils.cfg('Medical.cprNotifyPulseDurationMs', 150)) or 150))
    local fadeInMs = math.max(80, math.min(4000, tonumber(Utils.cfg('Medical.cprNotifyFadeInMs', 180)) or 180))
    local fadeOutMs = math.max(80, math.min(4000, tonumber(Utils.cfg('Medical.cprNotifyFadeOutMs', 260)) or 260))
    local extraLifetimeMs = math.max(0, tonumber(Utils.cfg('Medical.cprNotifyExtraLifetimeMs', 600)) or 600)

    return {
        pulseEnabled = true,
        pulseIntervalMs = pulseIntervalMs,
        pulseDurationMs = pulseDurationMs,
        fadeInMs = fadeInMs,
        fadeOutMs = fadeOutMs,
        lifetimeMs = math.max(1000, math.floor((durationMs or 10000) + extraLifetimeMs)),
    }
end

local function playCprSound(soundName, soundSet)
    if not Utils.cfg('Medical.cprPumpSoundEnabled', true) then
        return
    end

    PlaySoundFrontend(-1, tostring(soundName), tostring(soundSet), true)
end

local function playCprPumpSound(cadence, compressionCount)
    if not Utils.cfg('Medical.cprPumpSoundEnabled', true) then
        return
    end

    local stride = math.max(1, tonumber(cadence.pumpSoundStride) or 1)
    if compressionCount % stride ~= 0 then
        return
    end

    local style = tostring(cadence.soundStyle or 'standard'):lower()
    local primary = cadence.pumpSoundName
    local secondary = cadence.pumpAltSoundName
    local setName = cadence.pumpSoundSet

    if style == 'heartbeat' and secondary and secondary ~= '' then
        local beatIndex = math.floor(compressionCount / stride)
        if beatIndex % 2 == 0 then
            playCprSound(secondary, setName)
            return
        end
    end

    playCprSound(primary, setName)
end

local function drawPatientChoiceHud(cost, defaultChoice, secondsLeft, timeoutRatio, holdAction, holdRatio)
    local x = 0.5
    local y = 0.86
    local panelW = 0.42
    local panelH = 0.12
    local reviveSelected = holdAction == 'revive'
    local dropSelected = holdAction == 'dropoff'

    DrawRect(x, y, panelW, panelH, 8, 14, 24, 195)
    DrawRect(x, y - 0.044, panelW - 0.01, 0.028, 18, 32, 54, 220)

    SetTextFont(4)
    SetTextScale(0.32, 0.32)
    SetTextColour(220, 235, 255, 230)
    SetTextOutline()
    SetTextCentre(true)
    SetTextEntry('STRING')
    AddTextComponentString(('Ambulance Decision | Auto: %s in %ss'):format(tostring(defaultChoice), tonumber(secondsLeft) or 0))
    DrawText(x, y - 0.052)

    local optionY = y - 0.01
    DrawRect(0.42, optionY, 0.16, 0.036, reviveSelected and 70 or 26, reviveSelected and 130 or 47, reviveSelected and 80 or 70, 210)
    DrawRect(0.58, optionY, 0.16, 0.036, dropSelected and 70 or 26, dropSelected and 130 or 47, dropSelected and 80 or 70, 210)

    SetTextScale(0.32, 0.32)
    SetTextEntry('STRING')
    AddTextComponentString(('Hold [E] Revive ($%s)'):format(tostring(cost)))
    DrawText(0.42, optionY - 0.008)

    SetTextEntry('STRING')
    AddTextComponentString('Hold [G] Drop Off ($0)')
    DrawText(0.58, optionY - 0.008)

    local timeoutW = panelW - 0.04
    local timeoutRatioClamped = math.max(0.0, math.min(1.0, tonumber(timeoutRatio) or 0.0))
    local timeoutX = x - ((timeoutW * (1.0 - timeoutRatioClamped)) * 0.5)
    DrawRect(x, y + 0.038, timeoutW, 0.013, 20, 30, 44, 220)
    DrawRect(timeoutX, y + 0.038, timeoutW * timeoutRatioClamped, 0.010, 96, 205, 255, 220)

    if holdAction then
        local holdRatioClamped = math.max(0.0, math.min(1.0, tonumber(holdRatio) or 0.0))
        local holdW = panelW - 0.10
        local holdX = x - ((holdW * (1.0 - holdRatioClamped)) * 0.5)
        DrawRect(x, y + 0.063, holdW, 0.012, 32, 22, 18, 220)
        DrawRect(holdX, y + 0.063, holdW * holdRatioClamped, 0.009, 255, 170, 120, 220)
    end
end

local function getCprCadenceConfig()
    local cpm = math.max(60, math.min(140, tonumber(Utils.cfg('Medical.cprCompressionsPerMinute', 110)) or 110))
    local cycleTarget = math.max(10, math.min(60, tonumber(Utils.cfg('Medical.cprCycleCompressions', 30)) or 30))
    local pumpSoundName = tostring(Utils.cfg('Medical.cprPumpSoundName', 'CHECKPOINT_NORMAL'))
    local pumpAltSoundName = tostring(Utils.cfg('Medical.cprPumpAltSoundName', ''))
    local pumpSoundSet = tostring(Utils.cfg('Medical.cprPumpSoundSet', 'HUD_MINI_GAME_SOUNDSET'))
    local pumpSoundStride = math.max(1, tonumber(Utils.cfg('Medical.cprPumpSoundStride', 1)) or 1)
    local soundStyle = tostring(Utils.cfg('Medical.cprSoundStyle', 'standard'))
    local cycleSoundName = tostring(Utils.cfg('Medical.cprCycleSoundName', 'CHECKPOINT_PERFECT'))
    local cycleSoundSet = tostring(Utils.cfg('Medical.cprCycleSoundSet', 'HUD_MINI_GAME_SOUNDSET'))

    return {
        msPerCompression = math.floor(60000 / cpm),
        cycleTarget = cycleTarget,
        pumpSoundName = pumpSoundName,
        pumpAltSoundName = pumpAltSoundName,
        pumpSoundSet = pumpSoundSet,
        pumpSoundStride = pumpSoundStride,
        soundStyle = soundStyle,
        cycleSoundName = cycleSoundName,
        cycleSoundSet = cycleSoundSet,
    }
end

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
    local pickupDistance = Utils.cfg('Navigation.boatPickupDistance', 14.0)
    local forcePickupDistance = Utils.cfg('Navigation.boatPickupGraceDistance', 28.0)
    local deepWaterPickupDistance = forcePickupDistance + 18.0
    local victimWaterZ = Utils.getWaterOrDefault(deathPos.x, deathPos.y, deathPos.z)
    local victimDepth = victimWaterZ - deathPos.z
    local isDeepUnderwater = victimDepth >= 6.0
    local approachThreshold = isDeepUnderwater and deepWaterPickupDistance or pickupDistance
    local approachTarget = vector3(deathPos.x, deathPos.y, victimWaterZ + 0.7)

    local reached, finalPos = Utils.driveBoatToPoint(
        driver,
        boat,
        approachTarget,
        Utils.cfg('Navigation.boatPickupSpeed', 34.0),
        timeoutMs,
        approachThreshold
    )

    if reached then
        return true, finalPos
    end

    local boatPos = finalPos or GetEntityCoords(boat)
    local dx = boatPos.x - deathPos.x
    local dy = boatPos.y - deathPos.y
    local finalHorizontalDist = math.sqrt((dx * dx) + (dy * dy))

    if finalHorizontalDist <= forcePickupDistance then
        return true, boatPos
    end

    if isDeepUnderwater and finalHorizontalDist <= (deepWaterPickupDistance + 8.0) then
        Utils.debug(('Deep-water pickup fallback engaged at %.2fm horizontal distance'):format(finalHorizontalDist))
        return true, boatPos
    end

    return false, boatPos
end

local function forcePedOutOfVehicle(ped, vehicle, timeoutMs)
    if not DoesEntityExist(vehicle) then
        return true
    end

    if not IsPedInVehicle(ped, vehicle, false) then
        return true
    end

    TaskLeaveVehicle(ped, vehicle, 16)
    local deadline = GetGameTimer() + (timeoutMs or 2200)

    while GetGameTimer() < deadline do
        if not IsPedInVehicle(ped, vehicle, false) then
            return true
        end
        Wait(100)
    end

    -- Retry leave once more without any coordinate teleport fallback.
    ClearPedTasksImmediately(ped)
    TaskLeaveVehicle(ped, vehicle, 16)
    Wait(250)

    return not IsPedInVehicle(ped, vehicle, false)
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

    -- Fallback: force detach by repositioning when task-based leave does not complete.
    if IsPedInVehicle(ped, boat, false) then
        forcePedOutOfVehicle(ped, boat, 900)
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
            forcePedOutOfVehicle(ped, vehicle, 900)
            Wait(100)
        end
    end

    ClearPedTasksImmediately(ped)

    local target = Utils.parseCoords(handoffPoint, GetEntityCoords(ped))
    local groundZ = Utils.getGroundOrDefault(target.x, target.y, target.z)
    SetEntityCoords(ped, target.x, target.y, groundZ + 0.15, false, false, false, true)
end

local function getBoatPatientAttachBone(boat)
    local configured = Utils.cfg('Navigation.boatPatientAttachBone', nil)
    if type(configured) == 'string' and configured ~= '' then
        local configuredIndex = GetEntityBoneIndexByName(boat, configured)
        if configuredIndex and configuredIndex ~= -1 then
            return configuredIndex
        end
    end

    local candidateBones = {
        'seat_pside_r',
        'seat_dside_r',
        'seat_pside_f',
        'seat_dside_f',
        'chassis',
        'bodyshell'
    }

    for _, boneName in ipairs(candidateBones) do
        local index = GetEntityBoneIndexByName(boat, boneName)
        if index and index ~= -1 then
            return index
        end
    end

    return 0
end

local function boardPlayerForWaterTransit(ped, boat)
    if not DoesEntityExist(boat) then
        return nil
    end

    -- Preserve current animation/death state while attaching for transit.
    ClearPedSecondaryTask(ped)

    if IsPedInAnyVehicle(ped, false) then
        local currentVehicle = GetVehiclePedIsIn(ped, false)
        if currentVehicle and currentVehicle ~= 0 then
            forcePedOutOfVehicle(ped, currentVehicle, 900)
            Wait(100)
        end
    end

    -- Attach patient to a stable boat bone instead of seating in a vehicle seat.
    local attachBone = getBoatPatientAttachBone(boat)
    local offX = Utils.cfg('Navigation.boatPatientAttachOffset.x', 0.18)
    local offY = Utils.cfg('Navigation.boatPatientAttachOffset.y', -1.05)
    local offZ = Utils.cfg('Navigation.boatPatientAttachOffset.z', 0.35)
    local rotX = Utils.cfg('Navigation.boatPatientAttachRotation.x', 0.0)
    local rotY = Utils.cfg('Navigation.boatPatientAttachRotation.y', 0.0)
    local rotZ = Utils.cfg('Navigation.boatPatientAttachRotation.z', 90.0)

    SetEntityCollision(ped, false, false)
    AttachEntityToEntity(ped, boat, attachBone, offX, offY, offZ, rotX, rotY, rotZ, false, false, false, true, 2, true)
    Wait(100)

    if IsEntityAttachedToEntity(ped, boat) then
        return 'attached'
    end

    SetEntityCollision(ped, true, true)
    return nil
end

local function startBoatAttachedDeathPose(ped, boat)
    local running = true

    CreateThread(function()
        while running and rescueActive and DoesEntityExist(ped) and DoesEntityExist(boat) do
            if not IsEntityAttachedToEntity(ped, boat) then
                break
            end

            if Utils.loadAnimDict(BOAT_PATIENT_DEAD_ANIM_DICT)
                and not IsEntityPlayingAnim(ped, BOAT_PATIENT_DEAD_ANIM_DICT, BOAT_PATIENT_DEAD_ANIM_NAME, 3) then
                TaskPlayAnim(ped, BOAT_PATIENT_DEAD_ANIM_DICT, BOAT_PATIENT_DEAD_ANIM_NAME, 8.0, -8.0, -1, 33, 0.0, false, false, false)
            end

            Wait(450)
        end
    end)

    return function()
        running = false
    end
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
    for _, seat in ipairs({ 1, 2 }) do
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

local function getOppositeRearSeat(seat)
    if seat == 1 then
        return 2
    end
    if seat == 2 then
        return 1
    end
    return nil
end

local function boardMedicInAmbulance(medic, ambulance, reservedSeat)
    local preferredOpposite = getOppositeRearSeat(reservedSeat)
    if preferredOpposite and IsVehicleSeatFree(ambulance, preferredOpposite) then
        TaskWarpPedIntoVehicle(medic, ambulance, preferredOpposite)
        if IsPedInVehicle(medic, ambulance, false) then
            return true
        end
    end

    for _, seat in ipairs({ 2, 1 }) do
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

local function medicExtractPatientFromBoat(medic, ped, boat, dropPoint)
    if not DoesEntityExist(medic) or not DoesEntityExist(ped) then
        return false
    end

    local patientPos = GetEntityCoords(ped)
    SetPedKeepTask(medic, true)
    SetPedMoveRateOverride(medic, 10.0)
    SetPedMaxMoveBlendRatio(medic, 3.0)
    TaskGoToCoordAnyMeans(medic, patientPos.x, patientPos.y, patientPos.z, 5.0, 0, false, 786603, 0.0)

    local approachDeadline = GetGameTimer() + Utils.cfg('TimeoutsMs.walkToPatient', 12000)
    while GetGameTimer() < approachDeadline do
        local mPos = GetEntityCoords(medic)
        patientPos = GetEntityCoords(ped)
        if Vdist(mPos.x, mPos.y, mPos.z, patientPos.x, patientPos.y, patientPos.z) <= 2.2 then
            break
        end
        Wait(150)
    end

    prepPatientForCarry(ped)
    if DoesEntityExist(boat) and IsEntityAttachedToEntity(ped, boat) then
        DetachEntity(ped, true, true)
        SetEntityCollision(ped, true, true)
    end

    startShoulderCarry(medic, ped)
    local drop = Utils.parseCoords(dropPoint, GetEntityCoords(ped))
    TaskGoToCoordAnyMeans(medic, drop.x, drop.y, drop.z, 4.8, 0, false, 786603, 0.0)

    local carryDeadline = GetGameTimer() + Utils.cfg('TimeoutsMs.walkToPatient', 12000)
    while GetGameTimer() < carryDeadline do
        local mPos = GetEntityCoords(medic)
        if Vdist(mPos.x, mPos.y, mPos.z, drop.x, drop.y, drop.z) <= 1.8 then
            break
        end

        if not IsEntityAttachedToEntity(ped, medic) then
            startShoulderCarry(medic, ped, false)
        end
        ensureShoulderCarryAnimation(medic, ped)
        Wait(150)
    end

    stopShoulderCarry(medic, ped)

    local groundZ = Utils.getGroundOrDefault(drop.x, drop.y, drop.z)
    SetEntityCoords(ped, drop.x, drop.y, groundZ + 0.1, false, false, false, true)
    return true
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

    if IsPedInAnyVehicle(ped, false) then
        setAmbulanceRearDoorsOpen(ambulance, true)
        local preferredSeat = nil
        for _, seat in ipairs({ 1, 2 }) do
            if GetPedInVehicleSeat(ambulance, seat) == ped then
                preferredSeat = seat
                break
            end
        end

        if not preferredSeat then
            for _, seat in ipairs({ 1, 2 }) do
                if IsVehicleSeatFree(ambulance, seat) then
                    TaskWarpPedIntoVehicle(ped, ambulance, seat)
                    Wait(120)
                    break
                end
            end
        end

        TaskLeaveVehicle(ped, ambulance, 0)

        local deadline = GetGameTimer() + 6000
        while GetGameTimer() < deadline and IsPedInVehicle(ped, ambulance, false) do
            Wait(120)
        end

        if IsPedInVehicle(ped, ambulance, false) then
            -- Retry graceful exit without forced ejection to avoid teleport-like behavior.
            TaskLeaveVehicle(ped, ambulance, 16)
            Wait(900)
        end
    end

    if IsPedInVehicle(ped, ambulance, false) then
        return false
    end

    ClearPedSecondaryTask(ped)
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
    local holdToConfirmMs = math.max(250, tonumber(Utils.cfg('PatientChoice.holdToConfirmMs', 800)) or 800)
    local reviveControl = Utils.cfg('PatientChoice.reviveControl', 38)
    local dropoffControl = Utils.cfg('PatientChoice.dropoffControl', 47)
    local deadline = GetGameTimer() + (timeoutSeconds * 1000)
    local nextNotifyAt = 0
    local holdAction = nil
    local holdStartAt = 0

    while GetGameTimer() < deadline do
        local now = GetGameTimer()
        local secondsLeft = math.max(1, math.ceil((deadline - GetGameTimer()) / 1000))
        local timeoutRatio = (deadline - now) / (timeoutSeconds * 1000)
        local holdRatio = 0.0

        if holdAction == 'revive' then
            if IsControlPressed(0, reviveControl) then
                holdRatio = (now - holdStartAt) / holdToConfirmMs
                if holdRatio >= 1.0 then
                    return 'revive'
                end
            else
                holdAction = nil
                holdStartAt = 0
            end
        elseif holdAction == 'dropoff' then
            if IsControlPressed(0, dropoffControl) then
                holdRatio = (now - holdStartAt) / holdToConfirmMs
                if holdRatio >= 1.0 then
                    return 'dropoff'
                end
            else
                holdAction = nil
                holdStartAt = 0
            end
        end

        if holdAction == nil then
            if IsControlJustPressed(0, reviveControl) then
                holdAction = 'revive'
                holdStartAt = now
            elseif IsControlJustPressed(0, dropoffControl) then
                holdAction = 'dropoff'
                holdStartAt = now
            end
        end

        drawPatientChoiceHud(Utils.cfg('Billing.amount', 850), defaultChoice, secondsLeft, timeoutRatio, holdAction, holdRatio)

        if GetGameTimer() >= nextNotifyAt then
            Framework.notify(
                ('Ambulance choice: hold E to revive ($%s) or hold G to dropoff.'):format(tostring(Utils.cfg('Billing.amount', 850))),
                'medium',
                ('Auto: %s in %ss'):format(tostring(defaultChoice), secondsLeft),
                'ambulance'
            )
            nextNotifyAt = GetGameTimer() + 3000
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
    for _, seat in ipairs({ 1, 2 }) do
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

    if IsPedInAnyVehicle(medic, false) then
        local veh = GetVehiclePedIsIn(medic, false)
        if veh and veh ~= 0 then
            TaskLeaveVehicle(medic, veh, 16)
            Wait(450)
        end
    end

    if IsPedInAnyVehicle(ped, false) then
        local veh = GetVehiclePedIsIn(ped, false)
        if veh and veh ~= 0 then
            forcePedOutOfVehicle(ped, veh, 1000)
            Wait(150)
        end
    end

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
    local duration = durationMs or 10000
    local playedAnim = false
    local cadence = getCprCadenceConfig()
    local nextPumpAt = GetGameTimer()
    local cycleCount = 0
    local compressionCount = 0

    if IsPedInAnyVehicle(ped, false) then
        local veh = GetVehiclePedIsIn(ped, false)
        if veh and veh ~= 0 then
            TaskLeaveVehicle(ped, veh, 16)
            Wait(300)
            if IsPedInAnyVehicle(ped, false) then
                forcePedOutOfVehicle(ped, veh, 1000)
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
        TaskPlayAnim(medic, medicDict, 'cpr_pumpchest', 8.0, -8.0, -1, 1, 0, false, false, false)
        TaskPlayAnim(ped, patientDict, 'cpr_pumpchest', 8.0, -8.0, -1, 1, 0, false, false, false)
        playedAnim = true
    end

    if not playedAnim then
        ClearPedTasksImmediately(medic)
        TaskStartScenarioInPlace(medic, 'CODE_HUMAN_MEDIC_KNEEL', 0, true)
        ClearPedTasksImmediately(ped)
        TaskStartScenarioInPlace(ped, 'WORLD_HUMAN_SUNBATHE_BACK', 0, true)
    end

    Framework.notify(
        'CPR in progress...',
        'medium',
        ('Follow pulse beats | Target %d compressions per cycle'):format(cadence.cycleTarget),
        'waterrescue',
        buildCprNotifyOptions(cadence, duration)
    )

    local endAt = GetGameTimer() + duration
    while GetGameTimer() < endAt do
        local now = GetGameTimer()
        local remainingMs = endAt - GetGameTimer()
        local elapsed = math.max(0, duration - remainingMs)
        local pct = (elapsed / duration) * 100

        if now >= nextPumpAt then
            compressionCount = compressionCount + 1
            cycleCount = cycleCount + 1
            playCprPumpSound(cadence, compressionCount)

            if cycleCount >= cadence.cycleTarget then
                playCprSound(cadence.cycleSoundName, cadence.cycleSoundSet)
                cycleCount = 0
            end

            nextPumpAt = now + cadence.msPerCompression
        end

        drawCprProgressHud('CPR IN PROGRESS', pct, cycleCount, cadence.cycleTarget, { r = 96, g = 205, b = 255 })

        if playedAnim then
            if not IsEntityPlayingAnim(medic, medicDict, 'cpr_pumpchest', 3) then
                TaskPlayAnim(medic, medicDict, 'cpr_pumpchest', 8.0, -8.0, -1, 1, 0, false, false, false)
            end
            if not IsEntityPlayingAnim(ped, patientDict, 'cpr_pumpchest', 3) then
                TaskPlayAnim(ped, patientDict, 'cpr_pumpchest', 8.0, -8.0, -1, 1, 0, false, false, false)
            end
        end

        Wait(0)
    end

    FreezeEntityPosition(medic, false)
    FreezeEntityPosition(ped, false)
    ClearPedTasks(medic)
    ClearPedTasks(ped)
end

local function playCprSequenceInAmbulance(medic, ped, ambulance, patientSeat, durationMs)
    local duration = durationMs or 10000
    local medicSeat = getOppositeRearSeat(patientSeat) or getAmbulanceRearSeat(ambulance)
    local cadence = getCprCadenceConfig()
    local nextPumpAt = GetGameTimer()
    local cycleCount = 0
    local compressionCount = 0

    if not IsPedInVehicle(ped, ambulance, false) then
        TaskWarpPedIntoVehicle(ped, ambulance, patientSeat or 1)
        Wait(120)
    end

    if medicSeat and (not IsPedInVehicle(medic, ambulance, false) or GetPedInVehicleSeat(ambulance, medicSeat) ~= medic) then
        TaskWarpPedIntoVehicle(medic, ambulance, medicSeat)
        Wait(120)
    end

    setAmbulanceRearDoorsOpen(ambulance, true)

    local medicDict = 'mini@cpr@char_a@cpr_def'
    local patientDict = 'mini@cpr@char_b@cpr_def'
    local hasAnim = Utils.loadAnimDict(medicDict) and Utils.loadAnimDict(patientDict)

    Framework.notify(
        'Paramedic performing CPR in ambulance...',
        'medium',
        ('Follow pulse beats | Target %d compressions per cycle'):format(cadence.cycleTarget),
        'ambulance',
        buildCprNotifyOptions(cadence, duration)
    )

    local endAt = GetGameTimer() + duration

    while GetGameTimer() < endAt do
        local now = GetGameTimer()
        local remainingMs = endAt - GetGameTimer()
        local elapsed = math.max(0, duration - remainingMs)
        local pct = (elapsed / duration) * 100

        if now >= nextPumpAt then
            compressionCount = compressionCount + 1
            cycleCount = cycleCount + 1
            playCprPumpSound(cadence, compressionCount)

            if cycleCount >= cadence.cycleTarget then
                playCprSound(cadence.cycleSoundName, cadence.cycleSoundSet)
                cycleCount = 0
            end

            nextPumpAt = now + cadence.msPerCompression
        end

        drawCprProgressHud('AMBULANCE CPR', pct, cycleCount, cadence.cycleTarget, { r = 255, g = 138, b = 102 })

        if hasAnim then
            if IsPedInVehicle(medic, ambulance, false) and not IsEntityPlayingAnim(medic, medicDict, 'cpr_pumpchest', 3) then
                TaskPlayAnim(medic, medicDict, 'cpr_pumpchest', 4.0, -4.0, 1200, 49, 0, false, false, false)
            end
            if IsPedInVehicle(ped, ambulance, false) and not IsEntityPlayingAnim(ped, patientDict, 'cpr_pumpchest', 3) then
                TaskPlayAnim(ped, patientDict, 'cpr_pumpchest', 4.0, -4.0, 1200, 49, 0, false, false, false)
            end
        end

        Wait(0)
    end
end

local function setState(nextState)
    state = nextState
    Utils.debug(('STATE => %s'):format(nextState))
    Framework.requestBillingAndCooldown(nextState)
end

local function spawnRescueBoatNear(targetPos, heading, spawnDistanceOverride)
    local model = Utils.loadModel(Utils.cfg('Models.boat', 'dinghy'))
    if not model then return nil end

    local attempts = Utils.cfg('Search.rescueBoatSpawnAttempts', 14)
    local dist = tonumber(spawnDistanceOverride) or Utils.cfg('Search.rescueBoatSpawnDistance', 90.0)

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

local function isDryGroundPoint(x, y, z)
    local foundGround, groundZ = GetGroundZFor_3dCoord(x, y, z + 60.0, 0)
    if not foundGround then
        return false, z
    end

    local isWater, waterZ = GetWaterHeight(x, y, groundZ + 1.0, 0.0)
    if isWater and waterZ and groundZ <= (waterZ + 0.35) then
        return false, groundZ
    end

    return true, groundZ
end

local function findSafeAmbulanceSpawn(basePoint, dirSeaX, dirSeaY, perpX, perpY)
    local mainInland = Utils.cfg('Search.ambulanceInlandDistance', 28.0)
    local mainSide = Utils.cfg('Search.ambulanceSideOffset', 4.0)
    local fallbackStep = Utils.cfg('Search.ambulanceSpawnStep', 8.0)
    local fallbackAttempts = Utils.cfg('Search.ambulanceSpawnAttempts', 8)

    local function candidate(inland, side)
        return vector3(
            basePoint.x - (dirSeaX * inland) + (perpX * side),
            basePoint.y - (dirSeaY * inland) + (perpY * side),
            basePoint.z
        )
    end

    local first = candidate(mainInland, mainSide)
    local okFirst, firstGround = isDryGroundPoint(first.x, first.y, first.z)
    if okFirst then
        return vector3(first.x, first.y, firstGround)
    end

    for i = 1, fallbackAttempts do
        local ring = fallbackStep * i
        for _, side in ipairs({ mainSide + ring, mainSide - ring, -(mainSide + ring), -(mainSide - ring) }) do
            local inland = mainInland + (math.floor((i - 1) / 2) * fallbackStep)
            local c = candidate(inland, side)
            local okGround, gz = isDryGroundPoint(c.x, c.y, c.z)
            if okGround then
                return vector3(c.x, c.y, gz)
            end
        end
    end

    return vector3(first.x, first.y, firstGround)
end

local function drawWorldRescueText(x, y, z, message)
    local onScreen, screenX, screenY = World3dToScreen2d(x, y, z)
    if not onScreen then
        return
    end

    SetTextScale(0.34, 0.34)
    SetTextFont(4)
    SetTextProportional(1)
    SetTextColour(105, 210, 255, 220)
    SetTextEntry('STRING')
    SetTextCentre(true)
    AddTextComponentString(message)
    DrawText(screenX, screenY)
end

local function startRescueBoatIndicator(boat)
    if not DoesEntityExist(boat) then
        return nil
    end

    local blip = AddBlipForEntity(boat)
    SetBlipSprite(blip, Utils.cfg('Navigation.rescueBoatBlipSprite', 410))
    SetBlipColour(blip, Utils.cfg('Navigation.rescueBoatBlipColor', 3))
    SetBlipScale(blip, Utils.cfg('Navigation.rescueBoatBlipScale', 0.95))
    SetBlipAsShortRange(blip, false)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString('Water Rescue Boat')
    EndTextCommandSetBlipName(blip)

    local running = true

    CreateThread(function()
        while running and rescueActive and DoesEntityExist(boat) do
            local ped = PlayerPedId()
            local boatPos = GetEntityCoords(boat)
            local pedPos = GetEntityCoords(ped)
            local distance = Vdist(pedPos.x, pedPos.y, pedPos.z, boatPos.x, boatPos.y, boatPos.z)
            local drawDistance = Utils.cfg('Navigation.rescueBoatMarkerDistance', 190.0)
            local textHeight = Utils.cfg('Navigation.rescueBoatMarkerHeight', 2.1)

            if distance <= drawDistance and state == 'PICKUP' then
                DrawMarker(
                    1,
                    boatPos.x,
                    boatPos.y,
                    boatPos.z + 1.2,
                    0.0,
                    0.0,
                    0.0,
                    0.0,
                    0.0,
                    0.0,
                    1.2,
                    1.2,
                    0.35,
                    80,
                    200,
                    255,
                    170,
                    false,
                    true,
                    2,
                    nil,
                    nil,
                    false
                )
                drawWorldRescueText(boatPos.x, boatPos.y, boatPos.z + textHeight, 'Rescue Boat')
            end

            Wait(0)
        end

        if blip and DoesBlipExist(blip) then
            RemoveBlip(blip)
        end
    end)

    return function()
        running = false
    end
end

local function waitForRescueBoatApproachVisual(ped, boat, deathPos)
    local deadline = GetGameTimer() + Utils.cfg('TimeoutsMs.boatVisualWaitMax', 12000)
    local minDelayAt = GetGameTimer() + Utils.cfg('TimeoutsMs.boatPickupMinVisualDelay', 3500)
    local proximityMsRequired = Utils.cfg('TimeoutsMs.boatPickupVisibleProximityMs', 1200)
    local proximityDistance = Utils.cfg('Navigation.boatPickupVisibleDistance', 38.0)
    local proximityHeldMs = 0
    local tickMs = 120
    local hornPlayed = false

    while GetGameTimer() < deadline do
        if not DoesEntityExist(boat) then
            return
        end

        local boatPos = GetEntityCoords(boat)
        local dist = Vdist(boatPos.x, boatPos.y, boatPos.z, deathPos.x, deathPos.y, deathPos.z)

        if dist <= proximityDistance then
            proximityHeldMs = proximityHeldMs + tickMs
            if not hornPlayed then
                StartVehicleHorn(boat, 700, GetHashKey('NORMAL'), false)
                hornPlayed = true
            end
        else
            proximityHeldMs = 0
        end

        if GetGameTimer() >= minDelayAt and proximityHeldMs >= proximityMsRequired then
            return
        end

        Wait(tickMs)
    end
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
    local stopBoatAttachedPose = nil
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

        local ambulanceSpawn = findSafeAmbulanceSpawn(shore, dirSeaX, dirSeaY, perpX, perpY)

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

        local boat = nil
        local driver = nil
        local stopBoatIndicator = nil
        local boardingMode = nil
        local freeRetries = math.max(0, tonumber(Utils.cfg('Retry.freePickupRetries', 1)) or 1)
        local maxPickupAttempts = 1 + freeRetries

        for attempt = 1, maxPickupAttempts do
            local retrySpawnDistance = Utils.cfg('Search.rescueBoatRetrySpawnDistance', 48.0)
            local spawnDistance = (attempt == 1) and Utils.cfg('Search.rescueBoatSpawnDistance', 90.0) or retrySpawnDistance
            boat = track(spawnRescueBoatNear(deathPos, headingToSea, spawnDistance))
            if not boat then
                if attempt < maxPickupAttempts then
                    Framework.notify(('Rescue pickup failed to deploy. Retrying (%d/%d) at no extra cost...'):format(attempt, freeRetries), 'medium')
                    Wait(350)
                else
                    Framework.notify('Rescue failed to find safe boat spawn.', 'critical')
                    setState('FAILED')
                    return
                end
            else
                stopBoatIndicator = startRescueBoatIndicator(boat)

                driver = track(CreatePedInsideVehicle(boat, 26, driverModel, -1, true, false))
                if not DoesEntityExist(driver) then
                    if stopBoatIndicator then stopBoatIndicator() end

                    if attempt < maxPickupAttempts then
                        Framework.notify(('Rescue pickup failed to deploy driver. Retrying (%d/%d) at no extra cost...'):format(attempt, freeRetries), 'medium')
                        if DoesEntityExist(boat) then
                            DeleteEntity(boat)
                        end
                        Wait(350)
                    else
                        Framework.notify('Rescue failed to deploy lifeguard driver.', 'critical')
                        setState('FAILED')
                        return
                    end
                else
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

                    if pickedUp then
                        waitForRescueBoatApproachVisual(ped, boat, deathPos)
                        boardingMode = boardPlayerForWaterTransit(ped, boat)
                        if boardingMode then
                            if boardingMode == 'attached' then
                                stopBoatAttachedPose = startBoatAttachedDeathPose(ped, boat)
                            end
                            break
                        end
                    end

                    if stopBoatIndicator then stopBoatIndicator() end

                    if DoesEntityExist(driver) then
                        DeleteEntity(driver)
                    end
                    if DoesEntityExist(boat) then
                        DeleteEntity(boat)
                    end

                    if attempt < maxPickupAttempts then
                        Framework.notify(('Rescue pickup attempt failed. Retrying (%d/%d) at no extra cost...'):format(attempt, freeRetries), 'medium')
                        Wait(350)
                    else
                        Framework.notify('Rescue boat could not secure pickup in time.', 'critical')
                        setState('FAILED')
                        return
                    end
                end
            end
        end

        if stopBoatIndicator then stopBoatIndicator() end

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
        if stopBoatIndicator then stopBoatIndicator() end

        setState('BEACH_HANDOFF')

        local handoffPoint = vector3(
            finalBoatPos.x + (perpX * 2.6) - (dirSeaX * 1.1),
            finalBoatPos.y + (perpY * 2.6) - (dirSeaY * 1.1),
            Utils.getGroundOrDefault(finalBoatPos.x + (perpX * 2.6) - (dirSeaX * 1.1), finalBoatPos.y + (perpY * 2.6) - (dirSeaY * 1.1), finalBoatPos.z)
        )

        if not useAiAmbulance then
            if stopBoatAttachedPose then
                stopBoatAttachedPose()
                stopBoatAttachedPose = nil
            end
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

        if stopBoatAttachedPose then
            stopBoatAttachedPose()
            stopBoatAttachedPose = nil
        end

        local extractedFromBoat = medicExtractPatientFromBoat(medic, ped, boat, handoffPoint)
        if not extractedFromBoat then
            -- Safety fallback in case pathing/carry fails.
            placePlayerAtHandoffPoint(ped, boat, handoffPoint)
        end

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
            Framework.notify('Medical handoff failed: unable to load patient into ambulance.', 'critical', nil, 'ambulance')
            setState('FAILED')
            return
        end

        boardMedicInAmbulance(medic, ambulance, patientSeat)
        Wait(350)

        local patientChoice = choosePatientOutcomeInAmbulance()

        if patientChoice == 'revive' then
            setState('CPR')

            playCprSequenceInAmbulance(medic, ped, ambulance, patientSeat, Utils.cfg('Medical.cprDurationMs', 10000))

            TriggerServerEvent('dg-waterRescue:server:preparePatientRevive')
            Wait(250)
            Framework.reviveWithFallback(ped)

            if IsPedDeadOrDying(ped, true) then
                Framework.notify('Medical handoff failed: unable to revive patient in ambulance.', 'critical', nil, 'ambulance')
                setState('FAILED')
                return
            end

            -- Eject player from ambulance and place at rear doors
            if IsPedInVehicle(ped, ambulance, false) then
                TaskLeaveVehicle(ped, ambulance, 0)
                local rearPos, _ = getAmbulanceRearPositions(ambulance)
                Wait(800)
                -- Place at rear doors, slightly behind
                SetEntityCoords(ped, rearPos.x, rearPos.y, rearPos.z, false, false, false, true)
                SetEntityHeading(ped, GetEntityHeading(ambulance))
            end

            setState('REVIVED')
            Framework.notify('CPR complete. You were revived at the ambulance rear.', 'success', 'Seek treatment immediately', 'ambulance')
        else
            releasePatientFromAmbulance(ped, ambulance)
            SetEntityHealth(ped, math.max(101, math.min(GetEntityMaxHealth(ped), 110)))
            Framework.notify('You were dropped off without ambulance revival. No rescue bill was charged.', 'medium', 'Seek medical help when ready', 'ambulance')
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

    if stopBoatAttachedPose then
        stopBoatAttachedPose()
        stopBoatAttachedPose = nil
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
