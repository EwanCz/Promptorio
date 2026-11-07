extends RefCounted
## Base class for tests. A test file extends this ("res://tests/test_case.gd"),
## and every method named test_* is run by tests/run_tests.gd (coroutines are awaited).
## Override before_each()/after_each() for per-test setup and cleanup.

var tree: SceneTree
var checks: int = 0
var failures: int = 0


func before_each() -> void:
	pass


func after_each() -> void:
	pass


func autoload(autoload_name: String) -> Node:
	return tree.root.get_node(autoload_name)


func check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("  ok   ", label)
	else:
		failures += 1
		print("  FAIL ", label)


func check_eq(actual: Variant, expected: Variant, label: String) -> void:
	checks += 1
	if actual == expected:
		print("  ok   ", label)
	else:
		failures += 1
		print("  FAIL ", label, " (expected ", expected, ", got ", actual, ")")


## Waits in real time (headless frames are uncapped, so never count frames).
func wait_until(condition: Callable, timeout: float = 3.0) -> void:
	var deadline: int = Time.get_ticks_msec() + int(timeout * 1000.0)
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await tree.process_frame


func wait_seconds(seconds: float) -> void:
	await tree.create_timer(seconds).timeout
