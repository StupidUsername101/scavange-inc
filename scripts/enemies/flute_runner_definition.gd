@tool
class_name FluteRunnerDefinition
extends Resource

## Configuration for the first reusable expressive humanoid enemy. The authority consumes this
## resource; clients receive only compact state and derive the visible pose locally.

@export_group("Awareness")
@export_range(1.0, 120.0, 0.5, "or_greater") var sight_range := 34.0
@export_range(1.0, 120.0, 0.5, "or_greater") var hearing_range := 19.0
@export_range(0.02, 1.0, 0.01) var sense_interval_seconds := 0.12
@export_range(0.0, 20.0, 0.1) var visible_memory_seconds := 3.4
@export_range(0.0, 20.0, 0.1) var heard_memory_seconds := 1.8
@export_range(0.0, 30.0, 0.1) var search_seconds := 5.5

@export_group("Locomotion")
@export_range(0.0, 20.0, 0.1) var curious_speed := 3.2
@export_range(0.0, 20.0, 0.1) var pursuit_speed := 6.6
@export_range(0.0, 30.0, 0.1) var chase_speed := 10.8
@export_range(0.0, 30.0, 0.1) var acceleration := 20.0
@export_range(0.0, 30.0, 0.1) var braking_acceleration := 13.0
@export_range(0.0, 30.0, 0.1) var turn_speed_radians := 8.5
@export_range(0.0, 20.0, 0.1) var chase_distance := 10.5
@export_range(0.1, 10.0, 0.1) var preferred_distance := 1.15
@export_range(1.0, 200.0, 0.5) var roam_radius := 38.0
@export_range(0.1, 10.0, 0.1) var stuck_seconds := 0.72
@export_range(0.1, 4.0, 0.05) var fumble_seconds := 0.62

@export_group("Physical Tackle")
@export_range(0.0, 100.0, 0.5) var tackle_damage := 18.0
@export_range(0.0, 30.0, 0.1) var tackle_minimum_speed := 6.2
@export_range(-1.0, 1.0, 0.01) var tackle_minimum_facing_dot := 0.56
@export_range(0.0, 10.0, 0.1) var tackle_cooldown_seconds := 1.35
@export_range(0.0, 30.0, 0.1) var tackle_impulse := 8.4

@export_group("Flute Program")
@export var flute_program_enabled := true
@export var flute_pose_enabled := true
@export_file("*.wav", "*.ogg", "*.mp3") var flute_song_path := (
	"res://assets/sounds/music/gameplay/flute_runner_loop.wav"
)
@export_range(-80.0, 18.0, 0.5) var flute_output_level_db := -15.0
@export_range(1.0, 500.0, 1.0) var flute_hearing_distance := 74.0
@export_range(0.0, 1.0, 0.01) var flute_priority := 0.64
@export var flute_source_modifier: AcousticPathModifier

@export_group("Captured Voice Mimic")
@export var captured_voice_mimic_enabled := true
@export_range(1.0, 120.0, 0.5) var mimic_interval_min_seconds := 9.0
@export_range(1.0, 120.0, 0.5) var mimic_interval_max_seconds := 17.0
@export_range(0.1, 30.0, 0.1) var mimic_unavailable_retry_seconds := 1.5
