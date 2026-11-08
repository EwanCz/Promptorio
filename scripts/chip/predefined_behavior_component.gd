class_name PredefinedBehaviorComponent
extends Node
## Runs one entry of PredefinedBehaviors.TABLE on the parent Machine: no prompt, no LLM call, ever. A
## fixed-interval timer reapplies the behavior's tool call(s) through Machine.apply_tool_call, the same
## whitelist/validate/clamp path a ChipComponent's decision goes through — a predefined behavior is not a
## trusted shortcut around it. See scripts/chip/predefined_behavior.gd for what distinguishes this from a
## chip's LLM prompt and from the offline MockProvider.

signal activity_changed(outcome: String)

var behavior_id: int = 0
var behavior_name: String = ""
var behavior_description: String = ""

var _interval: int = 1
var _steps: Array = []
var _elapsed: int = 0
var _step_index: int = 0


func _ready() -> void:
	EventBus.tick_fired.connect(_on_tick)


func _exit_tree() -> void:
	EventBus.tick_fired.disconnect(_on_tick)


## Configures this component from one PredefinedBehaviors.TABLE entry (see PredefinedBehaviors.get_behavior).
func setup(behavior: Dictionary) -> void:
	behavior_id = int(behavior.get("id", 0))
	behavior_name = String(behavior.get("name", ""))
	behavior_description = String(behavior.get("description", ""))
	_interval = maxi(int(behavior.get("interval_ticks", 1)), 1)
	_steps = behavior.get("steps", [])
	_elapsed = _interval - clampi(int(behavior.get("initial_delay_ticks", _interval)), 1, _interval)
	_step_index = 0


func _on_tick(_tick: int) -> void:
	if _steps.is_empty():
		return
	_elapsed += 1
	if _elapsed < _interval:
		return
	_elapsed = 0
	var machine: Machine = get_parent() as Machine
	if machine == null:
		return
	var step: Dictionary = _steps[_step_index % _steps.size()]
	_step_index += 1
	var applied: bool = machine.apply_tool_call(String(step.get("tool", "")), step.get("args", {}))
	activity_changed.emit("applied" if applied else "failed")
