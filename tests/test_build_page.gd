extends "res://tests/test_case.gd"

var _main: Node
var _page: BuildPage
var _placement: Placement
var _game: Node
var _saved_money: int = 0


func before_each() -> void:
	_game = autoload("GameState")
	_saved_money = _game.money
	_game.money = 100
	_main = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(_main)
	_page = _main.get_node("%BuildPage")
	_placement = _main.get_node("Game/FactoryView/SubViewport/World/Placement")


func after_each() -> void:
	_game.money = _saved_money
	_main.free()


func _button(type: String) -> Button:
	return _page.get_node("%List").get_child(MachineCatalog.BUILDABLE.find(type)) as Button


func test_game_starts_with_100_money() -> void:
	check_eq(MachineCatalog.COSTS, {"miner": 20, "smelter": 30, "assembler": 40, "conveyor": 2}, "catalog prices")
	var tabs: TabBar = _main.get_node("%PageTabs")
	check_eq([tabs.get_tab_title(0), tabs.get_tab_title(1)], ["Build", "Chip Registry"], "Build and Chip Registry tabs side by side")


func test_lists_buildable_machines_with_costs_and_money() -> void:
	check_eq(_page.get_node("%List").get_child_count(), 4, "four buildable machines, no collector")
	for type: String in MachineCatalog.BUILDABLE:
		check(_button(type).text.contains(str(MachineCatalog.cost(type))), "%s shows its cost" % type)
	check_eq((_page.get_node("%MoneyLabel") as Label).text, "Money: 100", "current money shown")


func test_unaffordable_machines_are_disabled() -> void:
	_game.add_money(-75)
	check(not _button("conveyor").disabled, "conveyor (2) still affordable with 25")
	check(not _button("miner").disabled, "miner (20) still affordable with 25")
	check(_button("smelter").disabled, "smelter (30) disabled")
	check(_button("assembler").disabled, "assembler (40) disabled")
	check_eq((_page.get_node("%MoneyLabel") as Label).text, "Money: 25", "money label follows money_changed")


func test_button_enters_placement_without_charging() -> void:
	_button("smelter").pressed.emit()
	check_eq(_placement.selected, "smelter", "placement mode entered")
	check_eq(_game.money, 100, "selecting does not charge")
	check(_button("smelter").button_pressed, "selected type is highlighted")
	check((_page.get_node("%StatusLabel") as Label).text.contains("Smelter"), "status names the selection")


func test_pressing_again_or_cancel_leaves_placement() -> void:
	_button("miner").pressed.emit()
	_button("miner").pressed.emit()
	check_eq(_placement.selected, "", "second press deselects")
	_button("miner").pressed.emit()
	_placement.handle_input(_cancel())
	check_eq(_placement.selected, "", "cancel_placement exits")
	check(not _button("miner").button_pressed, "highlight cleared")


func test_rejected_placement_shows_feedback() -> void:
	_button("miner").pressed.emit()
	_placement.place("miner", Vector2i(9, 9))
	check((_page.get_node("%FeedbackLabel") as Label).text != "", "reason shown")
	check_eq(_game.money, 100, "nothing charged")
	_button("miner").pressed.emit()
	check_eq((_page.get_node("%FeedbackLabel") as Label).text, "", "feedback cleared on a new selection")


func test_placement_updates_money_label() -> void:
	_button("conveyor").pressed.emit()
	_placement.place("conveyor", Vector2i(8, 8))
	check_eq((_page.get_node("%MoneyLabel") as Label).text, "Money: 98", "charged once and shown")


func _cancel() -> InputEventAction:
	var event: InputEventAction = InputEventAction.new()
	event.action = "cancel_placement"
	event.pressed = true
	return event
