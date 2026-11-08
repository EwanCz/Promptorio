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
	check(_placement.place("miner", _grid.minesites[0]) is Miner, "miner accepted on a minesite")
	check(_placement.place("smelter", _grid.minesites[1]) is Smelter, "other machines may use minesites")


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


const BINDINGS: Dictionary = {
	"select_miner": KEY_1,
	"select_smelter": KEY_2,
	"select_assembler": KEY_3,
	"select_conveyor": KEY_5,
	"rotate_placement": KEY_R,
	"cancel_placement": KEY_ESCAPE,
	"destroy_machine": KEY_X,
}


func _action(name: String) -> InputEventAction:
	var event: InputEventAction = InputEventAction.new()
	event.action = name
	event.pressed = true
	return event


func _key(physical: Key, label: Key = KEY_NONE) -> InputEventKey:
	var event: InputEventKey = InputEventKey.new()
	event.pressed = true
	event.physical_keycode = physical
	event.keycode = label
	return event


func test_actions_have_physical_default_bindings() -> void:
	for action: String in BINDINGS:
		check(InputMap.has_action(action), "%s exists" % action)
		var physical: Array = InputMap.action_get_events(action).filter(
			func(e: InputEvent) -> bool: return e is InputEventKey and e.physical_keycode == BINDINGS[action] and e.keycode == KEY_NONE)
		check_eq(physical.size(), 1, "%s is bound to its physical default key" % action)


func test_actions_select_rotate_and_cancel() -> void:
	_main._unhandled_input(_action("select_smelter"))
	check_eq(_placement.selected, "smelter", "select_smelter selects the smelter")
	_main._unhandled_input(_action("rotate_placement"))
	check_eq(_placement.facing, Vector2i.DOWN, "rotate_placement rotates")
	_main._unhandled_input(_action("cancel_placement"))
	check_eq(_placement.selected, "", "cancel_placement deselects")


func test_destroy_machine_is_bound_to_x_and_delete() -> void:
	var keys: Array[int] = []
	for event: InputEvent in InputMap.action_get_events("destroy_machine"):
		keys.append((event as InputEventKey).physical_keycode)
	check(keys.has(KEY_X) and keys.has(KEY_DELETE), "X and Delete")


func test_destroy_action_removes_the_selected_machine() -> void:
	var belt: Machine = _placement.place("conveyor", Vector2i(8, 8))
	_main.get_node("%MachineTooltip").open(belt)
	_main._unhandled_input(_action("destroy_machine"))
	check(belt.is_queued_for_deletion(), "the shortcut removed it")
	check(_game.get_machine_at(Vector2i(8, 8)) == null, "and freed its cell")


## Every popup of the UI layer blocks the shortcut, and the shortcut works again once it is closed.
func test_destroy_shortcut_is_ignored_while_any_popup_is_open() -> void:
	var popups: Array[Control] = []
	for popup: Node in _main.get_node("UI").get_children():
		popups.append(popup as Control)
	check(popups.size() >= 6, "the UI layer has its popups (%d)" % popups.size())
	for popup: Control in popups:
		var belt: Machine = _placement.place("conveyor", Vector2i(8, 8))
		_main.get_node("%MachineTooltip").open(belt)
		popup.visible = true
		_main._unhandled_input(_action("destroy_machine"))
		check(not belt.is_queued_for_deletion(), "%s open: the machine stays" % popup.name)
		check(_game.get_machine_at(Vector2i(8, 8)) == belt, "%s open: its cell stays taken" % popup.name)
		popup.visible = false
		_main._unhandled_input(_action("destroy_machine"))
		check(belt.is_queued_for_deletion(), "%s closed: the shortcut works again" % popup.name)


func test_each_select_action_picks_its_machine() -> void:
	var expected: Dictionary = {"select_miner": "miner", "select_smelter": "smelter", "select_assembler": "assembler",
		"select_conveyor": "conveyor"}
	for action: String in expected:
		_main._unhandled_input(_action(action))
		check_eq(_placement.selected, expected[action], "%s -> %s" % [action, expected[action]])


func test_unaffordable_machine_cannot_be_selected_by_shortcut() -> void:
	var saved_money: int = _game.money
	_game.money = Placement.COSTS["miner"] - 1
	var rejections: Array[String] = []
	var on_rejected: Callable = func(reason: String) -> void: rejections.append(reason)
	_placement.placement_rejected.connect(on_rejected)
	_main._unhandled_input(_action("select_miner"))
	check_eq(_placement.selected, "", "unaffordable shortcut leaves placement cancelled")
	check_eq(rejections.size(), 1, "shortcut reports insufficient funds")
	check(rejections[0].contains("Not enough money"), "feedback explains why selection failed")
	_placement.placement_rejected.disconnect(on_rejected)
	_game.money = saved_money


func test_player_cannot_select_or_build_a_collector() -> void:
	check(not InputMap.has_action("select_collector"), "no collector action")
	check(not _placement.handle_input(_key(KEY_4, KEY_4)), "key 4 is not a placement key")
	_placement.select("miner")
	_placement.select("collector")
	check_eq(_placement.selected, "", "collector is not a selectable type")
	_placement.selected = "collector"
	var saved_money: int = _game.money
	_game.money = 1000
	_placement._on_cell_clicked(Vector2i(11, 11))
	_game.money = saved_money
	check(_game.get_machine_at(Vector2i(11, 11)) == null, "clicking with a collector selected builds nothing")
	var collectors: int = 0
	for machine: Machine in _placement.machines.get_children():
		collectors += 1 if machine is Collector else 0
	check_eq(collectors, 1, "only the center collector exists")


func test_default_keys_trigger_the_actions() -> void:
	_main._unhandled_input(_key(KEY_3, KEY_3))
	check_eq(_placement.selected, "assembler", "key 3 selects the assembler")
	_main._unhandled_input(_key(KEY_R, KEY_R))
	check_eq(_placement.facing, Vector2i.DOWN, "R rotates")
	_main._unhandled_input(_key(KEY_ESCAPE, KEY_ESCAPE))
	check_eq(_placement.selected, "", "Escape cancels")


func test_number_row_works_on_azerty() -> void:
	# AZERTY: the physical "5" key produces "(" and the physical "1" key produces "&".
	_main._unhandled_input(_key(KEY_5, KEY_PARENLEFT))
	check_eq(_placement.selected, "conveyor", "physical 5 selects the conveyor whatever the layout")
	_main._unhandled_input(_key(KEY_1, KEY_AMPERSAND))
	check_eq(_placement.selected, "miner", "physical 1 selects the miner whatever the layout")
	_main._unhandled_input(_key(KEY_NONE, KEY_5))
	check_eq(_placement.selected, "miner", "a label-only 5 (a different physical key) does nothing")


func test_unrelated_input_is_not_handled() -> void:
	check(not _placement.handle_input(_key(KEY_Q, KEY_A)), "unbound key is ignored")
	check(not _placement.handle_input(_action("toggle_bar")), "other actions are ignored")


func test_placed_machines_are_removed_with_the_scene() -> void:
	_placement.place("conveyor", Vector2i(8, 8))
	_main.free()
	check(_game.get_machine_at(Vector2i(8, 8)) == null, "freed machines leave the registry")
	check(_game.get_machine_at(_game.GRID_SIZE / 2) == null, "so does the collector")
	_main = Node.new()
