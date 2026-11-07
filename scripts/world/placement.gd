class_name Placement
extends Node
## Minimal build flow: pick a type (keys 1-5), rotate with R, click a grid cell to place it.
## Rules: inside the grid, free cell, miners only on minesites. Places the Collector at the map center.

const SCENES: Dictionary = {
	"miner": preload("res://scenes/machines/miner.tscn"),
	"smelter": preload("res://scenes/machines/smelter.tscn"),
	"assembler": preload("res://scenes/machines/assembler.tscn"),
	"collector": preload("res://scenes/machines/collector.tscn"),
	"conveyor": preload("res://scenes/machines/conveyor.tscn"),
}
const TYPES: Array[String] = ["miner", "smelter", "assembler", "collector", "conveyor"]

@export var grid: GridMap2D
@export var machines: Node2D

var selected: String = ""
var facing: Vector2i = Vector2i.RIGHT

var _next_id: int = 1


func _ready() -> void:
	grid.cell_clicked.connect(_on_cell_clicked)
	place("collector", GameState.GRID_SIZE / 2)


func _unhandled_key_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	var index: int = key.keycode - KEY_1
	if index >= 0 and index < TYPES.size():
		select(TYPES[index])
	elif key.keycode == KEY_R:
		rotate_facing()
	elif key.keycode == KEY_ESCAPE:
		select("")


func select(type: String) -> void:
	selected = type if SCENES.has(type) else ""


## Clockwise: right, down, left, up.
func rotate_facing() -> void:
	facing = Vector2i(-facing.y, facing.x)


## Returns the new machine, or null if the type is unknown or the cell is out of bounds, taken,
## or (for a miner) not a minesite.
func place(type: String, cell: Vector2i) -> Machine:
	if not SCENES.has(type) or not GameState.can_place(cell):
		return null
	if type == "miner" and not grid.is_minesite(cell):
		return null
	var machine: Machine = (SCENES[type] as PackedScene).instantiate() as Machine
	machine.cell = cell
	machine.facing = facing
	machine.machine_id = _next_id
	machine.position = GameState.cell_to_world(cell)
	_next_id += 1
	machines.add_child(machine)
	GameState.register_machine(machine, cell)
	return machine


func _on_cell_clicked(cell: Vector2i) -> void:
	if selected != "":
		place(selected, cell)
