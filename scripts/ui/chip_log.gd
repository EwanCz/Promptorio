class_name ChipLog
extends PanelContainer
## Keeps the last chip log lines of every machine (EventBus.chip_log_added) and shows one machine's log.
## Shown as a timeline of icons (checking, action, no action, failure), oldest first; hovering an icon
## explains it in plain language (see _describe). The technical entries stay in the session log.

const MAX_LINES: int = 200
## What set_direction's 0..3 means, as the conveyor turns it: right, down, left, up.
const DIRECTIONS: Array[String] = ["right", "down", "left", "up"]

var _machine: Machine = null
var _asking: RegEx = RegEx.create_from_string("^asking chip (.*) \\([^()]*\\)$")
var _tool_call: RegEx = RegEx.create_from_string("^(\\w+)\\((\\{.*\\})\\)$")
## Machine instance id -> Array of {kind: icon name, text: hover explanation}.
var _lines: Dictionary = {}

@onready var _title: Label = %Title
@onready var _scroll: ScrollContainer = %Scroll
@onready var _timeline: HFlowContainer = %Timeline
@onready var _close_button: Button = %CloseButton


func _ready() -> void:
	visible = false
	EventBus.chip_log_added.connect(_on_log_added)
	_close_button.pressed.connect(close)


## The explanation of every entry of the machine, oldest first (what the icons say on hover).
func get_lines(machine: Node) -> Array[String]:
	var result: Array[String] = []
	for entry: Dictionary in _lines.get(machine.get_instance_id(), []):
		result.append(entry["text"])
	return result


## The icon names of the machine's entries, oldest first.
func get_kinds(machine: Node) -> Array[String]:
	var result: Array[String] = []
	for entry: Dictionary in _lines.get(machine.get_instance_id(), []):
		result.append(entry["kind"])
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
	for icon: Node in _timeline.get_children():
		_timeline.remove_child(icon)
		icon.queue_free()
	for entry: Dictionary in _lines.get(_machine.get_instance_id(), []):
		_timeline.add_child(Icons.rect(entry["kind"], entry["text"]))
	_scroll_to_end.call_deferred()


func _on_log_added(machine: Node, message: String) -> void:
	var id: int = machine.get_instance_id()
	var lines: Array = _lines.get(id, [])
	lines.append(_describe(message))
	if lines.size() > MAX_LINES:
		lines.pop_front()
	_lines[id] = lines
	if visible and machine == _machine:
		_refresh()


func _scroll_to_end() -> void:
	_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)


## {kind, text} for a technical message: the icon and its hover text. Tool results say what was asked
## ("set"), never that something changed, because the command may have been a no-op. Anything unknown is
## an "info" icon with the message as is.
func _describe(message: String) -> Dictionary:
	var asking: RegExMatch = _asking.search(message)
	if asking != null:
		return {"kind": "checking", "text": "Checking: %s" % asking.get_string(1)}
	if message == "no tool calls":
		return {"kind": "none", "text": "No action"}
	if message.begins_with("chip request failed"):
		return {"kind": "failed", "text": "Request failed"}
	if message.begins_with("ignored "):
		return {"kind": "failed", "text": "Action rejected"}
	var call: RegExMatch = _tool_call.search(message)
	if call != null:
		var json: JSON = JSON.new()
		var args: Variant = json.data if json.parse(call.get_string(2)) == OK else null
		return {"kind": "applied", "text": _tool_label(call.get_string(1), args)}
	return {"kind": "info", "text": message}


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
			return "Mining pace set to %d ticks per item" % int(values.get("ticks", 0))
		"set_mined_item":
			return "Mining resource set to %s" % str(values.get("item", "")).capitalize()
		"set_product":
			return "Product set to %s" % str(values.get("item", "")).capitalize()
		"discard_stock":
			return "Discard up to %d %s" % [int(values.get("count", 0)), str(values.get("item", "")).capitalize()]
		"set_stock_limit":
			return "Stock limit set to %d" % int(values.get("limit", 0))
		"set_direction":
			return "Direction set to %s" % DIRECTIONS[clampi(int(values.get("direction", 0)), 0, DIRECTIONS.size() - 1)]
	return "Action requested"
