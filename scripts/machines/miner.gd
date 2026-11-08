class_name Miner
extends Machine
## Mines one unit of its resource every mine_ticks and pushes it forward. Stops while its output is blocked.
## It mines any resource of the catalog built by "miner" (ore by default): set_mined_item picks it. Each
## resource takes its own time to mine (ItemData.ticks): mine_ticks starts there and a chip can only raise it.

const MAX_MINE_TICKS: int = 100

## Ticks per unit of the current resource: never below get_min_mine_ticks(), reset to it by set_mined_item.
var mine_ticks: int = 0
## Id of the resource being mined. Change it through set_mined_item, which checks the miner may mine it.
var item: String = "ore"

var _progress: int = 0
var _held: String = ""
## True only after a delivery attempt failed; cleared when it succeeds or the contents are cleared.
var _blocked: bool = false


func _init() -> void:
	mine_ticks = get_min_mine_ticks()


## The mining time of the current resource: the fastest this miner can go on it.
func get_min_mine_ticks() -> int:
	return maxi(1, ItemCatalog.shared().ticks_of(item))


func get_state() -> Dictionary:
	return super.get_state().merged({"item": item, "mine_ticks": mine_ticks, "blocked": _blocked})


func _own_tool_schemas() -> Array:
	return [{
		"name": "set_mine_ticks",
		"description": "Set how many ticks the miner needs for one unit. Lower is faster, but not below %d, the time %s takes to mine." % [get_min_mine_ticks(), item],
		"input_schema": {"type": "object", "properties": {
			"ticks": {"type": "integer", "minimum": get_min_mine_ticks(), "maximum": MAX_MINE_TICKS},
		}},
	}, {
		"name": "set_mined_item",
		"description": "Choose the resource the miner mines from now on. It can mine: %s. Any other resource is refused." % ", ".join(ItemCatalog.shared().get_built_by_ids(machine_type)),
		"input_schema": {"type": "object", "properties": {"item": {"type": "string"}}},
	}]


func _apply(tool_name: String, args: Dictionary) -> bool:
	if tool_name == "set_mine_ticks":
		mine_ticks = args["ticks"]
		return true
	if tool_name == "set_mined_item":
		return set_mined_item(args["item"])
	return super._apply(tool_name, args)


## Switches to a resource that a machine of this type builds. False, and nothing changes, if the catalog
## says another machine builds it or it does not exist. The pace goes back to the new resource's own time and
## a unit already held is pushed on as it was.
func set_mined_item(new_item: String) -> bool:
	refusal = ItemCatalog.shared().refusal_for(new_item, machine_type)
	if refusal != "":
		return false
	item = new_item
	mine_ticks = get_min_mine_ticks()
	return true


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


func _save_data() -> Dictionary:
	return {"item": item, "mine_ticks": mine_ticks, "progress": _progress, "held": _held, "blocked": _blocked}


func _load_data(data: Dictionary) -> void:
	var saved_item: String = _read_item(data, "item", ItemCatalog.shared().get_built_by_ids(machine_type))
	if saved_item != "":
		item = saved_item
	mine_ticks = _read_int(data, "mine_ticks", get_min_mine_ticks(), get_min_mine_ticks(), MAX_MINE_TICKS)
	_progress = _read_int(data, "progress", 0, 0, mine_ticks)
	_held = _read_item(data, "held", ItemCatalog.shared().get_ids())
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
		_held = item
