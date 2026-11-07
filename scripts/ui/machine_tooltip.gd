class_name MachineTooltip
extends PanelContainer
## Opens when a machine is selected (EventBus.machine_selected), closes when it is selected again
## or when an empty cell is clicked.

signal log_requested(machine: Machine)

const PROMPT_PREVIEW: int = 40
const MAX_TIMEOUT: int = 100000
const MAX_LIMIT: int = 100000
const NO_WATCH: String = "(never)"

var _machine: Machine = null

@onready var _id_label: Label = %IdLabel
@onready var _type_label: Label = %TypeLabel
@onready var _status_label: Label = %StatusLabel
@onready var _action_label: Label = %ActionLabel
@onready var _rotate_button: Button = %RotateButton
@onready var _destroy_button: Button = %DestroyButton
@onready var _chips_list: VBoxContainer = %ChipsList
@onready var _picker: OptionButton = %ChipPicker
@onready var _add_button: Button = %AddButton
@onready var _log_button: Button = %LogButton


func _ready() -> void:
	visible = false
	EventBus.machine_selected.connect(_on_machine_selected)
	EventBus.tick_fired.connect(_on_tick)
	EventBus.chip_registered.connect(_on_registry_changed)
	EventBus.chip_removed.connect(_on_registry_changed)
	EventBus.chip_updated.connect(_on_registry_changed)
	EventBus.machine_unregistered.connect(_on_machine_unregistered)
	_rotate_button.pressed.connect(_on_rotate_pressed)
	_destroy_button.pressed.connect(_on_destroy_pressed)
	_add_button.pressed.connect(_on_add_pressed)
	_log_button.pressed.connect(_on_log_pressed)


func open(machine: Machine) -> void:
	_machine = machine
	_id_label.text = "Machine #%d" % machine.machine_id
	_type_label.text = "Type: %s" % machine.machine_type
	_rotate_button.visible = machine.can_rotate()
	_destroy_button.visible = machine.is_removable()
	visible = true
	_refresh_status()
	_refresh_chips()


func close() -> void:
	_machine = null
	visible = false


## Turns the machine shown in the tooltip, the same as the Rotate button. False if none is open
## or it has no facing.
func rotate_machine() -> bool:
	if _machine == null or not is_instance_valid(_machine) or not _machine.can_rotate():
		return false
	_on_rotate_pressed()
	return true


func _refresh_status() -> void:
	_status_label.text = "State: %s" % Machine.Status.keys()[_machine.status].to_lower()
	_action_label.text = _machine.get_action_text()
	_action_label.visible = _action_label.text != ""


func _refresh_chips() -> void:
	for row: Node in _chips_list.get_children():
		_chips_list.remove_child(row)
		row.queue_free()
	for component: ChipComponent in _machine.chips:
		_chips_list.add_child(_make_row(component))
	_picker.clear()
	for chip: ChipRessource in ChipRegistry.get_all():
		if _machine.get_chip(chip.id) == null:
			_picker.add_item(chip.name, chip.id)
	_add_button.disabled = _picker.item_count == 0


func _make_row(component: ChipComponent) -> Control:
	var box: VBoxContainer = VBoxContainer.new()
	var row: HBoxContainer = HBoxContainer.new()
	box.add_child(row)
	var label: Label = Label.new()
	label.text = "%s: %s" % [component.chip.name, component.chip.prompt.left(PROMPT_PREVIEW)]
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.clip_text = true
	row.add_child(label)
	var timeout: SpinBox = SpinBox.new()
	timeout.min_value = 1
	timeout.max_value = MAX_TIMEOUT
	timeout.suffix = "ticks"
	timeout.value = component.timeout
	timeout.value_changed.connect(_on_timeout_changed.bind(component))
	row.add_child(timeout)
	var remove: Button = Button.new()
	remove.text = "X"
	remove.pressed.connect(_on_remove_pressed.bind(component))
	row.add_child(remove)
	var ask: Button = Button.new()
	ask.text = "Ask now"
	ask.pressed.connect(_on_ask_pressed.bind(component))
	row.add_child(ask)
	box.add_child(_make_watch_row(component))
	return box


## Threshold trigger: pick a numeric state value and the limit it must rise above.
func _make_watch_row(component: ChipComponent) -> Control:
	var row: HBoxContainer = HBoxContainer.new()
	var title: Label = Label.new()
	title.text = "Ask when"
	row.add_child(title)
	var keys: OptionButton = OptionButton.new()
	keys.add_item(NO_WATCH, 0)
	var state: Dictionary = _machine.get_state()
	for key: String in state:
		if state[key] is int or state[key] is float:
			keys.add_item(key)
			if key == component.threshold_key:
				keys.select(keys.item_count - 1)
	keys.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(keys)
	var limit: SpinBox = SpinBox.new()
	limit.min_value = -MAX_LIMIT
	limit.max_value = MAX_LIMIT
	limit.prefix = ">"
	limit.value = component.threshold
	row.add_child(limit)
	keys.item_selected.connect(_on_watch_changed.bind(keys, limit, component))
	limit.value_changed.connect(_on_limit_changed.bind(keys, limit, component))
	return row


func _on_machine_selected(machine: Node) -> void:
	if machine == null or machine == _machine:
		close()
	elif machine is Machine:
		open(machine)


func _on_tick(_tick: int) -> void:
	if _machine == null:
		return
	if not is_instance_valid(_machine):
		close()
		return
	_refresh_status()


func _on_machine_unregistered(machine: Node, _cell: Vector2i) -> void:
	if machine == _machine:
		close()


func _on_rotate_pressed() -> void:
	_machine.rotate_facing()
	_refresh_status()


func _on_destroy_pressed() -> void:
	var machine: Machine = _machine
	close()
	machine.destroy()


func _on_registry_changed(_chip: Resource) -> void:
	if _machine != null and is_instance_valid(_machine):
		_refresh_chips()


func _on_add_pressed() -> void:
	if _machine.attach_chip(_picker.get_selected_id()) != null:
		_refresh_chips()


func _on_remove_pressed(component: ChipComponent) -> void:
	_machine.detach_chip(component.chip.id)
	_refresh_chips()


func _on_ask_pressed(component: ChipComponent) -> void:
	component.call_llm("manual")


func _on_watch_changed(_index: int, keys: OptionButton, limit: SpinBox, component: ChipComponent) -> void:
	_apply_watch(keys, limit, component)


func _on_limit_changed(_value: float, keys: OptionButton, limit: SpinBox, component: ChipComponent) -> void:
	_apply_watch(keys, limit, component)


func _apply_watch(keys: OptionButton, limit: SpinBox, component: ChipComponent) -> void:
	var key: String = "" if keys.selected == 0 else keys.get_item_text(keys.selected)
	component.set_threshold(key, limit.value)


func _on_timeout_changed(value: float, component: ChipComponent) -> void:
	component.set_timeout(int(value))


func _on_log_pressed() -> void:
	if _machine != null:
		log_requested.emit(_machine)
