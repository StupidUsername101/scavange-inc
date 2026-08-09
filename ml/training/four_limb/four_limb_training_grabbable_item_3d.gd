class_name FourLimbTrainingGrabbableItem3D
extends TrainingItem3D

#######################################################
# Backward-compatible per-worker task prop used when a limb pickup/delivery lesson has no usable
# authored Training Item. Its actual cargo definition lives in a .tres resource, so the fallback
# follows the same data-driven item contract as authored room cargo.
#######################################################

const FALLBACK_ITEM_DEFINITION: TrainingItemDefinition = preload(
	"res://resources/training/items/fallback_grabbable_cargo.tres"
)


func _ready() -> void:
	item_definition = FALLBACK_ITEM_DEFINITION
	training_item_id = maxi(int(get_instance_id()), 1)
	super._ready()
	# Preserve the old lesson prop's always-awake behavior; authored room items may sleep for
	# performance once settled, but the fallback stays maximally responsive to early grip forces.
	can_sleep = false


func reset_item(
	spawn_transform: Transform3D,
	allowed_owner_id: int = 0,
	configured_item_type: String = TrainingItem3D.DEFAULT_ITEM_TYPE
) -> void:
	if allowed_owner_id > 0:
		set_meta("grip_allowed_owner_id", allowed_owner_id)
	else:
		remove_meta("grip_allowed_owner_id")
	configure_from_definition(
		maxi(training_item_id, int(get_instance_id())),
		FALLBACK_ITEM_DEFINITION,
		spawn_transform,
		true,
		configured_item_type
	)
	# A finished/paused worker deliberately freezes its private prop. Normal episode respawn reuses
	# that same node, so reset_item() is the activation boundary for the next live lesson as well as
	# a transform reset.
	set_simulation_active(true)
