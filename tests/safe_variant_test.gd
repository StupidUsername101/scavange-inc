extends SceneTree

#######################################################
# Regression coverage for shared persisted-Variant decoding. The strict and compatibility helpers
# intentionally preserve the different legacy rules of the resources they replaced.
#######################################################

var failure_count: int = 0


func _init() -> void:
	_expect(SafeVariant.finite_float_or(2.5, 9.0) == 2.5, "finite floats are preserved")
	_expect(SafeVariant.finite_float_or(NAN, 9.0) == 9.0, "NaN falls back")
	_expect(SafeVariant.finite_int_or(INF, 7) == 7, "infinite integers fall back")
	_expect(
		SafeVariant.finite_int_or(2.75, 9) == 2,
		"compatibility integers retain legacy finite-float truncation"
	)
	_expect(
		SafeVariant.integral_int_or(2.0, 9) == 2,
		"integral decoder accepts integer-valued floats"
	)
	_expect(
		SafeVariant.integral_int_or(2.75, 9) == 9,
		"integral decoder rejects fractional identity values"
	)
	_expect(
		SafeVariant.integral_int_or(1000000000000.5, 9) == 9,
		"integral decoder does not approximate large fractional identities into integers"
	)

	_expect(SafeVariant.bool_or(1, false), "compatibility bool accepts legacy integer one")
	_expect(not SafeVariant.bool_or(0, true), "compatibility bool accepts legacy integer zero")
	_expect(
		SafeVariant.strict_bool_or(1, true),
		"strict bool rejects numeric values and keeps its fallback"
	)
	_expect(
		not SafeVariant.strict_bool_or(1, false),
		"strict bool never coerces numeric values"
	)

	var fallback: Vector3 = Vector3(10.0, 20.0, 30.0)
	_expect(
		SafeVariant.vector3_or([1.0, NAN, 3.0], fallback) == Vector3(1.0, 20.0, 3.0),
		"component-fallback vectors preserve valid axes"
	)
	_expect(
		SafeVariant.vector3_strict_or([1.0, NAN, 3.0], fallback) == fallback,
		"strict vectors reject the whole malformed record"
	)
	_expect(
		SafeVariant.vector3_or({"x": 1.0, "y": 2.0, "z": 3.0}, fallback) == fallback,
		"component-fallback vectors preserve the old Vector3/Array-only input contract"
	)
	_expect(
		SafeVariant.vector3_strict_or(
			{"x": 1.0, "y": 2.0, "z": 3.0},
			fallback
		) == Vector3(1.0, 2.0, 3.0),
		"strict vector decoding retains dictionary support where legacy callers had it"
	)

	var source: Dictionary = {"nested": {"value": 3}}
	var copied: Dictionary = SafeVariant.dictionary_copy(source)
	var nested_copy: Dictionary = copied["nested"] as Dictionary
	nested_copy["value"] = 9
	var original_nested: Dictionary = source["nested"] as Dictionary
	_expect(
		int(original_nested["value"]) == 3,
		"dictionary_copy is deep by default"
	)
	_expect(
		SafeVariant.dictionary_copy("not a dictionary").is_empty(),
		"wrong-type dictionary values fail closed"
	)

	quit(0 if failure_count == 0 else 1)


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("[PASS] %s" % label)
		return
	failure_count += 1
	push_error("[FAIL] %s" % label)
