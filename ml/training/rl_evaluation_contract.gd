class_name RLEvaluationContract
extends RefCounted

#######################################################
# Immutable task/environment contract for deterministic model promotion. Network weights are
# hashed separately; this contract freezes the world/task semantics under which Candidate and
# Best scores are allowed to be compared.
#######################################################

const SCHEMA_VERSION = 1


static func create(body_kind: String, environment: Dictionary) -> Dictionary:
	var contract: Dictionary = {
		"schema_version": SCHEMA_VERSION,
		"body_kind": body_kind,
		"environment": environment.duplicate(true),
	}
	contract["contract_hash"] = hash_contract(contract)
	return contract


static func hash_contract(contract: Dictionary) -> String:
	if contract.is_empty():
		return ""
	var payload: Dictionary = contract.duplicate(true)
	payload.erase("contract_hash")
	return JSON.stringify(payload, "", true, true).sha256_text()


static func is_valid(contract: Dictionary, expected_body_kind: String = "") -> bool:
	if RLTrainingMath.finite_int_or(contract.get("schema_version", 0), -1) != SCHEMA_VERSION:
		return false
	if not (contract.get("environment", {}) is Dictionary):
		return false
	var body_kind: String = str(contract.get("body_kind", ""))
	if body_kind.is_empty():
		return false
	if not expected_body_kind.is_empty() and body_kind != expected_body_kind:
		return false
	var stored_hash: String = str(contract.get("contract_hash", ""))
	return not stored_hash.is_empty() and stored_hash == hash_contract(contract)


static func same_contract(first: Dictionary, second: Dictionary) -> bool:
	if first.is_empty() or second.is_empty():
		return false
	return (
		str(first.get("contract_hash", ""))
		== str(second.get("contract_hash", ""))
		and is_valid(first)
		and is_valid(second)
	)
