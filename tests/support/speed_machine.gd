extends Machine
## Test double: a machine with numeric and integer tools, to exercise clamping.

var speed: float = 0.0
var level: int = 0


func _own_tool_schemas() -> Array:
	return [{
		"name": "set_speed",
		"description": "Set speed and level.",
		"input_schema": {"type": "object", "properties": {
			"value": {"type": "number", "minimum": 0.0, "maximum": 1.0},
			"level": {"type": "integer", "minimum": 1, "maximum": 3},
		}},
	}]


func _apply(tool_name: String, args: Dictionary) -> bool:
	if tool_name == "set_speed":
		speed = args["value"]
		level = args["level"]
		return true
	return super._apply(tool_name, args)
