@tool
class_name BallisticProjectileDefinition
extends Resource

const DEFAULT_DAMAGE := 10.0
const DEFAULT_MUZZLE_VELOCITY := 60.0
const DEFAULT_MAXIMUM_RANGE := 40.0
const DEFAULT_GRAVITY_SCALE := 1.0
const DEFAULT_IMPACT_IMPULSE := 0.8
const DEFAULT_IMPACT_SOUND_ID := &"projectile_impact_generic"
const DEFAULT_IMPACT_SOUND_MAX_DISTANCE := 68.0
const DEFAULT_IMPACT_SOUND_VOLUME_DB := 4.0
const DEFAULT_IMPACT_SOUND_PRIORITY := 0.58
const DEFAULT_IMPACT_RESPONSE_STRENGTH := 0.55
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

@export_group("Impact Audio")
@export var impact_sound_id := DEFAULT_IMPACT_SOUND_ID
## Hearing reach at 0 dB; impact_sound_volume_db scales it before listener culling.
@export_range(0.1, 10000.0, 0.1, "or_greater") var impact_sound_max_distance := (
	DEFAULT_IMPACT_SOUND_MAX_DISTANCE
)
@export_range(-60.0, 18.0, 0.1) var impact_sound_volume_db := (
	DEFAULT_IMPACT_SOUND_VOLUME_DB
)
@export_range(0.0, 1.0, 0.01) var impact_sound_priority := (
	DEFAULT_IMPACT_SOUND_PRIORITY
)
@export_range(0.0, 2.0, 0.01, "or_greater") var impact_response_strength := (
	DEFAULT_IMPACT_RESPONSE_STRENGTH
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
		"impact_sound_id": (
			impact_sound_id
			if not impact_sound_id.is_empty()
			else DEFAULT_IMPACT_SOUND_ID
		),
		"impact_sound_max_distance": maxf(
			impact_sound_max_distance,
			0.1
		),
		"impact_sound_volume_db": clampf(
			impact_sound_volume_db,
			-60.0,
			18.0
		),
		"impact_sound_priority": clampf(impact_sound_priority, 0.0, 1.0),
		"impact_response_strength": clampf(
			impact_response_strength,
			0.0,
			2.0
		),
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
	var impact_id := StringName(str(result.get(
		"impact_sound_id",
		DEFAULT_IMPACT_SOUND_ID
	)))
	result["impact_sound_id"] = (
		impact_id if not impact_id.is_empty() else DEFAULT_IMPACT_SOUND_ID
	)
	result["impact_sound_max_distance"] = maxf(
		float(result.get(
			"impact_sound_max_distance",
			DEFAULT_IMPACT_SOUND_MAX_DISTANCE
		)),
		0.1
	)
	result["impact_sound_volume_db"] = clampf(
		float(result.get(
			"impact_sound_volume_db",
			DEFAULT_IMPACT_SOUND_VOLUME_DB
		)),
		-60.0,
		18.0
	)
	result["impact_sound_priority"] = clampf(
		float(result.get(
			"impact_sound_priority",
			DEFAULT_IMPACT_SOUND_PRIORITY
		)),
		0.0,
		1.0
	)
	result["impact_response_strength"] = clampf(
		float(result.get(
			"impact_response_strength",
			DEFAULT_IMPACT_RESPONSE_STRENGTH
		)),
		0.0,
		2.0
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
