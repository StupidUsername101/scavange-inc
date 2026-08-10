class_name DroneRotorPhysics
extends RefCounted

#######################################################
# Shared pure rotor induced-power math. Runtime flight and training/loadout diagnostics must use
# the same equations so the creator cannot report lift capability that the physical drone cannot
# actually produce.
#######################################################

const MINIMUM_AIR_DENSITY_KG_M3: float = 0.01
const POWER_DENOMINATOR_FLOOR: float = 0.000001


static func thrust_for_power(
	shaft_power: float,
	disk_area: float,
	efficiency: float,
	air_density: float
) -> float:
	if shaft_power <= 0.0 or disk_area <= 0.0:
		return 0.0
	var safe_density: float = maxf(air_density, MINIMUM_AIR_DENSITY_KG_M3)
	var useful_power_term: float = (
		shaft_power
		* clampf(efficiency, 0.01, 1.0)
		* sqrt(2.0 * safe_density * disk_area)
	)
	return pow(maxf(useful_power_term, 0.0), 2.0 / 3.0)


static func power_for_thrust(
	thrust: float,
	disk_area: float,
	efficiency: float,
	air_density: float
) -> float:
	if thrust <= 0.0 or disk_area <= 0.0:
		return 0.0
	var safe_density: float = maxf(air_density, MINIMUM_AIR_DENSITY_KG_M3)
	var denominator: float = (
		clampf(efficiency, 0.01, 1.0)
		* sqrt(2.0 * safe_density * disk_area)
	)
	return pow(thrust, 1.5) / maxf(denominator, POWER_DENOMINATOR_FLOOR)
