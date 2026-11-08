extends "res://tests/test_case.gd"
## Main menu: its buttons, a new game, loading a save, the chip manager, and Options.

const TEST_DIR: String = "user://test_saves_menu"

var _menu: MainMenu
var _game: Node
var _registry: Node
var _saved_money: int = 0
var _saved_ticks: int = 0
var _saved_order: Dictionary = {}
var _saved_dir: String = ""
var _requested: int = 0
var _chip_ids: Array[int] = []


func before_each() -> void:
	_game = autoload("GameState")
	_registry = autoload("ChipRegistry")
	_saved_money = _game.money
	_saved_ticks = _game.tick_count
	_saved_order = {"product": _game.order_product, "quantity": _game.order_quantity, "progress": _game.order_progress, "reward": _game.order_reward}
	_saved_dir = SaveGame.save_dir
	SaveGame.save_dir = TEST_DIR
	_requested = 0
	_menu = load("res://scenes/menu/main_menu.tscn").instantiate()
	tree.root.add_child(_menu)
	_menu.game_requested.connect(_on_game_requested)


func after_each() -> void:
	_menu.game_requested.disconnect(_on_game_requested)
	tree.paused = false
	_menu.free()
	for id: int in _chip_ids:
		_registry.remove(id)
	_chip_ids.clear()
	if DirAccess.dir_exists_absolute(TEST_DIR):
		for file_name: String in DirAccess.get_files_at(TEST_DIR):
			DirAccess.remove_absolute(TEST_DIR + "/" + file_name)
		DirAccess.remove_absolute(TEST_DIR)
	SaveGame.pending = {}
	SaveGame.save_dir = _saved_dir
	_game.money = _saved_money
	_game.tick_count = _saved_ticks
	_game.restore_order(_saved_order["product"], _saved_order["quantity"], _saved_order["progress"], _saved_order["reward"])


func _on_game_requested() -> void:
	_requested += 1


func _write_save(slot: String, data: Dictionary) -> void:
	SaveGame.write(SaveGame.slot_path(slot), data)


func _valid_save() -> Dictionary:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(main)
	var placement: Placement = main.get_node("Game/FactoryView/SubViewport/World/Placement")
	placement.place("smelter", Vector2i(8, 8))
	var save: Dictionary = JSON.parse_string(JSON.stringify(SaveGame.snapshot(placement)))
	main.free()
	return save


func _listed(manager: ChipManager, chip_name: String) -> bool:
	for row: Node in manager.get_node("%ChipRegistryPage/List").get_children():
		if not row.is_queued_for_deletion() and (row as Button).text == chip_name:
			return true
	return false


func test_the_menu_has_its_five_buttons_and_no_credits() -> void:
	for button_name: String in ["PlayButton", "LoadButton", "ChipsButton", "OptionsButton", "ExitButton"]:
		check(_menu.get_node_or_null("%" + button_name) is PixelButton, button_name + " exists")
	check(_menu.get_node_or_null("%CreditsButton") == null, "there is no Credits button")
	check(not (_menu.get_node("%SaveDialog") as Control).visible, "popups start hidden")


func test_play_starts_a_new_game() -> void:
	_game.money = 5
	_game.tick_count = 42
	SaveGame.pending = {"stale": true}
	(_menu.get_node("%PlayButton") as Button).pressed.emit()
	check_eq(_requested, 1, "the game scene is requested")
	check_eq(_game.money, _game.START_MONEY, "with the starting money")
	check_eq(_game.tick_count, 0, "and a fresh clock")
	check(SaveGame.pending.is_empty(), "no save is waiting")


func test_load_game_lists_slots_without_pausing() -> void:
	_write_save("slot_a", _valid_save())
	(_menu.get_node("%LoadButton") as Button).pressed.emit()
	var dialog: SaveDialog = _menu.get_node("%SaveDialog")
	check(dialog.visible, "the load dialog opens")
	check(not tree.paused, "the menu is not paused")
	check_eq((dialog.get_node("%SlotList") as VBoxContainer).get_child_count(), 1, "the slot is listed")


func test_loading_a_slot_queues_the_save_for_the_game() -> void:
	_write_save("slot_a", _valid_save())
	var dialog: SaveDialog = _menu.get_node("%SaveDialog")
	dialog.open()
	_game.money = 5
	check(dialog.load_slot("slot_a"), "the slot loads")
	check_eq(_requested, 1, "the game scene is requested")
	check(not SaveGame.pending.is_empty(), "the save waits for the game")
	check_eq(_game.money, _game.START_MONEY, "the game state is reset before the save is restored")


func test_a_bad_save_starts_nothing() -> void:
	_write_save("junk", {"version": 1})
	var dialog: SaveDialog = _menu.get_node("%SaveDialog")
	dialog.open()
	check(not dialog.load_slot("junk"), "an incomplete save is refused")
	check_eq(_requested, 0, "no game is requested")
	check(SaveGame.pending.is_empty(), "nothing is queued")
	check(dialog.visible, "the dialog stays open")


func test_chips_button_opens_the_manager_and_a_chip_can_be_created() -> void:
	(_menu.get_node("%ChipsButton") as Button).pressed.emit()
	var manager: ChipManager = _menu.get_node("%ChipManager")
	check(manager.visible, "the chip manager opens")
	var page: ChipPage = _menu.get_node("%ChipPage")
	(manager.get_node("%ChipRegistryPage/NewButton") as Button).pressed.emit()
	check(page.visible, "New chip opens the chip page")
	(page.get_node("%NameEdit") as LineEdit).text = "menu_chip"
	(page.get_node("%SaveButton") as Button).pressed.emit()
	var created: ChipRessource = null
	for chip: ChipRessource in _registry.get_all():
		if chip.name == "menu_chip":
			created = chip
	check(created != null, "the chip is in the registry")
	if created != null:
		_chip_ids.append(created.id)
	check(not page.visible and not tree.paused, "the chip page closed and the menu is running")
	await wait_until(func() -> bool: return _listed(manager, "menu_chip"), 2.0)
	check(_listed(manager, "menu_chip"), "the list shows the new chip")


func test_options_opens_settings() -> void:
	(_menu.get_node("%OptionsButton") as Button).pressed.emit()
	check((_menu.get_node("%SettingsDialog") as Control).visible, "the settings dialog opens")
