class_name BuildPage
extends VBoxContainer
## Bar page: current money and one button per buildable machine with its cost.
## Selecting a machine enters placement mode; Placement charges when a machine is really placed.

var _placement: Placement
var _buttons: Dictionary = {}

@onready var _money_label: Label = %MoneyLabel
@onready var _list: VBoxContainer = %List
@onready var _status_label: Label = %StatusLabel
@onready var _feedback_label: Label = %FeedbackLabel


func _ready() -> void:
	for type: String in MachineCatalog.BUILDABLE:
		var button: Button = Button.new()
		button.toggle_mode = true
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.text = "%s - %d" % [type.capitalize(), MachineCatalog.cost(type)]
		button.pressed.connect(_on_button_pressed.bind(type))
		_list.add_child(button)
		_buttons[type] = button
	EventBus.money_changed.connect(_on_money_changed)
	_refresh()


func _exit_tree() -> void:
	EventBus.money_changed.disconnect(_on_money_changed)


func setup(placement: Placement) -> void:
	_placement = placement
	_placement.selection_changed.connect(_on_selection_changed)
	_placement.placement_rejected.connect(_on_placement_rejected)
	_refresh()


func _refresh() -> void:
	_money_label.text = "Money: %d" % GameState.money
	var selected: String = _placement.selected if _placement != null else ""
	for type: String in _buttons:
		var button: Button = _buttons[type]
		button.disabled = GameState.money < MachineCatalog.cost(type)
		button.set_pressed_no_signal(type == selected)
	if selected == "":
		_status_label.text = "Pick a machine to build"
	else:
		_status_label.text = "Placing: %s (Esc to cancel)" % selected.capitalize()


func _on_button_pressed(type: String) -> void:
	if _placement == null:
		return
	_placement.select("" if _placement.selected == type else type)


func _on_money_changed(_amount: int) -> void:
	_refresh()


func _on_selection_changed(_type: String) -> void:
	_feedback_label.text = ""
	_refresh()


func _on_placement_rejected(reason: String) -> void:
	_feedback_label.text = reason
