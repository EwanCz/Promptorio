class_name Conveyor
extends Machine
## Plain hardcoded transport: holds one item and hands it to the cell it faces after MOVE_TICKS.

const MOVE_TICKS: int = 5
const ARROWS: Dictionary = {
	Vector2i.RIGHT: "→", Vector2i.DOWN: "↓", Vector2i.LEFT: "←", Vector2i.UP: "↑",
}

var held: String = ""

var _wait: int = 0


func receive(item: String) -> bool:
	if held != "" or status == Status.DOWN:
		return false
	held = item
	_wait = 0
	return true


func get_action_text() -> String:
	return "Facing %s, %s" % [ARROWS.get(facing, "?"), "holds %s" % held if held != "" else "empty"]


func clear_contents() -> void:
	held = ""
	_wait = 0


func _tick() -> void:
	if held == "":
		return
	_wait += 1
	if _wait >= MOVE_TICKS and _push(held):
		held = ""


func _status_text() -> String:
	return str(ARROWS.get(facing, "?")) + ("•" if held != "" else "")
