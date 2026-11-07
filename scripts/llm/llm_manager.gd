extends Node
## The only code allowed to do HTTP. Queue, concurrency cap, timeouts, 429 backoff.
## Callers use request_decision() and listen to the two signals. requester_id is the
## caller's instance id: re-validate with is_instance_valid(instance_from_id(id)) on receipt.

signal decision_received(requester_id: int, tool_calls: Array[Dictionary])
signal decision_failed(requester_id: int, reason: String)

const MAX_RETRIES: int = 3
const BACKOFF_BASE: float = 1.0

var _queue: Array[Dictionary] = []
var _in_flight: int = 0
var _idle_requests: Array[HTTPRequest] = []


func request_decision(requester_id: int, system_prompt: String, state: Dictionary, tools: Array) -> void:
	for i: int in range(_queue.size() - 1, -1, -1):
		if _queue[i]["requester_id"] == requester_id:
			_queue.remove_at(i)
			decision_failed.emit(requester_id, "superseded")
	_queue.append({
		"requester_id": requester_id,
		"system_prompt": system_prompt,
		"state": state,
		"tools": tools,
	})
	_pump()


func _pump() -> void:
	while not _queue.is_empty() and _in_flight < Settings.max_concurrency:
		var job: Dictionary = _queue.pop_front()
		if not _requester_alive(job["requester_id"]):
			continue
		_in_flight += 1
		_run(job)


func _run(job: Dictionary) -> void:
	var provider: LLMProvider = _make_provider()
	var outcome: Dictionary = {"calls": [], "error": "unknown provider '%s'" % Settings.provider, "status": 0}
	if provider != null:
		for attempt: int in range(MAX_RETRIES + 1):
			outcome = await _execute(provider, job)
			if not _requester_alive(job["requester_id"]):
				break
			if outcome["status"] != 429 or attempt == MAX_RETRIES:
				break
			await get_tree().create_timer(BACKOFF_BASE * pow(2.0, attempt)).timeout
			if not _requester_alive(job["requester_id"]):
				break
	_in_flight -= 1
	var id: int = job["requester_id"]
	if not _requester_alive(id):
		_pump()
		return
	if outcome["error"] == "":
		var calls: Array[Dictionary] = []
		calls.assign(outcome["calls"])
		decision_received.emit(id, calls)
	else:
		decision_failed.emit(id, outcome["error"])
	_pump()


func _execute(provider: LLMProvider, job: Dictionary) -> Dictionary:
	var request: Dictionary = provider.build_request(job["system_prompt"], job["state"], job["tools"])
	if not provider.requires_network():
		await get_tree().create_timer(provider.simulated_latency()).timeout
		if not _requester_alive(job["requester_id"]):
			return _outcome([], "requester removed", 0)
		return _outcome(provider.parse_response(request["body"]), "", 200)

	var http: HTTPRequest = _acquire()
	http.timeout = Settings.request_timeout
	var headers: PackedStringArray = PackedStringArray(request["headers"])
	var err: Error = http.request(request["url"], headers, HTTPClient.METHOD_POST, JSON.stringify(request["body"]))
	if err != OK:
		_release(http)
		return _outcome([], "request failed to start (error %d)" % err, 0)
	var response: Array = await http.request_completed
	_release(http)
	if not _requester_alive(job["requester_id"]):
		return _outcome([], "requester removed", 0)

	var result: int = response[0]
	var status: int = response[1]
	var raw: PackedByteArray = response[3]
	if result != HTTPRequest.RESULT_SUCCESS:
		return _outcome([], "network error (result %d)" % result, 0)
	if status != 200:
		return _outcome([], "HTTP %d" % status, status)
	var parsed: Variant = JSON.parse_string(raw.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY:
		return _outcome([], "invalid JSON response", status)
	return _outcome(provider.parse_response(parsed), "", status)


func _outcome(calls: Array, error: String, status: int) -> Dictionary:
	return {"calls": calls, "error": error, "status": status}


func _requester_alive(id: int) -> bool:
	var requester: Object = instance_from_id(id)
	return is_instance_valid(requester) and requester is Node and requester.is_inside_tree() and not requester.is_queued_for_deletion()


func _make_provider() -> LLMProvider:
	match Settings.provider:
		"mock":
			return MockProvider.new()
	return null


func _acquire() -> HTTPRequest:
	if not _idle_requests.is_empty():
		return _idle_requests.pop_back()
	var http: HTTPRequest = HTTPRequest.new()
	add_child(http)
	return http


func _release(http: HTTPRequest) -> void:
	_idle_requests.append(http)
