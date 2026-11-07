class_name ChipComponent
extends Node
## One AI chip: one prompt, one timeout. A machine can have several chips.
## Asks LLMManager for decisions through request_decision(), which enforces cooldown
## and one request in flight.

signal decision_applied(reason: String, applied: int)

var chip_name: String = ""
var prompt_text: String = ""
var timeout: float = 10.0
var pending: bool = false

var _last_request_msec: int = -1000000
var _pending_reason: String = ""
var _elapsed_ticks: int = 0


func _ready() -> void:
	EventBus.tick_fired.connect(_on_tick)
	LLMManager.decision_received.connect(_on_decision_received)
	LLMManager.decision_failed.connect(_on_decision_failed)


func _exit_tree() -> void:
	EventBus.tick_fired.disconnect(_on_tick)
	LLMManager.decision_received.disconnect(_on_decision_received)
	LLMManager.decision_failed.disconnect(_on_decision_failed)


func set_chip(new_name: String, text: String, new_timeout: float) -> void:
	chip_name = new_name
	prompt_text = text
	timeout = maxf(new_timeout, 1.0)
	_elapsed_ticks = 0


## Returns true if a request was sent. Ignored (not queued) while pending or cooling down.
func request_decision(reason: String) -> bool:
	var machine: Machine = get_parent() as Machine
	if machine == null or pending or prompt_text == "":
		return false
	if Time.get_ticks_msec() - _last_request_msec < int(Settings.chip_cooldown * 1000.0):
		return false
	pending = true
	_pending_reason = reason
	_last_request_msec = Time.get_ticks_msec()
	_elapsed_ticks = 0
	machine.log_chip("asking chip (%s)" % reason)
	LLMManager.request_decision(get_instance_id(), prompt_text, machine.get_state(), machine.get_tool_schemas())
	return true


func _on_tick(_tick: int) -> void:
	if prompt_text == "":
		return
	_elapsed_ticks += 1
	if _elapsed_ticks >= roundi(timeout * GameState.TICK_RATE):
		request_decision("timer")


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
