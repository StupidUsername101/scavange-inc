@tool
class_name LimbSegmentDefinition
extends Resource

#######################################################
# Reusable physical part data for one rigid segment of a generic limb chain.
#######################################################

@export var segment_name := "Segment"
# Direction is authored in creature/core-local space. Length is stored separately so an editor
# can resize parts without changing their orientation.
@export var rest_direction_local := Vector3.DOWN
@export_range(0.05, 10.0, 0.01, "or_greater") var length := 1.0
@export_range(0.01, 1.0, 0.005, "or_greater") var radius := 0.075
@export_range(0.01, 500.0, 0.01, "or_greater") var mass := 0.4
@export_range(0.1, 1000000.0, 0.1, "or_greater") var maximum_health := 100.0
@export_range(0.0, 1.0, 0.01) var friction := 0.95
@export_range(0.0, 1.0, 0.01) var bounce := 0.01
# CCD is intentionally opt-in per segment. Articulated creatures pay its broad-phase/sweep cost
# for every enabled rigid part; distal contact segments can need it while protected proximal links
# usually do not.
@export var continuous_collision_detection: bool = false
# Rough surfaces contribute their own friction even when the contacted surface is more slippery.
# This stays opt-in so generic limbs preserve normal Godot material-combination semantics by
# default, while a future creature editor can explicitly author gripping feet.
@export var rough := false
@export var joint: LimbJointDefinition


func sanitize() -> void:
	if not rest_direction_local.is_finite() or rest_direction_local.length_squared() <= 0.000001:
		rest_direction_local = Vector3.DOWN
	rest_direction_local = rest_direction_local.normalized()
	length = maxf(length, 0.05)
	radius = clampf(radius, 0.01, length * 0.45)
	mass = maxf(mass, 0.01)
	maximum_health = maxf(maximum_health, 0.1)
	friction = clampf(friction, 0.0, 1.0)
	bounce = clampf(bounce, 0.0, 1.0)
	# A joint is authored part data. Do not fabricate one while sanitizing an incomplete creator
	# draft; accepted-body validation is responsible for rejecting a segment without a joint.
	if joint != null:
		joint.sanitize()
