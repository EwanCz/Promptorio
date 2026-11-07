class_name Machine
extends Node2D
## Base machine. Subclasses override get_tool_schemas(), get_state() and _apply().
## apply_tool_call() is the only way LLM output touches a machine.

signal tool_applied(tool_name: String, args: Dictionary)

enum Status { NORMAL, DOWN, OVERHEATING }

@export var machine_type: String = "machine"

var machine_id: int = 0
var cell: Vector2i = Vector2i.ZERO
var status: Status = Status.NORMAL
var enabled: bool = true


func get_tool_schemas() -> Array:
	return [{
		"name": "set_enabled",
		"description": "Turn the machine on or off.",
		"input_schema": {"type": "object", "properties": {"on": {"type": "boolean"}}},
	}]


## Compact state sent to the LLM. Only fields the chip needs.
func get_state() -> Dictionary:
	return {"type": machine_type, "enabled": enabled, "status": Status.keys()[status].to_lower()}


## Validates a tool call against get_tool_schemas(), clamps args, then applies it.
## Returns false (and logs to the ChipLog) for unknown tools or malformed args.
func apply_tool_call(tool_name: String, args: Dictionary) -> bool:
	var schema: Dictionary = _find_schema(tool_name)
	if schema.is_empty():
		log_chip("ignored unknown tool '%s'" % tool_name)
		return false
	var clean: Dictionary = {}
	var props: Dictionary = schema.get("input_schema", {}).get("properties", {})
	for key: String in props:
		if not args.has(key):
			log_chip("ignored %s: missing '%s'" % [tool_name, key])
			return false
		var value: Variant = _sanitize(props[key], args[key])
		if value == null:
			log_chip("ignored %s: bad value for '%s'" % [tool_name, key])
			return false
		clean[key] = value
	_apply(tool_name, clean)
	log_chip("%s(%s)" % [tool_name, JSON.stringify(clean)])
	tool_applied.emit(tool_name, clean)
	return true


func log_chip(message: String) -> void:
	EventBus.chip_log_added.emit(self, message)


func _apply(tool_name: String, args: Dictionary) -> void:
	if tool_name == "set_enabled":
		enabled = args["on"]


func _find_schema(tool_name: String) -> Dictionary:
	for schema: Dictionary in get_tool_schemas():
		if schema.get("name", "") == tool_name:
			return schema
	return {}


## Returns the clamped value, or null if the type is wrong.
func _sanitize(prop: Dictionary, value: Variant) -> Variant:
	match prop.get("type", ""):
		"boolean":
			return value if typeof(value) == TYPE_BOOL else null
		"integer":
			if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
				return null
			return clampi(int(value), int(prop.get("minimum", -2147483648)), int(prop.get("maximum", 2147483647)))
		"number":
			if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
				return null
			return clampf(float(value), float(prop.get("minimum", -INF)), float(prop.get("maximum", INF)))
	return null
