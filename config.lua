Config = {}

Config.Debug = false

Config.Trigger = {
	onlyDeadInWater = true,
	allowManualEvent = true,
	rescueMode = 'command', -- 'auto' or 'command'. If 'command', player must use /waterrescue to trigger rescue. If 'auto', rescue triggers automatically.
}

Config.Models = {
	boat = 'seashark2',
	rescueDrivers = {
		's_f_y_baywatch_01',
		's_m_y_baywatch_01',
	},
	rescueDriver = 's_m_y_baywatch_01',
	paramedic = 's_m_m_paramedic_01',
	ambulance = 'ambulance',
	lifeguardHut = 'prop_lifeguard_tower_01',
}

Config.Search = {
	rescueBoatSpawnDistance = 90.0,
	rescueBoatRetrySpawnDistance = 48.0,
	rescueBoatSpawnAttempts = 14,
	shoreSearchRadius = 2600.0,
	shoreSearchStep = 55.0,
	shoreSearchAngleStep = 10,
	shoreProbeForward = 10.0,
	maxShoreHeightAboveWater = 3.2,
	beachApproachDistance = 16.0,
	boatBeachInlandOffset = 3.0,
	beachInlandDistance = 10.0,
	patientDropInlandOffset = 4.0,
	ambulanceInlandDistance = 28.0,
	ambulanceSideOffset = 4.0,
	ambulanceSpawnStep = 8.0,
	ambulanceSpawnAttempts = 8,
}

Config.Navigation = {
	boatPickupDistance = 14.0,
	boatPickupGraceDistance = 28.0,
	boatPickupVisibleDistance = 38.0,
	boatPickupPassThroughDistance = 20.0,
	boatPickupSpeed = 20.0,
	boatShoreSpeed = 50.0,
	boatBeachSpeed = 60.0,
	boatShoreApproachThreshold = 10.0,
	boatBeachStopDistance = 1.0,
	rescueBoatMarkerDistance = 190.0,
	rescueBoatMarkerHeight = 2.1,
	rescueBoatBlipSprite = 410,
	rescueBoatBlipColor = 3,
	rescueBoatBlipScale = 0.95,
	boatPatientAttachOffset = {
		x = 0.18,
		y = -1.05,
		z = 0.35,
	},
	boatPatientAttachRotation = {
		x = 0.0,
		y = 0.0,
		z = 90.0,
	},
	ambulanceResponseSpeed = 24.0,
}

Config.TimeoutsMs = {
	boatPickup = 45000,
	boatPickupMinVisualDelay = 1000,
	boatPickupVisibleProximityMs = 1200,
	boatVisualWaitMax = 12000,
	boatToShore = 42000,
	boatBeach = 22000,
	ambulanceArrival = 20000,
	walkToPatient = 12000,
	postReviveCleanup = 10000,
}

Config.Retry = {
	freePickupRetries = 1,
}

Config.Medical = {
	cprDurationMs = 10000,
	partialReviveHealth = 130,
	cprCompressionsPerMinute = 110,
	cprCycleCompressions = 30,
	cprPumpSoundEnabled = true,
	cprSoundStyle = 'heartbeat',
	cprPumpSoundName = 'NAV_UP_DOWN',
	cprPumpAltSoundName = 'SELECT',
	cprPumpSoundSet = 'HUD_FRONTEND_DEFAULT_SOUNDSET',
	cprPumpSoundStride = 2,
	cprCycleSoundName = 'TIMER_STOP',
	cprCycleSoundSet = 'HUD_MINI_GAME_SOUNDSET',
	cprNotifyPulseDurationMs = 150,
	cprNotifyFadeInMs = 180,
	cprNotifyFadeOutMs = 260,
	cprNotifyExtraLifetimeMs = 600,
}

Config.PatientChoice = {
	enabled = true,
	timeoutSeconds = 12,
	holdToConfirmMs = 800,
	defaultChoice = 'dropoff',
	reviveControl = 38,
	dropoffControl = 47,
}

Config.Realism = {
	preferSandZones = true,
	beachZoneNames = {
		['DELBE'] = true,
		['VCANA'] = true,
		['CHIL'] = true,
		['PAC'] = true,
	},
	avoidObjectModels = {
		'prop_rock_4_big2',
		'prop_rock_4_cl_2',
		'prop_yacht_01',
		'prop_yacht_02',
		'prop_pier_01',
		'prop_pier_02',
		'prop_beach_fire',
	},
	hazardScanRadius = 2.0,
	largeHazardScanRadius = 90.0,
	blockedShoreAreas = {
		-- Main map yacht area (strictly excluded for rescue shoreline picks).
		{ x = -2028.0, y = -1035.0, z = 0.0, radius = 230.0 },
	},
}

Config.Billing = {
	enabled = true,
	moneyType = 'bank',
	amount = 850,
	requirePaymentToRevive = true,
}

Config.Cooldown = {
	enabled = true,
	seconds = 240,
}

Config.Dispatch = {
	preferRealEMS = true,
	qbEmsJobName = 'ambulance',
	requireOnDuty = true,
	alertBlip = {
		enabled = true,
		sprite = 153,
		color = 1,
		scale = 1.0,
		route = true,
		durationSeconds = 180,
		label = 'Lifeguard Alert: Water Rescue Call'
	}
}
