class_name ChipPage
extends PanelContainer
## Popup to edit one chip (name, description, prompt). Pauses the game while open.

const BLANK_NAME: String = "Blank"

## null means a new chip that is not in the registry until saved.
var _chip: ChipRessource = null

@onready var _vbox: VBoxContainer = %VBox
@onready var _name_edit: LineEdit = %NameEdit
@onready var _description_edit: TextEdit = %DescriptionEdit
@onready var _prompt_edit: TextEdit = %PromptEdit
@onready var _error_label: Label = %ErrorLabel
@onready var _save_button: Button = %SaveButton
@onready var _remove_button: Button = %RemoveButton
@onready var _close_button: Button = %CloseButton
## Shown only for a chip an Orchestrator created (ChipRessource.created_by != 0): saving here claims it
## (ChipRegistry.update() always clears created_by), so the player sees why before they do.
@onready var _owner_badge: TextureRect = Icons.rect("settings")


func _ready() -> void:
	_save_button.pressed.connect(_on_save_pressed)
	_remove_button.pressed.connect(_on_remove_pressed)
	_close_button.pressed.connect(close)
	_owner_badge.visible = false
	_vbox.add_child(_owner_badge)
	_vbox.move_child(_owner_badge, 1)


## Pass null to start from a blank chip.
func open(chip: ChipRessource) -> void:
	_chip = chip
	if chip == null:
		_fill(BLANK_NAME, "", "")
	else:
		_fill(chip.name, chip.description, chip.prompt)
	_remove_button.disabled = chip == null
	_error_label.text = ""
	_owner_badge.visible = chip != null and chip.created_by != 0
	if _owner_badge.visible:
		_owner_badge.tooltip_text = "Created by Orchestrator #%d. Saving claims this chip: it will no longer revise it." % chip.created_by
		_owner_badge.mouse_filter = Control.MOUSE_FILTER_STOP
	visible = true
	get_tree().paused = true


func close() -> void:
	visible = false
	get_tree().paused = false


func _fill(chip_name: String, desc: String, prompt: String) -> void:
	_name_edit.text = chip_name
	_description_edit.text = desc
	_prompt_edit.text = prompt


func _on_save_pressed() -> void:
	var chip_name: String = _name_edit.text.strip_edges()
	var saved: bool = false
	if _chip == null:
		saved = ChipRegistry.add(chip_name, _prompt_edit.text, _description_edit.text) != null
	else:
		saved = ChipRegistry.update(_chip.id, chip_name, _description_edit.text, _prompt_edit.text)
	if not saved:
		_error_label.text = "The name is empty or already used."
		return
	close()


func _on_remove_pressed() -> void:
	if _chip != null:
		ChipRegistry.remove(_chip.id)
	close()
