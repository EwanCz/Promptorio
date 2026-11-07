extends "res://tests/test_case.gd"
## ANTHROPIC_BASE_URL: relay origin for editor runs (process env, then .env, then the official endpoint).

const ScriptedManager: GDScript = preload("res://tests/support/scripted_llm_manager.gd")
const ENV_FILE: String = "user://test_base_url.env"
const VAR: String = "ANTHROPIC_BASE_URL"

var _settings: Node
var _saved: Dictionary = {}
var _checks: Array[Array] = []


func before_each() -> void:
	_settings = autoload("Settings")
	_saved = {
		"env": OS.get_environment(VAR),
		"env_path": _settings.env_path,
		"editor_run": _settings.editor_run,
		"provider": _settings.provider,
		"api_key": _settings.api_key,
		"base_url": _settings.anthropic_base_url,
	}
	_settings.anthropic_base_url = ""
	OS.unset_environment(VAR)
	_settings.env_path = "user://missing.env"
	_settings.editor_run = true
	_settings.provider = "anthropic"
	_settings.api_key = "relay-key"
	_settings.load_env()
	_checks.clear()
	autoload("EventBus").key_checked.connect(_on_key_checked)


func after_each() -> void:
	autoload("EventBus").key_checked.disconnect(_on_key_checked)
	if _saved["env"] == "":
		OS.unset_environment(VAR)
	else:
		OS.set_environment(VAR, _saved["env"])
	DirAccess.remove_absolute(ENV_FILE)
	_settings.env_path = _saved["env_path"]
	_settings.editor_run = _saved["editor_run"]
	_settings.provider = _saved["provider"]
	_settings.api_key = _saved["api_key"]
	_settings.anthropic_base_url = _saved["base_url"]
	_settings.load_env()


func _on_key_checked(state: String, detail: String) -> void:
	_checks.append([state, detail])


func _write_env(value: String) -> void:
	var file: FileAccess = FileAccess.open(ENV_FILE, FileAccess.WRITE)
	file.store_line("%s=%s" % [VAR, value])
	file.close()
	_settings.env_path = ENV_FILE
	_settings.load_env()


func _urls() -> Array[String]:
	var provider: AnthropicProvider = AnthropicProvider.new()
	return [provider.build_request("s", {}, [])["url"], provider.build_check_request()["url"]]


func _official() -> Array[String]:
	return ["https://api.anthropic.com/v1/messages", "https://api.anthropic.com/v1/models?limit=1"]


func test_defaults_to_the_official_endpoints() -> void:
	check_eq(_urls(), _official(), "chat and key check use api.anthropic.com")
	check_eq(AnthropicProvider.new().config_error(), "", "nothing to complain about")


func test_process_environment_beats_dot_env() -> void:
	_write_env("https://file.example.com")
	OS.set_environment(VAR, "https://env.example.com")
	check_eq(_urls(), ["https://env.example.com/v1/messages", "https://env.example.com/v1/models?limit=1"] as Array[String], "env wins")


func test_dot_env_is_used_when_the_process_variable_is_absent() -> void:
	_write_env("https://file.example.com")
	check_eq(_urls(), ["https://file.example.com/v1/messages", "https://file.example.com/v1/models?limit=1"] as Array[String], ".env used")
	OS.set_environment(VAR, "")
	check_eq(_urls()[0], "https://file.example.com/v1/messages", "an empty process variable counts as absent")


func test_trailing_slashes_are_normalized_on_both_paths() -> void:
	OS.set_environment(VAR, "  https://relay.example.com:8443//  ")
	check_eq(_urls(), ["https://relay.example.com:8443/v1/messages", "https://relay.example.com:8443/v1/models?limit=1"] as Array[String], "one slash between origin and path")
	check_eq(AnthropicProvider.new().config_error(), "", "valid origin")
	var req: Dictionary = AnthropicProvider.new().build_request("s", {}, [])
	check("x-api-key: relay-key" in req["headers"], "the key is still the x-api-key header")


func test_exported_builds_ignore_the_override() -> void:
	_write_env("https://file.example.com")
	OS.set_environment(VAR, "https://env.example.com")
	_settings.editor_run = false
	check_eq(_urls(), _official(), "official endpoints, override ignored")
	OS.set_environment(VAR, "http://not-valid")
	check_eq(AnthropicProvider.new().config_error(), "", "an ignored override is not validated either")


func test_malformed_overrides_are_rejected_without_echoing_them() -> void:
	for value: String in ["http://relay.example.com", "relay.example.com", "https://", "https://relay.example.com/api", "https://relay.example.com?x=1", "https://user:secret@relay.example.com", "https://relay example.com"]:
		OS.set_environment(VAR, value)
		var message: String = AnthropicProvider.new().config_error()
		check(message.contains("https origin"), "rejected: %s" % value.get_slice("@", 0))
		check(not message.contains("secret"), "the message never repeats the value")


func test_a_malformed_override_fails_before_any_request() -> void:
	OS.set_environment(VAR, "http://relay.example.com")
	var llm: Node = ScriptedManager.new()
	tree.root.add_child(llm)
	llm.responses = [{"result": HTTPRequest.RESULT_SUCCESS, "status": 200, "body": "{}".to_utf8_buffer()}] as Array[Dictionary]
	var failed: Array[String] = []
	var on_failed: Callable = func(_id: int, reason: String) -> void: failed.append(reason)
	llm.decision_failed.connect(on_failed)
	var requester: Node = Node.new()
	tree.root.add_child(requester)
	llm.request_decision(requester.get_instance_id(), "p", {}, [])
	await wait_until(func() -> bool: return not failed.is_empty(), 6.0)
	await llm.check_key()
	check(failed.size() == 1 and failed[0].contains("base URL"), "chat request fails clearly")
	check_eq(_checks.size(), 1, "key check reports once")
	check(_checks[0][0] == "error" and _checks[0][1].contains("base URL"), "key check says what is wrong, not that the key is bad")
	check_eq(llm.sent, 0, "the key was never sent anywhere")
	llm.decision_failed.disconnect(on_failed)
	llm.free()
	requester.free()


func test_a_valid_override_reaches_the_send_seam() -> void:
	OS.set_environment(VAR, "https://relay.example.com/")
	var llm: Node = ScriptedManager.new()
	tree.root.add_child(llm)
	llm.responses = [{"result": HTTPRequest.RESULT_SUCCESS, "status": 200, "body": "{}".to_utf8_buffer()}] as Array[Dictionary]
	await llm.check_key()
	check_eq(llm.requests[0]["url"], "https://relay.example.com/v1/models?limit=1", "the probe goes to the relay")
	llm.free()


func test_saved_setting_beats_the_environment_and_dot_env() -> void:
	_write_env("https://file.example.com")
	OS.set_environment(VAR, "https://env.example.com")
	_settings.anthropic_base_url = " https://saved.example.com/ "
	check_eq(_urls(), ["https://saved.example.com/v1/messages", "https://saved.example.com/v1/models?limit=1"] as Array[String], "saved value wins, normalized")
	_settings.anthropic_base_url = ""
	check_eq(_urls()[0], "https://env.example.com/v1/messages", "blank falls back to the environment")


func test_saved_setting_also_applies_to_exported_builds() -> void:
	_settings.editor_run = false
	OS.set_environment(VAR, "https://env.example.com")
	check_eq(_urls(), _official(), "environment ignored")
	_settings.anthropic_base_url = "https://saved.example.com"
	check_eq(_urls()[0], "https://saved.example.com/v1/messages", "a player-entered relay works in an export")


func test_malformed_saved_setting_is_rejected() -> void:
	for value: String in ["http://relay.example.com", "relay.example.com", "https://relay.example.com/v1", "https://user:secret@relay.example.com"]:
		_settings.anthropic_base_url = value
		var message: String = AnthropicProvider.new().config_error()
		check(message.contains("https origin"), "rejected: %s" % value.get_slice("@", 0))
		check(not message.contains("secret"), "the message never repeats the value")
