extends SceneTree

#######################################################
# Pure fixed-seed evaluation contract/suite tests. These intentionally avoid a physics world so
# candidate provenance and scenario-plan regressions can be checked cheaply in CI/headless runs.
#######################################################

var failure_count: int = 0
var assertion_count: int = 0


func _init() -> void:
	_test_drone_runtime_models_declare_compact_observation_contract()
	_test_drone_action_schema_has_one_authoritative_version()
	_test_drone_frozen_hardware_uses_identical_live_body_without_decode()
	_test_contract_hash_detects_environment_changes()
	_test_every_default_scenario_has_an_executor()
	_test_leg_only_drone_plan_skips_degraded_propeller()
	_test_routed_target_plan_is_deterministic()
	_test_item_pickup_contract_adds_evaluation_case()
	_test_item_delivery_contract_adds_evaluation_case()
	_test_plan_hash_detects_descriptor_changes()
	_test_suite_describes_case_durations()
	_test_complete_suite_requires_matching_contract_hash()
	_test_promotion_rejects_cross_contract_comparison()
	_test_promotion_rejects_cross_suite_comparison()
	_test_bootstrap_interval_reports_selection_statistic()
	_test_malformed_evaluation_metadata_is_rejected_safely()

	if failure_count == 0:
		print("ML evaluation contract tests passed: %d assertions" % assertion_count)
		quit(0)
	else:
		push_error("ML evaluation contract tests failed: %d/%d assertions" % [
			failure_count,
			assertion_count,
		])
		quit(1)


func _test_drone_runtime_models_declare_compact_observation_contract() -> void:
	# Regression for the fixed-seed failure that produced zero propeller commands: evaluator
	# preview inference must ask these runtime policies for the compact PPO-shaped snapshot.
	_expect(DronePPOModel.new({}).uses_compact_ppo_observation(), "PPO runtime model declares compact drone observation contract")
	_expect(DroneSACModel.new({}).uses_compact_ppo_observation(), "SAC runtime model declares compact drone observation contract")
	_expect(DroneTrainingPolicy.new({}).uses_compact_ppo_observation(), "baseline runtime policy declares compact drone observation contract")


func _test_drone_action_schema_has_one_authoritative_version() -> void:
	var adapter: DroneMLBodyAdapter = DroneMLBodyAdapter.new()
	_expect(DroneMLAction.SCHEMA_VERSION > 0, "drone ML action exposes a positive schema version")
	_expect(
		adapter.action_schema_version() == DroneMLAction.SCHEMA_VERSION,
		"drone body adapter and evaluation contract share the authoritative action schema version"
	)


func _test_drone_frozen_hardware_uses_identical_live_body_without_decode() -> void:
	var loadout: DroneLoadout = MLBodyPresetLibrary.drone_quad_loadout(false)
	var hardware: Dictionary = DroneTrainingLoadoutConfig.to_record(loadout)
	var contract: Dictionary = RLEvaluationContract.create("drone", {"hardware": hardware})
	var environment: Dictionary = contract.get("environment", {})
	var frozen_hardware: Dictionary = environment.get("hardware", {})
	var resolved: DroneLoadout = DroneTrainingLoadoutConfig.frozen_loadout(
		frozen_hardware,
		loadout
	)
	_expect(
		resolved != null
		and resolved != loadout
		and DroneTrainingLoadoutConfig.records_match(
			frozen_hardware,
			DroneTrainingLoadoutConfig.to_record(resolved)
		),
		"a fresh drone candidate can recover its exact frozen hardware from the unchanged live group without Resource snapshot decode"
	)


func _test_contract_hash_detects_environment_changes() -> void:
	var environment: Dictionary = {
		"algorithm": "ppo",
		"hardware": {"signature": "quad"},
		"reward_cards": {"survival": {"weight": 1.0}},
		"target_handler": {"kind_priorities": {"navigation": 100.0}},
	}
	var contract: Dictionary = RLEvaluationContract.create("drone", environment)
	_expect(RLEvaluationContract.is_valid(contract, "drone"), "fresh drone evaluation contract validates")
	var mutated: Dictionary = contract.duplicate(true)
	(mutated["environment"] as Dictionary)["algorithm"] = "sac_her"
	_expect(not RLEvaluationContract.is_valid(mutated, "drone"), "environment mutation invalidates the frozen contract hash")
	var recreated: Dictionary = RLEvaluationContract.create("drone", environment)
	_expect(RLEvaluationContract.same_contract(contract, recreated), "identical environment dictionaries reproduce the same contract")


func _test_every_default_scenario_has_an_executor() -> void:
	var body_kinds: Array[String] = ["drone", "four_limb", "turret"]
	for body_kind: String in body_kinds:
		var plan: Dictionary = RLDeterministicEvaluationSuite.default_plan(body_kind)
		for scenario_value: Variant in plan.get("scenario_ids", []):
			var scenario_id: String = str(scenario_value)
			var supported: bool = false
			match body_kind:
				"drone":
					supported = DroneCandidateEvaluationJob.supports_scenario_id(scenario_id)
				"four_limb":
					supported = FourLimbCandidateEvaluationJob.supports_scenario_id(scenario_id)
				"turret":
					supported = TurretCandidateEvaluationJob.supports_scenario_id(scenario_id)
			_expect(supported, "%s fixed-seed scenario %s has an evaluator implementation" % [body_kind, scenario_id])


func _test_leg_only_drone_plan_skips_degraded_propeller() -> void:
	var loadout: DroneLoadout = MLBodyPresetLibrary.drone_quad_loadout(false)
	_expect(loadout != null and loadout.core != null, "leg-only evaluation test loads a drone Core")
	if loadout == null or loadout.core == null:
		return
	loadout.core.propeller_slot_count = 0
	loadout.propellers.clear()
	loadout.propeller_slot_transforms.clear()
	var hardware: Dictionary = DroneTrainingLoadoutConfig.to_record(loadout)
	var contract: Dictionary = RLEvaluationContract.create("drone", {"hardware": hardware})
	var plan: Dictionary = RLDeterministicEvaluationSuite.plan_for_contract("drone", contract, 4433)
	var scenarios: Array = plan.get("scenario_ids", [])
	_expect(
		not scenarios.has("degraded_propeller")
		and RLDeterministicEvaluationSuite.default_plan("drone", 4433).get("scenario_ids", []).has("degraded_propeller"),
		"leg-only drone evaluation omits the impossible degraded-propeller case without changing the stock suite"
	)


func _test_routed_target_plan_is_deterministic() -> void:
	var environment: Dictionary = {
		"active_target_kinds": ["navigation", "cargo_delivery", "survival_escape"],
	}
	for body_kind: String in ["drone", "four_limb"]:
		var contract: Dictionary = RLEvaluationContract.create(body_kind, environment)
		var first: Dictionary = RLDeterministicEvaluationSuite.plan_for_contract(body_kind, contract, 4444)
		var second: Dictionary = RLDeterministicEvaluationSuite.plan_for_contract(body_kind, contract, 4444)
		_expect(str(first.get("suite_hash", "")) == str(second.get("suite_hash", "")), "%s target-aware suite hash is deterministic" % body_kind)
		var scenarios: Array = first.get("scenario_ids", [])
		_expect(scenarios.has("routed_target__cargo_delivery"), "%s evaluation covers active cargo routing" % body_kind)
		_expect(scenarios.has("routed_target__survival_escape"), "%s evaluation covers active survival routing" % body_kind)


func _test_item_pickup_contract_adds_evaluation_case() -> void:
	var enabled_contract: Dictionary = RLEvaluationContract.create(
		"four_limb",
		{
			"reward_cards": {
				"item_pickup": {"enabled": true, "intensity": 1.5},
			},
		}
	)
	var enabled_plan: Dictionary = RLDeterministicEvaluationSuite.plan_for_contract(
		"four_limb",
		enabled_contract,
		4545
	)
	_expect(
		(enabled_plan.get("scenario_ids", []) as Array).has("item_pickup"),
		"enabling the limb Item Pickup lesson adds a deterministic pickup benchmark"
	)
	_expect(
		FourLimbCandidateEvaluationJob.supports_scenario_id("item_pickup"),
		"the hidden four-limb evaluator implements the conditional pickup benchmark"
	)
	var found_pickup_duration: bool = false
	for case_value: Variant in enabled_plan.get("cases", []):
		if not (case_value is Dictionary):
			continue
		var case: Dictionary = case_value as Dictionary
		if str(case.get("scenario_id", "")) == "item_pickup":
			found_pickup_duration = true
			_expect(
				float(case.get("duration_seconds", 0.0)) == 12.0,
				"pickup evaluation allows time to approach, grip, and raise the canonical item"
			)
	_expect(found_pickup_duration, "pickup-enabled plan contains a concrete pickup case descriptor")

	var disabled_contract: Dictionary = RLEvaluationContract.create(
		"four_limb",
		{
			"reward_cards": {
				"item_pickup": {"enabled": false, "intensity": 1.5},
			},
		}
	)
	var disabled_plan: Dictionary = RLDeterministicEvaluationSuite.plan_for_contract(
		"four_limb",
		disabled_contract,
		4545
	)
	_expect(
		not (disabled_plan.get("scenario_ids", []) as Array).has("item_pickup"),
		"disabled Item Pickup lessons do not burden unrelated four-limb evaluations"
	)


func _test_item_delivery_contract_adds_evaluation_case() -> void:
	var enabled_contract: Dictionary = RLEvaluationContract.create(
		"four_limb",
		{
			"reward_cards": {
				"item_delivery": {"enabled": true, "intensity": 2.0},
			},
		}
	)
	var enabled_plan: Dictionary = RLDeterministicEvaluationSuite.plan_for_contract(
		"four_limb",
		enabled_contract,
		5656
	)
	_expect(
		(enabled_plan.get("scenario_ids", []) as Array).has("item_delivery"),
		"enabling the limb Item Delivery lesson adds a deterministic pickup-and-deliver benchmark"
	)
	_expect(
		FourLimbCandidateEvaluationJob.supports_scenario_id("item_delivery"),
		"the hidden four-limb evaluator implements the conditional delivery benchmark"
	)
	var found_delivery_duration: bool = false
	for case_value: Variant in enabled_plan.get("cases", []):
		if not (case_value is Dictionary):
			continue
		var case: Dictionary = case_value as Dictionary
		if str(case.get("scenario_id", "")) == "item_delivery":
			found_delivery_duration = true
			_expect(
				float(case.get("duration_seconds", 0.0)) == 16.0,
				"delivery evaluation allows time to approach, grip, carry, and enter the canonical destination"
			)
	_expect(found_delivery_duration, "delivery-enabled plan contains a concrete delivery case descriptor")

	var disabled_contract: Dictionary = RLEvaluationContract.create(
		"four_limb",
		{
			"reward_cards": {
				"item_delivery": {"enabled": false, "intensity": 2.0},
			},
		}
	)
	var disabled_plan: Dictionary = RLDeterministicEvaluationSuite.plan_for_contract(
		"four_limb",
		disabled_contract,
		5656
	)
	_expect(
		not (disabled_plan.get("scenario_ids", []) as Array).has("item_delivery"),
		"disabled Item Delivery lessons do not add the delivery benchmark"
	)


func _test_plan_hash_detects_descriptor_changes() -> void:
	var contract: Dictionary = RLEvaluationContract.create("drone", {"active_target_kinds": ["navigation"]})
	var plan: Dictionary = RLDeterministicEvaluationSuite.plan_for_contract("drone", contract, 5555)
	var candidate_hash: String = "candidate-hash"
	var records: Array[Dictionary] = _records_for_plan(plan, candidate_hash, 1.0)
	var original: Dictionary = RLDeterministicEvaluationSuite.aggregate_complete_suite(plan, records, candidate_hash)
	_expect(bool(original.get("suite_complete", false)), "fresh fixed-seed plan hash validates")
	var tampered: Dictionary = plan.duplicate(true)
	var cases: Array = tampered.get("cases", [])
	if not cases.is_empty() and cases[0] is Dictionary:
		(cases[0] as Dictionary)["seed"] = int((cases[0] as Dictionary).get("seed", 0)) + 1
	var rejected: Dictionary = RLDeterministicEvaluationSuite.aggregate_complete_suite(tampered, records, candidate_hash)
	_expect(rejected.is_empty(), "changing a case descriptor without rebuilding suite hash invalidates the plan")


func _test_complete_suite_requires_matching_contract_hash() -> void:
	var contract: Dictionary = RLEvaluationContract.create("drone", {"active_target_kinds": ["navigation"]})
	var plan: Dictionary = RLDeterministicEvaluationSuite.plan_for_contract("drone", contract, 777)
	var candidate_hash: String = "candidate-hash"
	var records: Array[Dictionary] = _records_for_plan(plan, candidate_hash, 1.0)
	var summary: Dictionary = RLDeterministicEvaluationSuite.aggregate_complete_suite(plan, records, candidate_hash)
	_expect(bool(summary.get("suite_complete", false)), "complete matching fixed-seed records aggregate successfully")
	_expect(str(summary.get("evaluation_contract_hash", "")) == str(contract.get("contract_hash", "")), "aggregate keeps the frozen evaluation contract hash")
	if not records.is_empty():
		records[0]["evaluation_contract_hash"] = "wrong-contract"
	var rejected: Dictionary = RLDeterministicEvaluationSuite.aggregate_complete_suite(plan, records, candidate_hash)
	_expect(rejected.is_empty(), "one cross-contract record invalidates the entire deterministic suite")
	var provenance_records: Array[Dictionary] = _records_for_plan(plan, candidate_hash, 1.0)
	if not provenance_records.is_empty():
		provenance_records[0].erase("suite_hash")
	var missing_suite_hash: Dictionary = RLDeterministicEvaluationSuite.aggregate_complete_suite(
		plan,
		provenance_records,
		candidate_hash
	)
	_expect(missing_suite_hash.is_empty(), "evaluation records cannot inherit a missing suite hash implicitly")
	var duration_records: Array[Dictionary] = _records_for_plan(plan, candidate_hash, 1.0)
	if not duration_records.is_empty():
		duration_records[0]["planned_duration_seconds"] = (
			float(duration_records[0].get("planned_duration_seconds", 0.0)) + 1.0
		)
	var wrong_duration: Dictionary = RLDeterministicEvaluationSuite.aggregate_complete_suite(
		plan,
		duration_records,
		candidate_hash
	)
	_expect(wrong_duration.is_empty(), "evaluation records must use the duration hashed into their suite case")


func _test_suite_describes_case_durations() -> void:
	var plan: Dictionary = RLDeterministicEvaluationSuite.default_plan("four_limb")
	_expect(
		RLDeterministicEvaluationSuite.is_valid_plan(plan, "four_limb")
		and not RLDeterministicEvaluationSuite.is_valid_plan(plan, "drone"),
		"deterministic plans are validated against the expected body kind"
	)
	var found_climb: bool = false
	for case_value: Variant in plan.get("cases", []):
		var case: Dictionary = case_value as Dictionary
		_expect(float(case.get("duration_seconds", 0.0)) > 0.0, "every deterministic evaluation case declares its planned duration")
		if str(case.get("scenario_id", "")) == "climb_platform":
			found_climb = true
			_expect(float(case.get("duration_seconds", 0.0)) == 12.0, "climb benchmark allows enough time for a multi-stage mount")
	_expect(found_climb, "four-limb deterministic suite contains its climbing benchmark")


func _test_promotion_rejects_cross_contract_comparison() -> void:
	var candidate: Dictionary = {
		"deterministic": true,
		"suite_complete": true,
		"suite_hash": "suite-a",
		"selection_score": 2.0,
		"crash_rate": 0.0,
		"evaluation_contract_hash": "contract-a",
	}
	var best: Dictionary = {
		"deterministic": true,
		"suite_complete": true,
		"suite_hash": "suite-a",
		"selection_score": 1.0,
		"crash_rate": 0.0,
		"evaluation_contract_hash": "contract-b",
	}
	var rejected: Dictionary = RLDeterministicEvaluator.promotion_decision(candidate, best)
	_expect(not bool(rejected.get("promote", true)), "higher-scoring candidate cannot beat Best across different environment contracts")
	_expect(str(rejected.get("reason", "")) == "evaluation_contract_mismatch", "cross-contract rejection reports the precise reason")
	best["evaluation_contract_hash"] = "contract-a"
	var accepted: Dictionary = RLDeterministicEvaluator.promotion_decision(candidate, best)
	_expect(bool(accepted.get("promote", false)), "same-contract robust improvement remains promotable")


func _test_promotion_rejects_cross_suite_comparison() -> void:
	var candidate: Dictionary = {
		"deterministic": true,
		"suite_complete": true,
		"suite_hash": "suite-new",
		"selection_score": 2.0,
		"crash_rate": 0.0,
		"evaluation_contract_hash": "contract-a",
	}
	var best: Dictionary = candidate.duplicate(true)
	best["suite_hash"] = "suite-old"
	best["selection_score"] = 1.0
	var rejected: Dictionary = RLDeterministicEvaluator.promotion_decision(candidate, best)
	_expect(not bool(rejected.get("promote", true)), "candidate cannot beat Best when deterministic suite descriptors differ")
	_expect(str(rejected.get("reason", "")) == "evaluation_suite_mismatch", "cross-suite rejection reports the precise reason")


func _test_bootstrap_interval_reports_selection_statistic() -> void:
	var records: Array[Dictionary] = []
	for scenario_index in range(3):
		for seed_index in range(5):
			records.append({
				"scenario_id": "scenario-%d" % scenario_index,
				"seed": 1000 + scenario_index * 100 + seed_index,
				"episode_return": float(scenario_index * 5 + seed_index),
			})
	var aggregate: Dictionary = RLDeterministicEvaluator.aggregate(records)
	_expect(str(aggregate.get("confidence_method", "")) == "stratified_bootstrap_iqm_95_v2", "evaluation diagnostics label the stratified bootstrap method")
	_expect(is_finite(float(aggregate.get("selection_score_confidence_low", NAN))), "bootstrap lower interval is finite")
	_expect(is_finite(float(aggregate.get("selection_score_confidence_high", NAN))), "bootstrap upper interval is finite")
	_expect(float(aggregate.get("selection_score_confidence_low", INF)) <= float(aggregate.get("selection_score_confidence_high", -INF)), "bootstrap interval is ordered")


func _test_malformed_evaluation_metadata_is_rejected_safely() -> void:
	var contract: Dictionary = RLEvaluationContract.create("drone", {"active_target_kinds": 17})
	_expect(RLEvaluationContract.is_valid(contract, "drone"), "evaluation contracts may contain unrelated environment data without weakening their hash")
	var plan_from_odd_environment: Dictionary = RLDeterministicEvaluationSuite.plan_for_contract("drone", contract, 9191)
	_expect(RLDeterministicEvaluationSuite.is_valid_plan(plan_from_odd_environment, "drone"), "non-array routed-target metadata is ignored instead of crashing plan construction")

	var malformed_contract: Dictionary = contract.duplicate(true)
	malformed_contract["schema_version"] = {"wrong": true}
	malformed_contract["contract_hash"] = RLEvaluationContract.hash_contract(malformed_contract)
	_expect(not RLEvaluationContract.is_valid(malformed_contract, "drone"), "wrong-type evaluation contract schema is rejected without a numeric cast failure")

	var plan: Dictionary = RLDeterministicEvaluationSuite.default_plan("drone", 9292)
	var malformed_plan: Dictionary = plan.duplicate(true)
	malformed_plan["schema_version"] = {"wrong": true}
	malformed_plan["suite_hash"] = _suite_hash(malformed_plan)
	_expect(not RLDeterministicEvaluationSuite.is_valid_plan(malformed_plan, "drone"), "wrong-type evaluation suite schema is rejected safely")

	var malformed_case_plan: Dictionary = plan.duplicate(true)
	var malformed_cases: Array = malformed_case_plan.get("cases", [])
	if not malformed_cases.is_empty() and malformed_cases[0] is Dictionary:
		(malformed_cases[0] as Dictionary)["seed"] = {"wrong": true}
	malformed_case_plan["suite_hash"] = _suite_hash(malformed_case_plan)
	_expect(not RLDeterministicEvaluationSuite.is_valid_plan(malformed_case_plan, "drone"), "wrong-type evaluation case seed is rejected safely")

	var malformed_bool_plan: Dictionary = plan.duplicate(true)
	var malformed_bool_cases: Array = malformed_bool_plan.get("cases", [])
	if not malformed_bool_cases.is_empty() and malformed_bool_cases[0] is Dictionary:
		(malformed_bool_cases[0] as Dictionary)["deterministic_policy"] = 1
	malformed_bool_plan["suite_hash"] = _suite_hash(malformed_bool_plan)
	_expect(not RLDeterministicEvaluationSuite.is_valid_plan(malformed_bool_plan, "drone"), "numeric deterministic flags cannot masquerade as persisted booleans")

	var candidate_hash: String = "candidate-malformed-metadata"
	var records: Array[Dictionary] = _records_for_plan(plan, candidate_hash, 1.0)
	if not records.is_empty():
		records[0]["seed"] = {"wrong": true}
	_expect(RLDeterministicEvaluationSuite.aggregate_complete_suite(plan, records, candidate_hash).is_empty(), "wrong-type evaluation record seed invalidates the suite without throwing")
	var malformed_bool_records: Array[Dictionary] = _records_for_plan(plan, candidate_hash, 1.0)
	if not malformed_bool_records.is_empty():
		malformed_bool_records[0]["terminated"] = 1
	_expect(RLDeterministicEvaluationSuite.aggregate_complete_suite(plan, malformed_bool_records, candidate_hash).is_empty(), "numeric terminal flags cannot enter deterministic Best evidence")

	var summary: Dictionary = {
		"schema_version": RLDeterministicEvaluationSuite.SUITE_SCHEMA_VERSION,
		"deterministic": true,
		"suite_complete": true,
		"expected_record_count": {"wrong": true},
		"record_count": 1,
		"candidate_hash": candidate_hash,
		"suite_hash": str(plan.get("suite_hash", "")),
		"selection_score": {"wrong": true},
		"success_rate": 0.0,
		"crash_rate": 0.0,
		"termination_rate": 0.0,
		"truncation_rate": 1.0,
	}
	_expect(not RLDeterministicEvaluationSuite.is_complete_summary(summary), "wrong-type deterministic summary counters/scores are rejected safely")
	var decision: Dictionary = RLDeterministicEvaluator.promotion_decision(summary)
	_expect(not bool(decision.get("promote", true)), "wrong-type promotion score cannot enter Best selection")

	var turret_contract: Dictionary = RLEvaluationContract.create("turret", {
		"hardware": {"fixture": true},
		"reward_cards": {"fixture": {"enabled": true}},
	})
	var turret_plan: Dictionary = RLDeterministicEvaluationSuite.plan_for_contract(
		"turret",
		turret_contract,
		9393
	)
	var candidate: Dictionary = {
		"candidate_id": 4,
		"candidate_hash": "candidate-4",
		"evaluation_contract": turret_contract,
		"evaluation_contract_hash": str(turret_contract.get("contract_hash", "")),
		"evaluation_plan": turret_plan,
	}
	var configured_job: Dictionary = RLTrainingCandidateSupport.evaluation_job_configuration(
		candidate,
		{"checkpoint": true},
		"turret",
		17
	)
	_expect(
		bool(configured_job.get("valid", false))
		and int(configured_job.get("environment_revision", -1)) == 17,
		"shared evaluator-job metadata accepts a matching frozen plan and contract"
	)
	var broken_environment_contract: Dictionary = RLEvaluationContract.create("turret", {
		"hardware": "broken",
		"reward_cards": {"fixture": {"enabled": true}},
	})
	var broken_environment_candidate: Dictionary = candidate.duplicate(true)
	broken_environment_candidate["evaluation_contract"] = broken_environment_contract
	broken_environment_candidate["evaluation_contract_hash"] = str(
		broken_environment_contract.get("contract_hash", "")
	)
	broken_environment_candidate["evaluation_plan"] = RLDeterministicEvaluationSuite.plan_for_contract(
		"turret",
		broken_environment_contract,
		9393
	)
	_expect(
		not bool(RLTrainingCandidateSupport.evaluation_job_configuration(
			broken_environment_candidate,
			{"checkpoint": true},
			"turret",
			17
		).get("valid", true)),
		"shared evaluator-job metadata rejects malformed frozen hardware instead of falling back to live state"
	)
	var malformed_job_candidate: Dictionary = candidate.duplicate(true)
	malformed_job_candidate["evaluation_plan"] = "broken"
	var malformed_job: Dictionary = RLTrainingCandidateSupport.evaluation_job_configuration(
		malformed_job_candidate,
		{"checkpoint": true},
		"turret",
		17
	)
	_expect(
		not bool(malformed_job.get("valid", true)),
		"shared evaluator-job metadata rejects wrong-type plans without a typed Dictionary failure"
	)


func _suite_hash(plan: Dictionary) -> String:
	var payload: Dictionary = plan.duplicate(true)
	payload.erase("suite_hash")
	return JSON.stringify(payload, "", true, true).sha256_text()


func _records_for_plan(plan: Dictionary, candidate_hash: String, reward: float) -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	for case_value: Variant in plan.get("cases", []):
		var case: Dictionary = case_value as Dictionary
		records.append({
			"scenario_id": str(case.get("scenario_id", "")),
			"seed": int(case.get("seed", 0)),
			"deterministic": true,
			"suite_hash": str(plan.get("suite_hash", "")),
			"planned_duration_seconds": float(case.get("duration_seconds", 0.0)),
			"episode_return": reward,
			"terminated": false,
			"truncated": true,
			"success": false,
			"crash": false,
			"candidate_hash": candidate_hash,
			"evaluation_contract_hash": str(plan.get("evaluation_contract_hash", "")),
		})
	return records


func _expect(condition: bool, message: String) -> void:
	assertion_count += 1
	if condition:
		return
	failure_count += 1
	push_error(message)
