class_name Miner
extends Machine
## Mines one unit of its resource every mine_ticks and pushes it forward. Stops while its output is blocked.
## It mines any resource of the catalog built by "miner" (ore by default): set_mined_item picks it. Each
## resource takes its own time to mine (ItemData.ticks): mine_ticks starts there and a chip can only raise it.
##
## start_prospecting pauses mining for PROSPECT_TICKS, then mines at BOOST_RATE times the pace (against the
## current mine_ticks, which a chip can still change at any time) for BOOST_TICKS, then returns to mining on
## its own. It is refused outside MINING, so a cycle cannot be restarted mid-prospect or mid-boost, and
## set_mined_item is refused outside MINING too, so the resource stays the same through the cycle. The boost
## timer keeps counting down even while the output is blocked (backpressure never pauses it); set_enabled(false)
## (and status DOWN) freezes the whole miner, timer included, same as it freezes ordinary mining progress.

const MAX_MINE_TICKS: int = 100
## Ticks spent prospecting (paused) before the boost starts.
const PROSPECT_TICKS: int = 80
## Ticks the boosted rate lasts before mining returns to normal.
const BOOST_TICKS: int = 200
## How many times faster mining goes while boosted, against the current mine_ticks.
const BOOST_RATE: int = 2

enum Mode { MINING, PROSPECTING, BOOST }

## Ticks per unit of the current resource: never below get_min_mine_ticks(), reset to it by set_mined_item.
var mine_ticks: int = 0
## Id of the resource being mined. Change it through set_mined_item, which checks the miner may mine it.
var item: String = "ore"
## MINING (normal pace), PROSPECTING (paused) or BOOST (BOOST_RATE times the pace). See get_state().
var mode: Mode = Mode.MINING
## Ticks left in the current prospecting or boost span; 0 while mining normally.
var mode_ticks_left: int = 0

var _progress: int = 0
var _held: String = ""
## True only after a delivery attempt failed; cleared when it succeeds or the contents are cleared.
var _blocked: bool = false
## In-world feedback for the current mode (prospecting/boost); hidden while mining normally.
var _mode_sprite: Sprite2D


func _init() -> void:
	mine_ticks = get_min_mine_ticks()


func _ready() -> void:
	super._ready()
	_mode_sprite = Sprite2D.new()
	_mode_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_mode_sprite.scale = Vector2(Icons.SCALE, Icons.SCALE)
	_mode_sprite.position = Vector2(GameState.CELL_SIZE - Icons.SIZE * Icons.SCALE / 2.0 - 2.0, -Icons.SIZE * Icons.SCALE / 2.0 - 2.0)
	_mode_sprite.z_index = 10
	_mode_sprite.visible = false
	add_child(_mode_sprite)


## The mining time of the current resource: the fastest this miner can go on it.
func get_min_mine_ticks() -> int:
	return maxi(1, ItemCatalog.shared().ticks_of(item))


func get_state() -> Dictionary:
	return super.get_state().merged({
		"item": item, "mine_ticks": mine_ticks, "blocked": _blocked,
		"mode": Mode.keys()[mode].to_lower(), "mode_ticks_left": mode_ticks_left,
	})


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
	}, {
		"name": "start_prospecting",
		"description": "Pause mining to prospect for %d ticks, then mine %s at %dx the normal rate for %d ticks before returning to the normal pace. Refused while already prospecting or boosted." % [PROSPECT_TICKS, item, BOOST_RATE, BOOST_TICKS],
		"input_schema": {"type": "object", "properties": {}},
	}]


func _apply(tool_name: String, args: Dictionary) -> bool:
	if tool_name == "set_mine_ticks":
		mine_ticks = args["ticks"]
		return true
	if tool_name == "set_mined_item":
		return set_mined_item(args["item"])
	if tool_name == "start_prospecting":
		return start_prospecting()
	return super._apply(tool_name, args)


## Switches to a resource that a machine of this type builds. False, and nothing changes, if the catalog
## says another machine builds it, it does not exist, or the miner is mid-prospect/boost (the resource stays
## the same through that cycle). The pace goes back to the new resource's own time and a unit already held
## is pushed on as it was.
func set_mined_item(new_item: String) -> bool:
	if mode != Mode.MINING:
		refusal = "the mined resource is locked while prospecting or boosted"
		return false
	refusal = ItemCatalog.shared().refusal_for(new_item, machine_type)
	if refusal != "":
		return false
	item = new_item
	mine_ticks = get_min_mine_ticks()
	return true


## Starts a prospecting pause (PROSPECT_TICKS), followed automatically by a boost (BOOST_TICKS at BOOST_RATE
## times the pace), then back to normal mining. False, and nothing changes, while already prospecting or
## boosted, so a cycle cannot be restarted mid-way.
func start_prospecting() -> bool:
	if mode != Mode.MINING:
		refusal = "already prospecting or boosted"
		return false
	mode = Mode.PROSPECTING
	mode_ticks_left = PROSPECT_TICKS
	_progress = 0
	return true


func get_progress() -> float:
	var denominator: int = _boosted_mine_ticks() if mode == Mode.BOOST else mine_ticks
	return clampf(float(_progress) / float(maxi(denominator, 1)), 0.0, 1.0)


func is_blocked() -> bool:
	return _blocked


func clear_contents() -> void:
	_held = ""
	_blocked = false
	_progress = 0
	mode = Mode.MINING
	mode_ticks_left = 0


func _save_data() -> Dictionary:
	return {
		"item": item, "mine_ticks": mine_ticks, "progress": _progress, "held": _held, "blocked": _blocked,
		"mode": mode, "mode_ticks_left": mode_ticks_left,
	}


func _load_data(data: Dictionary) -> void:
	var saved_item: String = _read_item(data, "item", ItemCatalog.shared().get_built_by_ids(machine_type))
	if saved_item != "":
		item = saved_item
	mine_ticks = _read_int(data, "mine_ticks", get_min_mine_ticks(), get_min_mine_ticks(), MAX_MINE_TICKS)
	_progress = _read_int(data, "progress", 0, 0, mine_ticks)
	_held = _read_item(data, "held", ItemCatalog.shared().get_ids())
	_blocked = _held != "" and data.get("blocked") == true
	mode = _read_int(data, "mode", Mode.MINING, Mode.MINING, Mode.BOOST) as Mode
	mode_ticks_left = _read_int(data, "mode_ticks_left", 0, 0, maxi(PROSPECT_TICKS, BOOST_TICKS))
	if mode == Mode.MINING:
		mode_ticks_left = 0


func _tick() -> void:
	if _held != "":
		_blocked = not _push(_held)
		if not _blocked:
			_held = ""
	if enabled:
		var current_mode: Mode = mode
		if current_mode != Mode.MINING:
			mode_ticks_left -= 1
			if mode_ticks_left <= 0:
				_advance_mode()
		if current_mode != Mode.PROSPECTING and _held == "":
			_progress += 1
			if _progress >= (_boosted_mine_ticks() if current_mode == Mode.BOOST else mine_ticks):
				_progress = 0
				_held = item
	_update_mode_sprite()


## PROSPECTING -> BOOST (a fresh BOOST_TICKS span) or BOOST -> MINING. Called once the current span's ticks
## run out; the tick that empties it still behaves as the span that just ended (see _tick()).
func _advance_mode() -> void:
	if mode == Mode.PROSPECTING:
		mode = Mode.BOOST
		mode_ticks_left = BOOST_TICKS
	else:
		mode = Mode.MINING
		mode_ticks_left = 0


func _boosted_mine_ticks() -> int:
	return maxi(1, mine_ticks / BOOST_RATE)


func _update_mode_sprite() -> void:
	_mode_sprite.visible = mode != Mode.MINING
	if mode == Mode.PROSPECTING:
		_mode_sprite.texture = Icons.icon("prospecting")
	elif mode == Mode.BOOST:
		_mode_sprite.texture = Icons.icon("boost")
