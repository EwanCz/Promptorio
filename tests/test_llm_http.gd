extends "res://tests/test_case.gd"
## The real HTTP path of LLMManager, offline: a scripted manager replays canned responses.

const ScriptedManager: GDScript = preload("res://tests/support/scripted_llm_manager.gd")
const OK_BODY: String = '{"content": [{"type": "tool_use", "name": "set_enabled", "input": {"on": true}}]}'

var _llm: Node
var _settings: Node
var _requester: Node
var _received: Dictionary = {}
var _failed: Dictionary = {}
var _saved_provider: String = ""
var _saved_key: String = ""
var _saved_env_path: String = ""
var _saved_debug: String = ""
var _saved_editor_run: bool = true
var _saved_base_url: String = ""
var _checks: Array[Array] = []


func before_each() -> void:
	_settings = autoload("Settings")
	_saved_provider = _settings.provider
	_saved_key = _settings.api_key
	_saved_env_path = _settings.env_path
	_settings.provider = "anthropic"
	_settings.api_key = "k"
	_settings.env_path = "user://missing.env"
	_settings.load_env()
	_saved_editor_run = _settings.editor_run
	_settings.editor_run = false
	_saved_base_url = _settings.anthropic_base_url
	_settings.anthropic_base_url = ""
	_saved_debug = OS.get_environment("PROMPTORIO_DEBUG_LLM")
	OS.unset_environment("PROMPTORIO_DEBUG_LLM")
	_llm = ScriptedManager.new()
	tree.root.add_child(_llm)
	_requester = Node.new()
	tree.root.add_child(_requester)
	_received.clear()
	_failed.clear()
	_llm.decision_received.connect(_on_received)
	_llm.decision_failed.connect(_on_failed)
	_checks.clear()
	autoload("EventBus").key_checked.connect(_on_key_checked)


func after_each() -> void:
	_llm.decision_received.disconnect(_on_received)
	_llm.decision_failed.disconnect(_on_failed)
	autoload("EventBus").key_checked.disconnect(_on_key_checked)
	_llm.free()
	_requester.free()
	_settings.provider = _saved_provider
	_settings.api_key = _saved_key
	_settings.env_path = _saved_env_path
	_settings.editor_run = _saved_editor_run
	_settings.anthropic_base_url = _saved_base_url
	_settings.load_env()
	if _saved_debug == "":
		OS.unset_environment("PROMPTORIO_DEBUG_LLM")
	else:
		OS.set_environment("PROMPTORIO_DEBUG_LLM", _saved_debug)


func _on_received(id: int, calls: Array[Dictionary]) -> void:
	_received[id] = calls


func _on_failed(id: int, reason: String) -> void:
	_failed[id] = reason


func _on_key_checked(state: String, detail: String) -> void:
	_checks.append([state, detail])


func _reply(result: int, status: int, body: String = "") -> Dictionary:
	return {"result": result, "status": status, "body": body.to_utf8_buffer()}


## Queues the scripted responses, sends one request and waits for its outcome.
func _ask(scripted: Array[Dictionary]) -> int:
	_llm.responses = scripted
	var id: int = _requester.get_instance_id()
	_llm.request_decision(id, "p", {}, [])
	await wait_until(func() -> bool: return _received.has(id) or _failed.has(id), 6.0)
	return id


func _check_failed(id: int, reason: String, label: String) -> void:
	check_eq(_failed.get(id, ""), reason, label)
	check(not _received.has(id), "%s: no decision_received" % label)
	check(_llm._in_flight == 0 and _llm._queue.is_empty(), "%s: slot released" % label)


func test_success_parses_tool_calls() -> void:
	var id: int = await _ask([_reply(HTTPRequest.RESULT_SUCCESS, 200, OK_BODY)])
	check_eq(_received.get(id, []), [{"name": "set_enabled", "args": {"on": true}}], "normalized call")
	check(_failed.is_empty(), "no failure")


func test_timeout_fails_without_retry() -> void:
	var id: int = await _ask([_reply(HTTPRequest.RESULT_TIMEOUT, 0)])
	_check_failed(id, "network error (result %d)" % HTTPRequest.RESULT_TIMEOUT, "timeout")
	check_eq(_llm.sent, 1, "timeout is not retried")


func test_transport_failure_fails_cleanly() -> void:
	var id: int = await _ask([_reply(HTTPRequest.RESULT_CANT_CONNECT, 0)])
	_check_failed(id, "network error (result %d)" % HTTPRequest.RESULT_CANT_CONNECT, "transport failure")


func test_non_200_fails_with_status() -> void:
	var id: int = await _ask([_reply(HTTPRequest.RESULT_SUCCESS, 500, "boom")])
	_check_failed(id, "HTTP 500", "server error")
	check_eq(_llm.sent, 1, "5xx is not retried")


func test_invalid_json_fails() -> void:
	var id: int = await _ask([_reply(HTTPRequest.RESULT_SUCCESS, 200, "not json")])
	_check_failed(id, "invalid JSON response", "garbage body")


func test_json_that_is_not_an_object_fails() -> void:
	var id: int = await _ask([_reply(HTTPRequest.RESULT_SUCCESS, 200, "[1, 2]")])
	_check_failed(id, "invalid JSON response", "array body")


func test_429_then_success_retries_with_backoff() -> void:
	var id: int = await _ask([
		_reply(HTTPRequest.RESULT_SUCCESS, 429),
		_reply(HTTPRequest.RESULT_SUCCESS, 429),
		_reply(HTTPRequest.RESULT_SUCCESS, 200, OK_BODY),
	])
	check(_received.has(id) and _failed.is_empty(), "succeeds after two 429s")
	check_eq(_llm.sent, 3, "three attempts")
	check_eq(_llm.delays, [1.0, 2.0] as Array[float], "retry delays double: 1s, 2s")


func test_429_retries_are_capped_at_three() -> void:
	var id: int = await _ask([_reply(HTTPRequest.RESULT_SUCCESS, 429)])
	_check_failed(id, "HTTP 429", "persistent 429")
	check_eq(_llm.sent, 4, "1 attempt + 3 retries")
	check_eq(_llm.delays, [1.0, 2.0, 4.0] as Array[float], "retry delays double: 1s, 2s, 4s")


func test_error_type_is_reported_without_the_message_by_default() -> void:
	var body: String = '{"type": "error", "error": {"type": "authentication_error", "message": "invalid x-api-key sk-secret"}}'
	var id: int = await _ask([_reply(HTTPRequest.RESULT_SUCCESS, 401, body)])
	_check_failed(id, "HTTP 401 (authentication_error)", "401 with an API error body")


func _script(replies: Array[Dictionary]) -> void:
	_llm.responses = replies


func _error_body(message: String) -> String:
	return JSON.stringify({"type": "error", "error": {"type": "invalid_request_error", "message": message}})


## Diagnostics are editor-only, so with the flag on an export-like run (no "editor" feature) must stay quiet.
func _debug_on() -> bool:
	_settings.api_key = "my-secret-key-123"
	OS.set_environment("PROMPTORIO_DEBUG_LLM", "1")
	return OS.has_feature("editor")


func test_debug_off_reports_status_and_type_only() -> void:
	var id: int = await _ask([_reply(HTTPRequest.RESULT_SUCCESS, 400, _error_body("max_tokens too large"))])
	_check_failed(id, "HTTP 400 (invalid_request_error)", "flag unset")
	check(not _llm._debug_enabled(), "diagnostics are off by default")


## A provider could put the key in `error.type` instead of `error.message`; that field must be
## masked too, since it is always included in the ChipLog text regardless of the debug flag.
func test_error_type_field_is_sanitized_with_debug_off() -> void:
	_settings.api_key = "my-secret-key-123"
	var body: String = JSON.stringify({"error": {"type": "my-secret-key-123"}})
	var id: int = await _ask([_reply(HTTPRequest.RESULT_SUCCESS, 401, body)])
	_check_failed(id, "HTTP 401 ([redacted])", "type field masked, diagnostics off")
	check(not _failed[id].contains("my-secret-key-123"), "key never appears in the failure")


func test_error_type_field_is_sanitized_with_debug_on() -> void:
	_debug_on()
	var body: String = JSON.stringify({"error": {"type": "my-secret-key-123"}})
	var id: int = await _ask([_reply(HTTPRequest.RESULT_SUCCESS, 401, body)])
	_check_failed(id, "HTTP 401 ([redacted])", "type field masked, diagnostics on")
	check(not _failed[id].contains("my-secret-key-123"), "key never appears in the failure")


func test_debug_flag_value_must_be_exactly_one() -> void:
	OS.set_environment("PROMPTORIO_DEBUG_LLM", "true")
	check(not _llm._debug_enabled(), "'true' does not enable diagnostics")
	OS.set_environment("PROMPTORIO_DEBUG_LLM", "0")
	check(not _llm._debug_enabled(), "'0' does not enable diagnostics")


func test_debug_on_appends_the_provider_message() -> void:
	var expected_on: bool = _debug_on()
	check_eq(_llm._debug_enabled(), expected_on, "enabled only in an editor run")
	var id: int = await _ask([_reply(HTTPRequest.RESULT_SUCCESS, 400, _error_body("max_tokens too large"))])
	var tail: String = ": max_tokens too large" if expected_on else ""
	_check_failed(id, "HTTP 400 (invalid_request_error)" + tail, "message appended")
	check(not _failed[id].contains("{"), "raw response body is not logged")


func test_debug_on_without_an_error_message_changes_nothing() -> void:
	_debug_on()
	var id: int = await _ask([_reply(HTTPRequest.RESULT_SUCCESS, 500, "boom")])
	_check_failed(id, "HTTP 500", "non-JSON body is never logged")


func test_debug_message_is_sanitized() -> void:
	if not _debug_on():
		return
	var message: String = "bad key my-secret-key-123\nand sk-ant-api03-AAAAAAAAAAAAAAAAAAAAAAAA\t  here"
	var id: int = await _ask([_reply(HTTPRequest.RESULT_SUCCESS, 401, _error_body(message))])
	_check_failed(id, "HTTP 401 (invalid_request_error): bad key [redacted] and [redacted] here", "key and token masked, whitespace collapsed")
	check(not _failed[id].contains("my-secret-key-123"), "configured key never appears")


func test_debug_message_is_truncated() -> void:
	if not _debug_on():
		return
	var id: int = await _ask([_reply(HTTPRequest.RESULT_SUCCESS, 400, _error_body("word ".repeat(100)))])
	var prefix: String = "HTTP 400 (invalid_request_error): "
	var message: String = _failed[id].trim_prefix(prefix)
	check_eq(message.length(), _llm.DEBUG_MAX_CHARS + 3, "capped, plus the ellipsis")
	check(message.ends_with("..."), "marked as truncated")


func test_no_key_fails_before_any_request() -> void:
	_settings.api_key = ""
	var id: int = await _ask([_reply(HTTPRequest.RESULT_SUCCESS, 200, OK_BODY)])
	_check_failed(id, "no API key (set one in Settings or .env)", "missing key")
	check_eq(_llm.sent, 0, "nothing is sent without a key")


func test_env_key_is_enough_to_send() -> void:
	_settings.api_key = ""
	var path: String = "user://test_llm_http.env"
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_line("ANTHROPIC_API_KEY=from-env")
	file.close()
	_settings.env_path = path
	_settings.load_env()
	var id: int = await _ask([_reply(HTTPRequest.RESULT_SUCCESS, 200, OK_BODY)])
	DirAccess.remove_absolute(path)
	check(_received.has(id) and _failed.is_empty(), "the .env key lets the request go out")
	check_eq(_llm.sent, 1, "one request sent")


func test_check_key_valid() -> void:
	_script([_reply(HTTPRequest.RESULT_SUCCESS, 200, "{}")])
	await _llm.check_key()
	check_eq(_checks, [["valid", ""]], "200 means the key works")
	check_eq(_llm.requests[0]["method"], HTTPClient.METHOD_GET, "a GET probe, not a chat request")
	check_eq(_llm.sent, 1, "one request")


func test_check_key_rejected_keys_are_invalid() -> void:
	var body: String = '{"type": "error", "error": {"type": "authentication_error", "message": "invalid x-api-key"}}'
	_script([_reply(HTTPRequest.RESULT_SUCCESS, 401, body)])
	await _llm.check_key()
	check_eq(_checks, [["invalid", "HTTP 401 (authentication_error)"]], "401 is an invalid key")
	_checks.clear()
	_script([_reply(HTTPRequest.RESULT_SUCCESS, 403)])
	await _llm.check_key()
	check_eq(_checks, [["invalid", "HTTP 403"]], "403 is an invalid key")


func test_check_key_other_failures_are_unverified_not_invalid() -> void:
	_script([_reply(HTTPRequest.RESULT_SUCCESS, 500)])
	await _llm.check_key()
	_script([_reply(HTTPRequest.RESULT_SUCCESS, 429)])
	await _llm.check_key()
	_script([_reply(HTTPRequest.RESULT_TIMEOUT, 0)])
	await _llm.check_key()
	check_eq(_checks, [
		["error", "HTTP 500"],
		["error", "HTTP 429"],
		["error", "network error (result %d)" % HTTPRequest.RESULT_TIMEOUT],
	], "a server or network problem never says the key is wrong")


func test_check_key_skips_the_request_without_a_key_or_for_mock() -> void:
	_script([_reply(HTTPRequest.RESULT_SUCCESS, 200, "{}")])
	_settings.api_key = ""
	await _llm.check_key()
	_settings.provider = "mock"
	await _llm.check_key()
	check_eq(_llm.sent, 0, "nothing sent")
	check(_checks.is_empty(), "nothing reported")
