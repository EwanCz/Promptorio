extends "res://tests/test_case.gd"


func test_empty_file_fails() -> void:
	var path: String = "res://tests/test_empty_runner_fixture.gd"
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		check(false, "create empty test fixture")
		return
	file.store_string('extends "res://tests/test_case.gd"\n')
	file.close()
	var output: Array = []
	var status: int = OS.execute(OS.get_executable_path(), ["--headless", "-s", "res://tests/run_tests.gd", "--", "empty_runner_fixture"], output, true)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	check_eq(status, 1, "empty test file fails the runner")
	check(not output.is_empty() and "no test methods found" in str(output[0]), "failure identifies the missing test methods")
