extends "res://tests/test_case.gd"

var _saved_key: String = ""
var _saved_base_url: String = ""
var _saved_editor_run: bool = true
var _saved_model: String = ""


func before_each() -> void:
	_saved_base_url = autoload("Settings").openai_base_url
	autoload("Settings").openai_base_url = ""
	_saved_editor_run = autoload("Settings").editor_run
	autoload("Settings").editor_run = false
	_saved_key = autoload("Settings").openai_api_key
	_saved_model = autoload("Settings").openai_model


func after_each() -> void:
	autoload("Settings").openai_base_url = _saved_base_url
	autoload("Settings").editor_run = _saved_editor_run
	autoload("Settings").openai_api_key = _saved_key
	autoload("Settings").openai_model = _saved_model


func test_build_request() -> void:
	autoload("Settings").openai_api_key = "ck"
	autoload("Settings").openai_model = "gpt-6-luna"
	var tools: Array = [{"name": "set_speed", "description": "d", "input_schema": {"type": "object", "properties": {"v": {"type": "number"}}}}]
	var req: Dictionary = OpenAIProvider.new().build_request("sys", {"a": 1}, tools)
	check_eq(req["url"], OpenAIProvider.URL, "url")
	check("authorization: Bearer ck" in req["headers"], "bearer header")
	check_eq(req["body"]["model"], "gpt-6-luna", "openai model used")
	check_eq(req["body"]["instructions"], "sys", "system prompt")
	check_eq(req["body"]["tool_choice"], "required", "tool use forced")
	check(req["body"]["max_output_tokens"] <= 300, "token cap")
	var tool: Dictionary = req["body"]["tools"][0]
	check_eq([tool["type"], tool["name"]], ["function", "set_speed"], "tool converted")
	check_eq(tool["parameters"]["required"], ["v"], "all properties required")
	check(not tools[0]["input_schema"].has("required"), "input schema not mutated")


func test_check_request_is_a_free_authenticated_get() -> void:
	autoload("Settings").openai_api_key = "ck"
	var req: Dictionary = OpenAIProvider.new().build_check_request()
	check_eq(req["method"], HTTPClient.METHOD_GET, "GET")
	check(req["url"].contains("/v1/models"), "lists models, no tokens spent")
	check("authorization: Bearer ck" in req["headers"], "bearer header")
	check(not req.has("body"), "no body")


func test_parse_response() -> void:
	var p: OpenAIProvider = OpenAIProvider.new()
	var calls: Array[Dictionary] = p.parse_response({"output": [
		{"type": "reasoning"},
		{"type": "function_call", "name": "set_enabled", "arguments": "{\"on\": true}"},
		{"type": "function_call", "name": "bad", "arguments": "not json"},
	]})
	check_eq(calls.size(), 2, "only function calls")
	check_eq(calls[0], {"name": "set_enabled", "args": {"on": true}}, "args parsed from the JSON string")
	check_eq(calls[1]["args"], {}, "bad JSON becomes empty")
	check_eq(p.parse_response({"output": "oops"}).size(), 0, "garbage output ignored")
