class_name MainMenu
extends Control
## Start screen: Play (new game), Load Game (a slot or any save file), Chips (prepare the chip registry),
## Options (Settings) and Exit. A new game or a loaded save asks for the game scene with game_requested.

signal game_requested

const GAME_SCENE: String = "res://scenes/main.tscn"
## icon name (from Icons.BADGES) per button, reusing the same glyphs the Bar uses.
const BUTTON_ICONS: Dictionary = {
	"PlayButton": "state_normal",
	"LoadButton": "save",
	"ChipsButton": "ask",
	"OptionsButton": "settings",
	"ExitButton": "failed",
}

@onready var _play_button: Button = %PlayButton
@onready var _load_button: Button = %LoadButton
@onready var _chips_button: Button = %ChipsButton
@onready var _options_button: Button = %OptionsButton
@onready var _exit_button: Button = %ExitButton
@onready var _save_dialog: SaveDialog = %SaveDialog
@onready var _chip_manager: ChipManager = %ChipManager
@onready var _chip_page: ChipPage = %ChipPage
@onready var _settings_dialog: SettingsDialog = %SettingsDialog


func _ready() -> void:
	_apply_button_icons()
	_save_dialog.use_as_menu()
	_play_button.pressed.connect(start_game)
	_load_button.pressed.connect(_save_dialog.open)
	_chips_button.pressed.connect(_chip_manager.open)
	_options_button.pressed.connect(_settings_dialog.open)
	_exit_button.pressed.connect(get_tree().quit)
	_save_dialog.save_picked.connect(start_game)
	_chip_manager.chip_requested.connect(_chip_page.open)
	game_requested.connect(_go_to_game)
	_play_button.grab_focus()


## A new game, or the game of a save (already validated) when one is given.
func start_game(save: Dictionary = {}) -> void:
	SaveGame.pending = save
	GameState.reset()
	game_requested.emit()


## Only the running scene switches, so a menu instanced by a test never replaces the test runner.
func _go_to_game() -> void:
	if get_tree().current_scene == self:
		Sfx.stop_all()
		get_tree().change_scene_to_file(GAME_SCENE)


## Gives each button the Icons glyph it shares with the Bar, scaled crisply like Icons.apply_button() does.
func _apply_button_icons() -> void:
	for button_name: String in BUTTON_ICONS:
		var button: Button = get_node("%" + button_name)
		var image: Image = Icons.icon(BUTTON_ICONS[button_name]).get_image()
		image.resize(Icons.SIZE * Icons.SCALE, Icons.SIZE * Icons.SCALE, Image.INTERPOLATE_NEAREST)
		button.icon = ImageTexture.create_from_image(image)
