Config = {}

Config.Debug = false

Config.Trigger = {
	onlyDeadInWater = true,
	allowManualEvent = true,
}

Config.Models = {
	boat = 'dinghy',
	rescueDriver = 's_m_y_baywatch_01',
	paramedic = 's_m_m_paramedic_01',
	ambulance = 'ambulance',
	lifeguardHut = 'prop_lifeguard_tower_01',
}

Config.Search = {
	rescueBoatSpawnDistance = 90.0,
	rescueBoatSpawnAttempts = 14,
	shoreSearchRadius = 2600.0,
	shoreSearchStep = 55.0,
	shoreSearchAngleStep = 10,
	shoreProbeForward = 10.0,
	beachApproachDistance = 16.0,
	boatBeachInlandOffset = 3.0,
	beachInlandDistance = 10.0,
	patientDropInlandOffset = 4.0,
	ambulanceInlandDistance = 28.0,
	ambulanceSideOffset = 4.0,
}

Config.Navigation = {
	boatPickupDistance = 14.0,
	boatPickupSpeed = 34.0,
	boatShoreSpeed = 36.0,
	boatBeachSpeed = 44.0,
	boatShoreApproachThreshold = 10.0,
	boatBeachStopDistance = 4.0,
	ambulanceResponseSpeed = 24.0,
}

Config.TimeoutsMs = {
	boatPickup = 45000,
	boatToShore = 42000,
	boatBeach = 22000,
	ambulanceArrival = 20000,
	walkToPatient = 12000,
	postReviveCleanup = 10000,
}

Config.Medical = {
	cprDurationMs = 6200,
	partialReviveHealth = 130,
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
	hazardScanRadius = 14.0,
}

Config.Billing = {
	enabled = true,
	moneyType = 'bank',
	amount = 850,
	requirePaymentToRevive = false,
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
		label = 'Water Rescue Call'
	}
}
