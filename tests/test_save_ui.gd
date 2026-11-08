extends "res://tests/test_case.gd"
## Save / Load popup: slots, import and export, pause, messages, and the Bar button.

const TEST_DIR: String = "user://test_saves_ui"
const EXPORT_PATH: String = "user://test_saves_ui/exported.json"

var _main: Node
var _placement: Placement
var _dialog: SaveDialog
var _game: Node
var _saved_money: int = 0
var _saved_dir: String = ""


func before_each() -> void:
	_game = autoload("GameState")
	_saved_money = _game.money
	_saved_dir = SaveGame.save_dir
	SaveGame.save_dir = TEST_DIR
	_game.money = 100
	_main = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(_main)
	_placement = _main.get_node("Game/FactoryView/SubViewport/World/Placement")
	_dialog = _main.get_node("%SaveDialog")


func after_each() -> void:
	tree.paused = false
	_main.free()
	if DirAccess.dir_exists_absolute(TEST_DIR):
		for file_name: String in DirAccess.get_files_at(TEST_DIR):
			DirAccess.remove_absolute(TEST_DIR + "/" + file_name)
		DirAccess.remove_absolute(TEST_DIR)
	SaveGame.save_dir = _saved_dir
	_game.money = _saved_money


func _rows() -> int:
	return (_dialog.get_node("%SlotList") as VBoxContainer).get_child_count()


func _status() -> String:
	return (_dialog.get_node("%StatusLabel") as Label).text


func test_dialog_and_button_are_in_the_scene() -> void:
	check(_dialog != null and not _dialog.visible, "the dialog exists and starts hidden")
	var button: Button = _main.get_node("%SavesButton")
	check(button.get_parent() == _main.get_node("%BarButtons"), "the button sits in the Bar's button row")
	check(button.get_index() < _main.get_node("%SettingsButton").get_index(), "before Settings, which stays last")


func test_bar_button_opens_the_dialog_and_pauses() -> void:
	(_main.get_node("%SavesButton") as Button).pressed.emit()
	check(_dialog.visible, "the button opens the dialog")
	check(tree.paused, "the game is paused while it is open")
	check_eq(_dialog.process_mode, Node.PROCESS_MODE_ALWAYS, "the dialog keeps working while paused")
	_dialog.close()
	check(not tree.paused and not _dialog.visible, "closing resumes the game")


func test_save_creates_a_slot_and_lists_it() -> void:
	_dialog.open()
	check_eq(_rows(), 0, "no slot at first")
	check(_dialog.save_slot("first"), "saving works")
	check(FileAccess.file_exists(TEST_DIR + "/first.json"), "the slot file exists")
	check_eq(_rows(), 1, "the slot is listed")
	check(_status().contains("first"), "the status confirms it")
	check(not _status().contains("user:"), "the status never shows a path")


func test_bad_slot_name_is_refused() -> void:
	_dialog.open()
	check(not _dialog.save_slot("../evil"), "a path-like name is refused")
	check(not _dialog.save_slot("   "), "an empty name is refused")
	check_eq(_rows(), 0, "nothing was written")
	check(_status() != "", "the player is told why")


func test_load_restores_the_game_and_closes() -> void:
	_placement.place("smelter", Vector2i(8, 8))
	_game.money = 61
	_dialog.open()
	_dialog.save_slot("before")
	_game.get_machine_at(Vector2i(8, 8)).destroy()
	_game.money = 5
	check(_dialog.load_slot("before"), "loading works")
	check(_game.get_machine_at(Vector2i(8, 8)) is Smelter, "the machine is back")
	check_eq(_game.money, 61, "money is back")
	check(not _dialog.visible and not tree.paused, "the dialog closes and the game resumes")


func test_loading_a_missing_slot_reports_it() -> void:
	_dialog.open()
	check(not _dialog.load_slot("ghost"), "a missing slot fails")
	check(_dialog.visible and tree.paused, "the dialog stays open")
	check_eq(_status(), "The file does not exist.", "with a message")
	check(not _dialog.load_slot("../ghost"), "an escaping name fails")
	check_eq(_status(), "There is no such save.", "without touching any path")


func test_delete_removes_the_slot() -> void:
	_dialog.open()
	_dialog.save_slot("gone")
	_dialog.delete_slot("gone")
	check(not FileAccess.file_exists(TEST_DIR + "/gone.json"), "the file is deleted")
	check_eq(_rows(), 0, "and the row disappears")


func test_slot_rows_have_load_and_delete_buttons() -> void:
	_dialog.open()
	_dialog.save_slot("row")
	var row: HBoxContainer = (_dialog.get_node("%SlotList") as VBoxContainer).get_child(0)
	var buttons: Array[String] = []
	for child: Node in row.get_children():
		if child is Button:
			buttons.append((child as Button).text)
	check_eq(buttons, ["Load", "Delete"], "each slot has Load and Delete")
	_game.money = 3
	((row.get_child(1)) as Button).pressed.emit()
	check_eq(_game.money, 100, "the Load button loads the slot")


func test_export_then_import_a_file() -> void:
	_placement.place("assembler", Vector2i(9, 9))
	_dialog.open()
	check(_dialog.export_to(EXPORT_PATH), "export works")
	_game.get_machine_at(Vector2i(9, 9)).destroy()
	check(_dialog.import_from(EXPORT_PATH), "import works")
	check(_game.get_machine_at(Vector2i(9, 9)) is Assembler, "the imported machine is there")
	check(not _dialog.visible, "the dialog closes after an import")


func test_importing_junk_changes_nothing() -> void:
	_placement.place("assembler", Vector2i(9, 9))
	DirAccess.make_dir_recursive_absolute(TEST_DIR)
	var file: FileAccess = FileAccess.open(EXPORT_PATH, FileAccess.WRITE)
	file.store_string("{\"version\": 1}")
	file.close()
	_dialog.open()
	check(not _dialog.import_from(EXPORT_PATH), "an incomplete save is refused")
	check(_game.get_machine_at(Vector2i(9, 9)) is Assembler, "the game is untouched")
	check(_dialog.visible, "the dialog stays open")
	check(_status() != "" and not _status().contains("user:"), "a message without a path")


func test_menu_mode_hands_a_valid_save_over_without_pausing() -> void:
	_placement.place("assembler", Vector2i(9, 9))
	_dialog.open()
	_dialog.save_slot("menu")
	_dialog.close()
	_dialog.use_as_menu()
	check(not (_dialog.get_node("%NameRow") as Control).visible and not (_dialog.get_node("%ExportButton") as Control).visible, "no Save row and no Export in the menu")
	var picked: Array[Dictionary] = []
	var on_picked: Callable = func(data: Dictionary) -> void: picked.append(data)
	_dialog.save_picked.connect(on_picked)
	_dialog.open()
	check(not tree.paused, "opening it in the menu does not pause")
	_game.get_machine_at(Vector2i(9, 9)).destroy()
	check(_dialog.load_slot("menu"), "loading a slot works")
	_dialog.save_picked.disconnect(on_picked)
	check_eq(picked.size(), 1, "the save is handed over")
	check(_game.get_machine_at(Vector2i(9, 9)) == null, "the running game is not touched")
	check(not _dialog.visible, "the dialog closes")


func test_menu_mode_refuses_a_bad_file() -> void:
	DirAccess.make_dir_recursive_absolute(TEST_DIR)
	var file: FileAccess = FileAccess.open(EXPORT_PATH, FileAccess.WRITE)
	file.store_string("{\"version\": 1}")
	file.close()
	_dialog.use_as_menu()
	var picked: Array[int] = [0]
	var on_picked: Callable = func(_data: Dictionary) -> void: picked[0] += 1
	_dialog.save_picked.connect(on_picked)
	_dialog.open()
	check(not _dialog.import_from(EXPORT_PATH), "an incomplete save is refused")
	_dialog.save_picked.disconnect(on_picked)
	check_eq(picked[0], 0, "nothing is handed over")
	check(_dialog.visible and _status() != "", "the dialog stays open with a message")
