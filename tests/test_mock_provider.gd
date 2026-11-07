extends "res://tests/test_case.gd"

const TOOLS: Array = [
	{"name": "set_speed", "input_schema": {"type": "object", "properties": {
		"value": {"type": "number", "minimum": 0.0, "maximum": 1.0},
		"level": {"type": "integer", "minimum": 2, "maximum": 9},
		"on": {"type": "boolean"},
	}}},
	{"name": "other", "input_schema": {"type": "object", "properties": {}}},
]


func _calls(tools: Array) -> Array[Dictionary]:
	var mock: MockProvider = MockProvider.new()
	return mock.parse_response(mock.build_request("sys", {}, tools)["body"])


func test_canned_response_is_deterministic() -> void:
	var calls: Array[Dictionary] = _calls(TOOLS)
	check_eq(calls, [{"name": "set_speed", "args": {"value": 0.5, "level": 2, "on": true}}], "first tool, fixed args")
	for i: int in 5:
		check_eq(_calls(TOOLS), calls, "same answer on call %d" % i)


func test_empty_tool_list_gives_no_calls() -> void:
	check_eq(_calls([]), [], "no tools, no calls")


func test_latency_is_still_random_and_bounded() -> void:
	var mock: MockProvider = MockProvider.new()
	var seen: Dictionary = {}
	for i: int in 20:
		var latency: float = mock.simulated_latency()
		check(latency >= 0.3 and latency <= 1.5, "latency in range")
		seen[latency] = true
	check(seen.size() > 1, "latency varies")
