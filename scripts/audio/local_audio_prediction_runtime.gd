class_name LocalAudioPredictionRuntime
extends RefCounted

const LOCAL_AUDIO_PREDICTION := preload(
	"res://scripts/audio/local_audio_prediction.gd"
)

## Per-client owner-prediction state. The static LocalAudioPrediction class owns the packet/key
## contract; this runtime owns only replaceable listener context and short-lived action sessions.

var _context: Dictionary = {}
var _next_sequence := 0
var _primary_session := 0
var _primary_shot_index := 0
var _primary_seconds_until_shot := 0.0
var _primary_remaining_rounds := 0
var _primary_profile: Dictionary = {}


func reset() -> void:
	_context.clear()
	_next_sequence = 0
	stop_primary()


func apply_context(context_value: Dictionary) -> bool:
	var context := LOCAL_AUDIO_PREDICTION.sanitize_context(context_value)
	if context.is_empty():
		return false
	_context = context
	return true


func predict(
	renderer: SpatialAudioRenderer,
	sound_id: StringName,
	source_position: Vector3,
	profile_value: Dictionary = {},
	prediction_key := 0
) -> int:
	if (
		not LOCAL_AUDIO_PREDICTION.ENABLED
		or renderer == null
		or sound_id.is_empty()
		or not source_position.is_finite()
	):
		return 0
	var profile := (
		profile_value
		if not profile_value.is_empty()
		else LOCAL_AUDIO_PREDICTION.player_cue_profile(sound_id)
	)
	if profile.is_empty():
		return 0
	var key := LOCAL_AUDIO_PREDICTION.sanitize_key(prediction_key)
	if key == 0:
		key = _allocate_sequence_key()
	var max_distance := clampf(
		SafeVariant.finite_float_or(profile.get("max_distance"), 24.0),
		0.1,
		10000.0
	)
	var volume_db := clampf(
		SafeVariant.finite_float_or(profile.get("volume_db"), 0.0),
		-80.0,
		18.0
	)
	var priority := clampf(
		SafeVariant.finite_float_or(profile.get("priority"), 0.5),
		0.0,
		1.0
	)
	var pressure_strength := LOCAL_AUDIO_PREDICTION.resolve_pressure_strength(
		SafeVariant.finite_float_or(profile.get("pressure_strength"), -1.0),
		max_distance,
		volume_db,
		priority
	)
	# Owner feedback must never wait for the replaceable server context. Before its first arrival,
	# build_packet deliberately produces a dry free-field packet; subsequent actions reuse the
	# latest authoritative room/path snapshot. Acceptance and duplicate suppression remain server
	# authoritative in both cases.
	var packet := LOCAL_AUDIO_PREDICTION.build_packet(
		_context,
		sound_id,
		source_position,
		volume_db,
		priority,
		key,
		pressure_strength
	)
	if packet.is_empty():
		return 0
	return key if renderer.submit_predicted(packet) else 0


func begin_primary(
	renderer: SpatialAudioRenderer,
	local_proxy: PlayerProxy
) -> int:
	stop_primary()
	if renderer == null or local_proxy == null:
		return 0
	var profile := local_proxy.get_weapon_audio_prediction_profile()
	if profile.is_empty():
		return 0
	_primary_session = (
		(_next_sequence % LOCAL_AUDIO_PREDICTION.WEAPON_MAX_SESSION) + 1
	)
	_next_sequence = _primary_session
	_primary_profile = profile
	_primary_shot_index = 0
	_primary_remaining_rounds = int(profile.get("available_rounds", 0))
	_predict_primary_shot(renderer, local_proxy)
	_primary_seconds_until_shot = (
		1.0 / maxf(float(profile.get("rounds_per_second", 1.0)), 0.1)
	)
	return _primary_session


func update_primary(
	renderer: SpatialAudioRenderer,
	delta: float,
	local_proxy: PlayerProxy
) -> void:
	if (
		_primary_session <= 0
		or renderer == null
		or local_proxy == null
		or not bool(_primary_profile.get("automatic", false))
		or _primary_remaining_rounds <= 0
	):
		return
	var interval := (
		1.0
		/ maxf(
			float(_primary_profile.get("rounds_per_second", 1.0)),
			0.1
		)
	)
	_primary_seconds_until_shot -= maxf(delta, 0.0)
	var catchup_count := 0
	while (
		_primary_seconds_until_shot <= 0.0
		and _primary_remaining_rounds > 0
		and catchup_count < 4
	):
		_predict_primary_shot(renderer, local_proxy)
		_primary_seconds_until_shot += interval
		catchup_count += 1


func primary_session() -> int:
	return _primary_session


func stop_primary() -> void:
	_primary_session = 0
	_primary_shot_index = 0
	_primary_seconds_until_shot = 0.0
	_primary_remaining_rounds = 0
	_primary_profile.clear()


func _predict_primary_shot(
	renderer: SpatialAudioRenderer,
	local_proxy: PlayerProxy
) -> void:
	if _primary_remaining_rounds <= 0:
		return
	var sound_id := StringName(str(_primary_profile.get("sound_id", "")))
	if sound_id.is_empty():
		return
	var prediction_key := LOCAL_AUDIO_PREDICTION.weapon_shot_key(
		_primary_session,
		_primary_shot_index
	)
	predict(
		renderer,
		sound_id,
		local_proxy.get_weapon_sound_source_position(),
		_primary_profile,
		prediction_key
	)
	_primary_shot_index += 1
	_primary_remaining_rounds -= mini(
		maxi(int(_primary_profile.get("rounds_per_trigger", 1)), 1),
		_primary_remaining_rounds
	)


func _allocate_sequence_key() -> int:
	_next_sequence = (_next_sequence % LOCAL_AUDIO_PREDICTION.MAX_SEQUENCE) + 1
	return LOCAL_AUDIO_PREDICTION.sequence_key(_next_sequence)
