@tool
class_name BallisticProjectileDefinition
extends Resource

const DEFAULT_DAMAGE := 10.0
const DEFAULT_MUZZLE_VELOCITY := 60.0
const DEFAULT_MAXIMUM_RANGE := 40.0
const DEFAULT_GRAVITY_SCALE := 1.0
const DEFAULT_IMPACT_IMPULSE := 0.8
const DEFAULT_TRACER_COLOR := Color(1.0, 0.68, 0.22, 1.0)
const DEFAULT_TRACER_LENGTH := 0.6
const DEFAULT_TRACER_RADIUS := 0.018
const MIN_MUZZLE_VELOCITY := 0.1
const MIN_MAXIMUM_RANGE := 0.1
const MIN_TRACER_LENGTH := 0.01
const MIN_TRACER_RADIUS := 0.002

#######################################################
# Defines the serialized ballistic projectile configuration shared by gameplay, inspection,
# and replication systems.
#######################################################

@export_group("Ballistics")
@export_range(0.0, 100000.0, 0.1, "or_greater") var damage := DEFAULT_DAMAGE
@export_range(0.1, 10000.0, 0.1, "or_greater") var muzzle_velocity := (
	DEFAULT_MUZZLE_VELOCITY
)
@export_range(0.1, 10000.0, 0.1, "or_greater") var maximum_range := (
	DEFAULT_MAXIMUM_RANGE
)
@export_range(0.0, 10.0, 0.01, "or_greater") var gravity_scale := (
	DEFAULT_GRAVITY_SCALE
)
@export_range(0.0, 1000.0, 0.01, "or_greater") var impact_impulse := (
	DEFAULT_IMPACT_IMPULSE
)

@export_group("Tracer")
@export var tracer_color := DEFAULT_TRACER_COLOR
@export_range(0.01, 5.0, 0.01, "or_greater") var tracer_length := (
	DEFAULT_TRACER_LENGTH
)
@export_range(0.002, 0.25, 0.001, "or_greater") var tracer_radius := (
	DEFAULT_TRACER_RADIUS
)


func to_ballistic_profile() -> Dictionary:
	return {
		"visual_definition_path": resource_path,
		"damage": maxf(damage, 0.0),
		"muzzle_velocity": maxf(muzzle_velocity, MIN_MUZZLE_VELOCITY),
		"maximum_range": maxf(maximum_range, MIN_MAXIMUM_RANGE),
		"gravity_scale": maxf(gravity_scale, 0.0),
		"impact_impulse": maxf(impact_impulse, 0.0),
		"tracer_color": tracer_color,
		"tracer_length": maxf(tracer_length, MIN_TRACER_LENGTH),
		"tracer_radius": maxf(tracer_radius, MIN_TRACER_RADIUS),
	}


static func normalize_profile(value: Dictionary) -> Dictionary:
	var result := value.duplicate(true)
	result["visual_definition_path"] = str(
		result.get("visual_definition_path", "")
	)
	result["damage"] = maxf(float(result.get("damage", 0.0)), 0.0)
	result["muzzle_velocity"] = maxf(
		float(result.get("muzzle_velocity", 0.0)),
		MIN_MUZZLE_VELOCITY
	)
	result["maximum_range"] = maxf(
		float(result.get("maximum_range", 0.0)),
		MIN_MAXIMUM_RANGE
	)
	result["gravity_scale"] = maxf(
		float(result.get("gravity_scale", 0.0)),
		0.0
	)
	result["impact_impulse"] = maxf(
		float(result.get("impact_impulse", 0.0)),
		0.0
	)
	result["tracer_color"] = result.get(
		"tracer_color",
		DEFAULT_TRACER_COLOR
	)
	result["tracer_length"] = maxf(
		float(result.get("tracer_length", DEFAULT_TRACER_LENGTH)),
		MIN_TRACER_LENGTH
	)
	result["tracer_radius"] = maxf(
		float(result.get("tracer_radius", DEFAULT_TRACER_RADIUS)),
		MIN_TRACER_RADIUS
	)
	return result
