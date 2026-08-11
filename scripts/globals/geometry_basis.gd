class_name GeometryBasis
extends RefCounted

#######################################################
# Small geometry-orientation helpers shared by authored Resources and runtime Nodes. Keeping these
# dependency-free prevents resource/runtime code from copying the same basis convention by hand.
#######################################################


static func from_y(direction: Vector3) -> Basis:
	var y_axis: Vector3 = direction.normalized()
	if y_axis.length_squared() <= 0.000001:
		y_axis = Vector3.DOWN
	var helper: Vector3 = Vector3.FORWARD
	if absf(y_axis.dot(helper)) > 0.92:
		helper = Vector3.RIGHT
	var x_axis: Vector3 = helper.cross(y_axis).normalized()
	var z_axis: Vector3 = x_axis.cross(y_axis).normalized()
	return Basis(x_axis, y_axis, z_axis).orthonormalized()
