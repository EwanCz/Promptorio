class_name MachineTooltip
extends PanelContainer
## Machine information panel in the bottom half of the Bar. It shows the machine selected through
## EventBus.machine_selected, and a hint again once that machine is selected a second time, an empty
## cell is clicked or the machine goes away.

signal log_requested(machine: Machine)

const NAME_MIN_WIDTH: int = 80
const MAX_TIMEOUT: int = 100000
const STATE_HINTS: Dictionary = {
	"normal": "Running normally",
	"down": "Down: this machine is out of service",
	"overheating": "Overheating: it explodes if it keeps heating up",
	"paused": "Paused: switched off, it does nothing until it is switched on",
}

var _machine: Machine = null

@onready var _hint_label: Label = %HintLabel
@onready var _scroll: ScrollContainer = %Scroll
@onready var _id_label: Label = %IdLabel
@onready var _status_icon: TextureRect = %StatusIcon
@onready var _action_label: Label = %ActionLabel
@onready var _rotate_button: Button = %RotateButton
@onready var _destroy_button: Button = %DestroyButton
@onready var _heat_row: HBoxContainer = %HeatRow
@onready var _thermo_icon: TextureRect = %ThermoIcon
@onready var _temp_label: Label = %TempLabel
@onready var _cool_icon: TextureRect = %CoolIcon
@onready var _chips_list: VBoxContainer = %ChipsList
@onready var _picker: OptionButton = %ChipPicker
@onready var _add_button: Button = %AddButton
@onready var _log_button: Button = %LogButton


func _ready() -> void:
	EventBus.machine_selected.connect(_on_machine_selected)
	EventBus.tick_fired.connect(_on_tick)
	EventBus.chip_registered.connect(_on_registry_changed)
	EventBus.chip_removed.connect(_on_registry_changed)
	EventBus.chip_updated.connect(_on_registry_changed)
	EventBus.machine_unregistered.connect(_on_machine_unregistered)
	Icons.apply_button(_rotate_button, "rotate", "Rotate")
	Icons.apply_button(_destroy_button, "destroy", "Destroy this machine")
	Icons.apply_button(_add_button, "add", "Add the chosen chip")
	Icons.apply_button(_log_button, "log", "Chip log")
	_picker.tooltip_text = "Chip to add"
	_rotate_button.pressed.connect(_on_rotate_pressed)
	_destroy_button.pressed.connect(_on_destroy_pressed)
	_add_button.pressed.connect(_on_add_pressed)
	_log_button.pressed.connect(_on_log_pressed)


func open(machine: Machine) -> void:
	_machine = machine
	_id_label.text = "%s #%d" % [machine.machine_type.capitalize(), machine.machine_id]
	_rotate_button.visible = machine.can_rotate()
	_destroy_button.visible = machine.is_removable()
	_show_details(true)
	_refresh_status()
	_refresh_chips()


func close() -> void:
	_machine = null
	_show_details(false)


## True while a machine's details are shown.
func is_open() -> bool:
	return _machine != null


## Turns the machine shown in the tooltip, the same as the Rotate button. False if none is open
## or it has no facing.
func rotate_machine() -> bool:
	if _machine == null or not is_instance_valid(_machine) or not _machine.can_rotate():
		return false
	_on_rotate_pressed()
	return true


func _show_details(shown: bool) -> void:
	_scroll.visible = shown
	_hint_label.visible = not shown


func _refresh_status() -> void:
	var status: String = Machine.Status.keys()[_machine.status].to_lower()
	var paused: bool = not _machine.enabled and _machine.honors_enabled()
	var shown: String = status
	if status == "normal" and paused:
		shown = "paused"
	var hint: String = STATE_HINTS[shown]
	if status == "overheating" and paused:
		hint += " (and paused)"
	Icons.apply(_status_icon, "state_" + shown, hint)
	_action_label.text = _machine.get_action_text()
	_action_label.visible = _action_label.text != ""
	var state: Dictionary = _machine.get_state()
	_heat_row.visible = state.has("temperature")
	if _heat_row.visible:
		var heat: float = float(state["temperature"])
		var fraction: float = inverse_lerp(Smelter.AMBIENT, Smelter.EXPLODE_AT, heat)
		_thermo_icon.texture = Icons.thermometer(fraction)
		_thermo_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_thermo_icon.custom_minimum_size = Vector2(Icons.SIZE * Icons.SCALE, Icons.SIZE * Icons.SCALE)
		_thermo_icon.tooltip_text = "Temperature (explodes at %d)" % int(Smelter.EXPLODE_AT)
		_thermo_icon.mouse_filter = Control.MOUSE_FILTER_STOP
		_temp_label.text = "%d°" % int(heat)
		var cooling: bool = state.get("cooling", false)
		Icons.apply(_cool_icon, "cooling_on" if cooling else "cooling_off", "Cooling on" if cooling else "Cooling off")


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


## One chip: its name (hover for the prompt), the timer in ticks, ask now and remove. Icons carry the
## meaning; each has a hover description.
func _make_row(component: ChipComponent) -> Control:
	var box: VBoxContainer = VBoxContainer.new()
	var row: HFlowContainer = HFlowContainer.new()
	row.name = "Main"
	box.add_child(row)
	var chip_name: Label = Label.new()
	chip_name.name = "Name"
	chip_name.text = component.chip.name
	chip_name.tooltip_text = component.chip.prompt
	chip_name.mouse_filter = Control.MOUSE_FILTER_STOP
	chip_name.custom_minimum_size.x = NAME_MIN_WIDTH
	chip_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chip_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(chip_name)
	var timeout: SpinBox = SpinBox.new()
	timeout.name = "Timeout"
	timeout.min_value = 1
	timeout.max_value = MAX_TIMEOUT
	timeout.value = component.timeout
	timeout.tooltip_text = "Ticks between automatic checks"
	timeout.value_changed.connect(_on_timeout_changed.bind(component))
	row.add_child(Icons.rect("timer", "Ticks between automatic checks"))
	row.add_child(timeout)
	var ask: Button = Icons.button("ask", "Ask the chip now")
	ask.name = "Ask"
	ask.pressed.connect(_on_ask_pressed.bind(component))
	row.add_child(ask)
	var remove: Button = Icons.button("remove", "Remove this chip")
	remove.name = "Remove"
	remove.pressed.connect(_on_remove_pressed.bind(component))
	row.add_child(remove)
	return box


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


func _on_timeout_changed(value: float, component: ChipComponent) -> void:
	component.set_timeout(int(value))


func _on_log_pressed() -> void:
	if _machine != null:
		log_requested.emit(_machine)
