extends Resource

#######################################################
# Builds the structured player equipment inspection data consumed by scanner-style terminal
# views.
#######################################################

func supports(definition: Resource) -> bool:
	return definition is BackpackDefinition or definition is EyeDefinition


func build_document(
	definition: Resource,
	_runtime_state: Dictionary
) -> Dictionary:
	if definition is BackpackDefinition:
		return _build_backpack_document(definition as BackpackDefinition)
	if definition is EyeDefinition:
		return _build_eye_document(definition as EyeDefinition)
	return {}


func _build_backpack_document(backpack: BackpackDefinition) -> Dictionary:
	return _node(
		backpack.display_name,
		"Wearable storage diagnostic",
		[
			_stat("Type", "Backpack"),
			_stat("Capacity", "%d total slots" % backpack.inventory_capacity),
			_stat("Equipment bus", str(backpack.equipment_slot)),
			_stat("Mass", "%.2f kg" % backpack.mass),
		],
		[
			_node(
				"Carry architecture",
				"Inventory expansion while equipped",
				[
					_stat(
						"Added utility",
						"%d slots above baseline"
						% (backpack.inventory_capacity - 1)
					),
					_stat("Hard limit", "9 player slots"),
					_stat("Overflow policy", "Reject unsafe downsizing"),
				]
			),
		]
	)


func _build_eye_document(eyes: EyeDefinition) -> Dictionary:
	var effects := "None installed"
	if not eyes.special_sight_effects.is_empty():
		var effect_names := PackedStringArray()
		for effect_id: StringName in eyes.special_sight_effects:
			effect_names.append(str(effect_id))
		effects = ", ".join(effect_names)

	return _node(
		eyes.display_name,
		"Exchangeable ocular diagnostic",
		[
			_stat("Type", "Ocular pair"),
			_stat("Equipment bus", str(eyes.equipment_slot)),
			_stat("Optical grade", _quality_name(eyes.optical_quality)),
			_stat("Mass", "%.2f kg" % eyes.mass),
		],
		[
			_node(
				"Human-equivalent sight",
				"Baseline perception characteristics",
				[
					_percent_stat("Visual acuity", eyes.visual_acuity),
					_percent_stat(
						"Contrast sensitivity",
						eyes.contrast_sensitivity
					),
					_percent_stat(
						"Light sensitivity",
						eyes.light_sensitivity
					),
				]
			),
			_node(
				"Signal integrity",
				"Display artifacts derived from optical quality",
				[
					_percent_stat("Optical quality", eyes.optical_quality),
					_percent_stat(
						"Estimated noise",
						1.0 - eyes.optical_quality
					),
					_percent_stat("Motion smear", eyes.motion_smear),
					_stat(
						"Lens distortion",
						"%+.3f" % eyes.lens_distortion
					),
				]
			),
			_node(
				"Special sight bus",
				"Reserved shader capabilities",
				[
					_stat("Installed effects", effects),
					_stat(
						"Capability count",
						str(eyes.special_sight_effects.size())
					),
				]
			),
		]
	)


func _node(
	title: String,
	subtitle: String,
	values: Array,
	children: Array = []
) -> Dictionary:
	return {
		"title": title,
		"subtitle": subtitle,
		"values": values,
		"children": children,
	}


func _stat(label: String, value: String) -> Dictionary:
	return {"label": label, "value": value}


func _percent_stat(label: String, value: float) -> Dictionary:
	return _stat(
		label,
		"%.0f%%" % (clampf(value, 0.0, 1.0) * 100.0)
	)


func _quality_name(quality: float) -> String:
	if quality >= 0.9:
		return "Precision"
	if quality >= 0.7:
		return "Serviceable"
	if quality >= 0.45:
		return "Degraded"
	return "Unreliable"
