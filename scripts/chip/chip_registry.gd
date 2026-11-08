extends Node
## Autoload. Owns every ChipRessource (the prompt registry) by id.
## Loads user://chip_registry.tres when it exists, else the shipped data/chip_registry.tres, and
## saves to the user path after every add/update/remove. A failed save keeps the edit in memory
## and is reported on EventBus.chip_storage_error (and in save_error) for the UI.

const DEFAULT_PATH: String = "res://data/chip_registry.tres"
const USER_PATH: String = "user://chip_registry.tres"
## md5 of the starter prompts shipped before, by chip id. A saved chip whose prompt is still exactly
## one of them is replaced by the current shipped prompt; an edited or custom prompt never is.
const OUTDATED_STARTER_PROMPTS: Dictionary = {
	2: ["828136d52cd886c88b44cabea1c540df", "22b71a85b041e25cac8b437a37ac04b1", "f84febd378c0ddc006ab0a6773e77fba", "435c19a839e759a1201f257b5b9e7b11"],
}

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
	var from_user: bool = false
	if FileAccess.file_exists(user_path):
		library = _read(user_path)
		from_user = library != null
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
	if from_user and _upgrade_starter_prompts():
		_save()


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


## Puts a chip from a save file in the registry under its own id: a chip with that id is overwritten (the
## save wins), else it is created. A name already used by another chip gets a number appended, so names
## stay unique. Null for an invalid id or an empty name.
func import_chip(chip_id: int, chip_name: String, desc: String, prompt: String) -> ChipRessource:
	if chip_id <= 0 or chip_name == "":
		return null
	var unique_name: String = chip_name
	var suffix: int = 2
	while _name_used_by_other(unique_name, chip_id):
		unique_name = "%s (%d)" % [chip_name, suffix]
		suffix += 1
	var chip: ChipRessource = _chips.get(chip_id)
	var created: bool = chip == null
	if created:
		chip = ChipRessource.new()
		chip.id = chip_id
		_chips[chip_id] = chip
		_next_id = maxi(_next_id, chip_id + 1)
	chip.name = unique_name
	chip.description = desc
	chip.prompt = prompt
	if created:
		EventBus.chip_registered.emit(chip)
	else:
		EventBus.chip_updated.emit(chip)
	_save()
	return chip


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


func _name_used_by_other(chip_name: String, chip_id: int) -> bool:
	for existing: ChipRessource in _chips.values():
		if existing.id != chip_id and existing.name == chip_name:
			return true
	return false
## Swaps in the shipped prompt of every starter chip still on an outdated, unedited prompt. True if any changed.
func _upgrade_starter_prompts() -> bool:
	var defaults: ChipLibrary = _read(DEFAULT_PATH)
	if defaults == null:
		return false
	var changed: bool = false
	for shipped: ChipRessource in defaults.chips:
		var saved: ChipRessource = _chips.get(shipped.id)
		var outdated: Array = OUTDATED_STARTER_PROMPTS.get(shipped.id, [])
		if saved != null and saved.name == shipped.name and saved.prompt.md5_text() in outdated:
			saved.prompt = shipped.prompt
			changed = true
	return changed


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
