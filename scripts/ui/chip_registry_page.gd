class_name ChipRegistryPage
extends VBoxContainer
## Bar page listing every chip of the ChipRegistry, with a "new chip" button on top.

## chip is null when the player asks for a new (blank) chip.
signal chip_requested(chip: ChipRessource)

@onready var _list: VBoxContainer = %List
@onready var _new_button: Button = %NewButton
@onready var _error_label: Label = %ErrorLabel


func _ready() -> void:
	_new_button.pressed.connect(_on_new_pressed)
	EventBus.chip_registered.connect(_on_registry_changed)
	EventBus.chip_removed.connect(_on_registry_changed)
	EventBus.chip_updated.connect(_on_registry_changed)
	EventBus.chip_storage_error.connect(_show_error)
	_show_error(ChipRegistry.save_error)
	_refresh()


func _refresh() -> void:
	for child: Node in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	for chip: ChipRessource in ChipRegistry.get_all():
		var button: Button = Button.new()
		button.text = chip.name
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.pressed.connect(chip_requested.emit.bind(chip))
		_list.add_child(button)


func _on_new_pressed() -> void:
	chip_requested.emit(null)


func _on_registry_changed(_chip: Resource) -> void:
	_refresh()


func _show_error(message: String) -> void:
	_error_label.text = message
	_error_label.visible = message != ""
