class_name RLTrainingCandidateSupport
extends RefCounted

#######################################################
# Pure shared helpers for candidate/best deterministic evaluation state. Trainers remain owners of
# their networks and nomination scores; this class centralizes validation and provenance rules so
# PPO/SAC/body-family copies cannot silently drift apart.
#######################################################


static func pending_candidate_id(candidate: Dictionary) -> int:
	return RLTrainingMath.finite_int_or(candidate.get("candidate_id", -1), -1)


static func is_resumable_candidate(
	candidate: Dictionary,
	candidate_network_state: Dictionary,
	expected_body_kind: String
) -> bool:
	if candidate.is_empty() or candidate_network_state.is_empty():
		return false
	if pending_candidate_id(candidate) < 0:
		return false
	var expected_hash: String = str(candidate.get("candidate_hash", ""))
	if (
		expected_hash.is_empty()
		or expected_hash != RLDeterministicEvaluator.candidate_hash(candidate_network_state)
	):
		return false
	var contract_value: Variant = candidate.get("evaluation_contract", {})
	var plan_value: Variant = candidate.get("evaluation_plan", {})
	if not (contract_value is Dictionary) or not (plan_value is Dictionary):
		return false
	var contract: Dictionary = contract_value as Dictionary
	var plan: Dictionary = plan_value as Dictionary
	if not RLEvaluationContract.is_valid(contract, expected_body_kind):
		return false
	var contract_hash: String = str(contract.get("contract_hash", ""))
	return (
		not contract_hash.is_empty()
		and str(candidate.get("evaluation_contract_hash", "")) == contract_hash
		and str(plan.get("evaluation_contract_hash", "")) == contract_hash
		and RLDeterministicEvaluationSuite.is_valid_plan(plan, expected_body_kind)
	)


static func evaluate_candidate_summary(
	candidate: Dictionary,
	candidate_network_state: Dictionary,
	candidate_id: int,
	evaluation_summary: Dictionary,
	best_evaluation: Dictionary
) -> Dictionary:
	if pending_candidate_id(candidate) != candidate_id:
		return {"valid": false, "promoted": false, "reason": "candidate_id_mismatch"}
	if candidate_network_state.is_empty():
		return {"valid": false, "promoted": false, "reason": "missing_candidate_network"}
	var expected_hash: String = str(candidate.get("candidate_hash", ""))
	if (
		expected_hash.is_empty()
		or expected_hash != RLDeterministicEvaluator.candidate_hash(candidate_network_state)
	):
		return {"valid": false, "promoted": false, "reason": "candidate_network_hash_mismatch"}
	var plan_value: Variant = candidate.get("evaluation_plan", {})
	if not (plan_value is Dictionary):
		return {"valid": false, "promoted": false, "reason": "invalid_evaluation_plan"}
	var plan: Dictionary = plan_value as Dictionary
	var validation: Dictionary = RLDeterministicEvaluationSuite.validate_summary_for_plan(
		plan,
		evaluation_summary,
		expected_hash
	)
	if not bool(validation.get("valid", false)):
		return {
			"valid": false,
			"promoted": false,
			"reason": str(validation.get("reason", "invalid_evaluation_summary")),
		}
	var verified_summary: Dictionary = evaluation_summary.duplicate(true)
	verified_summary["candidate_hash"] = expected_hash
	var decision: Dictionary = RLDeterministicEvaluator.promotion_decision(
		verified_summary,
		best_evaluation
	)
	return {
		"valid": true,
		"promoted": bool(decision.get("promote", false)),
		"reason": str(decision.get("reason", "unknown")),
		"candidate_hash": expected_hash,
		"evaluation": verified_summary,
	}


static func aggregate_candidate_records(
	candidate: Dictionary,
	candidate_id: int,
	records: Array[Dictionary]
) -> Dictionary:
	if pending_candidate_id(candidate) != candidate_id:
		return {"valid": false, "reason": "candidate_id_mismatch"}
	var plan_value: Variant = candidate.get("evaluation_plan", {})
	if not (plan_value is Dictionary):
		return {"valid": false, "reason": "invalid_evaluation_plan"}
	var candidate_hash: String = str(candidate.get("candidate_hash", ""))
	var summary: Dictionary = RLDeterministicEvaluationSuite.aggregate_complete_suite(
		plan_value as Dictionary,
		records,
		candidate_hash
	)
	if summary.is_empty():
		return {"valid": false, "reason": "invalid_evaluation_records"}
	return {"valid": true, "summary": summary}


static func evaluate_best_records(
	best_network_state: Dictionary,
	evaluation_plan: Dictionary,
	records: Array[Dictionary],
	pending_candidate: Dictionary,
	evaluation_contract_template: Dictionary,
	expected_body_kind: String
) -> Dictionary:
	if best_network_state.is_empty():
		return {"recorded": false, "reason": "missing_best_network"}
	var best_hash: String = RLDeterministicEvaluator.candidate_hash(best_network_state)
	var summary: Dictionary = RLDeterministicEvaluationSuite.aggregate_complete_suite(
		evaluation_plan,
		records,
		best_hash
	)
	if summary.is_empty():
		return {"recorded": false, "reason": "invalid_best_evaluation_records"}
	var validation: Dictionary = RLDeterministicEvaluationSuite.validate_summary_for_plan(
		evaluation_plan,
		summary,
		best_hash
	)
	if not bool(validation.get("valid", false)):
		return {
			"recorded": false,
			"reason": str(validation.get("reason", "invalid_best_evaluation")),
		}
	var verified_summary: Dictionary = summary.duplicate(true)
	verified_summary["candidate_hash"] = best_hash
	var verified_contract: Dictionary = _matching_contract_for_plan(
		evaluation_plan,
		pending_candidate,
		evaluation_contract_template,
		expected_body_kind
	)
	return {
		"recorded": true,
		"reason": "best_re_evaluated",
		"evaluation": verified_summary,
		"evaluation_contract": verified_contract,
		"evaluation_contract_hash": str(summary.get("evaluation_contract_hash", "")),
	}


static func best_selection_summary(
	promoted_training_summary: Dictionary,
	best_evaluation: Dictionary,
	legacy_selection_score: float,
	legacy_exact_policy_match: bool,
	verified_exact_policy_match: Variant = null
) -> Dictionary:
	var summary: Dictionary = promoted_training_summary.duplicate(true)
	if summary.is_empty():
		return {
			"selection_score": legacy_selection_score if is_finite(legacy_selection_score) else 0.0,
			"selection_method": "legacy_training_candidate_unverified",
			"evaluation_verified": false,
			"exact_policy_match": legacy_exact_policy_match,
		}
	var training_selection_score: float = RLTrainingMath.finite_float_or(
		summary.get("selection_score", 0.0),
		0.0
	)
	summary["training_selection_score"] = training_selection_score
	summary["selection_score"] = RLTrainingMath.finite_float_or(
		best_evaluation.get("selection_score", training_selection_score),
		training_selection_score
	)
	summary["selection_method"] = "deterministic_fixed_seed_suite_v2"
	if verified_exact_policy_match is bool:
		summary["exact_policy_match"] = bool(verified_exact_policy_match)
	summary["evaluation_verified"] = not best_evaluation.is_empty()
	summary["evaluation"] = best_evaluation.duplicate(true)
	return summary


static func _matching_contract_for_plan(
	evaluation_plan: Dictionary,
	pending_candidate: Dictionary,
	evaluation_contract_template: Dictionary,
	expected_body_kind: String
) -> Dictionary:
	var plan_contract_hash: String = str(evaluation_plan.get("evaluation_contract_hash", ""))
	var pending_contract_value: Variant = pending_candidate.get("evaluation_contract", {})
	if pending_contract_value is Dictionary:
		var pending_contract: Dictionary = pending_contract_value as Dictionary
		if (
			RLEvaluationContract.is_valid(pending_contract, expected_body_kind)
			and str(pending_contract.get("contract_hash", "")) == plan_contract_hash
		):
			return pending_contract.duplicate(true)
	if (
		RLEvaluationContract.is_valid(evaluation_contract_template, expected_body_kind)
		and str(evaluation_contract_template.get("contract_hash", "")) == plan_contract_hash
	):
		return evaluation_contract_template.duplicate(true)
	return {}
