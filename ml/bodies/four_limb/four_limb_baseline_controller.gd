class_name FourLimbBaselineController
extends RefCounted

#######################################################
# Raw-actuator diagnostic baseline. Zero commands mean the authored bent rest pose; this
# controller can test whether the physics body can stand without inserting a gait planner.
#######################################################


func predict_action(_observation: Dictionary) -> Dictionary:
	return FourLimbMLAction.from_commands(FourLimbMLAction.neutral_commands())


func display_name() -> String:
	return "Neutral joint hold"
