class_name DroneTrainingLoadoutConfig
extends RefCounted

const TRAINING_BELLY_GRABBER_PATH = "res://resources/drones/attachments/utility_arm.tres"
const TRAINING_BELLY_GRABBER_CAPABILITY: StringName = &"training_belly_grabber"
const CORE_DIRECTORY := "res://resources/drones/cores"
const BATTERY_DIRECTORY := "res://resources/drones/batteries"
const PROPELLER_DIRECTORY := "res://resources/drones/propellers"
const CURRENT_TRAINING_PROPELLER_COUNT: int = 4
const STANDARD_GRAVITY_MPS2 := 9.8
const DEFAULT_AIR_DENSITY_KG_M3 := 1.225
const MINIMUM_DENOMINATOR := 0.000001

#######################################################
# Owns training-room hardware templates without mutating the shared gameplay resources.
# Every worker receives a deep, explicit part copy, while checkpoints retain enough data to
# reconstruct the exact physical powertrain used by a model.
#######################################################


static func duplicate_loadout(source: DroneLoadout) -> DroneLoadout:
	var result = DroneLoadout.new()
	if source == null:
		return result
	result.core = _duplicate_core(source.core)
	result.battery = _duplicate_battery(source.battery)
	# Copy the physical Core topology exactly. The current training room may still choose to
	# constrain a particular algorithm/profile to four rotors, but the loadout/preset layer must not
	# destroy additional creator-authored slots while cloning or serializing a body.
	for slot_index in range(_propeller_slot_count(source)):
		result.propellers.append(_duplicate_propeller(source.get_propeller(slot_index)))
	var source_propeller_mounts: Array[Transform3D] = source.get_propeller_slot_transforms()
	for slot_index: int in range(source_propeller_mounts.size()):
		if not result.set_propeller_slot_transform(slot_index, source_propeller_mounts[slot_index]):
			return DroneLoadout.new()
	# Training/model-forge loadouts intentionally discard the legacy scripted AI chips. The
	# learned model owns control; carrying old behavior chips into a worker body would mix two
	# independent control systems and exposes meaningless creator slots.
	result.ai_chips.clear()
	for attachment in source.attachments:
		var attachment_copy: DroneAttachmentDefinition = null
		if attachment != null:
			attachment_copy = MLBodyPartContract.deep_duplicate_resource(attachment) as DroneAttachmentDefinition
			_set_source_path(attachment_copy, source_path(attachment))
		result.attachments.append(attachment_copy)
	var source_mounts: Array[Transform3D] = source.get_attachment_slot_transforms()
	for slot_index: int in range(source_mounts.size()):
		if not result.set_attachment_slot_transform(slot_index, source_mounts[slot_index]):
			return DroneLoadout.new()
	return result


static func core_presets() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for record in _part_presets(CORE_DIRECTORY, &"core"):
		var core = load(str(record.get("path", ""))) as DroneCoreDefinition
		if core != null and core.propeller_slot_count == CURRENT_TRAINING_PROPELLER_COUNT:
			result.append(record)
	return result


static func battery_presets() -> Array[Dictionary]:
	return _part_presets(BATTERY_DIRECTORY, &"battery")


static func propeller_presets() -> Array[Dictionary]:
	return _part_presets(PROPELLER_DIRECTORY, &"propeller")


static func install_core_preset(loadout: DroneLoadout, resource_path: String) -> bool:
	if loadout == null:
		return false
	var source = load(resource_path) as DroneCoreDefinition
	if source == null or source.propeller_slot_count != CURRENT_TRAINING_PROPELLER_COUNT:
		return false
	var part = _duplicate_core(source)
	_set_source_path(part, resource_path)
	loadout.install_core(part)
	return true


static func install_battery_preset(loadout: DroneLoadout, resource_path: String) -> bool:
	if loadout == null:
		return false
	var source = load(resource_path) as DroneBatteryDefinition
	if source == null:
		return false
	var part = _duplicate_battery(source)
	_set_source_path(part, resource_path)
	loadout.install_battery(part)
	return true


static func install_propeller_preset(
	loadout: DroneLoadout,
	resource_path: String
) -> bool:
	if loadout == null or loadout.core == null:
		return false
	var source = load(resource_path) as DronePropellerDefinition
	if source == null:
		return false
	for slot_index in range(_propeller_slot_count(loadout)):
		var part = _duplicate_propeller(source)
		_set_source_path(part, resource_path)
		if not loadout.install_propeller(slot_index, part):
			return false
	return true


static func has_training_belly_grabber(loadout: DroneLoadout) -> bool:
	if loadout == null or loadout.core == null:
		return false
	return not loadout.find_attachment_slots_with_capability(
		TRAINING_BELLY_GRABBER_CAPABILITY
	).is_empty()


static func install_training_belly_grabber(loadout: DroneLoadout) -> bool:
	if loadout == null or loadout.core == null:
		return false
	if has_training_belly_grabber(loadout):
		return true
	var source = load(TRAINING_BELLY_GRABBER_PATH) as DroneLimbAttachmentDefinition
	if source == null:
		return false
	var target_slot = -1
	for slot_index in range(loadout.core.attachment_slot_count):
		if loadout.get_attachment(slot_index) == null:
			target_slot = slot_index
			break
	if target_slot < 0:
		return false
	var part = MLBodyPartContract.deep_duplicate_resource(source) as DroneLimbAttachmentDefinition
	if part == null:
		return false
	_set_source_path(part, TRAINING_BELLY_GRABBER_PATH)
	return loadout.install_attachment(target_slot, part)


static func remove_training_belly_grabber(loadout: DroneLoadout) -> void:
	if loadout == null:
		return
	for slot_index in loadout.find_attachment_slots_with_capability(
		TRAINING_BELLY_GRABBER_CAPABILITY
	):
		loadout.remove_attachment(slot_index)


static func limb_action_count(loadout: DroneLoadout) -> int:
	if loadout == null:
		return 0
	var result: int = 0
	for attachment in loadout.attachments:
		var limb_attachment = attachment as DroneLimbAttachmentDefinition
		if limb_attachment != null:
			result += limb_attachment.required_limb_action_count()
	return result


static func linked_flight_power_per_rotor(loadout: DroneLoadout) -> float:
	if (
		loadout == null
		or loadout.core == null
		or loadout.battery == null
	):
		return 0.0
	var propeller_count: int = _propeller_slot_count(loadout)
	if propeller_count <= 0:
		return 0.0
	var rotor_cap = INF
	for slot_index in range(propeller_count):
		var propeller = loadout.get_propeller(slot_index)
		if propeller == null:
			return 0.0
		rotor_cap = minf(rotor_cap, maxf(propeller.max_power_draw, 0.0))
	var nominal_bus_per_rotor = minf(
		maxf(loadout.battery.nominal_power_output, 0.0),
		maxf(loadout.battery.maximum_power_output, 0.0)
	) / float(propeller_count)
	var core_bus_per_rotor = (
		maxf(loadout.core.max_power_throughput, 0.0)
		/ float(propeller_count)
	)
	return minf(rotor_cap, minf(nominal_bus_per_rotor, core_bus_per_rotor))


static func set_linked_flight_power_per_rotor(
	loadout: DroneLoadout,
	power_w: float
) -> bool:
	if (
		loadout == null
		or loadout.core == null
		or loadout.battery == null
	):
		return false
	var propeller_count: int = _propeller_slot_count(loadout)
	if propeller_count <= 0:
		return false
	var safe_power = maxf(power_w, 0.0)
	for slot_index in range(propeller_count):
		var propeller = loadout.get_propeller(slot_index)
		if propeller == null:
			return false
		propeller.max_power_draw = safe_power
	var total_power = safe_power * float(propeller_count)
	loadout.battery.nominal_power_output = total_power
	loadout.battery.maximum_power_output = total_power
	loadout.core.max_power_throughput = total_power
	return true


static func set_part_stat(
	loadout: DroneLoadout,
	part_kind: StringName,
	property_name: StringName,
	value: Variant
) -> bool:
	if loadout == null:
		return false
	match part_kind:
		&"core":
			if loadout.core == null:
				return false
			loadout.core.set(property_name, value)
			return true
		&"battery":
			if loadout.battery == null:
				return false
			loadout.battery.set(property_name, value)
			return true
		&"propeller":
			var changed = false
			for slot_index in range(_propeller_slot_count(loadout)):
				var propeller = loadout.get_propeller(slot_index)
				if propeller == null:
					continue
				propeller.set(property_name, value)
				changed = true
			return changed
	return false


static func part_stat(
	loadout: DroneLoadout,
	part_kind: StringName,
	property_name: StringName,
	fallback: Variant = 0.0
) -> Variant:
	if loadout == null:
		return fallback
	var part: DronePartDefinition
	match part_kind:
		&"core":
			part = loadout.core
		&"battery":
			part = loadout.battery
		&"propeller":
			part = loadout.get_propeller(0)
	if part == null:
		return fallback
	return part.get(property_name)


static func source_path(part: DronePartDefinition) -> String:
	return DroneLoadout.definition_path(part)


static func to_record(loadout: DroneLoadout) -> Dictionary:
	if loadout == null or loadout.core == null or loadout.battery == null:
		return {}
	var core_snapshot: Dictionary = MLBodyResourceSnapshot.encode_resource(loadout.core)
	var battery_snapshot: Dictionary = MLBodyResourceSnapshot.encode_resource(loadout.battery)
	if core_snapshot.is_empty() or battery_snapshot.is_empty():
		return {}
	var propeller_snapshots: Array[Dictionary] = _snapshot_part_slots(loadout, &"propeller")
	var attachment_snapshots: Array[Dictionary] = _snapshot_part_slots(loadout, &"attachment")
	if (
		propeller_snapshots.size() != maxi(loadout.core.propeller_slot_count, 0)
		or attachment_snapshots.size() != maxi(loadout.core.attachment_slot_count, 0)
	):
		return {}
	var propeller_mounts: Array[Dictionary] = []
	for slot_transform: Transform3D in loadout.get_propeller_slot_transforms():
		propeller_mounts.append(_transform_to_record(slot_transform))
	var attachment_mounts: Array[Dictionary] = []
	for slot_transform: Transform3D in loadout.get_attachment_slot_transforms():
		attachment_mounts.append(_transform_to_record(slot_transform))
	return {
		"schema_version": 6,
		"core": core_snapshot,
		"battery": battery_snapshot,
		"propellers": propeller_snapshots,
		"attachments": attachment_snapshots,
		"propeller_mounts": propeller_mounts,
		"attachment_mounts": attachment_mounts,
		"summary": physical_summary(loadout),
	}


static func records_match(first: Dictionary, second: Dictionary) -> bool:
	if first.is_empty() or second.is_empty():
		return false
	# Hardware records are deliberately JSON-safe. Canonical sorted JSON gives us a stable,
	# type-preserving-enough equality check for the exact frozen candidate payload without
	# depending on Dictionary insertion order.
	return (
		JSON.stringify(first, "", true, true)
		== JSON.stringify(second, "", true, true)
	)


static func frozen_loadout(record: Dictionary, live_loadout: DroneLoadout) -> DroneLoadout:
	# The common in-session path should not deserialize hardware that is already present as an
	# isolated runtime Resource tree. If the candidate's frozen record is byte-for-byte/canonically
	# equivalent to the current group's serialized body, cloning that body preserves the exact
	# candidate hardware while avoiding a second Resource snapshot decode. This is especially
	# important for creator-authored nested attachment resources.
	if live_loadout != null:
		var live_record: Dictionary = to_record(live_loadout)
		if records_match(record, live_record):
			return duplicate_loadout(live_loadout)
	# If hardware changed after nomination (or this candidate was restored from disk), the live
	# body is not authoritative. Reconstruct only the frozen record; never silently evaluate the
	# candidate on different hardware.
	return from_record(record)


static func from_record(record: Dictionary) -> DroneLoadout:
	# Serialized hardware is either complete or invalid. Stock hardware is selected explicitly via
	# MLBodyPresetLibrary; malformed checkpoint data must never turn into an implicit preset.
	if record.is_empty():
		return null
	var schema_version: int = int(record.get("schema_version", -1))
	if schema_version != 4 and schema_version != 5 and schema_version != 6:
		return null
	var core_value: Variant = record.get("core", {})
	var battery_value: Variant = record.get("battery", {})
	if not (core_value is Dictionary) or not (battery_value is Dictionary):
		return null
	var core: DroneCoreDefinition = MLBodyResourceSnapshot.decode_resource(
		core_value as Dictionary
	) as DroneCoreDefinition
	var battery: DroneBatteryDefinition = MLBodyResourceSnapshot.decode_resource(
		battery_value as Dictionary
	) as DroneBatteryDefinition
	if core == null or battery == null:
		return null
	var result = DroneLoadout.new()
	result.install_core(core)
	result.install_battery(battery)
	if not _restore_part_slots(result, record.get("propellers", []), &"propeller"):
		return null
	if not _restore_part_slots(result, record.get("attachments", []), &"attachment"):
		return null
	if schema_version >= 6:
		var propeller_mounts_value: Variant = record.get("propeller_mounts", [])
		if not (propeller_mounts_value is Array):
			return null
		var propeller_mounts: Array = propeller_mounts_value as Array
		if propeller_mounts.size() != result.core.propeller_slot_count:
			return null
		for slot_index: int in range(propeller_mounts.size()):
			var propeller_mount_value: Variant = propeller_mounts[slot_index]
			if not (propeller_mount_value is Dictionary):
				return null
			var decoded_propeller_mount: Dictionary = _transform_from_record(propeller_mount_value as Dictionary)
			if not bool(decoded_propeller_mount.get("valid", false)):
				return null
			var propeller_slot_transform: Transform3D = decoded_propeller_mount.get("transform", Transform3D.IDENTITY)
			if not result.set_propeller_slot_transform(slot_index, propeller_slot_transform):
				return null
	if schema_version >= 5:
		var mounts_value: Variant = record.get("attachment_mounts", [])
		if not (mounts_value is Array):
			return null
		var mounts: Array = mounts_value as Array
		if mounts.size() != result.core.attachment_slot_count:
			return null
		for slot_index: int in range(mounts.size()):
			var mount_value: Variant = mounts[slot_index]
			if not (mount_value is Dictionary):
				return null
			var decoded_mount: Dictionary = _transform_from_record(mount_value as Dictionary)
			if not bool(decoded_mount.get("valid", false)):
				return null
			var slot_transform: Transform3D = decoded_mount.get("transform", Transform3D.IDENTITY)
			if not result.set_attachment_slot_transform(slot_index, slot_transform):
				return null
	return result


static func _transform_to_record(value: Transform3D) -> Dictionary:
	return {
		"origin": [value.origin.x, value.origin.y, value.origin.z],
		"basis": [
			[value.basis.x.x, value.basis.x.y, value.basis.x.z],
			[value.basis.y.x, value.basis.y.y, value.basis.y.z],
			[value.basis.z.x, value.basis.z.y, value.basis.z.z],
		],
	}


static func _transform_from_record(value: Dictionary) -> Dictionary:
	var origin_value: Variant = value.get("origin", [])
	var basis_value: Variant = value.get("basis", [])
	if not (origin_value is Array) or not (basis_value is Array):
		return {}
	var origin_array: Array = origin_value as Array
	var basis_array: Array = basis_value as Array
	if origin_array.size() != 3 or basis_array.size() != 3:
		return {}
	var columns: Array[Vector3] = []
	for column_value: Variant in basis_array:
		if not (column_value is Array):
			return {}
		var column: Array = column_value as Array
		if column.size() != 3:
			return {}
		for component: Variant in column:
			if not (component is int or component is float):
				return {}
		columns.append(Vector3(float(column[0]), float(column[1]), float(column[2])))
	for component: Variant in origin_array:
		if not (component is int or component is float):
			return {}
	var origin: Vector3 = Vector3(
		float(origin_array[0]), float(origin_array[1]), float(origin_array[2])
	)
	var basis: Basis = Basis(columns[0], columns[1], columns[2])
	if (
		not origin.is_finite()
		or not basis.x.is_finite()
		or not basis.y.is_finite()
		or not basis.z.is_finite()
		or absf(basis.determinant()) <= 0.000001
	):
		return {}
	return {
		"valid": true,
		"transform": Transform3D(basis.orthonormalized(), origin),
	}


static func _external_limb_body_mass(loadout: DroneLoadout) -> float:
	if loadout == null or loadout.core == null:
		return 0.0
	var result = 0.0
	for slot_index in range(loadout.core.attachment_slot_count):
		var attachment = loadout.get_attachment(slot_index) as DroneLimbAttachmentDefinition
		if attachment == null:
			continue
		for limb in attachment.limb_definitions:
			if limb == null or not limb.installed:
				continue
			for segment in limb.segments:
				if segment != null:
					result += maxf(segment.mass, 0.01)
			if limb.end_effector != null and limb.end_effector.enabled:
				result += maxf(limb.end_effector.added_mass, 0.0)
	return result


static func physical_summary(
	loadout: DroneLoadout,
	air_density: float = DEFAULT_AIR_DENSITY_KG_M3
) -> Dictionary:
	if (
		loadout == null
		or loadout.core == null
		or loadout.battery == null
	):
		return {}
	var installed: Array[DronePropellerDefinition] = []
	var propeller_count: int = _propeller_slot_count(loadout)
	for slot_index in range(propeller_count):
		var propeller = loadout.get_propeller(slot_index)
		if propeller != null:
			installed.append(propeller)
	if installed.size() != propeller_count:
		return {}
	var total_mass = loadout.get_total_mass() + _external_limb_body_mass(loadout)
	if propeller_count == 0:
		return {
			"mass_kg": total_mass,
			"propeller_count": 0,
			"requested_rotor_power_w": 0.0,
			"nominal_bus_power_w": 0.0,
			"maximum_bus_power_w": 0.0,
			"hover_power_w": 0.0,
			"nominal_hover_power_margin": 0.0,
			"nominal_static_thrust_n": 0.0,
			"maximum_static_thrust_n": 0.0,
			"nominal_lift_to_weight": 0.0,
			"maximum_lift_to_weight": 0.0,
			"core_name": loadout.core.display_name,
			"battery_name": loadout.battery.display_name,
			"propeller_name": "No propellers",
		}
	var requested_rotor_power = 0.0
	for propeller in installed:
		requested_rotor_power += maxf(propeller.max_power_draw, 0.0)
	var nominal_bus_power = maxf(minf(
		minf(
			loadout.battery.nominal_power_output,
			loadout.battery.maximum_power_output
		),
		loadout.core.max_power_throughput
	), 0.0)
	var maximum_bus_power = maxf(minf(
		loadout.battery.maximum_power_output,
		loadout.core.max_power_throughput
	), 0.0)
	var nominal_power_scale = minf(
		nominal_bus_power / maxf(requested_rotor_power, MINIMUM_DENOMINATOR),
		1.0
	)
	var maximum_power_scale = minf(
		maximum_bus_power / maxf(requested_rotor_power, MINIMUM_DENOMINATOR),
		1.0
	)
	var nominal_static_thrust = 0.0
	var maximum_static_thrust = 0.0
	var hover_power = 0.0
	var hover_thrust_per_rotor = (
		total_mass * STANDARD_GRAVITY_MPS2 / float(installed.size())
	)
	for propeller in installed:
		nominal_static_thrust += _rotor_thrust(
			propeller.max_power_draw * nominal_power_scale,
			propeller,
			air_density
		)
		maximum_static_thrust += _rotor_thrust(
			propeller.max_power_draw * maximum_power_scale,
			propeller,
			air_density
		)
		hover_power += _rotor_power(
			hover_thrust_per_rotor,
			propeller,
			air_density
		)
	var weight = maxf(total_mass * STANDARD_GRAVITY_MPS2, MINIMUM_DENOMINATOR)
	return {
		"mass_kg": total_mass,
		"propeller_count": installed.size(),
		"requested_rotor_power_w": requested_rotor_power,
		"nominal_bus_power_w": nominal_bus_power,
		"maximum_bus_power_w": maximum_bus_power,
		"hover_power_w": hover_power,
		"nominal_hover_power_margin": nominal_bus_power / maxf(hover_power, MINIMUM_DENOMINATOR),
		"nominal_static_thrust_n": nominal_static_thrust,
		"maximum_static_thrust_n": maximum_static_thrust,
		"nominal_lift_to_weight": nominal_static_thrust / weight,
		"maximum_lift_to_weight": maximum_static_thrust / weight,
		"core_name": loadout.core.display_name,
		"battery_name": loadout.battery.display_name,
		"propeller_name": installed[0].display_name,
	}


static func _part_presets(
	directory_path: String,
	part_kind: StringName
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var directory = DirAccess.open(directory_path)
	if directory == null:
		return result
	for file_name in directory.get_files():
		if not file_name.ends_with(".tres"):
			continue
		var path = directory_path.path_join(file_name)
		var part = load(path) as DronePartDefinition
		var valid = (
			(part_kind == &"core" and part is DroneCoreDefinition)
			or (part_kind == &"battery" and part is DroneBatteryDefinition)
			or (part_kind == &"propeller" and part is DronePropellerDefinition)
		)
		if valid:
			result.append({
				"path": path,
				"name": part.display_name,
			})
	result.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return str(left.get("name", "")).naturalnocasecmp_to(
			str(right.get("name", ""))
		) < 0
	)
	return result


static func _snapshot_part_slots(loadout: DroneLoadout, part_kind: StringName) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if loadout == null or loadout.core == null:
		return result
	var slot_count: int = 0
	match part_kind:
		&"propeller":
			slot_count = maxi(loadout.core.propeller_slot_count, 0)
		&"attachment":
			slot_count = maxi(loadout.core.attachment_slot_count, 0)
	for slot_index in range(slot_count):
		var part: Resource = null
		match part_kind:
			&"propeller":
				part = loadout.get_propeller(slot_index)
			&"attachment":
				part = loadout.get_attachment(slot_index)
		var snapshot: Dictionary = MLBodyResourceSnapshot.encode_resource(part)
		if part != null and snapshot.is_empty():
			# An unsupported/cyclic nested Resource must invalidate the complete body record. Returning an
			# undersized slot array lets to_record() fail closed instead of serializing this as an empty slot.
			return []
		result.append(snapshot)
	return result


static func _restore_part_slots(
	loadout: DroneLoadout,
	snapshots_value: Variant,
	part_kind: StringName
) -> bool:
	if loadout == null or loadout.core == null or not (snapshots_value is Array):
		return false
	var snapshots: Array = snapshots_value
	var slot_count: int = 0
	match part_kind:
		&"propeller":
			slot_count = maxi(loadout.core.propeller_slot_count, 0)
		&"attachment":
			slot_count = maxi(loadout.core.attachment_slot_count, 0)
		_:
			return false
	if snapshots.size() != slot_count:
		return false
	for slot_index in range(slot_count):
		var snapshot_value: Variant = snapshots[slot_index]
		if not (snapshot_value is Dictionary):
			return false
		var snapshot: Dictionary = snapshot_value
		var part: Resource = (
			MLBodyResourceSnapshot.decode_resource(snapshot)
			if not snapshot.is_empty()
			else null
		)
		match part_kind:
			&"propeller":
				if part != null and not (part is DronePropellerDefinition):
					return false
				loadout.propellers.append(part as DronePropellerDefinition)
			&"attachment":
				if part != null and not (part is DroneAttachmentDefinition):
					return false
				loadout.attachments.append(part as DroneAttachmentDefinition)
	return true


static func _propeller_slot_count(loadout: DroneLoadout) -> int:
	if loadout == null:
		return 0
	if loadout.core != null:
		return maxi(loadout.core.propeller_slot_count, 0)
	return loadout.propellers.size()


static func _duplicate_core(source: DroneCoreDefinition) -> DroneCoreDefinition:
	if source == null:
		return null
	var result = MLBodyPartContract.deep_duplicate_resource(source) as DroneCoreDefinition
	_set_source_path(result, source_path(source))
	return result


static func _duplicate_battery(source: DroneBatteryDefinition) -> DroneBatteryDefinition:
	if source == null:
		return null
	var result = MLBodyPartContract.deep_duplicate_resource(source) as DroneBatteryDefinition
	_set_source_path(result, source_path(source))
	return result


static func _duplicate_propeller(
	source: DronePropellerDefinition
) -> DronePropellerDefinition:
	if source == null:
		return null
	var result = MLBodyPartContract.deep_duplicate_resource(source) as DronePropellerDefinition
	_set_source_path(result, source_path(source))
	return result


static func _set_source_path(part: DronePartDefinition, path: String) -> void:
	if part != null and not path.is_empty():
		part.set_meta("training_source_path", path)


static func _rotor_thrust(
	power_w: float,
	propeller: DronePropellerDefinition,
	air_density: float
) -> float:
	if propeller == null or power_w <= 0.0:
		return 0.0
	var useful_power_term = (
		power_w
		* clampf(propeller.aerodynamic_efficiency, 0.01, 1.0)
		* sqrt(2.0 * maxf(air_density, 0.01) * propeller.get_disk_area())
	)
	return pow(maxf(useful_power_term, 0.0), 2.0 / 3.0)


static func _rotor_power(
	thrust_n: float,
	propeller: DronePropellerDefinition,
	air_density: float
) -> float:
	if propeller == null or thrust_n <= 0.0:
		return 0.0
	var denominator = (
		clampf(propeller.aerodynamic_efficiency, 0.01, 1.0)
		* sqrt(2.0 * maxf(air_density, 0.01) * propeller.get_disk_area())
	)
	return pow(thrust_n, 1.5) / maxf(denominator, MINIMUM_DENOMINATOR)
