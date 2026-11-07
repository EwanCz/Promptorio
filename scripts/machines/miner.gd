class_name Miner
extends Machine
## Produces one ore every mine_ticks and pushes it forward. Stops while its output is blocked.

const ITEM: String = "ore"

@export var mine_ticks: int = 20

var _progress: int = 0
var _held: String = ""


func get_state() -> Dictionary:
	return super.get_state().merged({"item": ITEM, "blocked": _held != ""})


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
