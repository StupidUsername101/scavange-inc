class_name GameAudioLibrary
extends Node

## Registers the curated one-shot game sounds once per client world. Playback stays allocation-free:
## the existing SpatialAudioRenderer owns a fixed voice/DSP pool and chooses variations in-place.

const MOUTH_CLICK_AUDIO := preload(
	"res://scripts/audio/mouth_click_audio_catalog.gd"
)

const SURFACE_SPECS: Array[Dictionary] = [
	{
		"surface": &"concrete",
		"footstep_streams": [
			preload("res://assets/third_party/pizza_doggy/audio/rust_and_blood/footstep_concrete_1.ogg"),
			preload("res://assets/third_party/pizza_doggy/audio/rust_and_blood/footstep_concrete_2.ogg"),
			preload("res://assets/third_party/pizza_doggy/audio/rust_and_blood/footstep_concrete_3.ogg"),
			preload("res://assets/third_party/pizza_doggy/audio/rust_and_blood/footstep_concrete_4.ogg"),
		],
		"footstep_volume_db": -5.0,
	},
	{
		"surface": &"metal",
		"footstep_streams": [
			preload("res://assets/third_party/pizza_doggy/audio/rust_and_blood/footstep_metal_1.ogg"),
			preload("res://assets/third_party/pizza_doggy/audio/rust_and_blood/footstep_metal_2.ogg"),
			preload("res://assets/third_party/pizza_doggy/audio/rust_and_blood/footstep_metal_3.ogg"),
			preload("res://assets/third_party/pizza_doggy/audio/rust_and_blood/footstep_metal_4.ogg"),
		],
		"footstep_volume_db": -6.0,
	},
	{
		"surface": &"wood",
		"footstep_streams": [
			preload("res://assets/third_party/pizza_doggy/audio/rust_and_blood/footstep_wood_1.ogg"),
			preload("res://assets/third_party/pizza_doggy/audio/rust_and_blood/footstep_wood_2.ogg"),
			preload("res://assets/third_party/pizza_doggy/audio/rust_and_blood/footstep_wood_3.ogg"),
			preload("res://assets/third_party/pizza_doggy/audio/rust_and_blood/footstep_wood_4.ogg"),
		],
		"footstep_volume_db": -5.5,
	},
	{
		"surface": &"stone",
		"footstep_streams": [
			preload("res://assets/third_party/pizza_doggy/audio/rust_and_blood/footstep_stone_1.ogg"),
			preload("res://assets/third_party/pizza_doggy/audio/rust_and_blood/footstep_stone_2.ogg"),
			preload("res://assets/third_party/pizza_doggy/audio/rust_and_blood/footstep_stone_3.ogg"),
			preload("res://assets/third_party/pizza_doggy/audio/rust_and_blood/footstep_stone_4.ogg"),
		],
		"footstep_volume_db": -5.0,
	},
	{
		"surface": &"soil",
		"footstep_streams": [
			preload("res://assets/third_party/pizza_doggy/audio/rust_and_blood/footstep_soil_1.ogg"),
			preload("res://assets/third_party/pizza_doggy/audio/rust_and_blood/footstep_soil_2.ogg"),
			preload("res://assets/third_party/pizza_doggy/audio/rust_and_blood/footstep_soil_3.ogg"),
			preload("res://assets/third_party/pizza_doggy/audio/rust_and_blood/footstep_soil_4.ogg"),
		],
		"footstep_volume_db": -5.0,
	},
]

# Projectile identity selects the recorded excitation. The struck material is applied later by
# PhysicalImpactResponse, so adding ammunition no longer multiplies clips by every material.
const PROJECTILE_IMPACT_SPECS: Array[Dictionary] = [
	{
		"id": &"projectile_impact_generic",
		"streams": [
			preload("res://assets/third_party/pizza_doggy/audio/rust_and_blood/projectile_impacts/projectile_impact_9mm_1.ogg"),
			preload("res://assets/third_party/pizza_doggy/audio/rust_and_blood/projectile_impacts/projectile_impact_9mm_2.ogg"),
			preload("res://assets/third_party/pizza_doggy/audio/rust_and_blood/projectile_impacts/projectile_impact_9mm_3.ogg"),
		],
		"base_volume_db": 1.0,
		"pitch_min": 0.94,
		"pitch_max": 1.04,
	},
	{
		"id": &"projectile_impact_9mm",
		"streams": [
			preload("res://assets/third_party/pizza_doggy/audio/rust_and_blood/projectile_impacts/projectile_impact_9mm_1.ogg"),
			preload("res://assets/third_party/pizza_doggy/audio/rust_and_blood/projectile_impacts/projectile_impact_9mm_2.ogg"),
			preload("res://assets/third_party/pizza_doggy/audio/rust_and_blood/projectile_impacts/projectile_impact_9mm_3.ogg"),
		],
		"base_volume_db": 1.0,
		"pitch_min": 1.02,
		"pitch_max": 1.12,
	},
	{
		"id": &"projectile_impact_556",
		"streams": [
			preload("res://assets/third_party/pizza_doggy/audio/rust_and_blood/projectile_impacts/projectile_impact_556_1.ogg"),
			preload("res://assets/third_party/pizza_doggy/audio/rust_and_blood/projectile_impacts/projectile_impact_556_2.ogg"),
			preload("res://assets/third_party/pizza_doggy/audio/rust_and_blood/projectile_impacts/projectile_impact_556_3.ogg"),
		],
		"base_volume_db": 1.0,
		"pitch_min": 1.15,
		"pitch_max": 1.27,
	},
	{
		"id": &"projectile_impact_nail",
		"streams": [
			preload("res://assets/third_party/pizza_doggy/audio/rust_and_blood/projectile_impacts/projectile_impact_nail_1.ogg"),
			preload("res://assets/third_party/pizza_doggy/audio/rust_and_blood/projectile_impacts/projectile_impact_nail_2.ogg"),
		],
		"base_volume_db": 1.0,
		"pitch_min": 0.94,
		"pitch_max": 1.06,
	},
	{
		"id": &"projectile_impact_coil",
		"streams": [
			preload("res://assets/third_party/pizza_doggy/audio/rust_and_blood/projectile_impacts/projectile_impact_coil_1.ogg"),
			preload("res://assets/third_party/pizza_doggy/audio/rust_and_blood/projectile_impacts/projectile_impact_coil_2.ogg"),
			preload("res://assets/third_party/pizza_doggy/audio/rust_and_blood/projectile_impacts/projectile_impact_coil_3.ogg"),
		],
		"base_volume_db": 1.0,
		"pitch_min": 0.76,
		"pitch_max": 0.86,
	},
]

# Weapon reports live in the same semantic catalog as every other one-shot. Keeping their dry and
# purpose-authored pressure pairs together prevents a world-scene node from silently becoming the
# only registration path. pressure_layer_gain_db compensates recording calibration only; geometry,
# propagation, and reverb still come exclusively from the authoritative acoustic packet.
const WEAPON_REPORT_SPECS: Array[Dictionary] = [
	{
		"id": &"service_pistol_fire",
		"streams": [
			preload("res://assets/sounds/pistol/dry/service_pistol_dry_01.wav"),
			preload("res://assets/sounds/pistol/dry/service_pistol_dry_02.wav"),
			preload("res://assets/sounds/pistol/dry/service_pistol_dry_03.wav"),
			preload("res://assets/sounds/pistol/dry/service_pistol_dry_04.wav"),
		],
		"pressure_streams": [
			preload("res://assets/sounds/pistol/pressure/service_pistol_pressure_01.wav"),
			preload("res://assets/sounds/pistol/pressure/service_pistol_pressure_02.wav"),
			preload("res://assets/sounds/pistol/pressure/service_pistol_pressure_03.wav"),
			preload("res://assets/sounds/pistol/pressure/service_pistol_pressure_04.wav"),
		],
		"base_volume_db": -2.0,
		"pitch_min": 0.99,
		"pitch_max": 1.01,
		"pressure_layer_gain_db": 0.0,
		"foreground_transient_strength": 1.0,
	},
	{
		"id": &"automatic_rifle_fire",
		"streams": [
			preload("res://assets/third_party/pizza_doggy/audio/rust_and_blood/rifle/automatic_rifle_dry_1.ogg"),
			preload("res://assets/third_party/pizza_doggy/audio/rust_and_blood/rifle/automatic_rifle_dry_2.ogg"),
			preload("res://assets/third_party/pizza_doggy/audio/rust_and_blood/rifle/automatic_rifle_dry_3.ogg"),
			preload("res://assets/third_party/pizza_doggy/audio/rust_and_blood/rifle/automatic_rifle_dry_4.ogg"),
		],
		"pressure_streams": [
			preload("res://assets/third_party/pizza_doggy/audio/rust_and_blood/rifle/automatic_rifle_pressure_1.ogg"),
			preload("res://assets/third_party/pizza_doggy/audio/rust_and_blood/rifle/automatic_rifle_pressure_2.ogg"),
			preload("res://assets/third_party/pizza_doggy/audio/rust_and_blood/rifle/automatic_rifle_pressure_3.ogg"),
			preload("res://assets/third_party/pizza_doggy/audio/rust_and_blood/rifle/automatic_rifle_pressure_4.ogg"),
		],
		"base_volume_db": -1.0,
		"pitch_min": 0.985,
		"pitch_max": 1.015,
		# The source bundle's pressure take peaks roughly 5.6 dB below the pistol layer.
		"pressure_layer_gain_db": 5.5,
		"foreground_transient_strength": 1.0,
	},
]

const SOUND_SPECS: Array[Dictionary] = [
	{
		"id": &"rifle_reload_out",
		"streams": [preload("res://assets/third_party/pizza_doggy/audio/rust_and_blood/rifle/rifle_reload_out_1.ogg")],
		"base_volume_db": -4.0,
		"pitch_min": 0.98,
		"pitch_max": 1.02,
	},
	{
		"id": &"rifle_reload_in",
		"streams": [preload("res://assets/third_party/pizza_doggy/audio/rust_and_blood/rifle/rifle_reload_in_1.ogg")],
		"base_volume_db": -4.0,
		"pitch_min": 0.98,
		"pitch_max": 1.02,
	},
	{
		"id": &"pistol_reload_out",
		"streams": [preload("res://assets/third_party/pizza_doggy/audio/rust_and_blood/pistol_reload_out_1.ogg")],
		"base_volume_db": -5.0,
		"pitch_min": 0.98,
		"pitch_max": 1.02,
	},
	{
		"id": &"pistol_reload_in",
		"streams": [preload("res://assets/third_party/pizza_doggy/audio/rust_and_blood/pistol_reload_in_1.ogg")],
		"base_volume_db": -5.0,
		"pitch_min": 0.98,
		"pitch_max": 1.02,
	},
	{
		"id": &"item_pickup",
		"streams": [preload("res://assets/third_party/pizza_doggy/audio/rust_and_blood/item_pickup_1.ogg")],
		"base_volume_db": -6.0,
		"pitch_min": 0.98,
		"pitch_max": 1.02,
	},
	{
		"id": &"item_equip",
		"streams": [preload("res://assets/third_party/pizza_doggy/audio/rust_and_blood/item_equip_1.ogg")],
		"base_volume_db": -6.0,
		"pitch_min": 0.98,
		"pitch_max": 1.02,
	},
	{
		"id": &"industrial_button",
		"streams": [preload("res://assets/third_party/pizza_doggy/audio/echoes/industrial_button_1.ogg")],
		"base_volume_db": -4.0,
		"pitch_min": 0.99,
		"pitch_max": 1.01,
	},
	{
		"id": &"fieldlink_open",
		"streams": [preload("res://assets/third_party/pizza_doggy/audio/fieldlink/fieldlink_open.ogg")],
		"base_volume_db": 2.0,
		"pitch_min": 0.98,
		"pitch_max": 1.02,
		# The recording contains a quiet lead-in. Start at its physical onset so
		# the pull-out cue responds with the animation instead of trailing it.
		"start_offset_seconds": 0.04,
	},
	{
		"id": &"fieldlink_close",
		"streams": [preload("res://assets/third_party/pizza_doggy/audio/fieldlink/fieldlink_close.ogg")],
		"base_volume_db": 2.0,
		"pitch_min": 0.94,
		"pitch_max": 0.98,
		"start_offset_seconds": 0.075,
	},
	{
		"id": &"fieldlink_hover",
		"streams": [preload("res://assets/third_party/pizza_doggy/audio/fieldlink/fieldlink_hover.ogg")],
		"base_volume_db": 5.0,
		"pitch_min": 0.97,
		"pitch_max": 1.03,
	},
	{
		"id": &"fieldlink_click",
		"streams": [preload("res://assets/third_party/pizza_doggy/audio/fieldlink/fieldlink_click.ogg")],
		"base_volume_db": 0.0,
		"pitch_min": 0.97,
		"pitch_max": 1.0,
	},
	{
		"id": &"fieldlink_confirm",
		"streams": [preload("res://assets/third_party/pizza_doggy/audio/fieldlink/fieldlink_confirm.ogg")],
		"base_volume_db": -5.0,
		"pitch_min": 0.98,
		"pitch_max": 1.02,
	},
	{
		"id": &"fieldlink_warning",
		"streams": [preload("res://assets/third_party/pizza_doggy/audio/fieldlink/fieldlink_warning.ogg")],
		"base_volume_db": -3.0,
		"pitch_min": 0.92,
		"pitch_max": 0.96,
	},
]

var _owner_token := 0


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	var client := get_node_or_null("/root/Client")
	if client == null:
		return
	_owner_token = get_instance_id()
	for surface_spec: Dictionary in SURFACE_SPECS:
		var footstep_streams: Array[AudioStream] = []
		footstep_streams.assign(surface_spec.get("footstep_streams", []))
		var surface := str(surface_spec.get("surface", &"concrete"))
		_register(
			client,
			StringName("footstep_%s" % surface),
			footstep_streams,
			float(surface_spec.get("footstep_volume_db", -5.0)),
			0.96,
			1.04,
			0.0,
			0.78
		)
		_register(
			client,
			StringName("jump_%s" % surface),
			footstep_streams,
			-4.0,
			1.06,
			1.13,
			0.0,
			0.58
		)
		_register(
			client,
			StringName("landing_%s" % surface),
			footstep_streams,
			-2.0,
			0.88,
			0.96,
			0.0,
			0.88
		)
	for spec: Dictionary in WEAPON_REPORT_SPECS:
		var streams: Array[AudioStream] = []
		streams.assign(spec.get("streams", []))
		var pressure_streams: Array[AudioStream] = []
		pressure_streams.assign(spec.get("pressure_streams", []))
		_register(
			client,
			spec.get("id", &""),
			streams,
			float(spec.get("base_volume_db", 0.0)),
			float(spec.get("pitch_min", 0.97)),
			float(spec.get("pitch_max", 1.03)),
			0.0,
			float(spec.get("foreground_transient_strength", 1.0)),
			pressure_streams,
			float(spec.get("pressure_layer_gain_db", 0.0))
		)
	for spec: Dictionary in PROJECTILE_IMPACT_SPECS:
		var streams: Array[AudioStream] = []
		streams.assign(spec.get("streams", []))
		_register(
			client,
			spec.get("id", &""),
			streams,
			float(spec.get("base_volume_db", 0.0)),
			float(spec.get("pitch_min", 0.97)),
			float(spec.get("pitch_max", 1.03))
		)
	for spec: Dictionary in SOUND_SPECS:
		var streams: Array[AudioStream] = []
		streams.assign(spec.get("streams", []))
		_register(
			client,
			spec.get("id", &""),
			streams,
			float(spec.get("base_volume_db", 0.0)),
			float(spec.get("pitch_min", 0.97)),
			float(spec.get("pitch_max", 1.03)),
			float(spec.get("start_offset_seconds", 0.0))
		)
	_register(
		client,
		&"mouth_click",
		MOUTH_CLICK_AUDIO.streams(),
		-1.0,
		0.97,
		1.04,
		0.0,
		0.42
	)


func _register(
	client: Node,
	sound_id: StringName,
	streams: Array[AudioStream],
	base_volume_db: float,
	pitch_min: float,
	pitch_max: float,
	start_offset_seconds := 0.0,
	foreground_transient_strength := 0.0,
	pressure_streams: Array[AudioStream] = [],
	pressure_layer_gain_db := 0.0
) -> void:
	client.call(
		"register_spatial_sound",
		sound_id,
		streams,
		{
			"base_volume_db": base_volume_db,
			"pitch_min": pitch_min,
			"pitch_max": pitch_max,
			"start_offset_seconds": start_offset_seconds,
			"foreground_transient_strength": foreground_transient_strength,
			"pressure_streams": pressure_streams,
			"pressure_layer_gain_db": pressure_layer_gain_db,
		},
		_owner_token
	)


func _exit_tree() -> void:
	if Engine.is_editor_hint() or _owner_token == 0:
		return
	var client := get_node_or_null("/root/Client")
	if client == null:
		return
	for sound_id: StringName in registered_sound_ids():
		client.call(
			"unregister_spatial_sound",
			sound_id,
			_owner_token
		)


static func registered_sound_ids() -> Array[StringName]:
	var result: Array[StringName] = [&"mouth_click"]
	for surface_spec: Dictionary in SURFACE_SPECS:
		var surface := str(surface_spec.get("surface", &"concrete"))
		result.append(StringName("footstep_%s" % surface))
		result.append(StringName("jump_%s" % surface))
		result.append(StringName("landing_%s" % surface))
	for spec: Dictionary in WEAPON_REPORT_SPECS:
		result.append(spec.get("id", &""))
	for spec: Dictionary in PROJECTILE_IMPACT_SPECS:
		result.append(spec.get("id", &""))
	for spec: Dictionary in SOUND_SPECS:
		result.append(spec.get("id", &""))
	return result
