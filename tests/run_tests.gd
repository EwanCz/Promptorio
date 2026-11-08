extends SceneTree
## Test runner. Prefer tests/run.sh. Direct use:
##   godot --headless -s tests/run_tests.gd            run every tests/test_*.gd
##   godot --headless -s tests/run_tests.gd -- llm     only files whose name contains "llm"
## Exit code is 1 if any check fails or any test file has no checks.

const TESTS_DIR: String = "res://tests"
## Tests save chips here, never to the player's user://chip_registry.tres.
const TEST_CHIPS_PATH: String = "user://test_chip_registry.tres"
## The map draws random minesites; tests get this fixed layout so the cells they use stay valid.
const TEST_MINESITES: Array[Vector2i] = [
	Vector2i(4, 4), Vector2i(5, 4), Vector2i(4, 5),
	Vector2i(26, 4), Vector2i(27, 4), Vector2i(27, 5),
	Vector2i(4, 15), Vector2i(5, 15), Vector2i(5, 14),
	Vector2i(26, 15), Vector2i(27, 15), Vector2i(26, 14),
]


func _initialize() -> void:
	await process_frame
	var filter: String = ""
	var user_args: PackedStringArray = OS.get_cmdline_user_args()
	if not user_args.is_empty():
		filter = user_args[0]

	var registry: Node = root.get_node("ChipRegistry")
	registry.user_path = TEST_CHIPS_PATH
	DirAccess.remove_absolute(TEST_CHIPS_PATH)
	registry.load_registry()

	# Loaded at run time: this script compiles before the autoloads that GridMap2D needs exist.
	(load("res://scripts/world/grid_map_2d.gd") as GDScript).set("layout_override", TEST_MINESITES)

	var total_checks: int = 0
	var total_failures: int = 0
	var files: PackedStringArray = _find_test_files(filter)
	if files.is_empty():
		print("No test files found (filter '%s')" % filter)
		quit(1)
		return

	for file_name: String in files:
		var script: GDScript = load("%s/%s" % [TESTS_DIR, file_name])
		var test: RefCounted = script.new()
		test.set("tree", self)
		var methods: Array[String] = _find_test_methods(test)
		if methods.is_empty():
			print("== %s" % file_name)
			print("  FAIL no test methods found")
			total_failures += 1
			continue
		for method: String in methods:
			print("== %s :: %s" % [file_name, method])
			var checks_before: int = test.get("checks")
			test.before_each()
			await test.call(method)
			test.after_each()
			if int(test.get("checks")) == checks_before:
				print("  FAIL no checks ran (test aborted or empty)")
				test.set("failures", int(test.get("failures")) + 1)
		total_checks += int(test.get("checks"))
		total_failures += int(test.get("failures"))

	DirAccess.remove_absolute(TEST_CHIPS_PATH)
	print("--------")
	print("%d checks, %d failed" % [total_checks, total_failures])
	print("ALL PASSED" if total_failures == 0 else "FAILED")
	quit(1 if total_failures > 0 else 0)


func _find_test_files(filter: String) -> PackedStringArray:
	var found: PackedStringArray = PackedStringArray()
	for file_name: String in DirAccess.get_files_at(TESTS_DIR):
		if file_name.begins_with("test_") and file_name.ends_with(".gd") and file_name != "test_case.gd":
			if filter == "" or file_name.contains(filter):
				found.append(file_name)
	found.sort()
	return found


func _find_test_methods(test: RefCounted) -> Array[String]:
	var methods: Array[String] = []
	for info: Dictionary in test.get_method_list():
		var method_name: String = info["name"]
		if method_name.begins_with("test_"):
			methods.append(method_name)
	return methods
