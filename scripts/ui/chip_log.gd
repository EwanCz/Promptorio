class_name ChipLog
extends PanelContainer
## Keeps the last chip log lines of every machine (EventBus.chip_log_added) and shows one machine's log.
## Lines are shown in plain language (see _format); the technical entries stay in the session log.

const MAX_LINES: int = 200

var _machine: Machine = null
var _asking: RegEx = RegEx.create_from_string("^asking chip (.*) \\([^()]*\\)$")
var _tool_call: RegEx = RegEx.create_from_string("^(\\w+)\\((\\{.*\\})\\)$")
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
	lines.append(_format(message))
	if lines.size() > MAX_LINES:
		lines.pop_front()
	_lines[id] = lines
	if visible and machine == _machine:
		_refresh()


## Short readable text for the known technical messages; anything else is shown as is. Tool results say what
## was asked ("set"), never that something changed, because the command may have been a no-op.
func _format(message: String) -> String:
	var asking: RegExMatch = _asking.search(message)
	if asking != null:
		return "Checking: %s" % asking.get_string(1)
	if message == "no tool calls":
		return "No action"
	if message.begins_with("chip request failed"):
		return "Request failed"
	if message.begins_with("ignored "):
		return "Action rejected"
	var call: RegExMatch = _tool_call.search(message)
	if call != null:
		return _tool_label(call.get_string(1), JSON.parse_string(call.get_string(2)))
	return message


func _tool_label(tool_name: String, args: Variant) -> String:
	var values: Dictionary = args if typeof(args) == TYPE_DICTIONARY else {}
	var on: bool = values.get("on", false) == true
	match tool_name:
		"set_enabled":
			return "Machine set to running" if on else "Machine set to paused"
		"set_cooling":
			return "Cooling set on" if on else "Cooling set off"
		"set_emergency_stop":
			return "Emergency stop set" if on else "Emergency stop release requested"
		"set_accepting":
			return "Accepting items set on" if on else "Accepting items set off"
		"set_mine_ticks":
			return "Mining pace set to %d ticks per ore" % int(values.get("ticks", 0))
		"set_stock_limit":
			return "Stock limit set to %d" % int(values.get("limit", 0))
		"set_direction":
			return "Direction set"
	return "Action requested"
