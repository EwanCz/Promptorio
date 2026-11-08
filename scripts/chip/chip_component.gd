class_name ChipComponent
extends Node
## One AI chip running on a machine (child of the Machine). Holds a ChipRessource (the prompt),
## its own timeout and in-flight flag. call_llm() asks the LLM, the answer is applied to the machine.
## Triggers (all go through call_llm, so cooldown and one request in flight apply): timer, a machine
## event appearing (Machine.get_events), a state value rising above the threshold, and manual.
## A trigger that fires while pending or cooling down is dropped, the timer is the fallback.
## Not named `call`: Object.call() is native and cannot be overridden.

signal decision_applied(reason: String, applied: int)
## "checking" when a request goes out, then "applied", "none" (no tool calls) or "failed".
signal activity_changed(outcome: String)

const DEFAULT_TIMEOUT: int = 100

var chip: ChipRessource
## Ticks between two timer-triggered calls.
var timeout: int = DEFAULT_TIMEOUT
var pending: bool = false
## State key watched by the threshold trigger ("" = off) and the value it must exceed.
var threshold_key: String = ""
var threshold: float = 0.0

var _over: bool = false
var _events: Array[String] = []
var _elapsed: int = 0
var _last_msec: int = -1000000
var _reason: String = ""


func _ready() -> void:
	var machine: Machine = get_parent() as Machine
	if machine != null:
		_events = machine.get_events()
	EventBus.tick_fired.connect(_on_tick)
	LLMManager.decision_received.connect(_on_decision_received)
	LLMManager.decision_failed.connect(_on_decision_failed)


func _exit_tree() -> void:
	EventBus.tick_fired.disconnect(_on_tick)
	LLMManager.decision_received.disconnect(_on_decision_received)
	LLMManager.decision_failed.disconnect(_on_decision_failed)


func set_timeout(ticks: int) -> void:
	timeout = maxi(ticks, 1)
	_elapsed = 0


## Fires "threshold:<key>" when the state value `key` rises above `value`. An empty key turns it off.
func set_threshold(key: String, value: float) -> void:
	threshold_key = key
	threshold = value
	_over = false


## Returns true if a request was sent. Ignored (not queued) while pending or cooling down.
func call_llm(reason: String) -> bool:
	var machine: Machine = get_parent() as Machine
	if machine == null or chip == null or chip.prompt == "" or not is_inside_tree() or pending:
		return false
	if Time.get_ticks_msec() - _last_msec < int(Settings.chip_cooldown * 1000.0):
		return false
	pending = true
	_reason = reason
	_last_msec = Time.get_ticks_msec()
	_elapsed = 0
	machine.log_chip("asking chip %s (%s)" % [chip.name, reason])
	activity_changed.emit("checking")
	LLMManager.request_decision(get_instance_id(), chip.prompt, machine.get_state(), machine.get_tool_schemas())
	return true


func _on_tick(_tick: int) -> void:
	_elapsed += 1
	var reason: String = _check_triggers()
	if reason == "" and _elapsed >= timeout:
		reason = "timer"
	if reason != "":
		call_llm(reason)


## Reason of the first event or threshold crossing since the last tick, "" if none.
func _check_triggers() -> String:
	var machine: Machine = get_parent() as Machine
	if machine == null:
		return ""
	var reason: String = ""
	var events: Array[String] = machine.get_events()
	for event: String in events:
		if reason == "" and not _events.has(event):
			reason = "event:" + event
	_events = events
	if threshold_key != "":
		var value: Variant = machine.get_state().get(threshold_key)
		var over: bool = (value is int or value is float) and float(value) > threshold
		if over and not _over and reason == "":
			reason = "threshold:" + threshold_key
		_over = over
	return reason


func _on_decision_received(requester_id: int, tool_calls: Array[Dictionary]) -> void:
	if requester_id != get_instance_id():
		return
	pending = false
	var machine: Machine = get_parent() as Machine
	if machine == null:
		return
	if tool_calls.is_empty():
		machine.log_chip("no tool calls")
	var applied: int = 0
	for tool_call: Dictionary in tool_calls:
		var args: Variant = tool_call.get("args", {})
		if typeof(args) == TYPE_DICTIONARY and machine.apply_tool_call(str(tool_call.get("name", "")), args):
			applied += 1
	decision_applied.emit(_reason, applied)
	activity_changed.emit("applied" if applied > 0 else ("none" if tool_calls.is_empty() else "failed"))


func _on_decision_failed(requester_id: int, reason: String) -> void:
	if requester_id != get_instance_id():
		return
	pending = false
	var machine: Machine = get_parent() as Machine
	if machine != null:
		machine.log_chip("chip request failed: %s" % reason)
	activity_changed.emit("failed")
