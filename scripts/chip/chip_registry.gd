extends Node
## Autoload. Owns every ChipRessource (the prompt registry) by id.
## Loads user://chip_registry.tres when it exists, else the shipped data/chip_registry.tres, and
## saves to the user path after every add/update/remove. A failed save keeps the edit in memory
## and is reported on EventBus.chip_storage_error (and in save_error) for the UI.

const DEFAULT_PATH: String = "res://data/chip_registry.tres"
const USER_PATH: String = "user://chip_registry.tres"

## Where edits are saved. Tests point it elsewhere; an empty path disables saving.
var user_path: String = USER_PATH
## Empty when the last load/save worked.
var save_error: String = ""

var _chips: Dictionary = {}
var _next_id: int = 1


func _ready() -> void:
	load_registry()


## Replaces the in-memory registry with the user file, or the shipped defaults when there is none
## (or it cannot be read: then save_error says so). Emits no chip signals: call it before the UI exists.
func load_registry() -> void:
	_chips.clear()
	_next_id = 1
	save_error = ""
	var library: ChipLibrary = null
	if FileAccess.file_exists(user_path):
		library = _read(user_path)
		if library == null:
			save_error = "Saved chips could not be read; the default chips were loaded."
	if library == null:
		library = _read(DEFAULT_PATH)
	if library == null:
		return
	for chip: ChipRessource in library.chips:
		if chip != null and chip.id > 0 and chip.name != "" and not _chips.has(chip.id):
			_chips[chip.id] = chip
			_next_id = maxi(_next_id, chip.id + 1)
	_next_id = maxi(_next_id, library.next_id)


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
	_save()
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
	_save()
	return true


## Returns true if the id existed.
func remove(chip_id: int) -> bool:
	var chip: ChipRessource = _chips.get(chip_id)
	if chip == null:
		return false
	_chips.erase(chip_id)
	chip.id = 0
	EventBus.chip_removed.emit(chip)
	_save()
	return true


## Null if unknown.
func get_from_id(chip_id: int) -> ChipRessource:
	return _chips.get(chip_id)


func get_all() -> Array[ChipRessource]:
	var result: Array[ChipRessource] = []
	for chip: ChipRessource in _chips.values():
		result.append(chip)
	return result


func _read(path: String) -> ChipLibrary:
	return ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as ChipLibrary


func _save() -> void:
	if user_path == "":
		return
	var library: ChipLibrary = ChipLibrary.new()
	library.chips.assign(_chips.values())
	library.next_id = _next_id
	var err: Error = ResourceSaver.save(library, user_path)
	var message: String = "" if err == OK else "Chips could not be saved (%s). Your changes last until you quit." % error_string(err)
	if message != save_error:
		save_error = message
		EventBus.chip_storage_error.emit(message)
