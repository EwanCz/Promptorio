class_name ChipLibrary
extends Resource
## The saved form of the ChipRegistry (data/chip_registry.tres, user://chip_registry.tres).

@export var chips: Array[ChipRessource] = []
## Next id to hand out. Saved so ids stay stable and are never reused after a removal.
@export var next_id: int = 1
