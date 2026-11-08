extends "res://tests/test_case.gd"
## Drag-and-drop: a Build page button dragged onto the map, and a Chip Registry button dragged onto a
## machine. Drives FactoryView's drop handling directly (_can_drop_data/_drop_data are Godot virtuals with
## no other entry point), the same way other tests drive Placement and GridMap2D directly.

var _main: Node
var _placement: Placement
var _grid: GridMap2D
var _view: FactoryView
var _page: BuildPage
var _registry_page: ChipRegistryPage
var _camera: Camera2D
var _game: Node
var _registry: Node
var _saved_size: Vector2i = Vector2i.ZERO
var _saved_money: int = 0
var _chip_ids: Array[int] = []


func before_each() -> void:
	_game = autoload("GameState")
	_registry = autoload("ChipRegistry")
	_saved_money = _game.money
	_game.money = 100
	_saved_size = tree.root.size
	tree.root.size = Vector2i(1152, 648)
	_main = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(_main)
	_placement = _main.get_node("Game/FactoryView/SubViewport/World/Placement")
	_grid = _main.get_node("%GridMap2D")
	_view = _main.get_node("%FactoryView")
	_page = _main.get_node("%BuildPage")
	_registry_page = _main.get_node("%ChipRegistryPage")
	_camera = _main.get_node("Game/FactoryView/SubViewport/World/Camera2D")


func after_each() -> void:
	_main.free()
	tree.root.size = _saved_size
	for id: int in _chip_ids:
		_registry.remove(id)
	_chip_ids.clear()
	_game.money = _saved_money


## before_each() is called without being awaited by the runner (see run_tests.gd), so a wait only takes
## effect if it runs inside the test method itself: every test using _at() calls this first.
func _wait_for_camera() -> void:
	await wait_until(func() -> bool: return _camera.zoom.x > 0.1 and is_equal_approx(_camera.get_canvas_transform().get_scale().x, _camera.zoom.x), 5.0)


func _at(cell: Vector2i) -> Vector2:
	var center: Vector2 = Vector2(cell * _game.CELL_SIZE) + Vector2(_game.CELL_SIZE, _game.CELL_SIZE) / 2.0
	return _camera.get_canvas_transform() * center


func _buttons(page: Control) -> Array[DraggableButton]:
	var result: Array[DraggableButton] = []
	for child: Node in page.get_node("%List").get_children():
		result.append(child as DraggableButton)
	return result


func test_build_buttons_carry_a_machine_payload() -> void:
	var buttons: Array[DraggableButton] = _buttons(_page)
	check_eq(buttons[0].drag_payload, {"machine_type": "miner"}, "the first build button drags a miner")
	check_eq(buttons[3].drag_payload, {"machine_type": "conveyor"}, "the last one a conveyor")


func test_chip_buttons_carry_a_chip_payload() -> void:
	var chip: ChipRessource = _registry.add("drag_test_chip", "p")
	_chip_ids.append(chip.id)
	var button: DraggableButton = _buttons(_registry_page).filter(func(b: DraggableButton) -> bool: return b.text == "drag_test_chip")[0]
	check_eq(button.drag_payload, {"chip_id": chip.id}, "the chip button drags its own id")


func test_dropping_a_building_on_a_valid_cell_places_and_charges() -> void:
	await _wait_for_camera()
	var cell: Vector2i = Vector2i(8, 8)
	var data: Dictionary = {"machine_type": "smelter"}
	check(_view._can_drop_data(_at(cell), data), "the cell accepts the drop")
	_view._drop_data(_at(cell), data)
	check(_game.get_machine_at(cell) is Smelter, "the smelter was placed on drop")
	check_eq(_game.money, 70, "charged once, same as a click placement")


func test_dropping_on_an_occupied_cell_changes_nothing() -> void:
	await _wait_for_camera()
	var cell: Vector2i = Vector2i(8, 8)
	_placement.place("smelter", cell)
	var data: Dictionary = {"machine_type": "conveyor"}
	_view._drop_data(_at(cell), data)
	check(_game.get_machine_at(cell) is Smelter, "the original machine is untouched")
	check_eq(_game.money, 100, "an invalid drop never charges")


func test_dropping_outside_the_grid_is_rejected_and_charges_nothing() -> void:
	await _wait_for_camera()
	var data: Dictionary = {"machine_type": "miner"}
	check(not _view._can_drop_data(Vector2(-500, -500), data), "far outside the view, no cell under it")
	check_eq(_game.money, 100, "nothing charged for a target that was never valid")


func test_hovering_an_invalid_cell_changes_nothing_until_dropped() -> void:
	await _wait_for_camera()
	var cell: Vector2i = Vector2i(9, 9)
	var data: Dictionary = {"machine_type": "miner"}
	# _can_drop_data is probed on every frame while dragging over the view; the actual placement only
	# happens in _drop_data, so hovering alone (here, or a drag cancelled over the Bar) never places anything.
	_view._can_drop_data(_at(cell), data)
	check_eq(_grid.hover_color(), GridMap2D.HOVER_BLOCKED, "not a minesite: the live hover warns it is invalid")
	check(_game.get_machine_at(cell) == null, "no machine appeared from hovering alone")
	check_eq(_game.money, 100, "no money moved")


func test_dragging_a_chip_onto_a_machine_attaches_it_once() -> void:
	await _wait_for_camera()
	var cell: Vector2i = Vector2i(8, 8)
	var smelter: Smelter = _placement.place("smelter", cell)
	var chip: ChipRessource = _registry.add("attach_test_chip", "p")
	_chip_ids.append(chip.id)
	var data: Dictionary = {"chip_id": chip.id}
	check(_view._can_drop_data(_at(cell), data), "a machine sits here: a valid chip target")
	_view._drop_data(_at(cell), data)
	check_eq(smelter.chips.size(), 1, "the chip is attached")
	check_eq(smelter.chips[0].chip.id, chip.id, "the same chip, not a copy")
	_view._drop_data(_at(cell), data)
	check_eq(smelter.chips.size(), 1, "dropping the same chip again does not duplicate it")


func test_dragging_a_chip_onto_an_empty_cell_attaches_nothing() -> void:
	await _wait_for_camera()
	var cell: Vector2i = Vector2i(9, 9)
	var chip: ChipRessource = _registry.add("stray_chip", "p")
	_chip_ids.append(chip.id)
	check(_game.get_machine_at(cell) == null, "nothing here to begin with")
	_view._can_drop_data(_at(cell), {"chip_id": chip.id})
	check_eq(_grid.hover_color(), GridMap2D.HOVER_BLOCKED, "no machine here: the live hover warns it is invalid")
	_view._drop_data(_at(cell), {"chip_id": chip.id})
	check(_game.get_machine_at(cell) == null, "still nothing here")


func test_hover_highlight_follows_the_dragged_kind() -> void:
	await _wait_for_camera()
	var machine_cell: Vector2i = Vector2i(8, 8)
	_placement.place("smelter", machine_cell)
	var empty_cell: Vector2i = Vector2i(9, 9)
	var chip: ChipRessource = _registry.add("hover_test_chip", "p")
	_chip_ids.append(chip.id)
	_view._can_drop_data(_at(machine_cell), {"chip_id": chip.id})
	check_eq(_grid.hover_color(), GridMap2D.HOVER_OK, "a chip drag highlights a cell with a machine")
	_view._can_drop_data(_at(empty_cell), {"chip_id": chip.id})
	check_eq(_grid.hover_color(), GridMap2D.HOVER_BLOCKED, "and refuses an empty one")
	_view._can_drop_data(_at(empty_cell), {"machine_type": "miner"})
	check_eq(_grid.hover_color(), GridMap2D.HOVER_BLOCKED, "a miner off a minesite is still refused, by the normal placement rule")


## Regression test: SubViewportContainer forwards every mouse motion it receives into the embedded
## SubViewport (so the camera and click-to-place keep working), and that forwarding call resets the main
## viewport's own "input handled" bookkeeping as a side effect. Left unchecked, that reset stops the engine
## from ever resolving a drop target while a real (mouse-driven) drag is over the map, so a drop silently
## does nothing - _can_drop_data/_drop_data called directly (every other test above) never exercises this,
## since Godot's own drag machinery is what's affected, not our methods. force_drag() is the public API to
## start a real engine-tracked drag without a mouse (Control has no other entry point for it); ending it with
## a real button event is what exercises Viewport's own cleanup (_perform_drop), so nothing is leaked.
func test_dragging_pauses_the_embedded_viewports_input() -> void:
	await _wait_for_camera()
	var button: DraggableButton = _buttons(_page)[0]
	var viewport: SubViewport = _main.get_node("Game/FactoryView/SubViewport")
	check(not viewport.is_input_disabled(), "nothing dragging yet: the embedded viewport still takes input")
	button.force_drag(button.drag_payload, Control.new())
	await wait_until(func() -> bool: return viewport.is_input_disabled(), 1.0)
	check(viewport.is_input_disabled(), "dragging: forwarding into the embedded viewport is paused")
	var release: InputEventMouseButton = InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	tree.root.push_input(release)
	await wait_until(func() -> bool: return not viewport.is_input_disabled(), 1.0)
	check(not viewport.is_input_disabled(), "drag ended: forwarding resumes")
	check(not tree.root.gui_is_dragging(), "the forced drag is over")


## _cell_at() goes through the camera's own canvas_transform, so a drop still lands on the right cell
## whatever the current zoom (zoomed in here; the default fit-to-grid zoom is covered by every other test).
func test_dropping_still_works_after_zooming_in() -> void:
	await _wait_for_camera()
	var cell: Vector2i = Vector2i(8, 8)
	var starting_zoom: float = _camera.zoom.x
	_camera.zoom_at(3.0, _at(cell))
	check(_camera.zoom.x > starting_zoom * 1.5, "zoomed in")
	var data: Dictionary = {"machine_type": "smelter"}
	check(_view._can_drop_data(_at(cell), data), "still a valid target at the new zoom")
	_view._drop_data(_at(cell), data)
	check(_game.get_machine_at(cell) is Smelter, "placed on the right cell despite the zoom")
