class_name ItemData
extends Resource
## One resource of the game: what it sells for, the machine type that builds it and what it is built from.

@export var id: String = ""
@export var display_name: String = ""
## Pixel art (32x32) shown for the resource, e.g. on the conveyor that carries it.
@export var icon: Texture2D
## Money the Collector pays for one.
@export var price: int = 1
## machine_type of the only machine that builds it: "miner", "smelter" or "assembler".
@export var machine: String = ""
## Items consumed per unit built (item id -> count). Empty for a mined resource.
@export var inputs: Dictionary = {}
## Ticks one unit takes to build (smelter, assembler) or to mine (miner). A Miner can be slowed down by its
## chip but never goes faster than this.
@export var ticks: int = 0


## True if a machine of this type is the one that builds it.
func is_built_by(machine_type: String) -> bool:
	return machine == machine_type


func is_mined() -> bool:
	return machine == "miner"
