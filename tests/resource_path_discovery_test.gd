extends SceneTree

#######################################################
# Filesystem traversal regressions for the shared authored-resource discovery helper.
#######################################################

var failure_count: int = 0


func _init() -> void:
	var root_path: String = "user://tests/resource-path-discovery-pass55"
	var absolute_root: String = ProjectSettings.globalize_path(root_path)
	if DirAccess.dir_exists_absolute(absolute_root):
		TrainingFileIO.remove_directory_recursive_absolute(absolute_root)
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(root_path.path_join("nested"))
	)
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(root_path.path_join("excluded"))
	)
	_expect(
		TrainingFileIO.write_text_atomic(root_path.path_join("zeta.tres"), "zeta")
		and TrainingFileIO.write_text_atomic(
			root_path.path_join("nested").path_join("alpha.res"),
			"alpha"
		)
		and TrainingFileIO.write_text_atomic(
			root_path.path_join("nested").path_join("ignored.txt"),
			"ignored"
		)
		and TrainingFileIO.write_text_atomic(
			root_path.path_join("excluded").path_join("hidden.tres"),
			"hidden"
		),
		"resource discovery fixture files can be written"
	)
	_expect(
		ResourcePathDiscovery.collect("", ["tres"]).is_empty(),
		"empty discovery roots fail closed instead of scanning an implicit working directory"
	)
	var discovered: Array[String] = ResourcePathDiscovery.collect(
		root_path + "/",
		[".TRES", "res"],
		[root_path.path_join("excluded") + "/"]
	)
	_expect(
		discovered == [
			root_path.path_join("nested").path_join("alpha.res"),
			root_path.path_join("zeta.tres"),
		],
		"resource discovery is recursive, extension-normalized, excluded-subtree aware, and sorted"
	)
	if DirAccess.dir_exists_absolute(absolute_root):
		TrainingFileIO.remove_directory_recursive_absolute(absolute_root)
	quit(0 if failure_count == 0 else 1)


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("[PASS] %s" % label)
		return
	failure_count += 1
	push_error("[FAIL] %s" % label)
