extends "res://tests/test_case.gd"

var _saved_key: String = ""
var _heard: Array = []


func before_each() -> void:
	_saved_key = autoload("Settings").api_key
	_heard.clear()


func after_each() -> void:
	autoload("Settings").api_key = _saved_key


func test_build_request() -> void:
	autoload("Settings").api_key = "k"
	var req: Dictionary = AnthropicProvider.new().build_request("sys", {"a": 1}, [{"name": "t"}])
	check_eq(req["url"], AnthropicProvider.URL, "url")
	check("x-api-key: k" in req["headers"], "api key header")
	check_eq(req["body"]["system"], "sys", "system prompt")
	check_eq(req["body"]["tool_choice"]["type"], "any", "tool use forced")
	check(req["body"]["max_tokens"] <= 300, "max_tokens capped")


func test_parse_response() -> void:
	var p: AnthropicProvider = AnthropicProvider.new()
	var calls: Array[Dictionary] = p.parse_response({"content": [
		{"type": "text", "text": "hi"},
		{"type": "tool_use", "name": "set_enabled", "input": {"on": true}},
		{"type": "tool_use", "name": "bad", "input": "x"},
	]})
	check_eq(calls.size(), 2, "only tool_use blocks")
	check_eq(calls[0]["args"], {"on": true}, "args kept")
	check_eq(calls[1]["args"], {}, "non-dict input becomes empty")
	check_eq(p.parse_response({"content": "oops"}).size(), 0, "garbage content ignored")


func test_chip_events_on_bus() -> void:
	var bus: Node = autoload("EventBus")
	bus.chip_registered.connect(_on_registered)
	bus.chip_removed.connect(_on_removed)
	var registry: Node = autoload("ChipRegistry")
	registry.remove(registry.add("bus_chip", "p").id)
	bus.chip_registered.disconnect(_on_registered)
	bus.chip_removed.disconnect(_on_removed)
	check_eq(_heard, ["reg", "rem"], "register then remove")


func _on_registered(_chip: Resource) -> void:
	_heard.append("reg")


func _on_removed(_chip: Resource) -> void:
	_heard.append("rem")
