class_name SdfChunkBuildJob
extends RefCounted

## One immutable sampled chunk handed to WorkerThreadPool. The worker only performs scalar/vector
## math and writes its private result; ArrayMesh and physics resources remain on the main thread.

var snapshot: Dictionary
var result: Dictionary = {}
var cell_indices := PackedInt32Array()
var corner_distances := PackedFloat32Array()
var coordinate := Vector3i.ZERO
var task_id := -1
var started_usec := 0
var elapsed_usec := 0
var native_kernel: Object = SdfDualContouringMesher.create_native_kernel()


func configure(value: Dictionary) -> SdfChunkBuildJob:
	snapshot = value
	coordinate = value.get("chunk_coordinate", Vector3i.ZERO)
	return self


func capture(volume: SparseSdfVolumeData, chunk_coordinate: Vector3i) -> SdfChunkBuildJob:
	coordinate = chunk_coordinate
	snapshot = SdfDualContouringMesher.capture_chunk(volume, chunk_coordinate, snapshot)
	started_usec = 0
	elapsed_usec = 0
	task_id = -1
	return self


func execute() -> void:
	started_usec = Time.get_ticks_usec()
	if native_kernel != null and is_instance_valid(native_kernel):
		result = native_kernel.call(&"build_chunk_snapshot", snapshot) as Dictionary
	else:
		result = SdfDualContouringMesher.build_chunk_snapshot(
			snapshot,
			result,
			cell_indices,
			corner_distances
		)
	result = SdfDualContouringMesher.finalize_box_shell(result, snapshot)
	elapsed_usec = Time.get_ticks_usec() - started_usec


func uses_native_backend() -> bool:
	return native_kernel != null and is_instance_valid(native_kernel)
