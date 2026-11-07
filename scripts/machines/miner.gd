class_name Miner
extends Machine
## Produces one ore every mine_ticks and pushes it forward. Stops while its output is blocked.

const ITEM: String = "ore"

@export var mine_ticks: int = 20

var _progress: int = 0
var _held: String = ""


func get_state() -> Dictionary:
	return super.get_state().merged({"item": ITEM, "blocked": _held != ""})


func get_action_text() -> String:
	return "Mining 1 %s every %d ticks%s" % [ITEM, mine_ticks, " (output blocked)" if _held != "" else ""]


func clear_contents() -> void:
	_held = ""
	_progress = 0


func _tick() -> void:
	if _held != "":
		if _push(_held):
			_held = ""
		return
	if not enabled:
		return
	_progress += 1
	if _progress >= mine_ticks:
		_progress = 0
		_held = ITEM
