class_name CraftMachine
extends Machine
## Shared by Smelter and Assembler: buffers recipe inputs (capped per item), crafts over
## recipe.ticks, then pushes the output forward. A blocked output stalls the machine.

const MAX_STOCK: int = 10

@export var recipe: Recipe

var stock: Dictionary = {}
## Ticks left on the current craft, 0 when idle.
var progress: int = 0

var _output: String = ""


func receive(item: String) -> bool:
	if status == Status.DOWN or recipe == null or not recipe.inputs.has(item):
		return false
	if int(stock.get(item, 0)) >= MAX_STOCK:
		return false
	stock[item] = int(stock.get(item, 0)) + 1
	return true


func is_working() -> bool:
	return enabled and progress > 0


func get_state() -> Dictionary:
	return super.get_state().merged({"stock": stock, "working": is_working()})


func _tick() -> void:
	if _output != "":
		if _push(_output):
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
		progress = recipe.ticks


func _can_start() -> bool:
	if recipe == null:
		return false
	for item: String in recipe.inputs:
		if int(stock.get(item, 0)) < int(recipe.inputs[item]):
			return false
	return true
