class_name BuildPage
extends VBoxContainer
## Build page: money, one button per buildable machine (cost shown, disabled when unaffordable),
## the selected type and the last placement refusal. Selecting only enters placement mode.

var _placement: Placement = null
var _buttons: Dictionary = {}

@onready var _money_label: Label = %MoneyLabel
@onready var _list: VBoxContainer = %List
@onready var _feedback_label: Label = %FeedbackLabel


func _ready() -> void:
	for type: String in Placement.COSTS:
		var button: Button = Button.new()
		button.toggle_mode = true
		button.pressed.connect(_on_button_pressed.bind(type))
		_list.add_child(button)
		_buttons[type] = button
	EventBus.money_changed.connect(_on_money_changed)
	_refresh()


func _exit_tree() -> void:
	EventBus.money_changed.disconnect(_on_money_changed)


## Connects the page to the placement flow it drives.
func setup(placement: Placement) -> void:
	_placement = placement
	placement.selection_changed.connect(_on_selection_changed)
	placement.placement_rejected.connect(_on_placement_rejected)
	_refresh()


func _refresh() -> void:
	_money_label.text = "Money: %d" % GameState.money
	for type: String in _buttons:
		var button: Button = _buttons[type]
		button.text = "%s - %d" % [type.capitalize(), Placement.COSTS[type]]
		button.disabled = GameState.money < Placement.COSTS[type]
		button.set_pressed_no_signal(_placement != null and _placement.selected == type)


func _on_button_pressed(type: String) -> void:
	if _placement == null:
		return
	_feedback_label.text = ""
	_placement.select("" if _placement.selected == type else type)


func _on_selection_changed(_type: String) -> void:
	_refresh()


func _on_money_changed(_amount: int) -> void:
	_refresh()


func _on_placement_rejected(reason: String) -> void:
	_feedback_label.text = reason
