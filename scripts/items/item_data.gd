class_name ItemData
extends Resource
## One resource of the game: what it sells for, the machine type that builds it and what it is built from.

@export var id: String = ""
@export var display_name: String = ""
## Money the Collector pays for one.
@export var price: int = 1
## machine_type of the only machine that builds it: "miner", "smelter" or "assembler".
@export var machine: String = ""
## Items consumed per unit built (item id -> count). Empty for a mined resource.
@export var inputs: Dictionary = {}
## Ticks one unit takes to build in a smelter or assembler. Unused for mined resources: a Miner's speed is its own mine_ticks.
@export var ticks: int = 0


func is_mined() -> bool:
	return machine == "miner"
