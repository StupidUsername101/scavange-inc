extends Node

#######################################################
# End-to-end regression for creator-authored rotor counts and worker-frame uplift. This runs as a
# normal project scene so the Server autoload is present while the real ServerDrone is instantiated.
#######################################################

var assertion_count: int = 0
var failure_count: int = 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var runtime: DroneLoadout = _creator_six_rotor_loadout()
	_test_live_runtime(runtime)
	print("Variable propeller runtime assertions: %d, failures: %d" % [
		assertion_count,
		failure_count,
	])
	get_tree().quit(0 if failure_count == 0 else 1)


func _creator_six_rotor_loadout() -> DroneLoadout:
	var panel: MLBodyCreatorPanel = MLBodyCreatorPanel.new()
	add_child(panel)
	var core: DroneCoreDefinition = panel._current_physical_core() as DroneCoreDefinition
	var orientation_ready: bool = (
		core != null
		and core.set_model_orientation(Vector3.RIGHT, Vector3.BACK)
	)
	panel._realign_creator_propellers_to_worker_up()
	panel.mirror_next_checkbox.button_pressed = false
	panel.layout_slot_kind_picker.select(0)
	for slot_index: int in range(6):
		panel._on_layout_surface_clicked(Transform3D(
			panel._slot_basis_from_surface_normal(Vector3.FORWARD),
			Vector3(-0.30 + float(slot_index) * 0.12, 0.0, -0.425)
		))
	var worker_up: Vector3 = core.model_up_local.normalized() if core != null else Vector3.UP
	var axes_match: bool = orientation_ready
	for mount: Transform3D in panel.layout_slot_transforms:
		axes_match = axes_match and mount.basis.y.normalized().dot(worker_up) > 0.999
	_expect(
		panel.layout_slot_transforms.size() == 6 and axes_match,
		"creator accepts six rotor mounts and points their default thrust along worker up"
	)
	panel._accept_core_layout()
	var battery: DroneBatteryDefinition = load(
		"res://resources/drones/batteries/calibrated_reference_cell.tres"
	) as DroneBatteryDefinition
	var propeller: DronePropellerDefinition = load(
		"res://resources/drones/propellers/calibrated_reference_propeller.tres"
	) as DronePropellerDefinition
	var equipped: bool = panel.current_draft != null and battery != null and propeller != null
	if equipped:
		equipped = panel.current_draft.equip(
			&"battery",
			MLBodyPartContract.deep_duplicate_resource(battery)
		)
	for slot_index: int in range(6):
		if not equipped:
			break
		equipped = panel.current_draft.equip(
			StringName("propeller_%d" % slot_index),
			MLBodyPartContract.deep_duplicate_resource(propeller)
		)
	var runtime: DroneLoadout = (
		MLBodyCreatorRuntimeFactory.runtime_from_draft(
			panel.current_preset_id,
			panel.current_draft,
			panel.changed_slot_ids
		) as DroneLoadout
		if equipped
		else null
	)
	var summary: Dictionary = DroneTrainingLoadoutConfig.physical_summary(runtime)
	var manifest: MLBodyInterfaceManifest = (
		DroneMLBodyInterfaceFactory.finalize_loadout(runtime)
		if runtime != null
		else null
	)
	_expect(
		runtime != null
		and runtime.core.propeller_slot_count == 6
		and manifest != null
		and manifest.control_count() == 6
		and int(summary.get("propeller_count", 0)) == 6
		and float(summary.get("nominal_upward_thrust_n", 0.0)) > 0.0
		and float(summary.get("nominal_lift_to_weight", 0.0)) > 0.0,
		"creator runtime keeps six installed rotors and reports nonzero nominal uplift"
	)
	if manifest != null:
		var trainer: DronePPOTrainer = DronePPOTrainer.new({
			"body_interface": manifest.to_dictionary(),
		}, 60713)
		var checkpoint: Dictionary = trainer.to_checkpoint()
		var restored: DronePPOTrainer = DronePPOTrainer.new({
			"body_interface": manifest.to_dictionary(),
		}, 60714)
		_expect(
			trainer.is_initialized()
			and int(checkpoint.get("propeller_count", -1)) == 6
			and bool(DroneTrainingAlgorithmCatalog.inspect_checkpoint(
				checkpoint
			).get("compatible", false))
			and restored.load_checkpoint(checkpoint),
			"six-rotor PPO contracts allocate, inspect, and restore without a hidden quad checkpoint cap"
		)
	panel.free()
	return runtime


func _test_live_runtime(loadout: DroneLoadout) -> void:
	if loadout == null:
		return
	var air_environment: AirEnvironment = AirEnvironment.new()
	add_child(air_environment)
	var drone_scene: PackedScene = load("res://scenes/server/server_drone.tscn") as PackedScene
	var drone: ServerDrone = drone_scene.instantiate() as ServerDrone if drone_scene != null else null
	if drone == null:
		_expect(false, "real ServerDrone scene instantiates")
		air_environment.free()
		return
	drone.loadout = DroneTrainingLoadoutConfig.duplicate_loadout(loadout)
	drone.network_visible = false
	add_child(drone)
	var propeller_states: Array[Dictionary] = DroneMLObservation.capture_ppo_propeller_states(drone)
	_expect(
		drone.propeller_slots.size() == 6
		and drone.get_node_or_null("Propeller5Collision") is CollisionShape3D
		and propeller_states.size() == 6
		and DronePPOObservationEncoder.has_valid_propeller_topology({
			"propellers": propeller_states,
		}),
		"server runtime materializes all accepted rotor nodes, colliders, and ordered observations"
	)
	var proxy_scene: PackedScene = load("res://scenes/proxy/drone_proxy.tscn") as PackedScene
	var proxy: DroneProxy = proxy_scene.instantiate() as DroneProxy if proxy_scene != null else null
	if proxy != null:
		add_child(proxy)
		proxy.apply_server_state(drone.to_state_dict())
	_expect(
		proxy != null
		and proxy.propeller_visuals.size() == 6
		and proxy.propeller_guides.size() == 6
		and proxy.propeller_slot_transforms.size() == 6
		and proxy.propeller_visuals[5].visible,
		"client proxy grows its pooled rotor presentation to the authoritative topology"
	)
	if proxy != null:
		proxy.free()
	drone.free()
	air_environment.free()


func _expect(condition: bool, message: String) -> void:
	assertion_count += 1
	if condition:
		print("PASS: ", message)
		return
	failure_count += 1
	push_error("FAIL: %s" % message)
