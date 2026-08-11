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
	return InspectionDocumentBuilder.node(
		backpack.display_name,
		"Wearable storage diagnostic",
		[
			InspectionDocumentBuilder.stat("Type", "Backpack"),
			InspectionDocumentBuilder.stat("Capacity", "%d total slots" % backpack.inventory_capacity),
			InspectionDocumentBuilder.stat("Equipment bus", str(backpack.equipment_slot)),
			InspectionDocumentBuilder.stat("Mass", "%.2f kg" % backpack.mass),
		],
		[
			InspectionDocumentBuilder.node(
				"Carry architecture",
				"Inventory expansion while equipped",
				[
					InspectionDocumentBuilder.stat(
						"Added utility",
						"%d slots above baseline"
						% (backpack.inventory_capacity - 1)
					),
					InspectionDocumentBuilder.stat("Hard limit", "9 player slots"),
					InspectionDocumentBuilder.stat("Overflow policy", "Reject unsafe downsizing"),
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

	return InspectionDocumentBuilder.node(
		eyes.display_name,
		"Exchangeable ocular diagnostic",
		[
			InspectionDocumentBuilder.stat("Type", "Ocular pair"),
			InspectionDocumentBuilder.stat("Equipment bus", str(eyes.equipment_slot)),
			InspectionDocumentBuilder.stat("Optical grade", _quality_name(eyes.optical_quality)),
			InspectionDocumentBuilder.stat("Mass", "%.2f kg" % eyes.mass),
		],
		[
			InspectionDocumentBuilder.node(
				"Human-equivalent sight",
				"Baseline perception characteristics",
				[
					InspectionDocumentBuilder.percent_stat("Visual acuity", eyes.visual_acuity),
					InspectionDocumentBuilder.percent_stat(
						"Contrast sensitivity",
						eyes.contrast_sensitivity
					),
					InspectionDocumentBuilder.percent_stat(
						"Light sensitivity",
						eyes.light_sensitivity
					),
				]
			),
			InspectionDocumentBuilder.node(
				"Signal integrity",
				"Display artifacts derived from optical quality",
				[
					InspectionDocumentBuilder.percent_stat("Optical quality", eyes.optical_quality),
					InspectionDocumentBuilder.percent_stat(
						"Estimated noise",
						1.0 - eyes.optical_quality
					),
					InspectionDocumentBuilder.percent_stat("Motion smear", eyes.motion_smear),
					InspectionDocumentBuilder.stat(
						"Lens distortion",
						"%+.3f" % eyes.lens_distortion
					),
				]
			),
			InspectionDocumentBuilder.node(
				"Special sight bus",
				"Reserved shader capabilities",
				[
					InspectionDocumentBuilder.stat("Installed effects", effects),
					InspectionDocumentBuilder.stat(
						"Capability count",
						str(eyes.special_sight_effects.size())
					),
				]
			),
		]
	)


func _quality_name(quality: float) -> String:
	if quality >= 0.9:
		return "Precision"
	if quality >= 0.7:
		return "Serviceable"
	if quality >= 0.45:
		return "Degraded"
	return "Unreliable"
