class_name RopeInspectionInterface
extends Resource

#######################################################
# Builds the structured rope inspection data consumed by scanner-style terminal views.
#######################################################

func supports(definition: Resource) -> bool:
	return definition is RopeDefinition


func build_document(
	definition: Resource,
	_runtime_state: Dictionary
) -> Dictionary:
	var rope := definition as RopeDefinition
	if rope == null:
		return {}
	return InspectionDocumentBuilder.node(
		rope.display_name,
		"Deployable two-end rope and cable system",
		[
			InspectionDocumentBuilder.stat("Type", "Rope spool"),
			InspectionDocumentBuilder.stat("Spool mass", "%.3f kg" % rope.mass),
			InspectionDocumentBuilder.stat("Maximum length", "%.1f m" % rope.maximum_length),
			InspectionDocumentBuilder.stat("Visual effect", rope.get_effect_name()),
		],
		[
			InspectionDocumentBuilder.node(
				"Mechanical envelope",
				"Strength, weight and elastic response",
				[
					InspectionDocumentBuilder.stat("Breaking force", "%.0f N" % rope.breaking_force_newtons),
					InspectionDocumentBuilder.stat(
						"Line density",
						"%.3f kg/m" % rope.linear_density_kg_per_m
					),
					InspectionDocumentBuilder.stat("Diameter", "%.1f mm" % (rope.diameter * 1000.0)),
					InspectionDocumentBuilder.stat(
						"Stretch stiffness",
						"%.0f N/m" % rope.stretch_stiffness_newtons_per_m
					),
					InspectionDocumentBuilder.stat("Tension damping", "%.1f" % rope.tension_damping),
					InspectionDocumentBuilder.stat(
						"Force ramp",
						"%.0f N/s" % rope.tension_slew_rate_newtons_per_second
					),
					InspectionDocumentBuilder.stat("Placement slack", "%.2f m" % rope.placement_slack),
				]
			),
			InspectionDocumentBuilder.node(
				"Physical simulation",
				"Server-authoritative segmented rope",
				[
					InspectionDocumentBuilder.stat("Target segment", "%.2f m" % rope.target_segment_length),
					InspectionDocumentBuilder.stat("Visual repeat", "%.2f m" % rope.visual_repeat_length),
					InspectionDocumentBuilder.stat("Segment limit", "%d" % rope.maximum_simulation_segments),
					InspectionDocumentBuilder.stat("Solver passes", "%d" % rope.solver_iterations),
					InspectionDocumentBuilder.stat("Surface friction", "%.1f%%" % (rope.surface_friction * 100.0)),
					InspectionDocumentBuilder.stat("Break grace", "%.2f s" % rope.break_grace_seconds),
				]
			),
			InspectionDocumentBuilder.node(
				"Electrical conductor",
				"Battery-to-battery energy transfer",
				[
					InspectionDocumentBuilder.stat("Conductive", "Yes" if rope.transfers_power else "No"),
					InspectionDocumentBuilder.stat(
						"Transfer limit",
						"%.1f W" % rope.maximum_transfer_power_w
					),
					InspectionDocumentBuilder.stat(
						"Efficiency",
						"%.1f%%" % (rope.transfer_efficiency * 100.0)
					),
				]
			),
			InspectionDocumentBuilder.node(
				"Fiber data link",
				"Control path exposed to attached drones",
				[
					InspectionDocumentBuilder.stat("Fiber link", "Yes" if rope.provides_fiber_link else "No"),
					InspectionDocumentBuilder.stat("Bandwidth", "%.1f Mbit/s" % rope.data_bandwidth_mbps),
					InspectionDocumentBuilder.stat(
						"Signal loss",
						"%.3f%% / m" % (rope.signal_loss_per_meter * 100.0)
					),
				]
			),
		]
	)
