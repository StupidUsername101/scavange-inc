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
		SafeVariant.bool_or(0.000000001, false),
		"compatibility bool treats every finite nonzero float as true instead of approximately zero"
	)
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
	_expect(
		SafeVariant.vector2_strict_or("broken", Vector2(2.0, 3.0)) == Vector2(2.0, 3.0),
		"strict Vector2 decoding rejects wrong-type public state"
	)
	_expect(
		SafeVariant.color_strict_or(Color(NAN, 0.0, 0.0), Color.WHITE) == Color.WHITE,
		"strict Color decoding rejects non-finite public state"
	)
	var fallback_transform: Transform3D = Transform3D(Basis.IDENTITY, Vector3(9.0, 8.0, 7.0))
	var valid_transform: Transform3D = Transform3D(Basis.IDENTITY, Vector3(1.0, 2.0, 3.0))
	var invalid_transform: Transform3D = Transform3D(
		Basis.IDENTITY,
		Vector3(NAN, 0.0, 0.0)
	)
	_expect(
		SafeVariant.transform3d_strict_or(valid_transform, fallback_transform) == valid_transform,
		"strict Transform3D decoding preserves finite transforms"
	)
	_expect(
		SafeVariant.transform3d_strict_or(invalid_transform, fallback_transform) == fallback_transform,
		"strict Transform3D decoding rejects non-finite transforms"
	)
	_expect(
		SafeVariant.transform3d_strict_or("broken", fallback_transform) == fallback_transform,
		"strict Transform3D decoding rejects wrong-type public state"
	)
	var safe_points: PackedVector3Array = PackedVector3Array([Vector3.ONE, Vector3(2.0, 3.0, 4.0)])
	var bad_points: PackedVector3Array = PackedVector3Array([Vector3.ONE, Vector3(NAN, 0.0, 0.0)])
	_expect(
		SafeVariant.packed_vector3_array_strict_or(safe_points, PackedVector3Array()).size() == 2,
		"strict PackedVector3Array decoding preserves finite rope state"
	)
	_expect(
		SafeVariant.packed_vector3_array_strict_or(bad_points, PackedVector3Array()).is_empty(),
		"strict PackedVector3Array decoding rejects non-finite rope points"
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

	var array_source: Array = [{"value": 1}, 2]
	var array_copy: Array = SafeVariant.array_copy(array_source)
	(array_copy[0] as Dictionary)["value"] = 9
	_expect(
		int((array_source[0] as Dictionary).get("value", 0)) == 1,
		"array_copy is deep by default"
	)
	_expect(
		SafeVariant.array_copy("not an array").is_empty(),
		"wrong-type array values fail closed"
	)

	var dictionary_array_source: Array = [{"value": 1}, "skip", {"value": 2}]
	var dictionary_array: Array[Dictionary] = SafeVariant.dictionary_array_copy(
		dictionary_array_source
	)
	_expect(
		dictionary_array.size() == 2
		and int(dictionary_array[0].get("value", 0)) == 1
		and int(dictionary_array[1].get("value", 0)) == 2,
		"dictionary-array decoding filters wrong-type entries consistently"
	)
	dictionary_array[0]["value"] = 99
	_expect(
		int((dictionary_array_source[0] as Dictionary).get("value", 0)) == 1,
		"dictionary-array decoding deep-copies accepted records by default"
	)

	quit(0 if failure_count == 0 else 1)


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("[PASS] %s" % label)
		return
	failure_count += 1
	push_error("[FAIL] %s" % label)
