class_name Placement
extends Node
## Build flow: pick a type (Build page or select_* actions), rotate_placement, cancel_placement, click a grid cell to place it.
## Rules: inside the grid, free cell, miners only on minesites, enough money (charged once, on success).
## Places the free Collector at the map center.

signal selection_changed(type: String)
signal placement_rejected(reason: String)

const SCENES: Dictionary = {
	"miner": preload("res://scenes/machines/miner.tscn"),
	"smelter": preload("res://scenes/machines/smelter.tscn"),
	"assembler": preload("res://scenes/machines/assembler.tscn"),
	"collector": preload("res://scenes/machines/collector.tscn"),
	"conveyor": preload("res://scenes/machines/conveyor.tscn"),
}
## Input Map action -> machine type. Bindings live in project.godot (physical keys 1-5; 4 is unused, the Collector is not buildable).
const SELECT_ACTIONS: Dictionary = {
	"select_miner": "miner",
	"select_smelter": "smelter",
	"select_assembler": "assembler",
	"select_conveyor": "conveyor",
}

@export var grid: GridMap2D
@export var machines: Node2D

var selected: String = ""
var facing: Vector2i = Vector2i.RIGHT

var _next_id: int = 1


func _ready() -> void:
	grid.cell_clicked.connect(_on_cell_clicked)
	_spawn("collector", GameState.GRID_SIZE / 2)


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


## Only buildable types can be selected; anything else clears the selection.
func select(type: String) -> void:
	selected = type if MachineCatalog.is_buildable(type) else ""
	selection_changed.emit(selected)


## Clockwise: right, down, left, up.
func rotate_facing() -> void:
	facing = Vector2i(-facing.y, facing.x)


## Returns the new machine and charges its cost, or null (nothing charged, `placement_rejected` emitted)
## if the type is not buildable, the cell is out of bounds or taken, a miner is off a minesite,
## or there is not enough money.
func place(type: String, cell: Vector2i) -> Machine:
	if not MachineCatalog.is_buildable(type):
		return _reject("Cannot build that")
	if not GameState.can_place(cell):
		return _reject("Cell is occupied or outside the grid")
	if type == "miner" and not grid.is_minesite(cell):
		return _reject("Miners go on minesites only")
	var cost: int = MachineCatalog.cost(type)
	if GameState.money < cost:
		return _reject("Not enough money (%d needed)" % cost)
	var machine: Machine = _spawn(type, cell)
	GameState.add_money(-cost)
	return machine


func _reject(reason: String) -> Machine:
	placement_rejected.emit(reason)
	return null


func _spawn(type: String, cell: Vector2i) -> Machine:
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
