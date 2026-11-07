class_name MachineCatalog
extends RefCounted
## What the player can build and what it costs. Shared by Placement and the Build page.
## The Collector is provided at the map center: it is not in the catalog.

const BUILDABLE: Array[String] = ["miner", "smelter", "assembler", "conveyor"]
const COSTS: Dictionary = {
	"miner": 20,
	"smelter": 30,
	"assembler": 40,
	"conveyor": 2,
}


static func is_buildable(type: String) -> bool:
	return COSTS.has(type)


static func cost(type: String) -> int:
	return COSTS.get(type, 0)
