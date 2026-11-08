extends Node
## s. Queue, concurrency cap, timeouts, 429 backoff.
## Callers use request_decision() and listen to the two signals. requester_id is the
## caller's instance id: re-validate with is_instance_valid(instance_from_id(id)) on receipt.

signal decision_received(requester_id: int, tool_calls: Array[Dictionary])
signal decision_failed(requester_id: int, reason: String)

const MAX_RETRIES: int = 3
const BACKOFF_BASE: float = 1.0
const DEBUG_MAX_CHARS: int = 200

var _queue: Array[Dictionary] = []
var _key_check_id: int = 0
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


## Probes the selected provider's key with a free request and reports "valid", "invalid" (401/403)
## or "error" (network, 5xx, 429...) on EventBus.key_checked. Does nothing without a key to test.
## A newer check supersedes an older one, so a stale answer is never reported.
func check_key() -> void:
	_key_check_id += 1
	var id: int = _key_check_id
	var provider: LLMProvider = _make_provider()
	if provider == null or not provider.requires_network() or Settings.get_api_key(Settings.provider) == "":
		return
	if provider.config_error() != "":
		EventBus.key_checked.emit("error", provider.config_error())
		return
	var key: String = Settings.get_api_key(Settings.provider)
	var response: Dictionary = await _send(provider.build_check_request())
	if id != _key_check_id:
		return
	var status: int = response["status"]
	if response["result"] != HTTPRequest.RESULT_SUCCESS:
		EventBus.key_checked.emit("error", "network error (result %d)" % response["result"])
	elif status == 200:
		EventBus.key_checked.emit("valid", "")
	else:
		var state: String = "invalid" if status == 401 or status == 403 else "error"
		EventBus.key_checked.emit(state, _http_error(status, response["body"], key))


func _pump() -> void:
	while not _queue.is_empty() and _in_flight < Settings.max_concurrency:
		var job: Dictionary = _queue.pop_front()
		if not _requester_alive(job["requester_id"]):
			continue
		_in_flight += 1
		EventBus.llm_request_started.emit(job["requester_id"])
		_run(job)


func _run(job: Dictionary) -> void:
	var provider: LLMProvider = _make_provider()
	var provider_name: String = Settings.provider
	var outcome: Dictionary = {"calls": [], "error": "unknown provider '%s'" % Settings.provider, "status": 0}
	if provider != null:
		for attempt: int in range(MAX_RETRIES + 1):
			outcome = await _execute(provider, provider_name, job)
			if not _requester_alive(job["requester_id"]):
				break
			if outcome["status"] != 429 or attempt == MAX_RETRIES:
				break
			await _wait_backoff(BACKOFF_BASE * pow(2.0, attempt))
			if not _requester_alive(job["requester_id"]):
				break
	_in_flight -= 1
	var id: int = job["requester_id"]
	if not _requester_alive(id):
		_pump()
		return
	EventBus.llm_request_finished.emit(id, outcome["error"] == "")
	if outcome["error"] == "":
		var calls: Array[Dictionary] = []
		calls.assign(outcome["calls"])
		decision_received.emit(id, calls)
	else:
		decision_failed.emit(id, outcome["error"])
	_pump()


func _execute(provider: LLMProvider, provider_name: String, job: Dictionary) -> Dictionary:
	var key: String = Settings.get_api_key(provider_name)
	if provider.requires_network() and key == "":
		return _outcome([], "no API key (set one in Settings or .env)", 0)
	if provider.config_error() != "":
		return _outcome([], provider.config_error(), 0)
	var request: Dictionary = provider.build_request(job["system_prompt"], job["state"], job["tools"])
	if not provider.requires_network():
		await get_tree().create_timer(provider.simulated_latency()).timeout
		if not _requester_alive(job["requester_id"]):
			return _outcome([], "requester removed", 0)
		return _outcome(provider.parse_response(request["body"]), "", 200)

	var response: Dictionary = await _send(request)
	if not _requester_alive(job["requester_id"]):
		return _outcome([], "requester removed", 0)

	var result: int = response["result"]
	var status: int = response["status"]
	var raw: PackedByteArray = response["body"]
	if result != HTTPRequest.RESULT_SUCCESS:
		return _outcome([], "network error (result %d)" % result, 0)
	if status != 200:
		return _outcome([], _http_error(status, raw, key), status)
	var parsed: Variant = JSON.parse_string(raw.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY:
		return _outcome([], "invalid JSON response", status)
	return _outcome(provider.parse_response(parsed), "", status)


## Waits before a 429 retry. Tests override it to record the delay without waiting.
func _wait_backoff(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


## The only place that touches HTTPRequest; tests override it with scripted responses.
## Returns {result: int, status: int, body: PackedByteArray}.
func _send(request: Dictionary) -> Dictionary:
	var http: HTTPRequest = _acquire()
	http.timeout = Settings.request_timeout
	var headers: PackedStringArray = PackedStringArray(request["headers"])
	var method: int = request.get("method", HTTPClient.METHOD_POST)
	var body: String = "" if method == HTTPClient.METHOD_GET else JSON.stringify(request["body"])
	var err: Error = http.request(request["url"], headers, method, body)
	if err != OK:
		_release(http)
		return {"result": HTTPRequest.RESULT_CANT_CONNECT, "status": 0, "body": PackedByteArray()}
	var response: Array = await http.request_completed
	_release(http)
	return {"result": response[0], "status": response[1], "body": response[3]}


## "HTTP 401 (authentication_error)": the status plus the API's error type. The type always has
## the configured key masked (a provider could echo it there instead of in `message`); the
## message itself (which may also echo part of the key) is appended only when diagnostics are on.
func _http_error(status: int, raw: PackedByteArray, key: String) -> String:
	var parsed: Variant = JSON.parse_string(raw.get_string_from_utf8())
	var error: Variant = parsed.get("error") if typeof(parsed) == TYPE_DICTIONARY else null
	var type: String = _mask_key(str(error.get("type", "")), key) if typeof(error) == TYPE_DICTIONARY else ""
	var text: String = "HTTP %d (%s)" % [status, type] if type != "" else "HTTP %d" % status
	if typeof(error) == TYPE_DICTIONARY and _debug_enabled():
		var message: String = _sanitize(str(error.get("message", "")), key)
		if message != "":
			text += ": " + message
	return text


## Opt-in local diagnostics: PROMPTORIO_DEBUG_LLM=1 in an editor run; never in exported builds.
func _debug_enabled() -> bool:
	return OS.has_feature("editor") and OS.get_environment("PROMPTORIO_DEBUG_LLM") == "1"


## Replaces the configured API key, verbatim, with [redacted]. Safe to apply unconditionally,
## unlike _sanitize's token-shaped heuristic, which would also catch short provider-defined
## identifiers (e.g. "authentication_error" is 21 characters).
func _mask_key(text: String, key: String) -> String:
	if key != "":
		text = text.replace(key, "[redacted]")
	return text


## One line, secrets masked, capped at DEBUG_MAX_CHARS.
func _sanitize(message: String, key: String) -> String:
	message = _mask_key(message, key)
	# shortcut: masks any 20+ char token-like run (covers other key formats), may hide long identifiers
	var secret: RegEx = RegEx.create_from_string("[A-Za-z0-9_\\-]{20,}")
	message = secret.sub(message, "[redacted]", true)
	var spaces: RegEx = RegEx.create_from_string("\\s+")
	message = spaces.sub(message, " ", true).strip_edges()
	if message.length() > DEBUG_MAX_CHARS:
		message = message.substr(0, DEBUG_MAX_CHARS) + "..."
	return message


func _outcome(calls: Array, error: String, status: int) -> Dictionary:
	return {"calls": calls, "error": error, "status": status}


func _requester_alive(id: int) -> bool:
	var requester: Object = instance_from_id(id)
	return is_instance_valid(requester) and requester is Node and requester.is_inside_tree() and not requester.is_queued_for_deletion()


func _make_provider() -> LLMProvider:
	match Settings.provider:
		"mock":
			return MockProvider.new()
		"anthropic":
			return AnthropicProvider.new()
		"openai":
			return OpenAIProvider.new()
	return null


func _acquire() -> HTTPRequest:
	if not _idle_requests.is_empty():
		return _idle_requests.pop_back()
	var http: HTTPRequest = HTTPRequest.new()
	add_child(http)
	return http


func _release(http: HTTPRequest) -> void:
	_idle_requests.append(http)
