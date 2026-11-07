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


## Miner placement rules in the hover highlight. The scene must be in the tree for Placement to be ready.
const MINESITE: Vector2i = Vector2i(4, 4)
const PLAIN: Vector2i = Vector2i(10, 8)

var _saved_money: int = 0


func _enter_tree_with_money() -> Node:
	var game: Node = autoload("GameState")
	_saved_money = game.money
	game.money = 100
	tree.root.add_child(_main)
	return _main.get_node("Game/FactoryView/SubViewport/World/Placement")


func _color_at(cell: Vector2i) -> Color:
	_grid.hovered_cell = cell
	return _grid.hover_color()


func test_highlight_with_nothing_selected_is_the_plain_rule() -> void:
	var placement: Node = _enter_tree_with_money()
	check_eq(_color_at(PLAIN), _grid.HOVER_OK, "free ordinary cell is valid")
	check_eq(_color_at(MINESITE), _grid.HOVER_OK, "free minesite is valid")
	check_eq(_color_at(Vector2i(16, 10)), _grid.HOVER_BLOCKED, "occupied cell (collector) is blocked")
	autoload("GameState").money = _saved_money
	check(placement != null, "placement exists")


func test_miner_highlight_requires_a_minesite() -> void:
	var placement: Node = _enter_tree_with_money()
	placement.select("miner")
	check_eq(_color_at(PLAIN), _grid.HOVER_BLOCKED, "ordinary free cell looks invalid for a miner")
	check_eq(_color_at(MINESITE), _grid.HOVER_OK, "free minesite looks valid for a miner")
	check_eq(_color_at(Vector2i(16, 10)), _grid.HOVER_BLOCKED, "occupied cell stays blocked")
	placement.place("smelter", MINESITE)
	check_eq(_color_at(MINESITE), _grid.HOVER_BLOCKED, "an occupied minesite is blocked")
	autoload("GameState").money = _saved_money


func test_other_machines_may_use_minesites_and_ordinary_cells() -> void:
	var placement: Node = _enter_tree_with_money()
	for type: String in ["smelter", "assembler", "conveyor"]:
		placement.select(type)
		check_eq(_color_at(PLAIN), _grid.HOVER_OK, "%s: ordinary cell valid" % type)
		check_eq(_color_at(MINESITE), _grid.HOVER_OK, "%s: minesite valid" % type)
	autoload("GameState").money = _saved_money


func test_highlight_follows_the_selection() -> void:
	var placement: Node = _enter_tree_with_money()
	placement.select("miner")
	check_eq(_color_at(PLAIN), _grid.HOVER_BLOCKED, "miner selected")
	placement.select("")
	check_eq(_color_at(PLAIN), _grid.HOVER_OK, "cancel returns to the plain rule")
	placement.select("miner")
	autoload("GameState").money = 0
	placement.select("miner")
	check_eq(_grid.placement_type, "", "an unaffordable selection clears the highlight rule")
	autoload("GameState").money = _saved_money


func test_highlight_and_placement_agree() -> void:
	var placement: Node = _enter_tree_with_money()
	for cell: Vector2i in [PLAIN, MINESITE, Vector2i(16, 10)]:
		check_eq(_grid.can_place("miner", cell), placement.place("miner", cell) != null, "miner at %s" % cell)
	autoload("GameState").money = _saved_money
