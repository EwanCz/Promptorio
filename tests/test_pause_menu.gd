extends "res://tests/test_case.gd"
## In-game pause menu: opened from the Bar button or Escape, pauses, resumes, restarts, goes back to the menu.

var _main: Node
var _menu: PauseMenu
var _game: Node
var _saved_money: int = 0
var _saved_ticks: int = 0
var _saved_order: Dictionary = {}


func before_each() -> void:
	_game = autoload("GameState")
	_saved_money = _game.money
	_saved_ticks = _game.tick_count
	_saved_order = {"product": _game.order_product, "quantity": _game.order_quantity, "progress": _game.order_progress, "reward": _game.order_reward}
	_main = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(_main)
	_menu = _main.get_node("%PauseMenu")


func after_each() -> void:
	tree.paused = false
	_main.free()
	_game.money = _saved_money
	_game.tick_count = _saved_ticks
	_game.restore_order(_saved_order["product"], _saved_order["quantity"], _saved_order["progress"], _saved_order["reward"])


func _press_cancel() -> void:
	var event: InputEventAction = InputEventAction.new()
	event.action = "cancel_placement"
	event.pressed = true
	_main._unhandled_input(event)


func test_pause_menu_and_bar_button_are_in_the_scene() -> void:
	check(_menu != null and not _menu.visible, "the pause menu exists and starts hidden")
	check_eq(_menu.process_mode, Node.PROCESS_MODE_ALWAYS, "it keeps working while paused")
	var button: Button = _main.get_node("%MenuButton")
	check(button.get_parent() == _main.get_node("%BarButtons"), "the Menu button sits in the Bar's button row")
	check(button.get_index() < _main.get_node("%SettingsButton").get_index(), "before Settings, which stays last")


func test_bar_button_opens_and_resume_closes() -> void:
	(_main.get_node("%MenuButton") as Button).pressed.emit()
	check(_menu.visible and tree.paused, "the button opens the menu and pauses")
	(_menu.get_node("%ResumeButton") as Button).pressed.emit()
	check(not _menu.visible and not tree.paused, "Resume closes it and resumes the game")


func test_escape_opens_the_menu_when_nothing_is_selected() -> void:
	_press_cancel()
	check(_menu.visible and tree.paused, "Escape opens the pause menu")


func test_escape_with_a_selection_only_cancels_the_placement() -> void:
	var placement: Placement = _main.get_node("Game/FactoryView/SubViewport/World/Placement")
	placement.select("miner")
	_press_cancel()
	check_eq(placement.selected, "", "the placement is cancelled")
	check(not _menu.visible, "the menu stays closed")


func test_escape_closes_the_open_menu() -> void:
	_menu.open()
	var event: InputEventAction = InputEventAction.new()
	event.action = "cancel_placement"
	event.pressed = true
	_menu._unhandled_input(event)
	check(not _menu.visible and not tree.paused, "Escape closes it again")


func test_restart_and_main_menu_start_over() -> void:
	_game.money = 7
	_game.tick_count = 50
	_menu.open()
	(_menu.get_node("%RestartButton") as Button).pressed.emit()
	check_eq(_game.money, _game.START_MONEY, "Restart resets the money")
	check_eq(_game.tick_count, 0, "and the clock")
	check(not _menu.visible and not tree.paused, "and closes the menu")
	_game.money = 7
	_menu.open()
	(_menu.get_node("%MainMenuButton") as Button).pressed.emit()
	check_eq(_game.money, _game.START_MONEY, "Main Menu resets the game too")
	check(not tree.paused, "and the game is not left paused")


func test_the_menu_looks_like_the_main_menu() -> void:
	check_eq(_menu.theme_type_variation, &"MainMenuPanel", "same panel as the main menu")
	for button_name: String in ["ResumeButton", "RestartButton", "MainMenuButton"]:
		var button: Button = _menu.get_node("%" + button_name)
		check_eq(button.theme_type_variation, &"MainMenuButton", button_name + " uses the main menu button style")
		check(button.icon != null, button_name + " has an icon")
		check(button.text != "", button_name + " has a label")
