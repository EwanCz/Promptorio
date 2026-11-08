class_name ItemCatalog
extends Resource
## Every resource of the game, shipped in data/items.tres. Machines, the Collector and the Resources page read it.

const PATH: String = "res://data/items.tres"

static var _shared: ItemCatalog = null

## In file order: the first resource of a machine type is that machine's default.
@export var items: Array[ItemData] = []


static func shared() -> ItemCatalog:
	if _shared == null:
		_shared = load(PATH) as ItemCatalog
	return _shared


## Null for an unknown id.
func get_item(id: String) -> ItemData:
	for item: ItemData in items:
		if item.id == id:
			return item
	return null


func has_item(id: String) -> bool:
	return get_item(id) != null


## What the Collector pays for the item, 0 for an unknown id.
func price_of(id: String) -> int:
	var item: ItemData = get_item(id)
	return 0 if item == null else item.price


## Ticks the item takes to mine or build, 0 for an unknown id.
func ticks_of(id: String) -> int:
	var item: ItemData = get_item(id)
	return 0 if item == null else item.ticks


## Why a machine of this type cannot build the resource, as a sentence for the log. Empty when it can.
func refusal_for(id: String, machine_type: String) -> String:
	var item: ItemData = get_item(id)
	if item == null:
		return "'%s' is not a resource of the game" % id
	if item.is_built_by(machine_type):
		return ""
	return "'%s' cannot be made by this %s: it is built by %ss" % [id, machine_type, item.machine]


## The resources a machine type can build, in file order.
func get_built_by(machine_type: String) -> Array[ItemData]:
	var result: Array[ItemData] = []
	for item: ItemData in items:
		if item.machine == machine_type:
			result.append(item)
	return result


func get_ids() -> Array[String]:
	var ids: Array[String] = []
	for item: ItemData in items:
		ids.append(item.id)
	return ids


func get_built_by_ids(machine_type: String) -> Array[String]:
	var ids: Array[String] = []
	for item: ItemData in get_built_by(machine_type):
		ids.append(item.id)
	return ids
