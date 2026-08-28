class_name CriticallyDampedVector3
extends RefCounted

## Exact critically damped spring state for a moving Vector3 target. Instances are allocated once
## and reused; advance() is stable across frame rates and creates no temporary containers.

var value := Vector3.ZERO
var velocity := Vector3.ZERO


func snap(next_value: Vector3) -> void:
	value = next_value if next_value.is_finite() else Vector3.ZERO
	velocity = Vector3.ZERO


func advance(target: Vector3, delta: float, frequency_hz: float) -> Vector3:
	if delta <= 0.0:
		return value
	var safe_target := target if target.is_finite() else Vector3.ZERO
	var angular_frequency := TAU * maxf(frequency_hz, 0.001)
	var decay := exp(-angular_frequency * delta)
	var error := value - safe_target
	var step := (velocity + error * angular_frequency) * delta
	value = safe_target + (error + step) * decay
	velocity = (velocity - step * angular_frequency) * decay
	return value
