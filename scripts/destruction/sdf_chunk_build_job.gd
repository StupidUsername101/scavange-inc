class_name SdfChunkBuildJob
extends RefCounted

## One immutable sampled chunk handed to WorkerThreadPool. The worker only performs scalar/vector
## math and writes its private result; ArrayMesh and physics resources remain on the main thread.

var snapshot: Dictionary
var result: Dictionary = {}
var started_usec := 0
var elapsed_usec := 0


func configure(value: Dictionary) -> SdfChunkBuildJob:
	snapshot = value
	return self


func execute() -> void:
	started_usec = Time.get_ticks_usec()
	result = SdfDualContouringMesher.build_chunk_snapshot(snapshot)
	elapsed_usec = Time.get_ticks_usec() - started_usec
