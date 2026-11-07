extends Node
## Root script: wires the UI pieces together and forwards placement actions.

@onready var _bar: BarPanel = %Bar
@onready var _grid: GridMap2D = %GridMap2D
@onready var _build_page: BuildPage = %BuildPage
@onready var _registry_page: ChipRegistryPage = %ChipRegistryPage
@onready var _chip_page: ChipPage = %ChipPage
@onready var _tooltip: MachineTooltip = %MachineTooltip
@onready var _chip_log: ChipLog = %ChipLog
@onready var _settings_dialog: SettingsDialog = %SettingsDialog
@onready var _placement: Placement = get_node("Game/FactoryView/SubViewport/World/Placement") as Placement


func _ready() -> void:
	_grid.cell_clicked.connect(_on_cell_clicked)
	_build_page.setup(_placement)
	_registry_page.chip_requested.connect(_chip_page.open)
	_tooltip.log_requested.connect(_chip_log.show_machine)
	_bar.settings_requested.connect(_settings_dialog.open)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_bar"):
		_bar.visible = not _bar.visible
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("rotate_placement") and _placement.selected == "" and _tooltip.rotate_machine():
		get_viewport().set_input_as_handled()
	elif _placement.handle_input(event):
		get_viewport().set_input_as_handled()


func _on_cell_clicked(cell: Vector2i) -> void:
	EventBus.machine_selected.emit(GameState.get_machine_at(cell))
