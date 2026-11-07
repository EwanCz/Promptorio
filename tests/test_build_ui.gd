extends "res://tests/test_case.gd"
## Build page, placement costs, and the tooltip actions (rotate, destroy, current action).

var _main: Node
var _placement: Placement
var _page: BuildPage
var _tooltip: MachineTooltip
var _game: Node
var _saved_money: int = 0
var _registry: Node
var _chip_ids: Array[int] = []


func before_each() -> void:
	_game = autoload("GameState")
	_registry = autoload("ChipRegistry")
	_saved_money = _game.money
	_game.money = 100
	_main = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(_main)
	_placement = _main.get_node("Game/FactoryView/SubViewport/World/Placement")
	_page = _main.get_node("%BuildPage")
	_tooltip = _main.get_node("%MachineTooltip")


func after_each() -> void:
	_main.free()
	for id: int in _chip_ids:
		_registry.remove(id)
	_chip_ids.clear()
	_game.money = _saved_money


func _buttons() -> Array[Button]:
	var result: Array[Button] = []
	for child: Node in _page.get_node("%List").get_children():
		result.append(child as Button)
	return result


func test_start_money_and_catalog() -> void:
	check(_game.START_MONEY > 0, "the game starts with some money")
	check_eq(Placement.COSTS, {"miner": 20, "smelter": 30, "assembler": 40, "conveyor": 2}, "catalog costs")


func test_page_lists_machines_with_cost_and_money() -> void:
	var buttons: Array[Button] = _buttons()
	check_eq(buttons.size(), 4, "one button per buildable machine")
	check_eq(buttons[0].text, "Miner - 20", "cost shown")
	check_eq((_page.get_node("%MoneyLabel") as Label).text, "Money: 100", "money shown")


func test_unaffordable_machines_are_disabled() -> void:
	_game.add_money(-85)
	var buttons: Array[Button] = _buttons()
	check(buttons[0].disabled, "miner (20) too expensive with 15")
	check(buttons[3].disabled == false, "conveyor (2) still affordable")
	check_eq((_page.get_node("%MoneyLabel") as Label).text, "Money: 15", "money label follows money_changed")


func test_selecting_does_not_charge_and_toggles() -> void:
	var buttons: Array[Button] = _buttons()
	buttons[1].pressed.emit()
	check_eq(_placement.selected, "smelter", "button enters placement mode")
	check_eq(_game.money, 100, "selecting charges nothing")
	check(buttons[1].button_pressed, "selected type is highlighted")
	buttons[1].pressed.emit()
	check_eq(_placement.selected, "", "pressing it again cancels")


func test_selection_by_key_is_shown_on_the_page() -> void:
	_placement.select("assembler")
	check(_buttons()[2].button_pressed, "key selection highlights the same button")


func test_placing_charges_once_and_rejections_do_not() -> void:
	var rejected: Array[String] = []
	var on_rejected: Callable = func(reason: String) -> void: rejected.append(reason)
	_placement.placement_rejected.connect(on_rejected)
	check(_placement.try_place("smelter", Vector2i(8, 8)) is Smelter, "affordable placement works")
	check_eq(_game.money, 70, "charged exactly the cost")
	check(_placement.try_place("smelter", Vector2i(8, 8)) == null, "occupied cell refused")
	check(_placement.try_place("miner", Vector2i(9, 9)) == null, "miner off a minesite refused")
	check_eq(_game.money, 70, "rejections do not charge")
	_game.money = 10
	check(_placement.try_place("assembler", Vector2i(10, 10)) == null, "too expensive")
	check_eq(_game.money, 10, "money untouched when it cannot pay")
	check(_game.get_machine_at(Vector2i(10, 10)) == null, "registry untouched")
	check_eq(rejected.size(), 3, "each refusal gives feedback")
	_placement.placement_rejected.disconnect(on_rejected)


func test_click_charges_through_the_grid() -> void:
	var grid: GridMap2D = _main.get_node("%GridMap2D")
	_placement.select("conveyor")
	grid.cell_clicked.emit(Vector2i(8, 8))
	grid.cell_clicked.emit(Vector2i(9, 8))
	check_eq(_game.money, 96, "two conveyors charged 2 each, selection stays active")
	check_eq(_placement.selected, "conveyor", "selected type kept after placing")


func test_page_shows_rejection_feedback() -> void:
	_game.money = 0
	_placement.try_place("conveyor", Vector2i(8, 8))
	check((_page.get_node("%FeedbackLabel") as Label).text != "", "refusal is shown")


func test_destroy_discards_contents_and_frees_the_cell() -> void:
	var smelter: Smelter = _placement.place("smelter", Vector2i(8, 8))
	smelter.receive("ore")
	var chip: ChipRessource = _registry.add("destroy_chip", "p")
	_chip_ids.append(chip.id)
	smelter.attach_chip(chip.id)
	check(smelter.destroy(), "destroy succeeds")
	check(_game.get_machine_at(Vector2i(8, 8)) == null, "cell freed immediately")
	check(smelter.stock.is_empty(), "stock discarded")
	check(smelter.chips.is_empty(), "chips detached")
	check(smelter.get_parent() == null, "removed from the scene")
	check_eq(_game.money, 100, "no refund")
	check(_placement.place("smelter", Vector2i(8, 8)) != null, "the cell can be rebuilt")


func test_destroy_clears_every_machine_kind() -> void:
	var miner: Miner = _placement.place("miner", GridMap2D.MINESITES[0])
	miner._held = "ore"
	miner.destroy()
	check_eq(miner._held, "", "miner drops its held ore")
	var conveyor: Conveyor = _placement.place("conveyor", Vector2i(8, 8))
	conveyor.receive("ore")
	conveyor.destroy()
	check_eq(conveyor.held, "", "conveyor drops its item")


func test_collector_is_fixed() -> void:
	var collector: Machine = _game.get_machine_at(_game.GRID_SIZE / 2)
	check(not collector.is_removable(), "collector is not removable")
	check(not collector.can_rotate(), "collector has no facing")
	check(not collector.destroy(), "destroy refused")
	check(_game.get_machine_at(_game.GRID_SIZE / 2) == collector, "collector stays registered")


func test_rotate_is_clockwise_and_keeps_stock() -> void:
	var smelter: Smelter = _placement.place("smelter", Vector2i(8, 8))
	smelter.receive("ore")
	smelter.rotate_facing()
	check_eq(smelter.facing, Vector2i.DOWN, "right becomes down")
	check_eq(smelter.stock.get("ore"), 1, "stock unchanged")


func test_tooltip_destroy_and_rotate_buttons() -> void:
	var conveyor: Conveyor = _placement.place("conveyor", Vector2i(8, 8))
	_main.get_node("%GridMap2D").cell_clicked.emit(Vector2i(8, 8))
	check(_tooltip.visible, "tooltip opens on click")
	check(_tooltip.get_node("%RotateButton").visible, "conveyor can rotate")
	check(_tooltip.get_node("%DestroyButton").visible, "conveyor can be destroyed")
	check((_tooltip.get_node("%ActionLabel") as Label).text.begins_with("Facing"), "conveyor action shown")
	_tooltip.get_node("%RotateButton").pressed.emit()
	check_eq(conveyor.facing, Vector2i.DOWN, "rotate button rotates")
	_tooltip.get_node("%DestroyButton").pressed.emit()
	check(not _tooltip.visible, "tooltip closes")
	check(_game.get_machine_at(Vector2i(8, 8)) == null, "machine destroyed")


func test_tooltip_hides_actions_for_the_collector() -> void:
	_placement.select("")
	_main.get_node("%GridMap2D").cell_clicked.emit(_game.GRID_SIZE / 2)
	check(not _tooltip.get_node("%RotateButton").visible, "no rotate on the collector")
	check(not _tooltip.get_node("%DestroyButton").visible, "no destroy on the collector")
	check((_tooltip.get_node("%ActionLabel") as Label).text.begins_with("Sold"), "collector shows sales")


func test_action_text_per_machine() -> void:
	var miner: Miner = _placement.place("miner", GridMap2D.MINESITES[0])
	check(miner.get_action_text().contains("every %d ticks" % miner.mine_ticks), "miner rate")
	var smelter: Smelter = _placement.place("smelter", Vector2i(8, 8))
	var text: String = smelter.get_action_text()
	check(text.contains("idle") and text.contains("Temperature") and text.contains("cooling off"), "smelter state, temperature, cooling")
	smelter.receive("ore")
	check(smelter.get_action_text().contains("1 ore"), "smelter stock")


func test_destroyed_machine_closes_its_open_tooltip() -> void:
	var conveyor: Conveyor = _placement.place("conveyor", Vector2i(8, 8))
	_tooltip.open(conveyor)
	conveyor.destroy()
	check(not _tooltip.visible, "tooltip closes when the machine goes away")


func test_popups_consume_mouse_input() -> void:
	check_eq(_tooltip.mouse_filter, Control.MOUSE_FILTER_STOP, "tooltip blocks clicks to the map")
	check_eq((_main.get_node("%Bar") as Control).mouse_filter, Control.MOUSE_FILTER_STOP, "bar blocks clicks to the map")


func test_collector_cannot_be_built() -> void:
	var rejected: Array[String] = []
	var on_rejected: Callable = func(reason: String) -> void: rejected.append(reason)
	_placement.placement_rejected.connect(on_rejected)
	var before: int = _game.money
	check(_placement.try_place("collector", Vector2i(11, 11)) == null, "collector refused")
	check(_game.get_machine_at(Vector2i(11, 11)) == null, "nothing registered")
	check_eq(_game.money, before, "money untouched")
	check_eq(rejected.size(), 1, "refusal explained")
	_placement.placement_rejected.disconnect(on_rejected)
	for button: Button in _buttons():
		check(not button.text.begins_with("Collector"), "not on the build page")


func test_bar_switches_pages_with_named_buttons() -> void:
	var tabs: Node = _main.get_node("%PageTabs")
	check(tabs is HFlowContainer, "page markers are plain buttons, no scroll arrows")
	var names: Array[String] = []
	for button: Node in tabs.get_children():
		names.append((button as Button).text)
	check_eq(names, ["Build", "Chip Registry"], "buttons carry the page names")
	var pages: Node = _main.get_node("%Pages")
	check((pages.get_child(0) as Control).visible and not (pages.get_child(1) as Control).visible, "build page shown first")
	tabs.get_child(1).pressed.emit()
	check((pages.get_child(1) as Control).visible and not (pages.get_child(0) as Control).visible, "second button shows its page")
