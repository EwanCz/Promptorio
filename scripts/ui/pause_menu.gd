class_name PauseMenu
extends PanelContainer
## In-game pause menu: Resume, Restart, Main Menu. Pauses the game while open, like ChipPage. Restart and
## Main Menu only announce themselves: Main does the scene change.

signal restart_requested
signal main_menu_requested

@onready var _resume_button: PixelButton = %ResumeButton
@onready var _restart_button: PixelButton = %RestartButton
@onready var _main_menu_button: PixelButton = %MainMenuButton


func _ready() -> void:
	visible = false
	_resume_button.pressed.connect(close)
	_restart_button.pressed.connect(_on_restart_pressed)
	_main_menu_button.pressed.connect(_on_main_menu_pressed)


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("cancel_placement"):
		close()
		get_viewport().set_input_as_handled()


func open() -> void:
	visible = true
	get_tree().paused = true
	_resume_button.grab_focus()


func close() -> void:
	visible = false
	get_tree().paused = false


func _on_restart_pressed() -> void:
	close()
	restart_requested.emit()


func _on_main_menu_pressed() -> void:
	close()
	main_menu_requested.emit()
