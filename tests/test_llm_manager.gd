extends "res://tests/test_case.gd"

const TOOLS: Array = [{
	"name": "set_speed",
	"description": "Set speed",
	"input_schema": {"type": "object", "properties": {
		"value": {"type": "number", "minimum": 0.0, "maximum": 1.0},
		"on": {"type": "boolean"},
	}},
}]

var _llm: Node
var _settings: Node
var _received: Dictionary = {}
var _failed: Dictionary = {}
var _saved_provider: String = ""
var _saved_concurrency: int = 4
var _requesters: Array[Node] = []


func before_each() -> void:
	_llm = autoload("LLMManager")
	_settings = autoload("Settings")
	_saved_provider = _settings.provider
	_saved_concurrency = _settings.max_concurrency
	_settings.provider = "mock"
	_settings.max_concurrency = 4
	_received.clear()
	_failed.clear()
	_llm.decision_received.connect(_on_received)
	_llm.decision_failed.connect(_on_failed)


func after_each() -> void:
	for requester: Node in _requesters:
		if is_instance_valid(requester):
			requester.free()
	_requesters.clear()
	_llm.decision_received.disconnect(_on_received)
	_llm.decision_failed.disconnect(_on_failed)
	_settings.provider = _saved_provider
	_settings.max_concurrency = _saved_concurrency


func _requester() -> int:
	var node: Node = Node.new()
	tree.root.add_child(node)
	_requesters.append(node)
	return node.get_instance_id()


func _on_received(id: int, calls: Array[Dictionary]) -> void:
	_received[id] = calls


func _on_failed(id: int, reason: String) -> void:
	_failed[id] = reason


func test_mock_returns_normalized_call() -> void:
	var id: int = _requester()
	_llm.request_decision(id, "prompt", {"temp": 50}, TOOLS)
	await wait_until(func() -> bool: return _received.has(id), 4.0)
	check(_received.has(id), "decision_received for the requester")
	var calls: Array = _received.get(id, [])
	check(calls.size() == 1 and calls[0]["name"] == "set_speed", "one normalized {name, args} call")
	if calls.size() == 1:
		var args: Dictionary = calls[0]["args"]
		var value: float = args.get("value", -1.0)
		check(value >= 0.0 and value <= 1.0, "number arg within the schema range")
		check(args.get("on") is bool, "boolean arg generated")
	check(_failed.is_empty(), "no failures")


func test_mock_with_no_tools_returns_no_calls() -> void:
	var id: int = _requester()
	_llm.request_decision(id, "prompt", {}, [])
	await wait_until(func() -> bool: return _received.has(id), 4.0)
	check_eq(_received.get(id, null), [], "empty tool list gives no calls")


func test_newer_request_supersedes_queued_one() -> void:
	_settings.max_concurrency = 1
	var first: int = _requester()
	var second: int = _requester()
	_llm.request_decision(first, "p", {}, TOOLS)
	_llm.request_decision(second, "p", {}, TOOLS)
	_llm.request_decision(second, "p", {}, TOOLS)
	check_eq(_failed.get(second, ""), "superseded", "older queued request from the same requester fails as superseded")
	await wait_until(func() -> bool: return _received.has(first) and _received.has(second), 8.0)
	check(_received.has(first) and _received.has(second), "surviving requests still complete")


func test_concurrency_cap_queues_extra_requests() -> void:
	_settings.max_concurrency = 1
	for id: int in [_requester(), _requester(), _requester()]:
		_llm.request_decision(id, "p", {}, TOOLS)
	check_eq(_llm._in_flight, 1, "only 1 in flight with max_concurrency 1")
	check_eq(_llm._queue.size(), 2, "the other 2 are queued")
	await wait_until(func() -> bool: return _received.size() == 3, 10.0)
	check_eq(_received.size(), 3, "all 3 eventually complete")
	check(_llm._in_flight == 0 and _llm._queue.is_empty(), "nothing left in flight or queued")


func test_unknown_provider_fails_cleanly() -> void:
	_settings.provider = "bogus"
	var id: int = _requester()
	_llm.request_decision(id, "p", {}, TOOLS)
	await wait_until(func() -> bool: return _failed.has(id), 3.0)
	check(_failed.has(id), "decision_failed emitted")
	check(not _received.has(id), "no decision_received on failure")
	check_eq(_llm._in_flight, 0, "failure releases the in-flight slot")


func test_removed_requesters_are_discarded() -> void:
	_settings.max_concurrency = 1
	var active: int = _requester()
	var queued: int = _requester()
	var live: int = _requester()
	_llm.request_decision(active, "p", {}, TOOLS)
	_llm.request_decision(queued, "p", {}, TOOLS)
	_llm.request_decision(live, "p", {}, TOOLS)
	instance_from_id(active).free()
	instance_from_id(queued).free()
	await wait_until(func() -> bool: return _received.has(live), 5.0)
	check(_received.has(live), "live request completes after removed requesters")
	check(not _received.has(active) and not _failed.has(active), "removed active requester receives no signal")
	check(not _received.has(queued) and not _failed.has(queued), "removed queued requester receives no signal")
	check(_llm._in_flight == 0 and _llm._queue.is_empty(), "removed requests release capacity")


## The runner swaps in a fast-mock manager, so this covers the production script itself.
func test_production_manager_picks_the_unmodified_mock_provider() -> void:
	var production: Node = (load("res://scripts/llm/llm_manager.gd") as GDScript).new()
	_settings.provider = "mock"
	var provider: LLMProvider = production._make_provider()
	check(provider is MockProvider and provider.get_script() == MockProvider, "mock selects MockProvider itself, not a test subclass")
	check(provider.requires_network() == false, "offline")
	for i: int in 20:
		var latency: float = provider.simulated_latency()
		check(latency >= 0.3 and latency <= 1.5, "production mock latency is unchanged (0.3 to 1.5 s)")
	_settings.provider = "anthropic"
	check(production._make_provider() is AnthropicProvider, "anthropic")
	_settings.provider = "openai"
	check(production._make_provider() is OpenAIProvider, "openai")
	_settings.provider = "nope"
	check(production._make_provider() == null, "unknown provider")
	production.free()
	_settings.provider = "mock"
	check(autoload("LLMManager")._make_provider() is MockProvider, "the suite's manager is also a MockProvider, only faster")
	check(autoload("LLMManager")._make_provider().simulated_latency() < 0.1, "the suite stays fast")
