extends "res://tests/test_case.gd"
## Whole loop on the real provider path, offline: chip timer -> LLMManager -> Anthropic request ->
## scripted Anthropic reply -> tool call -> machine. The LLMManager autoload runs the scripted
## test double for the length of each test; a real network round-trip stays untested.

const ScriptedManager: GDScript = preload("res://tests/support/scripted_llm_manager.gd")
const REPLY: String = '{"content": [{"type": "tool_use", "name": "set_cooling", "input": {"on": true}}]}'

var _settings: Node
var _llm: Node
var _original_script: Script
var _machine: Machine
var _chip: ChipRessource
var _backup: Dictionary = {}
var _logs: Array[String] = []


func before_each() -> void:
	_settings = autoload("Settings")
	_backup = {
		"provider": _settings.provider,
		"api_key": _settings.api_key,
		"chip_cooldown": _settings.chip_cooldown,
		"env_path": _settings.env_path,
		"editor_run": _settings.editor_run,
		"anthropic_base_url": _settings.anthropic_base_url,
	}
	_settings.editor_run = false
	_settings.anthropic_base_url = ""
	_settings.provider = "anthropic"
	_settings.api_key = "test-key"
	_settings.chip_cooldown = 0.0
	_settings.env_path = "user://missing.env"
	_settings.load_env()
	_llm = autoload("LLMManager")
	_original_script = _llm.get_script()
	_llm.set_script(ScriptedManager)
	_chip = autoload("ChipRegistry").add("real_loop", "Keep the smelter cool")
	_machine = (load("res://scenes/machines/smelter.tscn") as PackedScene).instantiate() as Machine
	tree.root.add_child(_machine)
	autoload("EventBus").chip_log_added.connect(_on_log)
	_logs.clear()


func after_each() -> void:
	autoload("EventBus").chip_log_added.disconnect(_on_log)
	_machine.free()
	autoload("ChipRegistry").remove(_chip.id)
	_llm.set_script(_original_script)
	for key: String in _backup:
		_settings.set(key, _backup[key])
	_settings.load_env()


func _on_log(_source: Node, message: String) -> void:
	_logs.append(message)


func _reply(status: int, body: String) -> Dictionary:
	return {"result": HTTPRequest.RESULT_SUCCESS, "status": status, "body": body.to_utf8_buffer()}


func _ask_chip(reply: Dictionary) -> ChipComponent:
	_llm.responses.assign([reply])
	var component: ChipComponent = _machine.attach_chip(_chip.id)
	check(component.call_llm("manual"), "the chip sends a request")
	await wait_until(func() -> bool: return not component.pending, 6.0)
	return component


func test_chip_decision_goes_through_the_anthropic_request() -> void:
	await _ask_chip(_reply(200, REPLY))
	check(_machine.cooling, "the scripted tool call reached the smelter")
	var request: Dictionary = _llm.requests[0]
	check_eq(request["url"], AnthropicProvider.URL, "sent to the Anthropic endpoint")
	check("x-api-key: test-key" in request["headers"], "the key is sent as the x-api-key header")
	check_eq(request["body"]["system"], "Keep the smelter cool", "the chip prompt is the system prompt")
	var names: Array = (request["body"]["tools"] as Array).map(func(tool: Dictionary) -> String: return tool["name"])
	check_eq(names, ["set_enabled", "set_cooling"], "the smelter tools are offered")
	check(str(request["body"]["messages"][0]["content"]).contains("temperature"), "the machine state is sent")


func test_a_rejected_key_is_logged_and_the_machine_keeps_running() -> void:
	var body: String = '{"type": "error", "error": {"type": "authentication_error", "message": "invalid x-api-key"}}'
	var component: ChipComponent = await _ask_chip(_reply(401, body))
	check(not _machine.cooling and _machine.enabled, "the machine keeps its last settings")
	check("chip request failed: HTTP 401 (authentication_error)" in _logs, "the failure is in the chip log")
	check(not component.pending, "the chip can ask again")


func test_a_missing_key_is_logged_without_a_request() -> void:
	_settings.api_key = ""
	await _ask_chip(_reply(200, REPLY))
	check_eq(_llm.sent, 0, "nothing is sent")
	check("chip request failed: no API key (set one in Settings or .env)" in _logs, "the log says how to fix it")
