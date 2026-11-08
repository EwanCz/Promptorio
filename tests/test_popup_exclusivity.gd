extends "res://tests/test_case.gd"
## Only one popup of the UI layer (Resources, Tools, Settings, Saves, the pause menu...) is ever shown
## at once: opening one closes whichever other was already open. Regression test for a bug where a
## popup opened on top of another could not be closed (the top one's Close button stayed unresponsive
## while the bottom one kept the game paused).

var _main: Node
var _save_dialog: SaveDialog
var _settings_dialog: SettingsDialog
var _resources_page: ResourcesPage
var _tools_page: ToolsPage
var _pause_menu: PauseMenu


func before_each() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(_main)
	_save_dialog = _main.get_node("%SaveDialog")
	_settings_dialog = _main.get_node("%SettingsDialog")
	_resources_page = _main.get_node("%ResourcesPage")
	_tools_page = _main.get_node("%ToolsPage")
	_pause_menu = _main.get_node("%PauseMenu")


func after_each() -> void:
	tree.paused = false
	_main.free()


func test_opening_settings_over_an_open_save_dialog_closes_it() -> void:
	(_main.get_node("%SavesButton") as Button).pressed.emit()
	check(_save_dialog.visible and tree.paused, "Saves opens and pauses")
	(_main.get_node("%SettingsButton") as Button).pressed.emit()
	check(_settings_dialog.visible, "Settings opens")
	check(not _save_dialog.visible, "and the Save dialog closes")
	check(not tree.paused, "Settings does not pause, so the game resumes")
	(_settings_dialog.get_node("%CloseButton") as Button).pressed.emit()
	check(not _settings_dialog.visible, "Settings still closes normally")


func test_opening_resources_over_an_open_settings_dialog_closes_it() -> void:
	(_main.get_node("%SettingsButton") as Button).pressed.emit()
	check(_settings_dialog.visible, "Settings opens")
	var settings: Node = autoload("Settings")
	var original_volume: float = settings.master_volume
	(_settings_dialog.get_node("%MasterSlider") as HSlider).value = 0.12
	(_main.get_node("%ResourcesButton") as Button).pressed.emit()
	check(_resources_page.visible, "Resources opens")
	check(not _settings_dialog.visible, "and Settings closes")
	check_eq(settings.master_volume, original_volume, "unsaved audio changes are reverted")
	settings.master_volume = original_volume
	settings.apply_audio()


func test_closing_menu_chip_editor_returns_to_chip_list() -> void:
	var menu: Node = load("res://scenes/menu/main_menu.tscn").instantiate()
	tree.root.add_child(menu)
	(menu.get_node("%ChipsButton") as Button).pressed.emit()
	var manager: ChipManager = menu.get_node("%ChipManager")
	var page: ChipPage = menu.get_node("%ChipPage")
	manager.chip_requested.emit(null)
	check(page.visible and not manager.visible, "the editor replaces the chip list")
	page.close()
	check(manager.visible and not page.visible, "closing the editor returns to the chip list")
	menu.free()


func test_opening_tools_over_an_open_resources_page_closes_it() -> void:
	(_main.get_node("%ResourcesButton") as Button).pressed.emit()
	check(_resources_page.visible, "Resources opens")
	(_main.get_node("%ToolsButton") as Button).pressed.emit()
	check(_tools_page.visible, "Tools opens")
	check(not _resources_page.visible, "and Resources closes")


func test_opening_the_pause_menu_closes_an_unrelated_open_popup() -> void:
	(_main.get_node("%ToolsButton") as Button).pressed.emit()
	check(_tools_page.visible, "Tools opens")
	(_main.get_node("%MenuButton") as Button).pressed.emit()
	check(_pause_menu.visible and tree.paused, "the pause menu opens and pauses")
	check(not _tools_page.visible, "and Tools closes")


func test_opening_save_over_the_open_pause_menu_closes_it() -> void:
	(_main.get_node("%MenuButton") as Button).pressed.emit()
	check(_pause_menu.visible and tree.paused, "the pause menu opens and pauses")
	(_main.get_node("%SavesButton") as Button).pressed.emit()
	check(_save_dialog.visible, "Saves opens")
	check(not _pause_menu.visible, "and the pause menu closes")
	check(tree.paused, "the game stays paused: Saves pauses too")
