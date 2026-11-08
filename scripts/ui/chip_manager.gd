class_name ChipManager
extends PanelContainer
## Popup listing every chip of the registry with a "new chip" button: where the main menu prepares chips.
## Picking a chip (or "new chip") is forwarded as chip_requested, for a ChipPage to edit.

## chip is null when the player asks for a new (blank) chip.
signal chip_requested(chip: ChipRessource)

@onready var _registry_page: ChipRegistryPage = %ChipRegistryPage
@onready var _close_button: Button = %CloseButton


func _ready() -> void:
	visible = false
	_registry_page.chip_requested.connect(chip_requested.emit)
	_close_button.pressed.connect(close)


func open() -> void:
	visible = true


func close() -> void:
	visible = false
