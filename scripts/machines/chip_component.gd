class_name ChipComponent
extends Node
## The machine's AI chip. Holds prompts (each with its own timeout), and asks LLMManager
## for decisions through request_decision(), which enforces cooldown and one request in flight.

signal decision_applied(reason: String, applied: int)

var prompts: Array[Dictionary] = []
var pending: bool = false

var _last_request_msec: int = -1000000
var _pending_reason: String = ""
var _elapsed: Dictionary = {}


func _ready() -> void:
	EventBus.tick_fired.connect(_on_tick)
	LLMManager.decision_received.connect(_on_decision_received)
	LLMManager.decision_failed.connect(_on_decision_failed)


func _exit_tree() -> void:
	EventBus.tick_fired.disconnect(_on_tick)
	LLMManager.decision_received.disconnect(_on_decision_received)
	LLMManager.decision_failed.disconnect(_on_decision_failed)


func add_prompt(prompt_name: String, text: String, timeout: float) -> void:
	remove_prompt(prompt_name)
	prompts.append({"name": prompt_name, "text": text, "timeout": maxf(timeout, 1.0)})
	_elapsed[prompt_name] = 0


func remove_prompt(prompt_name: String) -> void:
	for i: int in range(prompts.size() - 1, -1, -1):
		if prompts[i]["name"] == prompt_name:
			prompts.remove_at(i)
	_elapsed.erase(prompt_name)


## Returns true if a request was sent. Ignored (not queued) while pending or cooling down.
func request_decision(reason: String, prompt_name: String = "") -> bool:
	var machine: Machine = get_parent() as Machine
	if machine == null or pending or prompts.is_empty():
		return false
	if Time.get_ticks_msec() - _last_request_msec < int(Settings.chip_cooldown * 1000.0):
		return false
	var prompt: Dictionary = _find_prompt(prompt_name)
	if prompt.is_empty():
		return false
	pending = true
	_pending_reason = reason
	_last_request_msec = Time.get_ticks_msec()
	machine.log_chip("asking chip (%s)" % reason)
	LLMManager.request_decision(get_instance_id(), prompt["text"], machine.get_state(), machine.get_tool_schemas())
	return true


func _find_prompt(prompt_name: String) -> Dictionary:
	if prompt_name == "":
		return prompts[0]
	for prompt: Dictionary in prompts:
		if prompt["name"] == prompt_name:
			return prompt
	return {}


func _on_tick(_tick: int) -> void:
	for prompt: Dictionary in prompts:
		var key: String = prompt["name"]
		_elapsed[key] = _elapsed.get(key, 0) + 1
		if _elapsed[key] >= roundi(prompt["timeout"] * GameState.TICK_RATE):
			if request_decision("timer", key):
				_elapsed[key] = 0


func _on_decision_received(requester_id: int, tool_calls: Array[Dictionary]) -> void:
	if requester_id != get_instance_id():
		return
	pending = false
	var machine: Machine = get_parent() as Machine
	if machine == null or not machine.is_inside_tree():
		return
	var applied: int = 0
	for call: Dictionary in tool_calls:
		if machine.apply_tool_call(str(call.get("name", "")), call.get("args", {})):
			applied += 1
	decision_applied.emit(_pending_reason, applied)


func _on_decision_failed(requester_id: int, reason: String) -> void:
	if requester_id != get_instance_id():
		return
	pending = false
	var machine: Machine = get_parent() as Machine
	if machine != null:
		machine.log_chip("chip request failed: %s" % reason)
