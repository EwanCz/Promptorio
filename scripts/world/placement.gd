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
	"orchestrator": preload("res://scenes/machines/orchestrator.tscn"),
}
## Input Map action -> machine type. Bindings live in project.godot (physical keys 1-3 and 5).
const SELECT_ACTIONS: Dictionary = {
	"select_miner": "miner",
	"select_smelter": "smelter",
	"select_assembler": "assembler",
	"select_conveyor": "conveyor",
}

## Machine catalog: money cost of every buildable type, in Build page order. The Collector is provided at the map center: not buildable, not removable.
## Orchestrator is the expensive late-game exception: needs playtesting, not fixed.
const COSTS: Dictionary = {"miner": 20, "smelter": 30, "assembler": 40, "conveyor": 2, "orchestrator": 150}

## Share of the price given back when the player destroys a machine: one over this (half).
const REFUND_DIVISOR: int = 2

## How long a freshly placed machine takes to pop in to full size.
const PLACE_ANIM_SECONDS: float = 0.18

@export var grid: GridMap2D
@export var machines: Node2D

var selected: String = ""
var facing: Vector2i = Vector2i.RIGHT
## Id given to the next machine placed. A loaded save sets it so ids never repeat.
var next_id: int = 1


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
	if type != "" and COSTS.has(type) and GameState.money < int(COSTS[type]):
		_set_selected("")
		placement_rejected.emit("Not enough money (%d needed)" % int(COSTS[type]))
		return
	_set_selected(type if COSTS.has(type) else "")


## Clockwise: right, down, left, up.
func rotate_facing() -> void:
	facing = Vector2i(-facing.y, facing.x)


## Returns the new machine, or null if the type is unknown or the cell is out of bounds, taken,
## or (for a miner) not a minesite.
func place(type: String, cell: Vector2i) -> Machine:
	if not SCENES.has(type) or not grid.can_place(type, cell):
		return null
	var machine: Machine = _spawn(type, cell, facing, next_id)
	next_id += 1
	return machine


## Recreates a machine from a save: same rules as place(), but with the saved direction and id, and no
## placement animation (a loaded game should not have every machine pop in at once).
func restore_machine(type: String, cell: Vector2i, direction: Vector2i, id: int) -> Machine:
	if not SCENES.has(type) or not grid.can_place(type, cell):
		return null
	return _spawn(type, cell, direction, id, false)


## Money given back for destroying a machine of this type: half its price, rounded down. 0 for a type
## that is not for sale (the Collector).
static func refund_for(type: String) -> int:
	return int(COSTS.get(type, 0)) / REFUND_DIVISOR


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


func _spawn(type: String, cell: Vector2i, direction: Vector2i, id: int, animate: bool = true) -> Machine:
	var machine: Machine = (SCENES[type] as PackedScene).instantiate() as Machine
	machine.cell = cell
	machine.facing = direction
	machine.machine_id = id
	machine.position = GameState.cell_to_world(cell)
	machines.add_child(machine)
	GameState.register_machine(machine, cell)
	if animate:
		_play_placement_animation(machine)
	return machine


## Pops the machine in from nothing: a purely visual tween on its own node, so it never touches simulation
## timing (EventBus.tick_fired keeps its own fixed pace regardless).
func _play_placement_animation(machine: Machine) -> void:
	machine.scale = Vector2.ZERO
	machine.modulate.a = 0.0
	var tween: Tween = machine.create_tween()
	tween.set_parallel(true)
	tween.tween_property(machine, "scale", Vector2.ONE, PLACE_ANIM_SECONDS).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(machine, "modulate:a", 1.0, PLACE_ANIM_SECONDS).set_ease(Tween.EASE_OUT)


func _set_selected(type: String) -> void:
	selected = type
	grid.set_placement_type(type)
	selection_changed.emit(selected)


func _on_cell_clicked(cell: Vector2i) -> void:
	if selected != "":
		try_place(selected, cell)
