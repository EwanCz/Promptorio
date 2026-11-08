class_name MachineTooltip
extends PanelContainer
## Machine information panel in the bottom half of the Bar. It shows the machine selected through
## EventBus.machine_selected, and a hint again once that machine is selected a second time, an empty
## cell is clicked or the machine goes away.

signal log_requested(machine: Machine)

const NAME_MIN_WIDTH: int = 80
## Resource art is 32 px: shown as it is.
const ITEM_ICON_PX: int = 32
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
@onready var _op_row: HFlowContainer = %OpRow
@onready var _progress: ProgressBar = %Progress
@onready var _stock_row: HFlowContainer = %StockRow
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
	_destroy_button.text = "X"
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


## Removes the machine shown in the tooltip, the same as the Destroy button (keys X / Delete). False if none
## is open or it cannot be removed (the Collector).
func destroy_machine() -> bool:
	if _machine == null or not is_instance_valid(_machine) or not _machine.is_removable():
		return false
	_on_destroy_pressed()
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
	_refresh_operation()
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


## What the machine is doing, as icons and numbers: the recipe or mined resource, a progress bar for the
## current job, the stock, and a blocked icon. Rows are rebuilt only when their content changes, so a hover
## in progress is not lost; the bar moves every tick.
func _refresh_operation() -> void:
	var catalog: ItemCatalog = ItemCatalog.shared()
	var op: Array[Dictionary] = []
	var stock: Array[Dictionary] = []
	if _machine is CraftMachine:
		var craft: CraftMachine = _machine as CraftMachine
		if craft is Assembler:
			var fast: bool = (craft as Assembler).mode == Assembler.MODE_FAST
			op.append(_icon_entry("mode_fast" if fast else "mode_normal", "", "Fast mode: extra inputs, shorter time" if fast else "Normal mode"))
		var product: ItemData = craft.get_product()
		if product == null:
			op.append(_icon_entry("warn", "", "No product"))
		else:
			var needs: Dictionary = craft.get_effective_inputs()
			for id: String in needs:
				op.append(_item_entry(id, "x%d" % int(needs[id]) if int(needs[id]) > 1 else "", "Needs %s"))
			op.append(_icon_entry("dir_right", "", "Makes"))
			op.append(_item_entry(product.id, "", "Makes %s"))
		for id: String in craft.stock:
			if int(craft.stock[id]) > 0:
				stock.append(_item_entry(id, str(int(craft.stock[id])), "In stock: %s"))
	elif _machine is Miner:
		var miner: Miner = _machine as Miner
		op.append(_item_entry(miner.item, "", "Mines %s"))
		op.append(_icon_entry("timer", str(miner.get_mining_ticks()), "Ticks per unit"))
		if miner.mode == Miner.Mode.PROSPECTING:
			op.append(_icon_entry("prospecting", str(miner.mode_ticks_left), "Prospecting: %d ticks left" % miner.mode_ticks_left))
		elif miner.mode == Miner.Mode.BOOST:
			op.append(_icon_entry("boost", str(miner.mode_ticks_left), "Boosted mining: %d ticks left" % miner.mode_ticks_left))
	elif _machine is Conveyor:
		var belt: Conveyor = _machine as Conveyor
		op.append(_icon_entry(Icons.direction(belt.facing), "", "Facing %s" % _direction_name(belt.facing)))
		if belt.held != "":
			op.append(_item_entry(belt.held, "", "Carrying %s"))
	elif _machine is Collector:
		var collector: Collector = _machine as Collector
		op.append(_icon_entry("money", str(collector.earned), "Money earned"))
		op.append(_icon_entry("applied", str(collector.sold), "Items sold"))
		if not collector.accepting:
			op.append(_icon_entry("blocked", "", "Not accepting items"))
	if _machine.is_blocked():
		op.append(_icon_entry("blocked", "", "Output blocked: nothing takes it"))
	elif _machine.shows_production_feedback() and _machine.get_production_state() == Machine.ProductionState.PRODUCING:
		var rate: float = _machine.get_production_rate()
		op.append(_icon_entry("state_normal", "%.1f/min" % rate, "Producing %.1f items per minute" % rate))
	_fill_row(_op_row, op, catalog)
	_fill_row(_stock_row, stock, catalog)
	var progress: float = _machine.get_progress()
	_progress.visible = progress >= 0.0
	_progress.value = maxf(progress, 0.0)
	_progress.tooltip_text = "Progress"


func _direction_name(facing: Vector2i) -> String:
	var index: int = [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP].find(facing)
	return ChipLog.DIRECTIONS[maxi(index, 0)]


## An entry of a row: a resource icon (hint is a format with the resource's name) or a badge icon.
func _item_entry(id: String, text: String, hint: String) -> Dictionary:
	var item: ItemData = ItemCatalog.shared().get_item(id)
	var name: String = id if item == null else item.display_name
	return {"item": id, "text": text, "hint": hint % name}


func _icon_entry(icon_name: String, text: String, hint: String) -> Dictionary:
	return {"icon": icon_name, "text": text, "hint": hint}


func _fill_row(row: HFlowContainer, entries: Array[Dictionary], catalog: ItemCatalog) -> void:
	row.visible = not entries.is_empty()
	var signature: String = JSON.stringify(entries)
	if row.get_meta("signature", "") == signature:
		return
	row.set_meta("signature", signature)
	for child: Node in row.get_children():
		row.remove_child(child)
		child.queue_free()
	for entry: Dictionary in entries:
		var cell: HBoxContainer = HBoxContainer.new()
		cell.add_theme_constant_override("separation", 2)
		var picture: TextureRect
		if entry.has("item"):
			var item: ItemData = catalog.get_item(entry["item"])
			picture = TextureRect.new()
			picture.texture = null if item == null else item.icon
			picture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			picture.custom_minimum_size = Vector2(ITEM_ICON_PX, ITEM_ICON_PX)
			picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			picture.tooltip_text = entry["hint"]
		else:
			picture = Icons.rect(entry["icon"], entry["hint"])
		cell.add_child(picture)
		if entry["text"] != "":
			var number: Label = Label.new()
			number.text = entry["text"]
			number.tooltip_text = entry["hint"]
			number.mouse_filter = Control.MOUSE_FILTER_STOP
			cell.add_child(number)
		row.add_child(cell)


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
	var refund: int = Placement.refund_for(machine.machine_type)
	close()
	if machine.destroy():
		GameState.add_money(refund)


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
