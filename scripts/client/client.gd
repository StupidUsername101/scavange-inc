extends Node

const HOST_RPC_ID = 1
const PLAYER_PROXY_SCENE := preload("res://scenes/proxy/player_proxy.tscn")
const ITEM_PROXY_SCENE := preload("res://scenes/proxy/item_proxy.tscn")
const DRONE_PROXY_SCENE := preload("res://scenes/proxy/drone_proxy.tscn")
const PROJECTILE_PROXY_SCENE := preload(
	"res://scenes/proxy/projectile_proxy.tscn"
)
const DRONE_PART_PROXY_SCENE := preload(
	"res://scenes/proxy/drone_part_proxy.tscn"
)
const ROPE_PROXY_SCENE := preload("res://scenes/proxy/rope_proxy.tscn")
const ENEMY_PROXY_SCENE := preload("res://scenes/proxy/enemy_proxy.tscn")
const CLIENT_WORLD_SCENE := preload("res://scenes/proxy/world.tscn")
const USE_HOLD_SECONDS := 0.5

#######################################################
# Collects local input, sends player intents to the authority, and owns the lifecycle of
# replicated client-side proxies.
#######################################################

var item_proxies_by_item_id: Dictionary[int, ItemProxy] = {}
var item_spawn_queue: Array[Dictionary] = []
var player_proxys_by_player_id: Dictionary[int, PlayerProxy] = {}
var drone_proxies_by_drone_id: Dictionary[int, Node3D] = {}
var projectile_proxies_by_id: Dictionary[int, ProjectileProxy] = {}
var drone_part_proxies_by_id: Dictionary[int, Node3D] = {}
var rope_proxies_by_rope_id: Dictionary[int, RopeProxy] = {}
var enemy_proxies_by_enemy_id: Dictionary[int, EnemyProxy] = {}

var client_world: Node3D
var local_player_id := -1
var grab_rotation_mode_sent := false
var use_hold_elapsed := 0.0
var use_hold_action_sent := false


func reset_session() -> void:
	for child: Node in get_children():
		child.queue_free()

	if is_instance_valid(client_world):
		client_world.queue_free()
	client_world = null

	item_proxies_by_item_id.clear()
	item_spawn_queue.clear()
	player_proxys_by_player_id.clear()
	drone_proxies_by_drone_id.clear()
	projectile_proxies_by_id.clear()
	drone_part_proxies_by_id.clear()
	rope_proxies_by_rope_id.clear()
	enemy_proxies_by_enemy_id.clear()
	local_player_id = -1
	grab_rotation_mode_sent = false
	use_hold_elapsed = 0.0
	use_hold_action_sent = false


@rpc("authority", "reliable", "call_local")
func spawn_client_world() -> void:
	if client_world != null:
		return

	client_world = CLIENT_WORLD_SCENE.instantiate()
	get_tree().current_scene.add_child(client_world)

#####################################################
### PROCESSING
#####################################################
func _physics_process(delta: float) -> void:
	if not _has_connected_multiplayer_peer():
		return

	var local_proxy := get_local_player_proxy()
	var yaw := 0.0
	var pitch := 0.0
	if local_proxy != null:
		yaw = local_proxy.look_yaw
		pitch = local_proxy.look_pitch

	_send_movement_input(yaw, pitch)
	_process_action_input(delta, yaw, pitch, local_proxy)
	_process_grab_input(yaw, pitch, local_proxy)


func _has_connected_multiplayer_peer() -> bool:
	var peer := multiplayer.multiplayer_peer
	return (
		peer != null
		and not peer is OfflineMultiplayerPeer
		and peer.get_connection_status()
		== MultiplayerPeer.CONNECTION_CONNECTED
	)


func _send_movement_input(yaw: float, pitch: float) -> void:
	var move := Input.get_vector(
		"move_left",
		"move_right",
		"move_forward",
		"move_back"
	)
	Server.rpc_id(
		HOST_RPC_ID,
		"receive_player_input",
		move,
		yaw,
		pitch,
		Input.is_action_pressed("run")
	)


func _process_action_input(
	delta: float,
	yaw: float,
	pitch: float,
	local_proxy: PlayerProxy
) -> void:
	if Input.is_action_just_pressed("jump"):
		Server.rpc_id(HOST_RPC_ID, "receive_jump")

	_process_use_input(delta, yaw, pitch, local_proxy)
	_process_inventory_input()
	if Input.is_action_just_pressed("reload_weapon"):
		Server.rpc_id(HOST_RPC_ID, "reload_selected_weapon")

	if (
		Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
		and Input.is_action_just_pressed("primary_action")
	):
		Server.rpc_id(
			HOST_RPC_ID,
			"primary_action",
			yaw,
			pitch
		)


func _process_grab_input(
	yaw: float,
	pitch: float,
	local_proxy: PlayerProxy
) -> void:
	if Input.is_action_just_pressed("grab"):
		Server.rpc_id(
			HOST_RPC_ID,
			"begin_grab",
			yaw,
			pitch
		)

	if Input.is_action_just_released("grab"):
		Server.rpc_id(
			HOST_RPC_ID,
			"release_grab"
		)

	var wants_grab_rotation := (
		Input.is_action_pressed("grab")
		and Input.is_action_pressed("rotate_grabbed")
	)
	if wants_grab_rotation != grab_rotation_mode_sent:
		grab_rotation_mode_sent = wants_grab_rotation
		Server.rpc_id(
			HOST_RPC_ID,
			"set_grab_rotation_active",
			wants_grab_rotation
		)

	if local_proxy == null:
		return
	var rotation_input := local_proxy.consume_grab_rotation_input()
	if wants_grab_rotation and not rotation_input.is_zero_approx():
		Server.rpc_id(
			HOST_RPC_ID,
			"receive_grab_rotation_input",
			rotation_input
		)


func _process_use_input(
	delta: float,
	yaw: float,
	pitch: float,
	local_proxy: PlayerProxy
) -> void:
	if Input.is_action_just_pressed("use"):
		use_hold_elapsed = 0.0
		use_hold_action_sent = false

	if Input.is_action_pressed("use"):
		use_hold_elapsed += delta
		if (
			not use_hold_action_sent
			and use_hold_elapsed >= USE_HOLD_SECONDS
		):
			use_hold_action_sent = true
			Server.rpc_id(
				HOST_RPC_ID,
				"equip_item",
				yaw,
				pitch
			)

	var hud: PlayerInventoryHud
	if local_proxy != null:
		hud = local_proxy.inventory_hud
	if hud != null:
		hud.set_hold_progress(
			clampf(use_hold_elapsed / USE_HOLD_SECONDS, 0.0, 1.0)
			if Input.is_action_pressed("use")
			else 0.0
		)

	if Input.is_action_just_released("use"):
		if not use_hold_action_sent:
			Server.rpc_id(
				HOST_RPC_ID,
				"store_item_or_use",
				yaw,
				pitch
			)
		use_hold_elapsed = 0.0
		use_hold_action_sent = false


func _process_inventory_input() -> void:
	for slot_index: int in range(PlayerInventoryRules.MAX_CAPACITY):
		if Input.is_action_just_pressed(
			"inventory_slot_%d" % (slot_index + 1)
		):
			Server.rpc_id(
				HOST_RPC_ID,
				"select_inventory_slot",
				slot_index
			)
			break

	if Input.is_action_just_pressed("drop_equipped_eyes"):
		Server.rpc_id(
			HOST_RPC_ID,
			"drop_equipment",
			PlayerInventoryRules.EYES_SLOT
		)
	elif Input.is_action_just_pressed("drop_inventory_item"):
		Server.rpc_id(HOST_RPC_ID, "drop_inventory_item")
	
func get_local_player_proxy() -> PlayerProxy:
	return player_proxys_by_player_id.get(
		local_player_id
	) as PlayerProxy

func process_item_spawn_queue() -> void:
	while not item_spawn_queue.is_empty():
		var state: Dictionary = item_spawn_queue.pop_front()
		var item_id: int = SafeVariant.integral_int_or(state.get("item_id", -1), -1)
		if item_id < 0:
			continue

		if item_proxies_by_item_id.has(item_id):
			continue

		var proxy: ItemProxy = ITEM_PROXY_SCENE.instantiate()
		add_child(proxy)

		proxy.global_position = SafeVariant.vector3_strict_or(state.get("pos", Vector3.ZERO), Vector3.ZERO)
		proxy.global_rotation = SafeVariant.vector3_strict_or(state.get("rot", Vector3.ZERO), Vector3.ZERO)
		proxy.from_server_state(state)

		item_proxies_by_item_id[item_id] = proxy

func _public_state_dictionary(states: Dictionary, state_id: Variant) -> Dictionary:
	return SafeVariant.dictionary_copy(states.get(state_id, {}), false)


#####################################################
### RECEIVING SERVER STATE
#####################################################
@rpc("authority", "call_local", "reliable")
func set_local_player_id(player_id: int) -> void:
	local_player_id = player_id

	for existing_player_id in player_proxys_by_player_id:
		var proxy: PlayerProxy = (
			player_proxys_by_player_id[existing_player_id]
		)

		proxy.set_local_player(
			existing_player_id == local_player_id
		)

@rpc("authority", "unreliable_ordered", "call_local")
func on_item_states_received(states: Dictionary) -> void:
	for item_id in states:
		var state: Dictionary = _public_state_dictionary(states, item_id)
		if state.is_empty():
			continue

		if not item_proxies_by_item_id.has(item_id):
			item_spawn_queue.append(state)
			continue

		item_proxies_by_item_id[item_id].from_server_state(state)

	process_item_spawn_queue()

	var existing_item_ids := item_proxies_by_item_id.keys()

	for item_id in existing_item_ids:
		if states.has(item_id):
			continue

		var proxy: ItemProxy = item_proxies_by_item_id[item_id]

		item_proxies_by_item_id.erase(item_id)
		proxy.queue_free()

@rpc("authority", "unreliable_ordered", "call_local")
func on_player_states_received(states: Dictionary) -> void:
	for player_id in states:
		var state: Dictionary = _public_state_dictionary(states, player_id)
		if state.is_empty():
			continue

		if not player_proxys_by_player_id.has(player_id):
			var proxy: PlayerProxy = PLAYER_PROXY_SCENE.instantiate()

			proxy.player_id = player_id
			proxy.is_local_player = (
				player_id == local_player_id
			)

			proxy.position = SafeVariant.vector3_strict_or(state.get("pos", Vector3.ZERO), Vector3.ZERO)
			proxy.rotation = SafeVariant.vector3_strict_or(state.get("rot", Vector3.ZERO), Vector3.ZERO)

			if proxy.is_local_player:
				proxy.look_yaw = proxy.rotation.y

			add_child(proxy)
			player_proxys_by_player_id[player_id] = proxy

		var proxy: PlayerProxy = player_proxys_by_player_id[player_id]
		proxy.apply_server_state(state)

	var existing_player_ids := player_proxys_by_player_id.keys()

	for player_id in existing_player_ids:
		if states.has(player_id):
			continue

		var proxy: PlayerProxy = player_proxys_by_player_id[player_id]

		player_proxys_by_player_id.erase(player_id)
		proxy.queue_free()
	
@rpc("authority", "unreliable_ordered", "call_local", 2)
func on_drone_states_received(states: Dictionary) -> void:
	for drone_id in states:
		var state: Dictionary = _public_state_dictionary(states, drone_id)
		if state.is_empty():
			continue

		if not drone_proxies_by_drone_id.has(drone_id):
			var proxy := DRONE_PROXY_SCENE.instantiate() as Node3D
			if proxy == null:
				push_error("Drone proxy scene root must inherit Node3D")
				continue

			proxy.set("drone_id", drone_id)
			proxy.position = SafeVariant.vector3_strict_or(state.get("pos", Vector3.ZERO), Vector3.ZERO)
			proxy.rotation = SafeVariant.vector3_strict_or(state.get("rot", Vector3.ZERO), Vector3.ZERO)
			add_child(proxy)
			drone_proxies_by_drone_id[drone_id] = proxy

		drone_proxies_by_drone_id[drone_id].call(
			"apply_server_state",
			state
		)

	var existing_drone_ids := drone_proxies_by_drone_id.keys()
	for drone_id in existing_drone_ids:
		if states.has(drone_id):
			continue

		var proxy: Node3D = drone_proxies_by_drone_id[drone_id]
		drone_proxies_by_drone_id.erase(drone_id)
		proxy.queue_free()


@rpc("authority", "unreliable", "call_local", 2)
func spawn_projectile_proxy(state: Dictionary) -> void:
	_upsert_projectile_proxy(state)


@rpc("authority", "unreliable", "call_local", 2)
func despawn_projectile_proxy(projectile_id: int) -> void:
	var proxy := projectile_proxies_by_id.get(
		projectile_id
	) as ProjectileProxy
	projectile_proxies_by_id.erase(projectile_id)
	if is_instance_valid(proxy):
		proxy.queue_free()


@rpc("authority", "unreliable_ordered", "call_local", 2)
func on_projectile_states_received(states: Dictionary) -> void:
	for projectile_id_value: Variant in states.keys():
		var state: Dictionary = _public_state_dictionary(states, projectile_id_value)
		if state.is_empty():
			continue
		_upsert_projectile_proxy(state)

	var existing_ids := projectile_proxies_by_id.keys()
	for projectile_id_value: Variant in existing_ids:
		var projectile_id := int(projectile_id_value)
		if states.has(projectile_id):
			continue
		despawn_projectile_proxy(projectile_id)


func _upsert_projectile_proxy(state: Dictionary) -> void:
	var projectile_id: int = SafeVariant.integral_int_or(state.get("projectile_id", -1), -1)
	if projectile_id < 0:
		return
	var proxy := projectile_proxies_by_id.get(
		projectile_id
	) as ProjectileProxy
	if proxy == null:
		proxy = PROJECTILE_PROXY_SCENE.instantiate() as ProjectileProxy
		if proxy == null:
			return
		add_child(proxy)
		projectile_proxies_by_id[projectile_id] = proxy
	proxy.apply_server_state(state)
	if str(state.get("source_kind", "")) == "drone":
		var source_drone: Node3D = drone_proxies_by_drone_id.get(
			SafeVariant.integral_int_or(state.get("source_id", -1), -1)
		) as Node3D
		if source_drone != null:
			source_drone.call(
				"apply_projectile_muzzle_aim",
				SafeVariant.integral_int_or(state.get("source_slot", -1), -1),
				SafeVariant.vector3_strict_or(
					state.get(
						"launch_direction",
						state.get("velocity", Vector3.ZERO)
					),
					Vector3.ZERO
				)
			)


@rpc("authority", "unreliable_ordered", "call_local", 4)
func on_drone_part_states_received(states: Dictionary) -> void:
	for part_id in states:
		var state: Dictionary = _public_state_dictionary(states, part_id)
		if state.is_empty():
			continue

		if not drone_part_proxies_by_id.has(part_id):
			var proxy := DRONE_PART_PROXY_SCENE.instantiate() as Node3D
			if proxy == null:
				push_error("Drone part proxy root must inherit Node3D")
				continue

			proxy.set("drone_part_id", part_id)
			proxy.position = SafeVariant.vector3_strict_or(state.get("pos", Vector3.ZERO), Vector3.ZERO)
			proxy.rotation = SafeVariant.vector3_strict_or(state.get("rot", Vector3.ZERO), Vector3.ZERO)
			add_child(proxy)
			drone_part_proxies_by_id[part_id] = proxy

		drone_part_proxies_by_id[part_id].call(
			"apply_server_state",
			state
		)

	var existing_part_ids := drone_part_proxies_by_id.keys()
	for part_id in existing_part_ids:
		if states.has(part_id):
			continue

		var proxy: Node3D = drone_part_proxies_by_id[part_id]
		drone_part_proxies_by_id.erase(part_id)
		proxy.queue_free()


@rpc("authority", "unreliable_ordered", "call_local", 4)
func on_rope_states_received(states: Dictionary) -> void:
	for rope_id_value: Variant in states.keys():
		var rope_id := int(rope_id_value)
		var state: Dictionary = _public_state_dictionary(states, rope_id_value)
		if state.is_empty():
			continue
		if not rope_proxies_by_rope_id.has(rope_id):
			var proxy := ROPE_PROXY_SCENE.instantiate() as RopeProxy
			if proxy == null:
				push_error("Rope proxy scene root must inherit RopeProxy")
				continue
			proxy.rope_id = rope_id
			add_child(proxy)
			rope_proxies_by_rope_id[rope_id] = proxy
		rope_proxies_by_rope_id[rope_id].apply_server_state(state)

	var existing_rope_ids := rope_proxies_by_rope_id.keys()
	for rope_id: int in existing_rope_ids:
		if states.has(rope_id):
			continue
		var proxy: RopeProxy = rope_proxies_by_rope_id[rope_id]
		rope_proxies_by_rope_id.erase(rope_id)
		proxy.queue_free()


@rpc("authority", "unreliable_ordered", "call_local", 4)
func on_enemy_states_received(states: Dictionary) -> void:
	for enemy_id_value: Variant in states.keys():
		var enemy_id := int(enemy_id_value)
		var state: Dictionary = _public_state_dictionary(states, enemy_id_value)
		if state.is_empty():
			continue
		if not enemy_proxies_by_enemy_id.has(enemy_id):
			var proxy := ENEMY_PROXY_SCENE.instantiate() as EnemyProxy
			if proxy == null:
				push_error("Enemy proxy scene root must inherit EnemyProxy")
				continue
			proxy.enemy_id = enemy_id
			proxy.position = SafeVariant.vector3_strict_or(state.get("pos", Vector3.ZERO), Vector3.ZERO)
			add_child(proxy)
			enemy_proxies_by_enemy_id[enemy_id] = proxy
		enemy_proxies_by_enemy_id[enemy_id].apply_server_state(state)

	var existing_enemy_ids := enemy_proxies_by_enemy_id.keys()
	for enemy_id: int in existing_enemy_ids:
		if states.has(enemy_id):
			continue
		var proxy: EnemyProxy = enemy_proxies_by_enemy_id[enemy_id]
		enemy_proxies_by_enemy_id.erase(enemy_id)
		proxy.queue_free()


@rpc("authority", "unreliable_ordered", "call_local")
func on_inspection_station_states_received(states: Dictionary) -> void:
	if client_world == null:
		return

	var station_nodes: Array[Node] = get_tree().get_nodes_in_group(
		"drone_inspection_station_proxies"
	)
	for station_node: Node in station_nodes:
		var station_id := int(station_node.get("station_id"))
		if states.has(station_id):
			station_node.call(
				"apply_server_state",
				_public_state_dictionary(states, station_id)
			)


@rpc("authority", "unreliable_ordered", "call_local", 6)
func on_body_part_shop_states_received(states: Dictionary) -> void:
	if client_world == null:
		return

	var terminal_nodes := get_tree().get_nodes_in_group(
		"body_part_shop_terminal_proxies"
	)
	for terminal_node: Node in terminal_nodes:
		var station_id := int(terminal_node.get("station_id"))
		if states.has(station_id):
			terminal_node.call(
				"apply_server_state",
				_public_state_dictionary(states, station_id)
			)
