class_name WeaponCraftingCatalog
extends RefCounted

const PARTS_DIRECTORY := "res://resources/guns/parts"
const CRAFTED_WEAPON_PATH := (
	"res://resources/guns/fabricated_modular_weapon.tres"
)

## The machine is intentionally topology-light. Only the primary barrel is
## required; the repeated optional lanes may select the same part again.
static func lane_specs() -> Array[Dictionary]:
	return [
		{
			"lane_id": "receiver",
			"label": "ACTION",
			"part_slot": GunPartDefinition.PartSlot.RECEIVER,
			"required": true,
		},
		{
			"lane_id": "barrel_0",
			"label": "BARREL 01",
			"part_slot": GunPartDefinition.PartSlot.BARREL,
			"required": true,
		},
		{
			"lane_id": "barrel_1",
			"label": "BARREL 02",
			"part_slot": GunPartDefinition.PartSlot.BARREL,
			"required": false,
		},
		{
			"lane_id": "barrel_2",
			"label": "BARREL 03",
			"part_slot": GunPartDefinition.PartSlot.BARREL,
			"required": false,
		},
		{
			"lane_id": "magazine",
			"label": "FEED",
			"part_slot": GunPartDefinition.PartSlot.MAGAZINE,
			"required": true,
		},
		{
			"lane_id": "ammunition",
			"label": "LOAD",
			"part_slot": GunPartDefinition.PartSlot.AMMUNITION,
			"required": true,
		},
	]


static func build_document() -> Dictionary:
	var parts_by_slot := _load_parts_by_slot()
	var lanes: Array[Dictionary] = []
	for spec: Dictionary in lane_specs():
		var options: Array[Dictionary] = []
		if not bool(spec["required"]):
			options.append({
				"definition_path": "",
				"title": "EMPTY MOUNT",
				"inventory_code": "---",
				"caliber": "OPEN",
				"mass": 0.0,
				"subtitle": "No component installed",
				"color": Color(0.16, 0.17, 0.18, 1.0),
			})
		var slot := int(spec["part_slot"])
		for part_value: Variant in parts_by_slot.get(slot, []):
			var part := part_value as GunPartDefinition
			if part != null:
				options.append(_part_option(part))
		lanes.append({
			"lane_id": str(spec["lane_id"]),
			"label": str(spec["label"]),
			"part_slot": slot,
			"required": bool(spec["required"]),
			"options": options,
		})
	var signature_parts := PackedStringArray(["weapon_catalog_v1"])
	for lane: Dictionary in lanes:
		signature_parts.append(str(lane["lane_id"]))
		for option: Dictionary in lane["options"]:
			signature_parts.append(str(option["definition_path"]))
	return {
		"version": 1,
		"catalog_signature": "|".join(signature_parts),
		"title": "SCAV INC. // ARMS DIVISION",
		"lanes": lanes,
		"optics_reserved": true,
	}


static func default_selection_indices(document: Dictionary) -> Array[int]:
	var result: Array[int] = []
	for lane_value: Variant in document.get("lanes", []):
		var lane: Dictionary = lane_value if lane_value is Dictionary else {}
		var options: Array = lane.get("options", []) if lane.get("options", []) is Array else []
		result.append(0 if not options.is_empty() else -1)
	return result


static func sanitized_selection_indices(
	document: Dictionary,
	selection_value: Variant
) -> Array[int]:
	var source: Array = (
		selection_value as Array
		if selection_value is Array
		else []
	)
	var result: Array[int] = []
	var lanes: Array = document.get("lanes", []) if document.get("lanes", []) is Array else []
	for lane_index: int in range(lanes.size()):
		var lane: Dictionary = lanes[lane_index] if lanes[lane_index] is Dictionary else {}
		var options: Array = lane.get("options", []) if lane.get("options", []) is Array else []
		var selected := (
			SafeVariant.integral_int_or(source[lane_index], 0)
			if lane_index < source.size()
			else 0
		)
		result.append(clampi(selected, 0, maxi(options.size() - 1, 0)))
	return result


static func selected_option(
	document: Dictionary,
	selection_value: Variant,
	lane_index: int
) -> Dictionary:
	var lanes: Array = document.get("lanes", []) if document.get("lanes", []) is Array else []
	if lane_index < 0 or lane_index >= lanes.size():
		return {}
	var lane: Dictionary = lanes[lane_index] if lanes[lane_index] is Dictionary else {}
	var options: Array = lane.get("options", []) if lane.get("options", []) is Array else []
	if options.is_empty():
		return {}
	var selection := sanitized_selection_indices(document, selection_value)
	return SafeVariant.dictionary_copy(options[selection[lane_index]], false)


static func build_from_selection(
	document: Dictionary,
	selection_value: Variant
) -> GunBuild:
	var build := GunBuild.new()
	var lanes: Array = document.get("lanes", []) if document.get("lanes", []) is Array else []
	var selection := sanitized_selection_indices(document, selection_value)
	for lane_index: int in range(lanes.size()):
		var lane: Dictionary = lanes[lane_index] if lanes[lane_index] is Dictionary else {}
		var options: Array = lane.get("options", []) if lane.get("options", []) is Array else []
		if options.is_empty():
			continue
		var option := SafeVariant.dictionary_copy(
			options[selection[lane_index]],
			false
		)
		var definition_path := str(option.get("definition_path", ""))
		if definition_path.is_empty():
			continue
		var part := load(definition_path) as GunPartDefinition
		if part == null or int(part.part_slot) != int(lane.get("part_slot", -1)):
			continue
		if part is GunBarrelDefinition:
			build.add_barrel(part as GunBarrelDefinition)
		else:
			build.install_part(part)
	return build


static func build_summary(
	document: Dictionary,
	selection_value: Variant
) -> Dictionary:
	var build := build_from_selection(document, selection_value)
	var errors := build.get_compatibility_errors()
	var profile := build.get_ballistic_profile()
	return {
		"complete": build.is_complete(),
		"compatible": build.is_compatible(),
		"errors": Array(errors),
		"barrel_count": build.get_barrel_count(),
		"mass": build.get_total_mass(),
		"capacity": build.get_magazine_capacity(),
		"automatic": build.is_automatic(),
		"rounds_per_second": SafeVariant.finite_float_or(
			profile.get("rounds_per_second"),
			0.0
		),
		"damage_per_barrel": SafeVariant.finite_float_or(
			profile.get("damage"),
			0.0
		),
	}


static func make_crafted_instance_state(build: GunBuild) -> Dictionary:
	if build == null:
		return {}
	var build_state := build.to_state_dict()
	return {
		"build": build_state,
		GunItemDefinition.BUILD_SIGNATURE_KEY: (
			GunBuild.visual_signature_from_state(build_state)
		),
		"rounds": build.get_magazine_capacity(),
	}


static func _load_parts_by_slot() -> Dictionary:
	var result: Dictionary = {}
	for slot: int in GunPartDefinition.PartSlot.values():
		result[slot] = []
	for resource_path: String in ResourcePathDiscovery.collect_shallow(
		PARTS_DIRECTORY,
		["tres"]
	):
		var part := load(resource_path) as GunPartDefinition
		if part == null:
			continue
		(result[int(part.part_slot)] as Array).append(part)
	for slot_value: Variant in result.keys():
		(result[slot_value] as Array).sort_custom(
			func(left: GunPartDefinition, right: GunPartDefinition) -> bool:
				return left.display_name.naturalnocasecmp_to(
					right.display_name
				) < 0
		)
	return result


static func _part_option(part: GunPartDefinition) -> Dictionary:
	return {
		"definition_path": part.resource_path,
		"title": part.display_name,
		"inventory_code": part.get_inventory_code(),
		"caliber": str(part.caliber_id),
		"mass": maxf(part.mass, 0.0),
		"subtitle": _part_subtitle(part),
		"color": part.component_color,
	}


static func _part_subtitle(part: GunPartDefinition) -> String:
	if part is GunReceiverDefinition:
		var receiver := part as GunReceiverDefinition
		return "%s  •  %.1f RPS" % [
			"AUTO" if receiver.automatic else "SEMI",
			receiver.rounds_per_second,
		]
	if part is GunBarrelDefinition:
		var barrel_part := part as GunBarrelDefinition
		return "%.0f MM  •  %.2f× VELOCITY" % [
			barrel_part.barrel_length * 1000.0,
			barrel_part.velocity_multiplier,
		]
	if part is GunMagazineDefinition:
		return "%d ROUND FEED" % (part as GunMagazineDefinition).capacity
	if part is GunAmmunitionDefinition:
		var ammunition_part := part as GunAmmunitionDefinition
		return (
			"BALLISTIC LOAD"
			if ammunition_part.projectile != null
			else "INERT LOAD"
		)
	return "COMPONENT"
