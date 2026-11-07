extends "res://tests/test_case.gd"
## The real HTTP path of LLMManager, offline: a scripted manager replays canned responses.

const ScriptedManager: GDScript = preload("res://tests/support/scripted_llm_manager.gd")
const OK_BODY: String = '{"content": [{"type": "tool_use", "name": "set_enabled", "input": {"on": true}}]}'
const BASE: float = 0.1

var _llm: Node
var _settings: Node
var _requester: Node
var _received: Dictionary = {}
var _failed: Dictionary = {}
var _saved_provider: String = ""


func before_each() -> void:
	_settings = autoload("Settings")
	_saved_provider = _settings.provider
	_settings.provider = "anthropic"
	_llm = ScriptedManager.new()
	_llm.backoff_base = BASE
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
	check_eq(_llm.sent_msec.size(), 1, "timeout is not retried")


func test_transport_failure_fails_cleanly() -> void:
	var id: int = await _ask([_reply(HTTPRequest.RESULT_CANT_CONNECT, 0)])
	_check_failed(id, "network error (result %d)" % HTTPRequest.RESULT_CANT_CONNECT, "transport failure")


func test_non_200_fails_with_status() -> void:
	var id: int = await _ask([_reply(HTTPRequest.RESULT_SUCCESS, 500, "boom")])
	_check_failed(id, "HTTP 500", "server error")
	check_eq(_llm.sent_msec.size(), 1, "5xx is not retried")


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
	check_eq(_llm.sent_msec.size(), 3, "three attempts")
	_check_backoff_gaps()


func test_429_retries_are_capped_at_three() -> void:
	var id: int = await _ask([_reply(HTTPRequest.RESULT_SUCCESS, 429)])
	_check_failed(id, "HTTP 429", "persistent 429")
	check_eq(_llm.sent_msec.size(), 4, "1 attempt + 3 retries")
	_check_backoff_gaps()


## Each wait doubles (BASE, 2*BASE, 4*BASE), so the gaps between sends keep growing. Only the
## growth is asserted: a timer started mid-frame can fire up to one frame early.
func _check_backoff_gaps() -> void:
	var gaps: Array[int] = []
	for i: int in range(1, _llm.sent_msec.size()):
		gaps.append(_llm.sent_msec[i] - _llm.sent_msec[i - 1])
	for i: int in range(1, gaps.size()):
		check(gaps[i] > gaps[i - 1], "wait %d is longer than wait %d" % [i + 1, i])
	check(gaps[-1] >= int(BASE * pow(2.0, gaps.size() - 1) * 1000.0 * 0.5), "last wait is about BASE * 2^n")
