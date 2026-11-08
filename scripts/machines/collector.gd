class_name Collector
extends Machine
## Accepts every resource of the catalog and sells it for its price.

var sold: int = 0
var earned: int = 0
var accepting: bool = true


func receive(item: String) -> bool:
	if not accepting or not ItemCatalog.shared().has_item(item):
		return false
	var price: int = ItemCatalog.shared().price_of(item)
	GameState.add_money(price)
	GameState.record_order_sale(item)
	sold += 1
	earned += price
	return true


func is_removable() -> bool:
	return false


func can_rotate() -> bool:
	return false


func honors_enabled() -> bool:
	return false


func get_state() -> Dictionary:
	return super.get_state().merged({"accepting": accepting, "sold": sold})


func _save_data() -> Dictionary:
	return {"sold": sold, "earned": earned, "accepting": accepting}


func _load_data(data: Dictionary) -> void:
	sold = _read_int(data, "sold", 0, 0, 2147483647)
	earned = _read_int(data, "earned", 0, 0, 2147483647)
	accepting = data.get("accepting", true) == true


func _own_tool_schemas() -> Array:
	return [{
		"name": "set_accepting",
		"description": "Accept or refuse incoming items. A refusing collector sells nothing and blocks the line behind it.",
		"input_schema": {"type": "object", "properties": {"on": {"type": "boolean"}}},
	}]


func _apply(tool_name: String, args: Dictionary) -> bool:
	if tool_name == "set_accepting":
		accepting = args["on"]
		return true
	return super._apply(tool_name, args)
