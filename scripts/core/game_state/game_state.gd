extends Node
## Grid, machine registry, tick clock and money.

const TICK_RATE: int = 10
const GRID_SIZE: Vector2i = Vector2i(32, 20)
const CELL_SIZE: int = 64

var tick_count: int = 0
var money: int = 0

var _machines: Dictionary = {}
var _tick_timer: Timer


func _ready() -> void:
	_tick_timer = Timer.new()
	_tick_timer.wait_time = 1.0 / TICK_RATE
	_tick_timer.timeout.connect(_on_tick)
	add_child(_tick_timer)
	_tick_timer.start()


func is_in_grid(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < GRID_SIZE.x and cell.y < GRID_SIZE.y


func can_place(cell: Vector2i) -> bool:
	return is_in_grid(cell) and not _machines.has(cell)


func register_machine(machine: Node, cell: Vector2i) -> bool:
	if not can_place(cell):
		return false
	_machines[cell] = machine
	EventBus.machine_registered.emit(machine, cell)
	return true


func unregister_machine(cell: Vector2i) -> void:
	if not _machines.has(cell):
		return
	var machine: Node = _machines[cell]
	_machines.erase(cell)
	EventBus.machine_unregistered.emit(machine, cell)


func get_machine_at(cell: Vector2i) -> Node:
	return _machines.get(cell, null)


func get_machines() -> Array:
	return _machines.values()


func cell_to_world(cell: Vector2i) -> Vector2:
	return Vector2(cell * CELL_SIZE)


func world_to_cell(pos: Vector2) -> Vector2i:
	return Vector2i((pos / CELL_SIZE).floor())


func add_money(amount: int) -> void:
	money += amount
	EventBus.money_changed.emit(money)


func _on_tick() -> void:
	tick_count += 1
	EventBus.tick_fired.emit(tick_count)
