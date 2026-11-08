class_name PauseMenu
extends PanelContainer
## In-game pause menu: Resume, Restart, Main Menu. Pauses the game while open, like ChipPage. Restart and
## Main Menu only announce themselves: Main does the scene change.

signal restart_requested
signal main_menu_requested

## icon name (from Icons.BADGES) per button, the same glyphs the main menu and the Bar use.
const BUTTON_ICONS: Dictionary = {
	"ResumeButton": "state_normal",
	"RestartButton": "rotate",
	"MainMenuButton": "menu",
}

@onready var _resume_button: Button = %ResumeButton
@onready var _restart_button: Button = %RestartButton
@onready var _main_menu_button: Button = %MainMenuButton


func _ready() -> void:
	visible = false
	_apply_button_icons()
	for button: Button in [_resume_button, _restart_button, _main_menu_button]:
		SfxEvents.attach_click(button)
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


## Gives each button its Icons glyph, scaled crisply like the main menu does.
func _apply_button_icons() -> void:
	for button_name: String in BUTTON_ICONS:
		var button: Button = get_node("%" + button_name)
		var image: Image = Icons.icon(BUTTON_ICONS[button_name]).get_image()
		image.resize(Icons.SIZE * Icons.SCALE, Icons.SIZE * Icons.SCALE, Image.INTERPOLATE_NEAREST)
		button.icon = ImageTexture.create_from_image(image)
