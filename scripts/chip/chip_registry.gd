extends Node
## Autoload. Owns every ChipRessource (the prompt registry) by id.

var _chips: Dictionary = {}
var _next_id: int = 1


## Creates a chip with a fresh id and returns it. Returns null if the name is empty or already used.
func add(chip_name: String, prompt: String, desc: String = "") -> ChipRessource:
	if chip_name == "":
		return null
	for existing: ChipRessource in _chips.values():
		if existing.name == chip_name:
			return null
	var chip: ChipRessource = ChipRessource.new()
	chip.id = _next_id
	chip.name = chip_name
	chip.prompt = prompt
	chip.description = desc
	_next_id += 1
	_chips[chip.id] = chip
	EventBus.chip_registered.emit(chip)
	return chip


## Edits a chip in place. Returns false for an unknown id, an empty name, or a name used by another chip.
func update(chip_id: int, chip_name: String, desc: String, prompt: String) -> bool:
	var chip: ChipRessource = _chips.get(chip_id)
	if chip == null or chip_name == "":
		return false
	for existing: ChipRessource in _chips.values():
		if existing != chip and existing.name == chip_name:
			return false
	chip.name = chip_name
	chip.description = desc
	chip.prompt = prompt
	EventBus.chip_updated.emit(chip)
	return true


## Returns true if the id existed.
func remove(chip_id: int) -> bool:
	var chip: ChipRessource = _chips.get(chip_id)
	if chip == null:
		return false
	_chips.erase(chip_id)
	chip.id = 0
	EventBus.chip_removed.emit(chip)
	return true


## Null if unknown.
func get_from_id(chip_id: int) -> ChipRessource:
	return _chips.get(chip_id)


func get_all() -> Array[ChipRessource]:
	var result: Array[ChipRessource] = []
	for chip: ChipRessource in _chips.values():
		result.append(chip)
	return result
