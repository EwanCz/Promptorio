class_name Miner
extends Machine
## Produces one ore every mine_ticks and pushes it forward. Stops while its output is blocked.

const ITEM: String = "ore"
const MIN_MINE_TICKS: int = 5
const MAX_MINE_TICKS: int = 100

@export var mine_ticks: int = 20

var _progress: int = 0
var _held: String = ""
## True only after a delivery attempt failed; cleared when it succeeds or the contents are cleared.
var _blocked: bool = false


func get_state() -> Dictionary:
	return super.get_state().merged({"item": ITEM, "mine_ticks": mine_ticks, "blocked": _blocked})


func _own_tool_schemas() -> Array:
	return [{
		"name": "set_mine_ticks",
		"description": "Set how many ticks the miner needs for one ore. Lower is faster.",
		"input_schema": {"type": "object", "properties": {
			"ticks": {"type": "integer", "minimum": MIN_MINE_TICKS, "maximum": MAX_MINE_TICKS},
		}},
	}]


func _apply(tool_name: String, args: Dictionary) -> void:
	if tool_name == "set_mine_ticks":
		mine_ticks = args["ticks"]
		return
	super._apply(tool_name, args)


func get_events() -> Array[String]:
	var events: Array[String] = super.get_events()
	if _blocked:
		events.append("output_full")
	return events


func get_action_text() -> String:
	return "Mining 1 %s every %d ticks%s" % [ITEM, mine_ticks, " (output blocked)" if _blocked else ""]


func clear_contents() -> void:
	_held = ""
	_blocked = false
	_progress = 0


func _save_data() -> Dictionary:
	return {"mine_ticks": mine_ticks, "progress": _progress, "held": _held, "blocked": _blocked}


func _load_data(data: Dictionary) -> void:
	mine_ticks = _read_int(data, "mine_ticks", mine_ticks, MIN_MINE_TICKS, MAX_MINE_TICKS)
	_progress = _read_int(data, "progress", 0, 0, mine_ticks)
	_held = _read_item(data, "held", [ITEM])
	_blocked = _held != "" and data.get("blocked") == true


func _tick() -> void:
	if _held != "":
		_blocked = not _push(_held)
		if not _blocked:
			_held = ""
		return
	if not enabled:
		return
	_progress += 1
	if _progress >= mine_ticks:
		_progress = 0
		_held = ITEM
