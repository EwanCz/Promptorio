extends "res://tests/test_case.gd"
## Save files: snapshot/restore round trip, refusal of bad files, clamping, chips, slots and file writing.

const TEST_DIR: String = "user://test_saves_game"

var _main: Node
var _placement: Placement
var _game: Node
var _registry: Node
var _saved_money: int = 0
var _saved_ticks: int = 0
var _saved_dir: String = ""
var _chip_ids: Array[int] = []


func before_each() -> void:
	_game = autoload("GameState")
	_registry = autoload("ChipRegistry")
	_saved_money = _game.money
	_saved_ticks = _game.tick_count
	_saved_dir = SaveGame.save_dir
	SaveGame.save_dir = TEST_DIR
	_game.money = 100
	_main = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(_main)
	_placement = _main.get_node("Game/FactoryView/SubViewport/World/Placement")


func after_each() -> void:
	_main.free()
	for id: int in _chip_ids:
		_registry.remove(id)
	_chip_ids.clear()
	_clear_dir(TEST_DIR)
	SaveGame.save_dir = _saved_dir
	_game.money = _saved_money
	_game.tick_count = _saved_ticks


func _clear_dir(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for file_name: String in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path + "/" + file_name)
	DirAccess.remove_absolute(path)


func _chip(chip_name: String, prompt: String = "prompt") -> ChipRessource:
	var chip: ChipRessource = _registry.add(chip_name, prompt, "desc of " + chip_name)
	_chip_ids.append(chip.id)
	return chip


## One machine of each kind, with contents, a chip with a threshold, and non-default money and tick.
func _build_world() -> void:
	var miner: Miner = _placement.place("miner", GridMap2D.MINESITES[0])
	miner.mine_ticks = 33
	miner._progress = 7
	miner._held = "ore"
	miner.enabled = false
	var smelter: Smelter = _placement.place("smelter", Vector2i(8, 8))
	smelter.stock = {"ore": 4}
	smelter.progress = 5
	smelter._output = "ingot"
	smelter.temperature = 71.5
	smelter.cooling = true
	smelter.status = Machine.Status.OVERHEATING
	var chip: ChipRessource = _chip("save_chip", "keep it cool")
	var component: ChipComponent = smelter.attach_chip(chip.id, 55)
	component.set_threshold("temperature", 90.0)
	var assembler: Assembler = _placement.place("assembler", Vector2i(10, 8))
	assembler.stock = {"ingot": 2}
	_placement.facing = Vector2i.DOWN
	var conveyor: Conveyor = _placement.place("conveyor", Vector2i(12, 8))
	conveyor.held = "ingot"
	conveyor._wait = 3
	_placement.facing = Vector2i.RIGHT
	var collector: Collector = _game.get_machine_at(_game.GRID_SIZE / 2)
	collector.sold = 5
	collector.earned = 12
	collector.accepting = false
	_game.money = 77
	_game.tick_count = 1234


func _text(data: Dictionary) -> String:
	return JSON.stringify(data, "", true)


func _machine_dict(save: Dictionary, type: String) -> Dictionary:
	for entry: Dictionary in save["machines"]:
		if entry["type"] == type:
			return entry
	return {}


func _count(type: String) -> int:
	var count: int = 0
	for machine: Machine in _game.get_machines():
		if machine.machine_type == type:
			count += 1
	return count


func test_snapshot_restore_round_trip() -> void:
	_build_world()
	var before: Dictionary = SaveGame.snapshot(_placement)
	check_eq(before["machines"].size(), 5, "every machine is saved (4 built + the Collector)")
	check_eq(before["chips"].size(), 1, "the chip used by a machine is embedded")
	_game.get_machine_at(Vector2i(8, 8)).destroy()
	_game.get_machine_at(Vector2i(12, 8)).destroy()
	_placement.place("smelter", Vector2i(20, 12))
	_game.money = 5
	_game.tick_count = 1
	check_eq(SaveGame.restore(_placement, before), "", "restore accepts its own snapshot")
	check_eq(_text(SaveGame.snapshot(_placement)), _text(before), "the game is identical after restoring")
	var smelter: Smelter = _game.get_machine_at(Vector2i(8, 8))
	check(smelter != null, "the destroyed smelter is back")
	check_eq(smelter.stock, {"ore": 4}, "stock restored")
	check_eq(smelter.temperature, 71.5, "temperature restored")
	check_eq(smelter.status, Machine.Status.OVERHEATING, "status restored")
	check_eq(smelter.chips.size(), 1, "chip reattached")
	check_eq(smelter.chips[0].timeout, 55, "chip timeout restored")
	check_eq(smelter.chips[0].threshold_key, "temperature", "chip threshold key restored")
	check_eq(smelter.chips[0].threshold, 90.0, "chip threshold restored")
	check(_game.get_machine_at(Vector2i(20, 12)) == null, "a machine that is not in the save is gone")
	check_eq(_game.money, 77, "money restored")
	check_eq(_game.tick_count, 1234, "tick restored")


func test_round_trip_through_a_file() -> void:
	_build_world()
	var before: Dictionary = SaveGame.snapshot(_placement)
	var path: String = SaveGame.slot_path("round trip")
	check_eq(SaveGame.write(path, before), OK, "write succeeds")
	check(not FileAccess.file_exists(path + ".tmp"), "no temporary file is left behind")
	_game.get_machine_at(Vector2i(10, 8)).destroy()
	var result: Dictionary = SaveGame.read(path)
	check_eq(result["error"], "", "read succeeds")
	check_eq(SaveGame.restore(_placement, result["data"]), "", "restore accepts the parsed file (JSON numbers are floats)")
	check_eq(_text(SaveGame.snapshot(_placement)), _text(before), "identical after a trip through the file")
	var conveyor: Conveyor = _game.get_machine_at(Vector2i(12, 8))
	check_eq(conveyor.facing, Vector2i.DOWN, "direction restored")
	check_eq(conveyor.held, "ingot", "held item restored")
	var miner: Miner = _game.get_machine_at(GridMap2D.MINESITES[0])
	check_eq([miner.mine_ticks, miner._progress, miner._held, miner.enabled], [33, 7, "ore", false], "miner restored")


func test_write_replaces_an_older_save() -> void:
	var path: String = SaveGame.slot_path("again")
	SaveGame.write(path, {"a": 1})
	check_eq(SaveGame.write(path, {"b": 2}), OK, "second write succeeds")
	check_eq(SaveGame.read(path)["data"], {"b": 2.0}, "the file holds the newest save")
	check(not FileAccess.file_exists(path + ".tmp"), "no temporary file")


func test_collector_is_not_duplicated_and_keeps_its_totals() -> void:
	_build_world()
	var before: Dictionary = SaveGame.snapshot(_placement)
	SaveGame.restore(_placement, before)
	SaveGame.restore(_placement, before)
	check_eq(_count("collector"), 1, "still one Collector")
	var collector: Collector = _game.get_machine_at(_game.GRID_SIZE / 2)
	check_eq([collector.sold, collector.earned, collector.accepting], [5, 12, false], "Collector totals restored")


func test_ids_do_not_repeat_after_a_load() -> void:
	_build_world()
	SaveGame.restore(_placement, SaveGame.snapshot(_placement))
	var used: Dictionary = {}
	for machine: Machine in _game.get_machines():
		used[machine.machine_id] = true
	var fresh: Machine = _placement.place("conveyor", Vector2i(2, 2))
	check(not used.has(fresh.machine_id), "a machine placed after the load gets a new id")


func test_money_label_follows_a_restore() -> void:
	_build_world()
	var before: Dictionary = SaveGame.snapshot(_placement)
	_game.money = 5
	SaveGame.restore(_placement, before)
	check_eq((_main.get_node("%BuildPage").get_node("%MoneyLabel") as Label).text, "Money: 77", "the Build page shows the restored money")


func test_exploding_smelter_is_not_saved() -> void:
	var smelter: Smelter = _placement.place("smelter", Vector2i(8, 8))
	smelter.temperature = Smelter.EXPLODE_AT
	check_eq(_machine_dict(SaveGame.snapshot(_placement), "smelter"), {}, "a smelter at the explosion temperature is left out")


func test_bad_files_are_refused_and_leave_the_game_untouched() -> void:
	_build_world()
	var good: Dictionary = SaveGame.snapshot(_placement)
	var good_text: String = _text(good)
	var cases: Dictionary = {
		"not a dictionary": func(_d: Dictionary) -> Variant: return [1, 2],
		"version 2": func(d: Dictionary) -> Variant: d["version"] = 2; return d,
		"no version": func(d: Dictionary) -> Variant: d.erase("version"); return d,
		"negative money": func(d: Dictionary) -> Variant: d["money"] = -1; return d,
		"money as text": func(d: Dictionary) -> Variant: d["money"] = "lots"; return d,
		"fractional tick": func(d: Dictionary) -> Variant: d["tick_count"] = 1.5; return d,
		"bad id counter": func(d: Dictionary) -> Variant: d["next_machine_id"] = 0; return d,
		"machines not a list": func(d: Dictionary) -> Variant: d["machines"] = {}; return d,
		"unknown type": func(d: Dictionary) -> Variant: d["machines"][0]["type"] = "reactor"; return d,
		"cell outside the grid": func(d: Dictionary) -> Variant: d["machines"][1]["cell"] = [99, 99]; return d,
		"cell not a pair": func(d: Dictionary) -> Variant: d["machines"][1]["cell"] = [1]; return d,
		"two machines on a cell": func(d: Dictionary) -> Variant: d["machines"][2]["cell"] = d["machines"][1]["cell"]; return d,
		"two machines with an id": func(d: Dictionary) -> Variant: d["machines"][2]["id"] = d["machines"][1]["id"]; return d,
		"miner off a minesite": func(d: Dictionary) -> Variant: _machine_dict(d, "miner")["cell"] = [1, 1]; return d,
		"diagonal direction": func(d: Dictionary) -> Variant: d["machines"][1]["facing"] = [1, 1]; return d,
		"unknown chip": func(d: Dictionary) -> Variant: _machine_dict(d, "smelter")["chips"][0]["id"] = 9999; return d,
		"chip without a name": func(d: Dictionary) -> Variant: d["chips"][0]["name"] = ""; return d,
		"huge chip prompt": func(d: Dictionary) -> Variant: d["chips"][0]["prompt"] = "x".repeat(SaveGame.MAX_CHIP_TEXT + 1); return d,
		"no Collector": func(d: Dictionary) -> Variant: d["machines"] = d["machines"].filter(func(m: Dictionary) -> bool: return m["type"] != "collector"); return d,
	}
	for label: String in cases:
		var broken: Variant = (cases[label] as Callable).call(JSON.parse_string(good_text))
		var error: String = SaveGame.restore(_placement, broken)
		check(error != "", "refused: " + label)
		check_eq(_text(SaveGame.snapshot(_placement)), good_text, "game untouched after: " + label)


func test_values_in_a_file_are_clamped() -> void:
	_build_world()
	var save: Dictionary = JSON.parse_string(_text(SaveGame.snapshot(_placement)))
	var miner_data: Dictionary = _machine_dict(save, "miner")["data"]
	miner_data["mine_ticks"] = 9999
	miner_data["progress"] = -50
	miner_data["held"] = "gold"
	var smelter_entry: Dictionary = _machine_dict(save, "smelter")
	smelter_entry["data"]["stock"] = {"ore": 999, "gold": 3}
	smelter_entry["data"]["temperature"] = 99999
	smelter_entry["data"]["output"] = "diamond"
	smelter_entry["status"] = 42
	smelter_entry["chips"][0]["timeout"] = -3
	_machine_dict(save, "conveyor")["data"]["held"] = "plutonium"
	check_eq(SaveGame.restore(_placement, save), "", "structure is valid")
	var miner: Miner = _game.get_machine_at(GridMap2D.MINESITES[0])
	check_eq([miner.mine_ticks, miner._progress, miner._held], [Miner.MAX_MINE_TICKS, 0, ""], "miner values clamped, unknown item dropped")
	var smelter: Smelter = _game.get_machine_at(Vector2i(8, 8))
	check_eq(smelter.stock, {"ore": CraftMachine.MAX_STOCK}, "stock capped, unknown item dropped")
	check(smelter.temperature < Smelter.EXPLODE_AT, "temperature stays below the explosion")
	check_eq(smelter._output, "", "an item the recipe cannot make is dropped")
	check(smelter.status == Machine.Status.DOWN or smelter.status == Machine.Status.OVERHEATING, "status stays a valid value")
	check_eq(smelter.chips[0].timeout, 1, "timeout is at least one tick")
	check_eq((_game.get_machine_at(Vector2i(12, 8)) as Conveyor).held, "", "unknown held item dropped")


func test_missing_chips_are_recreated_and_attached() -> void:
	_build_world()
	var chip: ChipRessource = _chip_for_smelter()
	var save: Dictionary = JSON.parse_string(_text(SaveGame.snapshot(_placement)))
	var chip_id: int = chip.id
	_registry.remove(chip_id)
	check(_registry.get_from_id(chip_id) == null, "the chip is gone from the registry")
	check_eq(SaveGame.restore(_placement, save), "", "restore works without the chip")
	var back: ChipRessource = _registry.get_from_id(chip_id)
	check(back != null and back.prompt == "keep it cool" and back.name == "save_chip", "the chip is recreated with its prompt")
	_chip_ids.append(chip_id)
	check_eq((_game.get_machine_at(Vector2i(8, 8)) as Machine).chips.size(), 1, "and attached to its machine")


func _chip_for_smelter() -> ChipRessource:
	return (_game.get_machine_at(Vector2i(8, 8)) as Machine).chips[0].chip


func test_existing_chip_is_overwritten_by_the_save() -> void:
	_build_world()
	var chip: ChipRessource = _chip_for_smelter()
	var save: Dictionary = JSON.parse_string(_text(SaveGame.snapshot(_placement)))
	_registry.update(chip.id, "renamed", "other", "changed prompt")
	SaveGame.restore(_placement, save)
	var same: ChipRessource = _registry.get_from_id(chip.id)
	check_eq([same.name, same.prompt], ["save_chip", "keep it cool"], "the saved chip text wins")
	check_eq(_registry.get_all().filter(func(c: ChipRessource) -> bool: return c.id == chip.id).size(), 1, "no duplicate")


func test_chip_name_clash_gets_a_suffix() -> void:
	var other: ChipRessource = _chip("clash")
	var imported: ChipRessource = _registry.import_chip(other.id + 500, "clash", "d", "p")
	_chip_ids.append(imported.id)
	check_eq(imported.name, "clash (2)", "a name used by another chip is numbered")
	check(_registry.import_chip(0, "x", "", "") == null, "invalid id refused")
	check(_registry.import_chip(7777, "", "", "") == null, "empty name refused")
	var next: ChipRessource = _chip("after_import")
	check(next.id > imported.id, "new chips never reuse an imported id")


func test_validate_without_a_placement_is_a_full_check() -> void:
	_build_world()
	var save: Dictionary = SaveGame.snapshot(_placement)
	check_eq(SaveGame.validate(null, save), "", "a good save passes without a placement (main menu)")
	var bad: Dictionary = JSON.parse_string(JSON.stringify(save))
	for entry: Dictionary in bad["machines"]:
		if entry["type"] == "miner":
			entry["cell"] = [0, 0]
	check(SaveGame.validate(null, bad) != "", "a miner off a minesite is refused without a placement too")
	bad["machines"] = []
	check(SaveGame.validate(null, bad) != "", "a save without a Collector is refused")


func test_pending_save_is_taken_once() -> void:
	SaveGame.pending = {"version": 1}
	check_eq(SaveGame.take_pending(), {"version": 1}, "the pending save is returned")
	check(SaveGame.pending.is_empty() and SaveGame.take_pending().is_empty(), "and is gone afterwards")


func test_main_scene_restores_the_pending_save() -> void:
	_build_world()
	var save: Dictionary = JSON.parse_string(JSON.stringify(SaveGame.snapshot(_placement)))
	_main.free()
	check(_game.get_machine_at(Vector2i(8, 8)) == null, "the old game is gone")
	SaveGame.pending = save
	_main = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(_main)
	check(_game.get_machine_at(Vector2i(8, 8)) is Smelter, "the saved machine is back")
	check_eq(_game.money, 77, "money is back")
	check_eq(_count("collector"), 1, "the Collector is not duplicated")
	check(SaveGame.pending.is_empty(), "nothing is left pending")


func test_slot_names_are_checked() -> void:
	check_eq(SaveGame.slot_path("my save"), TEST_DIR + "/my save.json", "a plain name works")
	for bad: String in ["", "   ", "../escape", "a/b", "a\\b", ".hidden", "x".repeat(SaveGame.MAX_SLOT_NAME_LENGTH + 1), "a:b"]:
		check_eq(SaveGame.slot_path(bad), "", "refused name: '%s'" % bad)


func test_default_dir_is_the_project_folder_in_the_editor() -> void:
	var dir: String = SaveGame.default_save_dir()
	if OS.has_feature("editor"):
		check_eq(dir, ProjectSettings.globalize_path("res://").path_join("saves"), "slots go to saves/ in the project")
	else:
		check_eq(dir, "user://saves", "an exported build uses the user folder")


func test_slots_are_listed_and_deleted() -> void:
	SaveGame.write(SaveGame.slot_path("one"), {"x": 1})
	SaveGame.write(SaveGame.slot_path("two"), {"x": 1})
	var f: FileAccess = FileAccess.open(TEST_DIR + "/notes.txt", FileAccess.WRITE)
	f.store_string("not a save")
	f.close()
	var names: Array[String] = []
	for slot: Dictionary in SaveGame.list_slots():
		names.append(slot["name"])
	names.sort()
	check_eq(names, ["one", "two"], "only .json files are slots")
	check(SaveGame.delete_slot("one"), "delete works")
	check(not SaveGame.delete_slot("one"), "deleting a missing slot reports false")
	check(not SaveGame.delete_slot("../one"), "an escaping name is not deleted")


func test_read_reports_broken_files() -> void:
	check(SaveGame.read(TEST_DIR + "/nope.json")["error"] != "", "missing file")
	DirAccess.make_dir_recursive_absolute(TEST_DIR)
	var file: FileAccess = FileAccess.open(TEST_DIR + "/broken.json", FileAccess.WRITE)
	file.store_string("{ not json")
	file.close()
	check(SaveGame.read(TEST_DIR + "/broken.json")["error"] != "", "broken JSON")
	file = FileAccess.open(TEST_DIR + "/list.json", FileAccess.WRITE)
	file.store_string("[1, 2]")
	file.close()
	check(SaveGame.read(TEST_DIR + "/list.json")["error"] != "", "JSON that is not an object")
