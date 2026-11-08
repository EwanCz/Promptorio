class_name SaveGame
extends RefCounted
## Save files: the whole game (money, tick, machines with their contents and chips, and the chips they use)
## as one JSON document. A file is never trusted: restore() validates all of it before touching the game,
## so a bad file leaves the current game as it was. Slots live in `save_dir`; any other path works too.
##
## Format (version 1): {version, tick_count, money, next_machine_id, chips: [{id, name, description, prompt}],
## machines: [{type, id, cell: [x, y], facing: [x, y], enabled, status, chips: [{id, timeout, threshold_key,
## threshold}], data: {...state of the machine type, see Machine._save_data()}}]}

const VERSION: int = 1
## Slots go to `saves/` in the project folder when run from the editor (so a save can be committed and shared),
## else to the player's user folder (`res://` is read-only in an exported build).
const PROJECT_SLOT_DIR: String = "res://saves"
const USER_SLOT_DIR: String = "user://saves"
const EXTENSION: String = "json"
const MAX_FILE_BYTES: int = 4 * 1024 * 1024
const MAX_SLOT_NAME_LENGTH: int = 40
const MAX_MONEY: int = 1000000000
const MAX_CHIPS: int = 200
const MAX_CHIP_TEXT: int = 20000
const DIRECTIONS: Array[Vector2i] = [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]

## Where slots are written. Tests point it elsewhere.
static var save_dir: String = default_save_dir()


## `saves/` next to project.godot in an editor run, `user://saves` in an exported build.
static func default_save_dir() -> String:
	if OS.has_feature("editor"):
		return ProjectSettings.globalize_path(PROJECT_SLOT_DIR)
	return USER_SLOT_DIR


## The current game as a JSON-ready Dictionary.
static func snapshot(placement: Placement) -> Dictionary:
	var machines: Array = []
	var chip_ids: Dictionary = {}
	for node: Node in GameState.get_machines():
		var machine: Machine = node as Machine
		if machine == null or not machine.is_saveable():
			continue
		machines.append(machine.to_dict())
		for component: ChipComponent in machine.chips:
			chip_ids[component.chip.id] = true
	var chips: Array = []
	for chip_id: int in chip_ids:
		var chip: ChipRessource = ChipRegistry.get_from_id(chip_id)
		if chip != null:
			chips.append({"id": chip.id, "name": chip.name, "description": chip.description, "prompt": chip.prompt})
	return {
		"version": VERSION,
		"tick_count": GameState.tick_count,
		"money": GameState.money,
		"next_machine_id": placement.next_id,
		"chips": chips,
		"machines": machines,
	}


## Replaces the game with the save. Returns "" on success, else why it was refused (the game is untouched).
static func restore(placement: Placement, data: Variant) -> String:
	var error: String = validate(placement, data)
	if error != "":
		return error
	var save: Dictionary = data
	for node: Node in GameState.get_machines():
		var machine: Machine = node as Machine
		if machine != null:
			machine.discard()
	for entry: Dictionary in save["chips"]:
		ChipRegistry.import_chip(int(entry["id"]), entry["name"], entry.get("description", ""), entry.get("prompt", ""))
	var highest_id: int = 0
	for entry: Dictionary in save["machines"]:
		var cell: Vector2i = _to_cell(entry["cell"])
		var direction: Vector2i = _to_cell(entry["facing"])
		var id: int = int(entry["id"])
		var machine: Machine = placement.restore_machine(entry["type"], cell, direction, id)
		if machine != null:
			machine.load_dict(entry)
			highest_id = maxi(highest_id, id)
	placement.next_id = maxi(int(save["next_machine_id"]), highest_id + 1)
	GameState.tick_count = int(save["tick_count"])
	GameState.add_money(int(save["money"]) - GameState.money)
	return ""


## "" if the document can be restored, else a one-line reason. Checks the structure only: the values
## inside a machine's data are clamped when it loads.
static func validate(placement: Placement, data: Variant) -> String:
	if typeof(data) != TYPE_DICTIONARY:
		return "This file is not a Promptorio save."
	var save: Dictionary = data
	if not _is_whole(save.get("version")) or int(save["version"]) != VERSION:
		return "This save has an unsupported version."
	if not _is_whole(save.get("tick_count")) or int(save["tick_count"]) < 0:
		return "The save has an invalid tick count."
	if not _is_whole(save.get("money")) or int(save["money"]) < 0 or int(save["money"]) > MAX_MONEY:
		return "The save has an invalid amount of money."
	if not _is_whole(save.get("next_machine_id")) or int(save["next_machine_id"]) < 1:
		return "The save has an invalid machine id counter."
	var chip_error: String = _validate_chips(save.get("chips"))
	if chip_error != "":
		return chip_error
	return _validate_machines(placement, save.get("machines"), _chip_ids(save["chips"]))


## Writes the document through a temporary file, so a failed write never destroys an older save.
static func write(path: String, data: Dictionary) -> Error:
	var error: Error = DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if error != OK:
		return error
	var temp_path: String = path + ".tmp"
	var file: FileAccess = FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(data, "\t"))
	error = file.get_error()
	file.close()
	if error != OK:
		DirAccess.remove_absolute(temp_path)
		return error
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	return DirAccess.rename_absolute(temp_path, path)


## {"data": the parsed document, "error": ""} or {"error": reason}. Does not check the content: see validate().
static func read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"error": "The file does not exist."}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"error": "The file could not be opened."}
	if file.get_length() > MAX_FILE_BYTES:
		return {"error": "The file is too big to be a save."}
	var json: JSON = JSON.new()
	if json.parse(file.get_as_text()) != OK or typeof(json.data) != TYPE_DICTIONARY:
		return {"error": "This file is not a Promptorio save."}
	return {"data": json.data, "error": ""}


## Path of a slot, or "" when the name is empty, too long, or not usable as a file name.
static func slot_path(slot_name: String) -> String:
	var clean: String = slot_name.strip_edges()
	if clean == "" or clean.length() > MAX_SLOT_NAME_LENGTH or not clean.is_valid_filename() or clean.begins_with("."):
		return ""
	return "%s/%s.%s" % [save_dir, clean, EXTENSION]


## Saved slots, newest first: {name, path, modified (unix time)}.
static func list_slots() -> Array[Dictionary]:
	var slots: Array[Dictionary] = []
	if not DirAccess.dir_exists_absolute(save_dir):
		return slots
	for file_name: String in DirAccess.get_files_at(save_dir):
		if file_name.get_extension() != EXTENSION:
			continue
		var path: String = "%s/%s" % [save_dir, file_name]
		slots.append({"name": file_name.get_basename(), "path": path, "modified": FileAccess.get_modified_time(path)})
	slots.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["modified"] > b["modified"])
	return slots


static func delete_slot(slot_name: String) -> bool:
	var path: String = slot_path(slot_name)
	return path != "" and FileAccess.file_exists(path) and DirAccess.remove_absolute(path) == OK


static func _validate_chips(chips: Variant) -> String:
	if typeof(chips) != TYPE_ARRAY or (chips as Array).size() > MAX_CHIPS:
		return "The save has an invalid chip list."
	var seen: Dictionary = {}
	for entry: Variant in chips:
		if typeof(entry) != TYPE_DICTIONARY:
			return "The save has an invalid chip."
		var chip: Dictionary = entry
		if not _is_whole(chip.get("id")) or int(chip["id"]) < 1 or seen.has(int(chip["id"])):
			return "The save has a chip with an invalid id."
		if typeof(chip.get("name")) != TYPE_STRING or str(chip["name"]).strip_edges() == "":
			return "The save has a chip without a name."
		for key: String in ["name", "description", "prompt"]:
			if chip.has(key) and (typeof(chip[key]) != TYPE_STRING or str(chip[key]).length() > MAX_CHIP_TEXT):
				return "The save has a chip with an invalid %s." % key
		seen[int(chip["id"])] = true
	return ""


static func _chip_ids(chips: Array) -> Dictionary:
	var ids: Dictionary = {}
	for entry: Dictionary in chips:
		ids[int(entry["id"])] = true
	return ids


static func _validate_machines(placement: Placement, machines: Variant, chip_ids: Dictionary) -> String:
	if typeof(machines) != TYPE_ARRAY or (machines as Array).size() > GameState.GRID_SIZE.x * GameState.GRID_SIZE.y:
		return "The save has an invalid machine list."
	var cells: Dictionary = {}
	var ids: Dictionary = {}
	var has_collector: bool = false
	for entry: Variant in machines:
		if typeof(entry) != TYPE_DICTIONARY:
			return "The save has an invalid machine."
		var machine: Dictionary = entry
		if typeof(machine.get("type")) != TYPE_STRING or not Placement.SCENES.has(machine["type"]):
			return "The save has a machine of an unknown type."
		if not _is_whole(machine.get("id")) or int(machine["id"]) < 1 or ids.has(int(machine["id"])):
			return "The save has a machine with an invalid id."
		if not _is_pair(machine.get("cell")) or not _is_pair(machine.get("facing")):
			return "The save has a machine with an invalid position."
		var cell: Vector2i = _to_cell(machine["cell"])
		if not GameState.is_in_grid(cell) or cells.has(cell):
			return "The save has a machine outside the grid or on a taken cell."
		if machine["type"] == "miner" and not placement.grid.is_minesite(cell):
			return "The save has a miner outside a minesite."
		if not DIRECTIONS.has(_to_cell(machine["facing"])):
			return "The save has a machine with an invalid direction."
		if machine.has("chips") and not _chips_valid(machine["chips"], chip_ids):
			return "The save has a machine with an unknown chip."
		cells[cell] = true
		ids[int(machine["id"])] = true
		has_collector = has_collector or machine["type"] == "collector"
	if not has_collector:
		return "The save has no Collector."
	return ""


static func _chips_valid(chips: Variant, chip_ids: Dictionary) -> bool:
	if typeof(chips) != TYPE_ARRAY:
		return false
	for entry: Variant in chips:
		if typeof(entry) != TYPE_DICTIONARY or not _is_whole(entry.get("id")) or not chip_ids.has(int(entry["id"])):
			return false
	return true


## True for an int, or a float with no fractional part (JSON has only one number type).
static func _is_whole(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	return typeof(value) == TYPE_FLOAT and is_finite(value) and absf(value) < 1.0e15 and value == floorf(value)


static func _is_pair(value: Variant) -> bool:
	return typeof(value) == TYPE_ARRAY and (value as Array).size() == 2 and _is_whole(value[0]) and _is_whole(value[1])


static func _to_cell(pair: Array) -> Vector2i:
	return Vector2i(int(pair[0]), int(pair[1]))
