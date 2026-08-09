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
	return _node(
		rope.display_name,
		"Deployable two-end rope and cable system",
		[
			_stat("Type", "Rope spool"),
			_stat("Spool mass", "%.3f kg" % rope.mass),
			_stat("Maximum length", "%.1f m" % rope.maximum_length),
			_stat("Visual effect", rope.get_effect_name()),
		],
		[
			_node(
				"Mechanical envelope",
				"Strength, weight and elastic response",
				[
					_stat("Breaking force", "%.0f N" % rope.breaking_force_newtons),
					_stat(
						"Line density",
						"%.3f kg/m" % rope.linear_density_kg_per_m
					),
					_stat("Diameter", "%.1f mm" % (rope.diameter * 1000.0)),
					_stat(
						"Stretch stiffness",
						"%.0f N/m" % rope.stretch_stiffness_newtons_per_m
					),
					_stat("Tension damping", "%.1f" % rope.tension_damping),
					_stat(
						"Force ramp",
						"%.0f N/s" % rope.tension_slew_rate_newtons_per_second
					),
					_stat("Placement slack", "%.2f m" % rope.placement_slack),
				]
			),
			_node(
				"Physical simulation",
				"Server-authoritative segmented rope",
				[
					_stat("Target segment", "%.2f m" % rope.target_segment_length),
					_stat("Visual repeat", "%.2f m" % rope.visual_repeat_length),
					_stat("Segment limit", "%d" % rope.maximum_simulation_segments),
					_stat("Solver passes", "%d" % rope.solver_iterations),
					_stat("Surface friction", "%.1f%%" % (rope.surface_friction * 100.0)),
					_stat("Break grace", "%.2f s" % rope.break_grace_seconds),
				]
			),
			_node(
				"Electrical conductor",
				"Battery-to-battery energy transfer",
				[
					_stat("Conductive", "Yes" if rope.transfers_power else "No"),
					_stat(
						"Transfer limit",
						"%.1f W" % rope.maximum_transfer_power_w
					),
					_stat(
						"Efficiency",
						"%.1f%%" % (rope.transfer_efficiency * 100.0)
					),
				]
			),
			_node(
				"Fiber data link",
				"Control path exposed to attached drones",
				[
					_stat("Fiber link", "Yes" if rope.provides_fiber_link else "No"),
					_stat("Bandwidth", "%.1f Mbit/s" % rope.data_bandwidth_mbps),
					_stat(
						"Signal loss",
						"%.3f%% / m" % (rope.signal_loss_per_meter * 100.0)
					),
				]
			),
		]
	)


func _node(
	title: String,
	subtitle := "",
	values: Array = [],
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
