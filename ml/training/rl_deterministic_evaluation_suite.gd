class_name RLDeterministicEvaluationSuite
extends RefCounted

#######################################################
# Body-agnostic fixed-seed evaluation plan and record validator. Simulation rooms execute
# these descriptors with a frozen candidate and submit raw records; promotion code accepts
# only a complete plan, never one lucky training episode or a partial evaluator run.
#######################################################

const SUITE_SCHEMA_VERSION = 2
const SEEDS_PER_SCENARIO = 5
const DEFAULT_SEED_BASE = 173205080
const DEFAULT_CASE_DURATION_SECONDS = 8.0


static func default_plan(body_kind: String, seed_base: int = DEFAULT_SEED_BASE) -> Dictionary:
	return _build_plan(body_kind, [], "", seed_base, false, false)


static func plan_for_contract(
	body_kind: String,
	evaluation_contract: Dictionary,
	seed_base: int = DEFAULT_SEED_BASE
) -> Dictionary:
	var contract_hash: String = str(evaluation_contract.get("contract_hash", ""))
	var active_target_kinds: Array[String] = []
	var item_pickup_enabled: bool = false
	var item_delivery_enabled: bool = false
	if RLEvaluationContract.is_valid(evaluation_contract, body_kind):
		var environment: Dictionary = evaluation_contract.get("environment", {})
		var active_target_kinds_value: Variant = environment.get("active_target_kinds", [])
		if not (active_target_kinds_value is Array):
			active_target_kinds_value = []
		for value: Variant in active_target_kinds_value:
			var target_kind: String = str(value).strip_edges()
			if (
				not target_kind.is_empty()
				and target_kind != "navigation"
				and target_kind != "fallback"
				and not active_target_kinds.has(target_kind)
			):
				active_target_kinds.append(target_kind)
		if body_kind == "four_limb":
			var reward_cards_value: Variant = environment.get("reward_cards", {})
			if reward_cards_value is Dictionary:
				var pickup_card_value: Variant = (reward_cards_value as Dictionary).get("item_pickup", {})
				if pickup_card_value is Dictionary:
					var pickup_card: Dictionary = pickup_card_value as Dictionary
					item_pickup_enabled = (
						RLTrainingMath.bool_or(pickup_card.get("enabled", false), false)
						and RLTrainingMath.finite_float_or(pickup_card.get("intensity", 0.0), 0.0) > 0.0
					)
				var delivery_card_value: Variant = (reward_cards_value as Dictionary).get("item_delivery", {})
				if delivery_card_value is Dictionary:
					var delivery_card: Dictionary = delivery_card_value as Dictionary
					item_delivery_enabled = (
						RLTrainingMath.bool_or(delivery_card.get("enabled", false), false)
						and RLTrainingMath.finite_float_or(delivery_card.get("intensity", 0.0), 0.0) > 0.0
					)
	active_target_kinds.sort()
	return _build_plan(
		body_kind,
		active_target_kinds,
		contract_hash,
		seed_base,
		item_pickup_enabled,
		item_delivery_enabled
	)


static func _build_plan(
	body_kind: String,
	active_target_kinds: Array[String],
	contract_hash: String,
	seed_base: int,
	item_pickup_enabled: bool,
	item_delivery_enabled: bool
) -> Dictionary:
	var scenarios: Array[String] = _scenario_ids(body_kind)
	if body_kind == "four_limb" and item_pickup_enabled:
		scenarios.append("item_pickup")
	if body_kind == "four_limb" and item_delivery_enabled:
		scenarios.append("item_delivery")
	if body_kind == "drone" or body_kind == "four_limb":
		for target_kind: String in active_target_kinds:
			scenarios.append("routed_target__%s" % target_kind)
	var cases: Array[Dictionary] = []
	for scenario_index in range(scenarios.size()):
		for seed_offset in range(SEEDS_PER_SCENARIO):
			cases.append({
				"scenario_id": scenarios[scenario_index],
				"seed": seed_base + scenario_index * 1009 + seed_offset * 37,
				"deterministic_policy": true,
				"duration_seconds": _scenario_duration_seconds(
					body_kind,
					scenarios[scenario_index]
				),
			})
	var plan: Dictionary = {
		"schema_version": SUITE_SCHEMA_VERSION,
		"body_kind": body_kind,
		"seed_base": seed_base,
		"seeds_per_scenario": SEEDS_PER_SCENARIO,
		"scenario_ids": scenarios,
		"cases": cases,
		"evaluation_contract_hash": contract_hash,
	}
	plan["suite_hash"] = JSON.stringify(plan, "", true, true).sha256_text()
	return plan


static func aggregate_complete_suite(
	plan: Dictionary,
	records: Array[Dictionary],
	candidate_hash: String
) -> Dictionary:
	if not _valid_plan(plan) or candidate_hash.is_empty():
		return {}
	var expected_contract_hash: String = str(plan.get("evaluation_contract_hash", ""))
	var expected: Dictionary = {}
	for case_value in plan.get("cases", []):
		if not (case_value is Dictionary):
			return {}
		var case: Dictionary = case_value
		var case_seed: int = RLTrainingMath.finite_int_or(case.get("seed", 0), -2147483648)
		var case_duration: float = RLTrainingMath.finite_float_or(
			case.get("duration_seconds", NAN),
			NAN
		)
		expected[_case_key(str(case.get("scenario_id", "")), case_seed)] = case_duration
	var seen: Dictionary = {}
	var normalized: Array[Dictionary] = []
	for record_value in records:
		if not (record_value is Dictionary):
			return {}
		var record = (record_value as Dictionary).duplicate(true)
		if str(record.get("candidate_hash", "")) != candidate_hash:
			return {}
		if str(record.get("suite_hash", "")) != str(plan.get("suite_hash", "")):
			return {}
		var deterministic_value: Variant = record.get("deterministic", false)
		if not (deterministic_value is bool) or not bool(deterministic_value):
			return {}
		if (
			not expected_contract_hash.is_empty()
			and str(record.get("evaluation_contract_hash", "")) != expected_contract_hash
		):
			return {}
		var record_seed: int = RLTrainingMath.finite_int_or(
			record.get("seed", 0),
			2147483647
		)
		var key = _case_key(str(record.get("scenario_id", "")), record_seed)
		if not expected.has(key) or seen.has(key):
			return {}
		var planned_duration: float = RLTrainingMath.finite_float_or(
			record.get("planned_duration_seconds", NAN),
			NAN
		)
		if (
			not is_finite(planned_duration)
			or planned_duration <= 0.0
			or not is_equal_approx(planned_duration, float(expected[key]))
		):
			return {}
		if not is_finite(RLTrainingMath.finite_float_or(record.get("episode_return", NAN), NAN)):
			return {}
		var terminated_value: Variant = record.get("terminated", false)
		var truncated_value: Variant = record.get("truncated", false)
		if not (terminated_value is bool) or not (truncated_value is bool):
			return {}
		var terminated: bool = bool(terminated_value)
		var truncated: bool = bool(truncated_value)
		if terminated == truncated:
			return {}
		seen[key] = true
		record["candidate_hash"] = candidate_hash
		normalized.append(record)
	if seen.size() != expected.size():
		return {
			"suite_complete": false,
			"deterministic": true,
			"candidate_hash": candidate_hash,
			"suite_hash": str(plan.get("suite_hash", "")),
			"evaluation_contract_hash": expected_contract_hash,
			"expected_record_count": expected.size(),
			"record_count": seen.size(),
			"missing_case_count": expected.size() - seen.size(),
		}
	var aggregate = RLDeterministicEvaluator.aggregate(normalized)
	if aggregate.is_empty():
		return {}
	var by_scenario: Dictionary = {}
	for scenario_id_value in plan.get("scenario_ids", []):
		var scenario_id = str(scenario_id_value)
		var scenario_records: Array[Dictionary] = []
		for record in normalized:
			if str(record.get("scenario_id", "")) == scenario_id:
				scenario_records.append(record)
		by_scenario[scenario_id] = RLDeterministicEvaluator.aggregate(scenario_records)
	aggregate["schema_version"] = SUITE_SCHEMA_VERSION
	aggregate["suite_complete"] = true
	aggregate["deterministic"] = true
	aggregate["body_kind"] = str(plan.get("body_kind", ""))
	aggregate["candidate_hash"] = candidate_hash
	aggregate["suite_hash"] = str(plan.get("suite_hash", ""))
	aggregate["evaluation_contract_hash"] = expected_contract_hash
	aggregate["expected_record_count"] = expected.size()
	aggregate["scenario_count"] = (plan.get("scenario_ids", []) as Array).size()
	aggregate["seeds_per_scenario"] = RLTrainingMath.finite_int_or(
		plan.get("seeds_per_scenario", SEEDS_PER_SCENARIO),
		SEEDS_PER_SCENARIO
	)
	aggregate["scenario_aggregates"] = by_scenario
	return aggregate


static func is_complete_summary(summary: Dictionary) -> bool:
	if summary.is_empty():
		return false
	var expected_count: int = RLTrainingMath.finite_int_or(
		summary.get("expected_record_count", -1),
		-1
	)
	return (
		RLTrainingMath.finite_int_or(summary.get("schema_version", 0), -1) == SUITE_SCHEMA_VERSION
		and summary.get("deterministic", false) is bool
		and bool(summary.get("deterministic", false))
		and summary.get("suite_complete", false) is bool
		and bool(summary.get("suite_complete", false))
		and expected_count > 0
		and RLTrainingMath.finite_int_or(summary.get("record_count", -1), -1) == expected_count
		and not str(summary.get("candidate_hash", "")).is_empty()
		and not str(summary.get("suite_hash", "")).is_empty()
		and is_finite(RLTrainingMath.finite_float_or(summary.get("selection_score", NAN), NAN))
		and _is_probability(summary.get("success_rate", NAN))
		and _is_probability(summary.get("crash_rate", NAN))
		and _is_probability(summary.get("termination_rate", NAN))
		and _is_probability(summary.get("truncation_rate", NAN))
		and _has_complete_outcome_rates(summary)
	)


static func validate_summary_for_plan(
	plan: Dictionary,
	summary: Dictionary,
	candidate_hash: String
) -> Dictionary:
	if not _valid_plan(plan):
		return {"valid": false, "reason": "invalid_evaluation_plan"}
	if summary.is_empty():
		return {"valid": false, "reason": "missing_evaluation_summary"}
	if candidate_hash.is_empty() or str(summary.get("candidate_hash", "")) != candidate_hash:
		return {"valid": false, "reason": "candidate_hash_mismatch"}
	if str(summary.get("suite_hash", "")) != str(plan.get("suite_hash", "")):
		return {"valid": false, "reason": "evaluation_suite_mismatch"}
	var expected_contract_hash: String = str(plan.get("evaluation_contract_hash", ""))
	if (
		not expected_contract_hash.is_empty()
		and str(summary.get("evaluation_contract_hash", "")) != expected_contract_hash
	):
		return {"valid": false, "reason": "evaluation_contract_mismatch"}
	if str(summary.get("body_kind", "")) != str(plan.get("body_kind", "")):
		return {"valid": false, "reason": "evaluation_body_kind_mismatch"}
	var deterministic_value: Variant = summary.get("deterministic", false)
	if not (deterministic_value is bool) or not bool(deterministic_value):
		return {"valid": false, "reason": "evaluation_not_deterministic"}
	var suite_complete_value: Variant = summary.get("suite_complete", false)
	if not (suite_complete_value is bool) or not bool(suite_complete_value):
		return {"valid": false, "reason": "incomplete_evaluation_suite"}
	var expected_count = (plan.get("cases", []) as Array).size()
	if (
		RLTrainingMath.finite_int_or(summary.get("expected_record_count", -1), -1) != expected_count
		or RLTrainingMath.finite_int_or(summary.get("record_count", -1), -1) != expected_count
	):
		return {"valid": false, "reason": "evaluation_record_count_mismatch"}
	if not is_finite(RLTrainingMath.finite_float_or(summary.get("selection_score", NAN), NAN)):
		return {"valid": false, "reason": "non_finite_candidate_score"}
	if (
		not _is_probability(summary.get("success_rate", NAN))
		or not _is_probability(summary.get("crash_rate", NAN))
		or not _is_probability(summary.get("termination_rate", NAN))
		or not _is_probability(summary.get("truncation_rate", NAN))
		or not _has_complete_outcome_rates(summary)
	):
		return {"valid": false, "reason": "invalid_evaluation_rates"}
	return {"valid": true, "reason": "complete_fixed_seed_suite"}


static func _is_probability(value: Variant) -> bool:
	if not (value is float or value is int):
		return false
	var numeric_value: float = float(value)
	return is_finite(numeric_value) and numeric_value >= 0.0 and numeric_value <= 1.0


static func _has_complete_outcome_rates(summary: Dictionary) -> bool:
	var termination_rate: float = RLTrainingMath.finite_float_or(
		summary.get("termination_rate", NAN),
		NAN
	)
	var truncation_rate: float = RLTrainingMath.finite_float_or(
		summary.get("truncation_rate", NAN),
		NAN
	)
	return (
		is_finite(termination_rate)
		and is_finite(truncation_rate)
		and is_equal_approx(termination_rate + truncation_rate, 1.0)
	)


static func is_valid_plan(plan: Dictionary, expected_body_kind: String = "") -> bool:
	var stored_hash: String = str(plan.get("suite_hash", ""))
	if stored_hash.is_empty():
		return false
	if RLTrainingMath.finite_int_or(plan.get("schema_version", 0), -1) != SUITE_SCHEMA_VERSION:
		return false
	var body_kind: String = str(plan.get("body_kind", "")).strip_edges()
	if body_kind.is_empty():
		return false
	if not expected_body_kind.is_empty() and body_kind != expected_body_kind:
		return false
	var scenario_ids_value: Variant = plan.get("scenario_ids", [])
	var cases_value: Variant = plan.get("cases", [])
	if not (scenario_ids_value is Array) or not (cases_value is Array):
		return false
	var scenario_ids: Array = scenario_ids_value
	var cases: Array = cases_value
	if scenario_ids.is_empty() or cases.is_empty():
		return false
	if RLTrainingMath.finite_int_or(plan.get("seeds_per_scenario", 0), -1) != SEEDS_PER_SCENARIO:
		return false
	if cases.size() != scenario_ids.size() * SEEDS_PER_SCENARIO:
		return false
	var known_scenarios: Dictionary = {}
	for scenario_value: Variant in scenario_ids:
		var scenario_id: String = str(scenario_value).strip_edges()
		if scenario_id.is_empty() or known_scenarios.has(scenario_id):
			return false
		known_scenarios[scenario_id] = true
	var known_cases: Dictionary = {}
	var scenario_case_counts: Dictionary = {}
	for case_value: Variant in cases:
		if not (case_value is Dictionary):
			return false
		var evaluation_case: Dictionary = case_value
		var scenario_id: String = str(evaluation_case.get("scenario_id", ""))
		var seed: int = RLTrainingMath.finite_int_or(
			evaluation_case.get("seed", 0),
			-2147483648
		)
		var duration_seconds: float = RLTrainingMath.finite_float_or(
			evaluation_case.get("duration_seconds", NAN),
			NAN
		)
		var case_key: String = _case_key(scenario_id, seed)
		if (
			not known_scenarios.has(scenario_id)
			or known_cases.has(case_key)
			or not (evaluation_case.get("deterministic_policy", false) is bool)
			or not bool(evaluation_case.get("deterministic_policy", false))
			or not is_finite(duration_seconds)
			or duration_seconds <= 0.0
		):
			return false
		known_cases[case_key] = true
		scenario_case_counts[scenario_id] = int(scenario_case_counts.get(scenario_id, 0)) + 1
	for scenario_value: Variant in scenario_ids:
		var scenario_id: String = str(scenario_value)
		if int(scenario_case_counts.get(scenario_id, 0)) != SEEDS_PER_SCENARIO:
			return false
	var hash_payload: Dictionary = plan.duplicate(true)
	hash_payload.erase("suite_hash")
	var computed_hash: String = JSON.stringify(hash_payload, "", true, true).sha256_text()
	return stored_hash == computed_hash


static func _valid_plan(plan: Dictionary) -> bool:
	return is_valid_plan(plan)


static func _scenario_duration_seconds(body_kind: String, scenario_id: String) -> float:
	# Climbing needs enough time for reach -> grip -> support/pull -> re-grip -> mount. Keeping
	# this duration in the hashed case descriptor makes any future benchmark-duration change an
	# explicit new suite instead of silently changing the meaning of historical Best scores.
	if body_kind == "four_limb" and scenario_id in ["climb_platform", "item_pickup"]:
		return 12.0
	if body_kind == "four_limb" and scenario_id == "item_delivery":
		return 16.0
	return DEFAULT_CASE_DURATION_SECONDS


static func _scenario_ids(body_kind: String) -> Array[String]:
	match body_kind:
		"drone":
			# Keep these identifiers stable: suite hashes and historical Best evaluations use
			# them as part of the deterministic benchmark contract. The universal room maps
			# each descriptor onto an executable hidden-drone scenario.
			return [
				"open_static_target",
				"sparse_walls",
				"corridor",
				"moving_target",
				"degraded_propeller",
				"turret_exposure",
			]
		"four_limb":
			return [
				"ground_target",
				"obstacle_path",
				"climb_platform",
				"controlled_jump",
				"landing_recovery",
				"turret_exposure",
			]
		"turret":
			return [
				"stationary_target",
				"crossing_target",
				"elevated_target",
				"occluded_target",
				"mixed_drone_limb_targets",
			]
		_:
			return ["baseline"]


static func _case_key(scenario_id: String, seed: int) -> String:
	return "%s:%d" % [scenario_id, seed]
