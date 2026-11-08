class_name ChipComponent
extends Node
## One AI chip running on a machine (child of the Machine). Holds a ChipRessource (the prompt),
## its own timeout and in-flight flag. call_llm() asks the LLM, the answer is applied to the machine.
## Only two triggers go through call_llm (so cooldown and one request in flight apply): the timer and manual.
## A machine's state or events (temperature, status, output full...) never wake a chip; the state is only
## sent along when the chip is asked. A request that fires while pending or cooling down is dropped.
## Not named `call`: Object.call() is native and cannot be overridden.

signal decision_applied(reason: String, applied: int)
## "checking" when a request goes out, then "applied", "none" (no tool calls) or "failed".
signal activity_changed(outcome: String)

const DEFAULT_TIMEOUT: int = 100

var chip: ChipRessource
## Ticks between two timer-triggered calls.
var timeout: int = DEFAULT_TIMEOUT
var pending: bool = false

var _elapsed: int = 0
var _last_msec: int = -1000000
var _reason: String = ""


func _ready() -> void:
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
	if _elapsed >= timeout:
		call_llm("timer")


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
