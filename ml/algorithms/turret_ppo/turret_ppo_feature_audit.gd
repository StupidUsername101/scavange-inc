class_name TurretPPOFeatureAudit
extends RefCounted

#######################################################
# Turret facade around the shared PPO feature auditor. Body-specific wording stays here while
# statistics/rank/correlation behavior is identical to the other PPO trainers.
#######################################################


static func analyze_rollout(
	rollout: Array[Dictionary],
	feature_names: Array[String]
) -> Dictionary:
	return PPOFeatureAudit.analyze_rollout(rollout, feature_names)


static func analyze_samples(
	samples: Array,
	feature_names: Array[String]
) -> Dictionary:
	return PPOFeatureAudit.analyze_samples(samples, feature_names)


static func status_text(report: Dictionary) -> String:
	return PPOFeatureAudit.status_text(report, "Turret PPO", "movement data", "body inputs")
