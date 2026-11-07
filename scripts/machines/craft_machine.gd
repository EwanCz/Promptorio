class_name CraftMachine
extends Machine
## Shared by Smelter and Assembler: buffers recipe inputs (capped per item), crafts over
## recipe.ticks, then pushes the output forward. A blocked output stalls the machine.

const MAX_STOCK: int = 10

@export var recipe: Recipe

var stock: Dictionary = {}
## Per-item cap on the input stock, at most MAX_STOCK.
var stock_limit: int = MAX_STOCK
## Ticks left on the current craft, 0 when idle.
var progress: int = 0

var _output: String = ""
## True only after a delivery attempt failed; cleared when it succeeds or the contents are cleared.
var _blocked: bool = false


func receive(item: String) -> bool:
	if status == Status.DOWN or recipe == null or not recipe.inputs.has(item):
		return false
	if int(stock.get(item, 0)) >= stock_limit:
		return false
	stock[item] = int(stock.get(item, 0)) + 1
	return true


func is_working() -> bool:
	return enabled and progress > 0


func get_state() -> Dictionary:
	return super.get_state().merged({"stock": stock, "working": is_working()})


func get_events() -> Array[String]:
	var events: Array[String] = super.get_events()
	if _blocked:
		events.append("output_full")
	elif progress == 0 and not _can_start():
		events.append("input_empty")
	return events


func get_action_text() -> String:
	if recipe == null:
		return "No recipe"
	var state: String = "idle"
	if _blocked:
		state = "output blocked"
	elif is_working():
		state = "working, %d ticks left" % progress
	return "%s -> %s\nStock: %s\n%s" % [_items_text(recipe.inputs), recipe.output, _items_text(stock), state]


func clear_contents() -> void:
	stock.clear()
	progress = 0
	_output = ""
	_blocked = false


func _items_text(items: Dictionary) -> String:
	if items.is_empty():
		return "empty"
	var parts: PackedStringArray = []
	for item: String in items:
		parts.append("%d %s" % [int(items[item]), item])
	return ", ".join(parts)


func _tick() -> void:
	if _output != "":
		_blocked = not _push(_output)
		if not _blocked:
			_output = ""
		return
	if not enabled:
		return
	if progress > 0:
		progress -= 1
		if progress == 0:
			_output = recipe.output
	elif _can_start():
		for item: String in recipe.inputs:
			stock[item] = int(stock[item]) - int(recipe.inputs[item])
		progress = _craft_ticks()


## Duration of a craft starting now. Subclasses can slow it down.
func _craft_ticks() -> int:
	return recipe.ticks


func _can_start() -> bool:
	if recipe == null:
		return false
	for item: String in recipe.inputs:
		if int(stock.get(item, 0)) < int(recipe.inputs[item]):
			return false
	return true
