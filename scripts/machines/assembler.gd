class_name Assembler
extends CraftMachine
## Assembles resources from other resources (a part from ingots by default).


func get_state() -> Dictionary:
	return super.get_state().merged({"stock_limit": stock_limit})


func _own_tool_schemas() -> Array:
	return [{
		"name": "set_stock_limit",
		"description": "Set how many of each input item the assembler keeps in stock. Upstream machines are refused above it.",
		"input_schema": {"type": "object", "properties": {
			"limit": {"type": "integer", "minimum": 1, "maximum": MAX_STOCK},
		}},
	}] + super._own_tool_schemas()


func _apply(tool_name: String, args: Dictionary) -> void:
	if tool_name == "set_stock_limit":
		stock_limit = args["limit"]
		return
	super._apply(tool_name, args)
