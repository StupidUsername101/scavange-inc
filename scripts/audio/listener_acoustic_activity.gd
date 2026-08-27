class_name ListenerAcousticActivity
extends RefCounted

## One normalized, listener-side measure for non-audio consumers. Inputs must already contain the
## server's distance, obstruction, room, and source-level response. Continuous audio uses its pooled
## analyzer so musical silence stays quiet; short events use their received playback level.

const RECEIVED_LEVEL_RANGE_DB := Vector2(-30.0, -2.0)
const SPECTRUM_AMPLITUDE_RANGE := Vector2(0.012, 0.16)


static func from_received_volume_db(received_volume_db: float) -> float:
	var level_db := clampf(
		received_volume_db if is_finite(received_volume_db) else -80.0,
		-80.0,
		18.0
	)
	return pow(
		smoothstep(
			RECEIVED_LEVEL_RANGE_DB.x,
			RECEIVED_LEVEL_RANGE_DB.y,
			level_db
		),
		1.25
	)


static func from_spectrum(
	bass_magnitude: Vector2,
	body_magnitude: Vector2,
	brilliance_magnitude: Vector2
) -> float:
	var bass := maxf(absf(bass_magnitude.x), absf(bass_magnitude.y)) * 1.15
	var body := maxf(absf(body_magnitude.x), absf(body_magnitude.y))
	var brilliance := (
		maxf(absf(brilliance_magnitude.x), absf(brilliance_magnitude.y))
		* 0.70
	)
	return pow(
		smoothstep(
			SPECTRUM_AMPLITUDE_RANGE.x,
			SPECTRUM_AMPLITUDE_RANGE.y,
			maxf(bass, maxf(body, brilliance))
		),
		1.1
	)


static func combine_energy(left: float, right: float) -> float:
	var safe_left := clampf(left, 0.0, 1.0)
	var safe_right := clampf(right, 0.0, 1.0)
	return minf(sqrt(safe_left * safe_left + safe_right * safe_right), 1.0)


static func follow(
	current: float,
	target: float,
	delta: float,
	attack_speed: float,
	release_speed: float
) -> float:
	var bounded_current := clampf(current, 0.0, 1.0)
	var bounded_target := clampf(target, 0.0, 1.0)
	var speed := attack_speed if bounded_target > bounded_current else release_speed
	return lerpf(
		bounded_current,
		bounded_target,
		1.0 - exp(-maxf(speed, 0.0) * maxf(delta, 0.0))
	)
