extends "res://tests/test_case.gd"

var _main: Node
var _placement: Placement
var _grid: GridMap2D
var _game: Node


func before_each() -> void:
	_game = autoload("GameState")
	_main = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(_main)
	_placement = _main.get_node("Game/FactoryView/SubViewport/World/Placement")
	_grid = _main.get_node("Game/FactoryView/SubViewport/World/GridMap2D")


func after_each() -> void:
	_main.free()


func test_collector_is_placed_at_map_center() -> void:
	var center: Vector2i = _game.GRID_SIZE / 2
	check(_game.get_machine_at(center) is Collector, "collector at the center")


func test_place_registers_and_positions_machine() -> void:
	var cell: Vector2i = Vector2i(8, 8)
	var machine: Machine = _placement.place("smelter", cell)
	check(machine is Smelter, "a smelter is built")
	check(_game.get_machine_at(cell) == machine, "registered in GameState")
	check_eq(machine.cell, cell, "knows its cell")
	check_eq(machine.position, _game.cell_to_world(cell), "positioned on the grid")
	check_eq(machine.get_parent(), _placement.machines, "child of the Machines node")


func test_occupied_and_out_of_bounds_are_refused() -> void:
	check(_placement.place("conveyor", Vector2i(8, 8)) != null, "first placement works")
	check(_placement.place("conveyor", Vector2i(8, 8)) == null, "occupied cell refused")
	check(_placement.place("conveyor", Vector2i(-1, 0)) == null, "negative cell refused")
	check(_placement.place("conveyor", _game.GRID_SIZE) == null, "past the far edge refused")
	check(_placement.place("bogus", Vector2i(9, 9)) == null, "unknown type refused")


func test_miners_only_on_minesites() -> void:
	check(_placement.place("miner", Vector2i(8, 8)) == null, "miner refused on plain ground")
	check(_placement.place("miner", GridMap2D.MINESITES[0]) is Miner, "miner accepted on a minesite")
	check(_placement.place("smelter", GridMap2D.MINESITES[1]) is Smelter, "other machines may use minesites")


func test_click_places_the_selected_type() -> void:
	_grid.cell_clicked.emit(Vector2i(8, 8))
	check(_game.get_machine_at(Vector2i(8, 8)) == null, "nothing selected, nothing placed")
	_placement.select("assembler")
	_grid.cell_clicked.emit(Vector2i(8, 8))
	check(_game.get_machine_at(Vector2i(8, 8)) is Assembler, "click builds the selection")
	_placement.select("bogus")
	check_eq(_placement.selected, "", "unknown selection clears it")


func test_rotation_is_applied_to_new_machines() -> void:
	var seen: Array[Vector2i] = []
	for i: int in 4:
		seen.append(_placement.facing)
		_placement.rotate_facing()
	check_eq(seen, [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP], "right, down, left, up")
	_placement.rotate_facing()
	check_eq(_placement.place("conveyor", Vector2i(8, 8)).facing, Vector2i.DOWN, "machine takes the current facing")


func test_keys_select_and_rotate() -> void:
	var key: InputEventKey = InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_2
	_placement._unhandled_key_input(key)
	check_eq(_placement.selected, "smelter", "key 2 selects the smelter")
	key.keycode = KEY_R
	_placement._unhandled_key_input(key)
	check_eq(_placement.facing, Vector2i.DOWN, "R rotates")
	key.keycode = KEY_ESCAPE
	_placement._unhandled_key_input(key)
	check_eq(_placement.selected, "", "Escape deselects")


func test_placed_machines_are_removed_with_the_scene() -> void:
	_placement.place("conveyor", Vector2i(8, 8))
	_main.free()
	check(_game.get_machine_at(Vector2i(8, 8)) == null, "freed machines leave the registry")
	check(_game.get_machine_at(_game.GRID_SIZE / 2) == null, "so does the collector")
	_main = Node.new()
