class_name Placement
extends Node
## Minimal build flow: pick a type (select_* actions), rotate_placement, cancel_placement, click a grid cell to place it.
## Rules: inside the grid, free cell, miners only on minesites. Places the Collector at the map center.

signal selection_changed(type: String)
signal placement_rejected(reason: String)

const SCENES: Dictionary = {
	"miner": preload("res://scenes/machines/miner.tscn"),
	"smelter": preload("res://scenes/machines/smelter.tscn"),
	"assembler": preload("res://scenes/machines/assembler.tscn"),
	"collector": preload("res://scenes/machines/collector.tscn"),
	"conveyor": preload("res://scenes/machines/conveyor.tscn"),
}
## Input Map action -> machine type. Bindings live in project.godot (physical keys 1-5).
const SELECT_ACTIONS: Dictionary = {
	"select_miner": "miner",
	"select_smelter": "smelter",
	"select_assembler": "assembler",
	"select_collector": "collector",
	"select_conveyor": "conveyor",
}

## Machine catalog: money cost of every buildable type, in Build page order. The Collector is provided at the map center: not buildable, not removable.
const COSTS: Dictionary = {"miner": 20, "smelter": 30, "assembler": 40, "conveyor": 2}

@export var grid: GridMap2D
@export var machines: Node2D

var selected: String = ""
var facing: Vector2i = Vector2i.RIGHT

var _next_id: int = 1


func _ready() -> void:
	grid.cell_clicked.connect(_on_cell_clicked)
	place("collector", GameState.GRID_SIZE / 2)


## Handles the placement actions from the Input Map. True if the event was one of them.
func handle_input(event: InputEvent) -> bool:
	for action: String in SELECT_ACTIONS:
		if event.is_action_pressed(action):
			select(SELECT_ACTIONS[action])
			return true
	if event.is_action_pressed("rotate_placement"):
		rotate_facing()
		return true
	if event.is_action_pressed("cancel_placement"):
		select("")
		return true
	return false


func select(type: String) -> void:
	selected = type if SCENES.has(type) else ""
	selection_changed.emit(selected)


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


## Same rules as place(), plus the cost: charged once, only on success. Emits placement_rejected otherwise.
func try_place(type: String, cell: Vector2i) -> Machine:
	if not COSTS.has(type):
		placement_rejected.emit("The %s cannot be built" % type)
		return null
	var cost: int = COSTS[type]
	if GameState.money < cost:
		placement_rejected.emit("Not enough money (%d needed)" % cost)
		return null
	var machine: Machine = place(type, cell)
	if machine == null:
		placement_rejected.emit("Cannot place a %s here" % type)
		return null
	GameState.add_money(-cost)
	return machine


func _on_cell_clicked(cell: Vector2i) -> void:
	if selected != "":
		try_place(selected, cell)
