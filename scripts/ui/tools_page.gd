class_name ToolsPage
extends PanelContainer
## Popup listing, for each type of machine, every tool a chip may call on it: the name with its arguments
## and what it does. Read from the machines' own get_tool_schemas(), so a new tool shows up by itself.

const WIDTH: int = 560

@onready var _list: VBoxContainer = %List
@onready var _close_button: Button = %CloseButton


func _ready() -> void:
	visible = false
	_close_button.pressed.connect(close)
	for type: String in Placement.SCENES:
		_add_machine(type)


func open() -> void:
	visible = true


func close() -> void:
	visible = false


## "set_mine_ticks(ticks: integer 20..100)": the tool name and its arguments with their range or choices.
static func signature(schema: Dictionary) -> String:
	var props: Dictionary = schema.get("input_schema", {}).get("properties", {})
	var args: PackedStringArray = []
	for key: String in props:
		var prop: Dictionary = props[key]
		var text: String = "%s: %s" % [key, prop.get("type", "?")]
		if prop.has("enum"):
			text += " (one of %d)" % (prop["enum"] as Array).size()
		elif prop.has("minimum") and prop.has("maximum"):
			text += " %s..%s" % [prop["minimum"], prop["maximum"]]
		args.append(text)
	return "%s(%s)" % [schema.get("name", "?"), ", ".join(args)]


func _add_machine(type: String) -> void:
	var machine: Machine = (Placement.SCENES[type] as PackedScene).instantiate() as Machine
	var title: Label = Label.new()
	title.text = type.capitalize()
	title.add_theme_color_override("font_color", Color("e0b82e"))
	_list.add_child(title)
	for schema: Dictionary in machine.get_tool_schemas():
		_add_text(signature(schema))
		_add_text(str(schema.get("description", "")), true)
	machine.free()
	_list.add_child(HSeparator.new())


func _add_text(text: String, note: bool = false) -> void:
	var label: Label = Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = WIDTH
	if note:
		label.add_theme_color_override("font_color", Color(0.7, 0.72, 0.78))
		label.text = "    " + text
	_list.add_child(label)
