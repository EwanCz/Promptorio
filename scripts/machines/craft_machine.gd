class_name CraftMachine
extends Machine
## Shared by Smelter and Assembler: stores any resource (capped per item), builds its product from the
## stock over the product's ticks, then pushes it forward. A blocked output stalls the machine.
## The product is one resource of the catalog built by this machine type: set_product picks it.

const MAX_STOCK: int = 10

## Id of the resource being built. Change it through set_product, which checks the machine may build it.
@export var product_id: String = ""

var stock: Dictionary = {}
## Per-item cap on the stock, at most MAX_STOCK.
var stock_limit: int = MAX_STOCK
## Ticks left on the current craft, 0 when idle.
var progress: int = 0

var _making: String = ""
var _output: String = ""
## True only after a delivery attempt failed; cleared when it succeeds or the contents are cleared.
var _blocked: bool = false


## Any resource of the catalog is stored, whether this machine needs it or not (discard_stock removes it).
func receive(item: String) -> bool:
	if status == Status.DOWN or not ItemCatalog.shared().has_item(item):
		return false
	if int(stock.get(item, 0)) >= stock_limit:
		return false
	stock[item] = int(stock.get(item, 0)) + 1
	return true


## Switches the product to a resource that a machine of this type builds. False, and nothing changes, if the
## catalog says another machine builds it or it does not exist. A craft already running finishes as it started.
func set_product(item: String) -> bool:
	refusal = ItemCatalog.shared().refusal_for(item, machine_type)
	if refusal != "":
		return false
	product_id = item
	return true


## Null when product_id is not a resource of the catalog.
func get_product() -> ItemData:
	return ItemCatalog.shared().get_item(product_id)


func is_working() -> bool:
	return enabled and progress > 0


func get_state() -> Dictionary:
	var product: ItemData = get_product()
	var needs: Dictionary = {} if product == null else product.inputs
	return super.get_state().merged({"product": product_id, "needs": needs, "stock": stock, "working": is_working()})


func get_action_text() -> String:
	var product: ItemData = get_product()
	if product == null:
		return "No product"
	var state: String = "idle"
	if _blocked:
		state = "output blocked"
	elif is_working():
		state = "working, %d ticks left" % progress
	return "%s -> %s\nStock: %s\n%s" % [_items_text(product.inputs), product.id, _items_text(stock), state]


func clear_contents() -> void:
	stock.clear()
	progress = 0
	_making = ""
	_output = ""
	_blocked = false


func _own_tool_schemas() -> Array:
	var catalog: ItemCatalog = ItemCatalog.shared()
	return [{
		"name": "set_product",
		"description": "Choose the resource to build from now on. This machine can build: %s. Any other resource is refused. A craft already running finishes first." % ", ".join(catalog.get_built_by_ids(machine_type)),
		"input_schema": {"type": "object", "properties": {"item": {"type": "string"}}},
	}, {
		"name": "discard_stock",
		"description": "Throw away units of a resource held in stock (any resource can be stored, even one this machine does not use).",
		"input_schema": {"type": "object", "properties": {
			"item": {"type": "string", "enum": catalog.get_ids()},
			"count": {"type": "integer", "minimum": 1, "maximum": MAX_STOCK},
		}},
	}]


func _apply(tool_name: String, args: Dictionary) -> bool:
	if tool_name == "set_product":
		return set_product(args["item"])
	if tool_name == "discard_stock":
		var item: String = args["item"]
		var left: int = int(stock.get(item, 0)) - int(args["count"])
		if left > 0:
			stock[item] = left
		else:
			stock.erase(item)
		return true
	return super._apply(tool_name, args)


func _save_data() -> Dictionary:
	return {"product": product_id, "stock": stock.duplicate(), "stock_limit": stock_limit, "progress": progress, "making": _making, "output": _output, "blocked": _blocked}


## Any resource of the catalog can be stored, each within the stock limit. A saved product this machine
## type cannot build is dropped for the default one.
func _load_data(data: Dictionary) -> void:
	var catalog: ItemCatalog = ItemCatalog.shared()
	stock_limit = _read_int(data, "stock_limit", MAX_STOCK, 1, MAX_STOCK)
	stock.clear()
	_output = ""
	_making = ""
	progress = 0
	_blocked = false
	var saved_product: String = _read_item(data, "product", catalog.get_built_by_ids(machine_type))
	if saved_product != "":
		product_id = saved_product
	var saved_stock: Variant = data.get("stock")
	if typeof(saved_stock) == TYPE_DICTIONARY:
		for item: String in catalog.get_ids():
			var count: int = _read_int(saved_stock, item, 0, 0, stock_limit)
			if count > 0:
				stock[item] = count
	_making = _read_item(data, "making", catalog.get_built_by_ids(machine_type))
	progress = _read_int(data, "progress", 0, 0, _max_saved_progress(_making))
	_output = _read_item(data, "output", catalog.get_ids())
	_blocked = _output != "" and data.get("blocked") == true


func _items_text(items: Dictionary) -> String:
	if items.is_empty():
		return "empty"
	var parts: PackedStringArray = []
	for item: String in items:
		parts.append("%d %s" % [int(items[item]), item])
	return ", ".join(parts)


func _tick() -> void:
	if _output != "":
		_blocked = not _push(_output)
		if not _blocked:
			_output = ""
		return
	if not enabled:
		return
	if progress > 0:
		progress -= 1
		if progress == 0:
			_output = _making
	elif _can_start():
		var product: ItemData = get_product()
		for item: String in product.inputs:
			stock[item] = int(stock[item]) - int(product.inputs[item])
		_making = product.id
		progress = _craft_ticks()


## Duration of a craft starting now (the product being made). Subclasses can slow it down.
func _craft_ticks() -> int:
	return ItemCatalog.shared().ticks_of(_making)


## Maximum duration a saved craft could have started with.
func _max_saved_progress(item: String) -> int:
	return ItemCatalog.shared().ticks_of(item)


func _can_start() -> bool:
	var product: ItemData = get_product()
	if product == null:
		return false
	for item: String in product.inputs:
		if int(stock.get(item, 0)) < int(product.inputs[item]):
			return false
	return true
