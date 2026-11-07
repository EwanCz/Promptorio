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


func before_each() -> void:
	_settings = autoload("Settings")
	_saved_provider = _settings.provider
	_saved_key = _settings.api_key
	_saved_env_path = _settings.env_path
	_settings.provider = "anthropic"
	_settings.api_key = "k"
	_settings.env_path = "user://missing.env"
	_settings.load_env()
	_llm = ScriptedManager.new()
	tree.root.add_child(_llm)
	_requester = Node.new()
	tree.root.add_child(_requester)
	_received.clear()
	_failed.clear()
	_llm.decision_received.connect(_on_received)
	_llm.decision_failed.connect(_on_failed)


func after_each() -> void:
	_llm.decision_received.disconnect(_on_received)
	_llm.decision_failed.disconnect(_on_failed)
	_llm.free()
	_requester.free()
	_settings.provider = _saved_provider
	_settings.api_key = _saved_key
	_settings.env_path = _saved_env_path
	_settings.load_env()


func _on_received(id: int, calls: Array[Dictionary]) -> void:
	_received[id] = calls


func _on_failed(id: int, reason: String) -> void:
	_failed[id] = reason


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


func test_error_type_is_reported_without_the_message() -> void:
	var body: String = '{"type": "error", "error": {"type": "authentication_error", "message": "invalid x-api-key sk-secret"}}'
	var id: int = await _ask([_reply(HTTPRequest.RESULT_SUCCESS, 401, body)])
	_check_failed(id, "HTTP 401 (authentication_error)", "401 with an API error body")


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
