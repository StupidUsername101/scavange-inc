class_name DronePPOFeatureAudit
extends RefCounted

#######################################################
# Drone-specific facade around the shared PPO feature auditor. Keeping this name preserves the
# trainer/test API while all feature statistics now use one implementation across body families.
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
	return PPOFeatureAudit.status_text(report, "PPO", "flight data", "sensor inputs")
