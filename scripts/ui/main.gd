extends Node
## Root script: wires the UI pieces together and forwards placement actions.

const MAIN_MENU_SCENE: String = "res://scenes/menu/main_menu.tscn"

@onready var _bar: BarPanel = %Bar
@onready var _grid: GridMap2D = %GridMap2D
@onready var _build_page: BuildPage = %BuildPage
@onready var _registry_page: ChipRegistryPage = %ChipRegistryPage
@onready var _chip_page: ChipPage = %ChipPage
@onready var _tooltip: MachineTooltip = %MachineTooltip
@onready var _chip_log: ChipLog = %ChipLog
@onready var _settings_dialog: SettingsDialog = %SettingsDialog
@onready var _save_dialog: SaveDialog = %SaveDialog
@onready var _pause_menu: PauseMenu = %PauseMenu
@onready var _placement: Placement = get_node("Game/FactoryView/SubViewport/World/Placement") as Placement


func _ready() -> void:
	_grid.cell_clicked.connect(_on_cell_clicked)
	_build_page.setup(_placement)
	_registry_page.chip_requested.connect(_chip_page.open)
	_tooltip.log_requested.connect(_chip_log.show_machine)
	_save_dialog.setup(_placement)
	_bar.saves_requested.connect(_save_dialog.open)
	_bar.settings_requested.connect(_settings_dialog.open)
	_bar.menu_requested.connect(_pause_menu.open)
	_pause_menu.restart_requested.connect(_on_restart_requested)
	_pause_menu.main_menu_requested.connect(_on_main_menu_requested)
	_restore_pending_save()
	EventBus.settings_changed.connect(_check_key)
	_check_key()
	_start_session_log()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_bar"):
		_bar.visible = not _bar.visible
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("cancel_placement") and _placement.selected == "":
		_pause_menu.open()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("rotate_placement"):
		# One key turns both the selected machine and the next placement.
		_tooltip.rotate_machine()
		_placement.rotate_facing()
		get_viewport().set_input_as_handled()
	elif _placement.handle_input(event):
		get_viewport().set_input_as_handled()


func _on_cell_clicked(cell: Vector2i) -> void:
	EventBus.machine_selected.emit(GameState.get_machine_at(cell))


## A save picked in the main menu is restored here, once the world (and its Collector) exists. It was
## validated there; restore() checks it again and leaves a fresh game if it still fails.
func _restore_pending_save() -> void:
	var pending: Dictionary = SaveGame.take_pending()
	if not pending.is_empty():
		SaveGame.restore(_placement, pending)


## Only the running scene switches, so a Main instanced by a test is not replaced.
func _on_restart_requested() -> void:
	GameState.reset()
	if get_tree().current_scene == self:
		get_tree().reload_current_scene()


func _on_main_menu_requested() -> void:
	GameState.reset()
	if get_tree().current_scene == self:
		get_tree().change_scene_to_file(MAIN_MENU_SCENE)


## Verifies the key for the Bar's status. Headless runs (tests) never touch the network.
func _check_key() -> void:
	if DisplayServer.get_name() != "headless":
		LLMManager.check_key()


## Headless runs (tests) write no session file.
func _start_session_log() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var session_log: SessionLog = SessionLog.new()
	add_child(session_log)
	session_log.start()
