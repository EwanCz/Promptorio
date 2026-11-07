extends "res://tests/test_case.gd"
## Placement driven through Godot's input pipeline (Input.parse_input_event), not by calling handlers.

var _main: Node
var _placement: Placement
var _grid: GridMap2D
var _game: Node
var _saved_money: int = 0
var _saved_size: Vector2i = Vector2i.ZERO


func before_each() -> void:
	_game = autoload("GameState")
	_saved_money = _game.money
	_game.money = 1000
	# The headless root window is 64x64, which would drop mouse events outside it.
	_saved_size = tree.root.size
	tree.root.size = Vector2i(1152, 648)
	_main = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(_main)
	_placement = _main.get_node("Game/FactoryView/SubViewport/World/Placement")
	_grid = _main.get_node("Game/FactoryView/SubViewport/World/GridMap2D")
	await tree.process_frame


func after_each() -> void:
	_game.money = _saved_money
	_main.free()
	tree.root.size = _saved_size


## Presses then releases a physical key. `label` is what the layout would type on that key.
func _tap(physical: Key, label: Key) -> void:
	for pressed: bool in [true, false]:
		var event: InputEventKey = InputEventKey.new()
		event.physical_keycode = physical
		event.keycode = label
		event.pressed = pressed
		Input.parse_input_event(event)
	await tree.process_frame


## Moves the mouse over the cell (so the grid hovers it), then left-clicks.
func _click_cell(cell: Vector2i) -> void:
	var position: Vector2 = Vector2(cell * _game.CELL_SIZE) + Vector2(_game.CELL_SIZE, _game.CELL_SIZE) / 2.0
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = position
	motion.global_position = position
	Input.parse_input_event(motion)
	await tree.process_frame
	for pressed: bool in [true, false]:
		var click: InputEventMouseButton = InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.position = position
		click.global_position = position
		click.pressed = pressed
		Input.parse_input_event(click)
	await tree.process_frame


func test_key_selects_then_escape_cancels_and_click_places_nothing() -> void:
	var cell: Vector2i = Vector2i(8, 8)
	await _tap(KEY_3, KEY_3)
	check_eq(_placement.selected, "assembler", "physical 3 selects the assembler through the input system")

	await _click_cell(cell)
	check_eq(_grid.hovered_cell, cell, "the mouse events reached the grid and hovered the cell")
	check(_game.get_machine_at(cell) is Assembler, "with a selection, the click places the machine")
	_game.unregister_machine(cell)

	await _tap(KEY_ESCAPE, KEY_ESCAPE)
	check_eq(_placement.selected, "", "Escape cancels the selection")

	var other: Vector2i = Vector2i(9, 8)
	await _click_cell(other)
	check_eq(_grid.hovered_cell, other, "the second click reached the grid too")
	check(_game.get_machine_at(other) == null, "after Escape the click places nothing")


func test_azerty_number_row_selects_through_the_input_system() -> void:
	await _tap(KEY_5, KEY_PARENLEFT)
	check_eq(_placement.selected, "conveyor", "physical 5 (typing '(') selects the conveyor")
