extends "res://tests/test_case.gd"

var _main: Node
var _grid: Node


func before_each() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	_grid = _main.get_node("Game/FactoryView/SubViewport/World/GridMap2D")


func after_each() -> void:
	_main.free()


func test_every_cell_has_a_tile() -> void:
	_grid._build_ground()
	var size: Vector2i = autoload("GameState").GRID_SIZE
	var missing: int = 0
	for x: int in size.x:
		for y: int in size.y:
			if _grid.get_cell_source_id(Vector2i(x, y)) == -1:
				missing += 1
	check_eq(missing, 0, "every grid cell has a ground tile")
	check_eq(_grid.get_cell_source_id(size), -1, "no tile outside the grid")


func test_minesites() -> void:
	_grid._build_ground()
	check(_grid.is_minesite(Vector2i(4, 4)), "listed cell is a minesite")
	check(not _grid.is_minesite(Vector2i(16, 10)), "map center is not a minesite")


func test_hovered_cell_conversion() -> void:
	var game_state: Node = autoload("GameState")
	var cell: Vector2i = Vector2i(5, 7)
	var world: Vector2 = game_state.cell_to_world(cell) + Vector2(3, 3)
	check_eq(_grid.get_hovered_cell(world), cell, "world position maps to its cell")
	check_eq(_grid.get_hovered_cell(Vector2(-10, -10)), Vector2i(-1, -1), "outside the grid is invalid")
	check_eq(_grid.get_hovered_cell(Vector2(game_state.GRID_SIZE * game_state.CELL_SIZE)), Vector2i(-1, -1), "past the far edge is invalid")
