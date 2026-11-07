extends "res://tests/test_case.gd"

const SpeedMachine: GDScript = preload("res://tests/support/speed_machine.gd")

var _machine: Machine
var _logs: Array[String] = []


func before_each() -> void:
	_machine = Machine.new()
	_logs.clear()
	autoload("EventBus").chip_log_added.connect(_on_log)


func after_each() -> void:
	autoload("EventBus").chip_log_added.disconnect(_on_log)
	_machine.free()


func _on_log(_machine_node: Node, message: String) -> void:
	_logs.append(message)


func test_set_enabled_applies() -> void:
	check(_machine.apply_tool_call("set_enabled", {"on": false}), "valid call accepted")
	check_eq(_machine.enabled, false, "machine disabled")


func test_unknown_tool_rejected_and_logged() -> void:
	check(not _machine.apply_tool_call("explode", {}), "unknown tool rejected")
	check_eq(_logs.size(), 1, "rejection logged")


func test_wrong_type_rejected() -> void:
	check(not _machine.apply_tool_call("set_enabled", {"on": "yes"}), "string is not a bool")
	check_eq(_machine.enabled, true, "state unchanged")


func test_missing_arg_rejected() -> void:
	check(not _machine.apply_tool_call("set_enabled", {}), "missing arg rejected")


func test_numbers_are_clamped() -> void:
	var speedy: Machine = SpeedMachine.new()
	check(speedy.apply_tool_call("set_speed", {"value": 5, "level": 9}), "out-of-range call accepted")
	check_eq(speedy.speed, 1.0, "number clamped high")
	check_eq(speedy.level, 3, "integer clamped high")
	speedy.apply_tool_call("set_speed", {"value": -3.0, "level": -4})
	check_eq(speedy.speed, 0.0, "number clamped low")
	check_eq(speedy.level, 1, "integer clamped low")
	check(not speedy.apply_tool_call("set_speed", {"value": "fast", "level": 2}), "string rejected for number")
	check_eq(speedy.speed, 0.0, "state unchanged after rejection")
	speedy.free()


func test_state_is_compact() -> void:
	var state: Dictionary = _machine.get_state()
	check_eq(state["status"], "normal", "status name")
	check_eq(state["enabled"], true, "enabled flag")
