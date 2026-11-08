class_name Assembler
extends CraftMachine
## Assembles resources from other resources (a part from ingots by default). Normal mode is the recipe
## unchanged. Fast mode trades material for speed: a craft needs FAST_INPUT_MULTIPLIER times each input and
## takes the recipe time divided by FAST_TIME_DIVISOR (rounded down, floored at 1 tick); if the extra inputs
## are not in stock, the assembler waits rather than falling back to normal mode (_can_start checks the
## mode's own scaled inputs). A mode change only affects the next craft: costs and duration are fixed when a
## craft starts (inputs are spent then, and the duration already chosen is not recomputed).

const MODE_NORMAL: String = "normal"
const MODE_FAST: String = "fast"
const FAST_INPUT_MULTIPLIER: int = 2
const FAST_TIME_DIVISOR: int = 2
## A light warm tint marks fast mode on the sprite; normal mode keeps the art's own colours.
const FAST_TINT: Color = Color(1.0, 0.82, 0.45)

var mode: String = MODE_NORMAL


func get_state() -> Dictionary:
	return super.get_state().merged({"stock_limit": stock_limit, "mode": mode})


func _own_tool_schemas() -> Array:
	return [{
		"name": "set_mode",
		"description": "Choose the production mode for crafts starting from now on. '%s' is the recipe unchanged. '%s' needs %dx the inputs of each recipe and finishes in the recipe time divided by %d (rounded down, at least 1 tick); if the assembler does not have the extra inputs in stock it waits, it never falls back to normal mode. A craft already running keeps the cost and duration it started with." % [MODE_NORMAL, MODE_FAST, FAST_INPUT_MULTIPLIER, FAST_TIME_DIVISOR],
		"input_schema": {"type": "object", "properties": {
			"mode": {"type": "string", "enum": [MODE_NORMAL, MODE_FAST]},
		}},
	}, {
		"name": "set_stock_limit",
		"description": "Set how many of each input item the assembler keeps in stock. Upstream machines are refused above it.",
		"input_schema": {"type": "object", "properties": {
			"limit": {"type": "integer", "minimum": 1, "maximum": MAX_STOCK},
		}},
	}] + super._own_tool_schemas()


func _apply(tool_name: String, args: Dictionary) -> bool:
	if tool_name == "set_mode":
		mode = args["mode"]
		_update_mode_tint()
		return true
	if tool_name == "set_stock_limit":
		stock_limit = args["limit"]
		return true
	return super._apply(tool_name, args)


func _scale_inputs(product: ItemData) -> Dictionary:
	if mode != MODE_FAST:
		return product.inputs
	var scaled: Dictionary = {}
	for item: String in product.inputs:
		scaled[item] = int(product.inputs[item]) * FAST_INPUT_MULTIPLIER
	return scaled


func _craft_ticks() -> int:
	if mode == MODE_FAST:
		return maxi(1, super._craft_ticks() / FAST_TIME_DIVISOR)
	return super._craft_ticks()


func _save_data() -> Dictionary:
	return super._save_data().merged({"mode": mode})


func _load_data(data: Dictionary) -> void:
	super._load_data(data)
	var saved_mode: String = _read_item(data, "mode", [MODE_NORMAL, MODE_FAST])
	mode = saved_mode if saved_mode != "" else MODE_NORMAL
	_update_mode_tint()


func _update_mode_tint() -> void:
	if _sprite != null:
		_sprite.modulate = FAST_TINT if mode == MODE_FAST else Color.WHITE
