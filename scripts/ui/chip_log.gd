class_name ChipLog
extends PanelContainer
## Keeps the last chip log lines of every machine (EventBus.chip_log_added) and shows one machine's log.

const MAX_LINES: int = 200

var _machine: Machine = null
## Machine instance id -> Array of lines.
var _lines: Dictionary = {}

@onready var _title: Label = %Title
@onready var _text: RichTextLabel = %Text
@onready var _close_button: Button = %CloseButton


func _ready() -> void:
	visible = false
	EventBus.chip_log_added.connect(_on_log_added)
	_close_button.pressed.connect(close)


func get_lines(machine: Node) -> Array[String]:
	var result: Array[String] = []
	for line: String in _lines.get(machine.get_instance_id(), []):
		result.append(line)
	return result


func show_machine(machine: Machine) -> void:
	_machine = machine
	_title.text = "Log of machine #%d (%s)" % [machine.machine_id, machine.machine_type]
	visible = true
	_refresh()


func close() -> void:
	_machine = null
	visible = false


func _refresh() -> void:
	_text.text = "\n".join(get_lines(_machine))


func _on_log_added(machine: Node, message: String) -> void:
	var id: int = machine.get_instance_id()
	var lines: Array = _lines.get(id, [])
	lines.append(message)
	if lines.size() > MAX_LINES:
		lines.pop_front()
	_lines[id] = lines
	if visible and machine == _machine:
		_refresh()
