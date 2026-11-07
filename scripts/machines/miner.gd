class_name Miner
extends Machine
## Mines one unit of its resource every mine_ticks and pushes it forward. Stops while its output is blocked.
## It mines any resource of the catalog built by "miner" (ore by default): set_mined_item picks it.

const MIN_MINE_TICKS: int = 5
const MAX_MINE_TICKS: int = 100

@export var mine_ticks: int = 20
## Id of the resource being mined. Changing it only affects the next unit: one already held is pushed on.
@export var item: String = "ore"

var _progress: int = 0
var _held: String = ""
## True only after a delivery attempt failed; cleared when it succeeds or the contents are cleared.
var _blocked: bool = false


func get_state() -> Dictionary:
	return super.get_state().merged({"item": item, "mine_ticks": mine_ticks, "blocked": _blocked})


func _own_tool_schemas() -> Array:
	return [{
		"name": "set_mine_ticks",
		"description": "Set how many ticks the miner needs for one unit. Lower is faster.",
		"input_schema": {"type": "object", "properties": {
			"ticks": {"type": "integer", "minimum": MIN_MINE_TICKS, "maximum": MAX_MINE_TICKS},
		}},
	}, {
		"name": "set_mined_item",
		"description": "Choose the resource the miner mines from now on.",
		"input_schema": {"type": "object", "properties": {
			"item": {"type": "string", "enum": ItemCatalog.shared().get_built_by_ids("miner")},
		}},
	}]


func _apply(tool_name: String, args: Dictionary) -> void:
	if tool_name == "set_mine_ticks":
		mine_ticks = args["ticks"]
		return
	if tool_name == "set_mined_item":
		item = args["item"]
		return
	super._apply(tool_name, args)


func get_events() -> Array[String]:
	var events: Array[String] = super.get_events()
	if _blocked:
		events.append("output_full")
	return events


func get_action_text() -> String:
	return "Mining 1 %s every %d ticks%s" % [item, mine_ticks, " (output blocked)" if _blocked else ""]


func clear_contents() -> void:
	_held = ""
	_blocked = false
	_progress = 0


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
		_held = item
