extends SceneTree

## Integration coverage for the temporary death loop: lethal authority, detached persistent corpse,
## immediate reusable player identity, and matching client lifecycle.

var assertion_count := 0
var failure_count := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var server := root.get_node_or_null("/root/Server")
	var client := root.get_node_or_null("/root/Client")
	var game_state := root.get_node_or_null("/root/GameState")
	if server == null or client == null or game_state == null:
		_expect(false, "death integration autoloads are available")
		_finish()
		return
	server.call("_clear_runtime_session")
	client.call("reset_session")
	game_state.call("reset_session")
	server.call("spawn_server_world")
	var player_id: int = game_state.call("try_register_player", 1, 1000, 4)
	server.call(
		"spawn_server_player",
		player_id,
		Vector3(0.0, 3.0, 0.0),
		null,
		load("res://resources/character_loadouts/full_body.tres")
	)
	var player := server.call("get_server_player", player_id) as ServerPlayer
	player.global_position = Vector3(24.0, 3.0, -17.0)
	var original_anchor: Node = player.authoritative_ragdoll_anchor
	player.velocity = Vector3(4.0, 0.0, -1.0)
	player.apply_damage(ServerPlayer.MAX_HEALTH)
	await process_frame
	await physics_frame
	var pending_respawns: Dictionary = server.get(
		"pending_player_respawn_generation_by_player_id"
	)
	_expect(
		player.health <= 0.0
		and player.death_pending
		and player.ragdoll_active
		and (server.get("server_player_corpses_by_id") as Dictionary).is_empty()
		and pending_respawns.has(player_id),
		"lethal damage holds the physical death instead of respawning in the same frame"
	)
	await create_timer(
		float(server.call("get_player_death_hold_seconds")) + 0.15
	).timeout
	await process_frame
	await physics_frame
	var corpses: Dictionary = server.get("server_player_corpses_by_id")
	var corpse_record: Dictionary = corpses.get(0, {})
	var corpse_anchor := corpse_record.get("anchor") as PlayerRagdollAnchor3D
	_expect(
		player.health == ServerPlayer.MAX_HEALTH
		and not player.death_pending
		and not player.ragdoll_active
		and player.authoritative_ragdoll_anchor != original_anchor,
		"the completed death hold restores the same playable identity with a fresh body"
	)
	_expect(
		corpse_anchor == original_anchor
		and corpse_anchor.get_parent() == server.get("server_world")
		and corpse_anchor.is_active(),
		"the old authoritative ragdoll remains independently simulated after respawn"
	)
	var client_corpses: Dictionary = client.get("player_corpse_proxies_by_id")
	var corpse_proxy := client_corpses.get(0) as Node
	var corpse_ragdoll: Variant = (
		corpse_proxy.get("ragdoll") if corpse_proxy != null else null
	)
	var live_proxy := (
		(client.get("player_proxys_by_player_id") as Dictionary).get(player_id)
		as PlayerProxy
	)
	var corpse_skin := (
		corpse_ragdoll.call("get_authored_skin") as PlayerCharacterSkin
		if corpse_ragdoll != null
		else null
	)
	_expect(
		corpse_proxy != null
		and corpse_ragdoll != null
		and bool(corpse_ragdoll.call("is_active"))
		and bool(corpse_ragdoll.call("has_authored_skin")),
		"listen-host presentation receives the persistent authored corpse through the network contract"
	)
	_expect(
		corpse_skin != null
		and live_proxy != null
		and corpse_skin != live_proxy.character_skin
		and corpse_skin.model_root != live_proxy.character_skin.model_root
		and corpse_skin.skeleton != live_proxy.character_skin.skeleton,
		"corpse presentation owns an independent scene, skeleton, and skin instead of aliasing the respawned player"
	)
	for _frame: int in range(30):
		await physics_frame
		await process_frame
	corpse_record = corpses.get(0, {})
	corpse_anchor = corpse_record.get("anchor") as PlayerRagdollAnchor3D
	corpse_proxy = (client.get("player_corpse_proxies_by_id") as Dictionary).get(0) as Node
	corpse_ragdoll = corpse_proxy.get("ragdoll") if corpse_proxy != null else null
	_expect(
		corpse_anchor != null
		and corpse_anchor.is_active()
		and corpse_anchor.get_player_reference_position().distance_to(player.global_position) > 8.0
		and corpse_proxy != null
		and corpse_ragdoll != null
		and bool(corpse_ragdoll.call("is_active"))
		and (
			corpse_ragdoll.call("get_torso_world_position") as Vector3
		).distance_to(player.global_position) > 8.0,
		"corpse authority and presentation remain at the death site after later respawn snapshots"
	)
	corpse_record["expires_msec"] = 0
	corpses[0] = corpse_record
	server.call("_expire_player_corpses")
	client.call("on_player_corpse_states_received", {})
	await process_frame
	_expect(
		(server.get("server_player_corpses_by_id") as Dictionary).is_empty()
		and (client.get("player_corpse_proxies_by_id") as Dictionary).is_empty(),
		"corpse expiration removes both authoritative physics and client presentation"
	)
	server.call("_clear_runtime_session")
	client.call("reset_session")
	game_state.call("reset_session")
	_finish()


func _expect(condition: bool, description: String) -> void:
	assertion_count += 1
	if condition:
		print("PASS: ", description)
		return
	failure_count += 1
	push_error("FAIL: " + description)


func _finish() -> void:
	if failure_count == 0:
		print("Player death/respawn tests passed: %d assertions" % assertion_count)
		quit(0)
	else:
		push_error(
			"Player death/respawn tests failed: %d/%d assertions"
			% [failure_count, assertion_count]
		)
		quit(1)
