extends "res://tests/test_case.gd"

var _registry: Node
var _ids: Array[int] = []


func before_each() -> void:
	_registry = autoload("ChipRegistry")
	_ids.clear()


func after_each() -> void:
	for id: int in _ids:
		_registry.remove(id)


func _add(chip_name: String, prompt: String = "p", desc: String = "") -> ChipRessource:
	var chip: ChipRessource = _registry.add(chip_name, prompt, desc)
	if chip != null:
		_ids.append(chip.id)
	return chip


func test_add_stores_fields_and_assigns_unique_ids() -> void:
	var first: ChipRessource = _add("reg_a", "prompt a", "desc a")
	var second: ChipRessource = _add("reg_b")
	check(first != null and second != null, "chips created")
	check_eq([first.name, first.prompt, first.description], ["reg_a", "prompt a", "desc a"], "fields stored")
	check_eq(second.description, "", "description defaults to empty")
	check(first.id != 0 and second.id != first.id, "ids are unique")
	check_eq(_registry.get_from_id(first.id), first, "lookup by id")
	check(_registry.get_all().has(second), "listed")


func test_add_refuses_duplicate_or_empty_name() -> void:
	_add("reg_dup")
	check(_add("reg_dup") == null, "duplicate name refused")
	check(_add("") == null, "empty name refused")


func test_remove() -> void:
	var chip: ChipRessource = _add("reg_rm")
	var id: int = chip.id
	check(_registry.remove(id), "removed")
	check(_registry.get_from_id(id) == null, "gone from registry")
	check(not _registry.remove(id), "second remove reports false")
	check(_add("reg_rm") != null, "name reusable after removal")


func test_update_edits_in_place_and_emits() -> void:
	var chip: ChipRessource = _add("reg_up", "old", "d")
	var seen: Array[ChipRessource] = []
	var on_updated: Callable = func(c: ChipRessource) -> void: seen.append(c)
	autoload("EventBus").chip_updated.connect(on_updated)
	check(_registry.update(chip.id, "reg_up2", "new desc", "new prompt"), "update succeeds")
	check_eq([chip.name, chip.description, chip.prompt], ["reg_up2", "new desc", "new prompt"], "fields changed")
	check_eq(seen, [chip], "chip_updated emitted with the chip")
	check(_registry.update(chip.id, "reg_up2", "", ""), "keeping its own name is allowed")
	autoload("EventBus").chip_updated.disconnect(on_updated)


func test_update_refuses_bad_input() -> void:
	var first: ChipRessource = _add("reg_u1")
	var second: ChipRessource = _add("reg_u2")
	check(not _registry.update(second.id, "reg_u1", "", ""), "name of another chip refused")
	check(not _registry.update(first.id, "", "", ""), "empty name refused")
	check(not _registry.update(99999, "x", "", ""), "unknown id refused")
	check_eq(second.name, "reg_u2", "refused update changes nothing")


## Persistence. Each test saves to its own temp file and restores the runner's path and defaults.
const TMP_PATH: String = "user://test_chip_persist.tres"
var _saved_path: String = ""


func _use_tmp_path() -> void:
	_saved_path = _registry.user_path
	_registry.user_path = TMP_PATH
	DirAccess.remove_absolute(TMP_PATH)
	_registry.load_registry()


func _restore_path() -> void:
	DirAccess.remove_absolute(TMP_PATH)
	_registry.user_path = _saved_path
	_registry.load_registry()


func test_defaults_are_loaded_when_there_is_no_user_file() -> void:
	_use_tmp_path()
	var chips: Array[ChipRessource] = _registry.get_all()
	check_eq(chips.size(), 3, "three starter chips")
	for chip: ChipRessource in chips:
		check(chip.id > 0 and chip.name != "" and chip.description != "" and chip.prompt != "", "starter chip %s is complete" % chip.name)
	check(not FileAccess.file_exists(TMP_PATH), "loading defaults writes nothing")
	check_eq(_registry.save_error, "", "no error")
	_restore_path()


func test_starter_prompts_only_use_real_tools() -> void:
	_use_tmp_path()
	var known: Array[String] = []
	for scene: String in ["miner", "smelter", "assembler"]:
		var machine: Machine = load("res://scenes/machines/%s.tscn" % scene).instantiate()
		for schema: Dictionary in machine.get_tool_schemas():
			known.append(schema["name"])
		machine.free()
	for chip: ChipRessource in _registry.get_all():
		var tools: Array[String] = []
		for tool_name: String in known:
			if chip.prompt.contains(tool_name):
				tools.append(tool_name)
		check(not tools.is_empty(), "%s names a tool" % chip.name)
	_restore_path()


func _smelter_cooler(registry_chips: Array[ChipRessource]) -> ChipRessource:
	for chip: ChipRessource in registry_chips:
		if chip.name == "Smelter Cooler":
			return chip
	return null


func test_smelter_cooler_manages_heat_with_cooling_and_pauses_only_in_an_emergency() -> void:
	_use_tmp_path()
	var prompt: String = _smelter_cooler(_registry.get_all()).prompt
	check(prompt.contains("set_cooling") and prompt.contains("on=true") and prompt.contains("on=false"), "cooling on and off")
	check(prompt.contains("set_emergency_stop") and prompt.contains("emergency_stop is true"), "the emergency pause and its own resume")
	check(prompt.contains("another chip paused") and prompt.contains("leave it disabled"), "another chip's pause is left alone")
	check(prompt.contains("never set_enabled"), "it does not use the plain pause")
	var cool_on: int = 60
	var cool_off: int = 40
	for number: int in [cool_on, cool_off, int(Smelter.SAFE_AT)]:
		check(prompt.contains(str(number)), "prompt states %d" % number)
	check(prompt.contains("status is \"overheating\""), "the pause is tied to OVERHEATING (100)")
	check(prompt.contains("Never pause for routine temperature control"), "no routine pausing")
	check(cool_off < cool_on and cool_on < Smelter.OVERHEAT_AT, "cooling has a gap and starts before the emergency")
	_restore_path()


func test_edits_survive_a_reload_with_stable_ids() -> void:
	_use_tmp_path()
	var added: ChipRessource = _registry.add("persist_new", "np", "nd")
	var starter: ChipRessource = _registry.get_all()[0]
	var starter_id: int = starter.id
	_registry.update(starter_id, "renamed", "new desc", "new prompt")
	var removed_id: int = _registry.get_all()[1].id
	_registry.remove(removed_id)
	var added_id: int = added.id
	_registry.load_registry()
	var reloaded: ChipRessource = _registry.get_from_id(added_id)
	check(reloaded != null and [reloaded.name, reloaded.prompt, reloaded.description] == ["persist_new", "np", "nd"], "added chip kept with its id")
	check_eq(_registry.get_from_id(starter_id).name, "renamed", "edit kept")
	check_eq(_registry.get_from_id(starter_id).prompt, "new prompt", "edited prompt kept")
	check(_registry.get_from_id(removed_id) == null, "removal kept")
	check_eq(_registry.get_all().size(), 3, "3 defaults - 1 removed + 1 added")
	var next: ChipRessource = _registry.add("persist_next", "p")
	check(next.id > added_id and next.id != removed_id, "ids are never reused")
	_restore_path()


func test_reload_after_edit_can_save_again() -> void:
	_use_tmp_path()
	_registry.add("persist_a", "p")
	_registry.load_registry()
	var chip: ChipRessource = _registry.get_all()[-1]
	check(_registry.update(chip.id, "persist_b", "", "p2"), "loaded chip can be edited")
	_registry.load_registry()
	check_eq(_registry.get_from_id(chip.id).name, "persist_b", "second save wrote the edit")
	_restore_path()


func test_wrong_type_user_file_falls_back_to_defaults_and_reports() -> void:
	_use_tmp_path()
	var file: FileAccess = FileAccess.open(TMP_PATH, FileAccess.WRITE)
	# a well-formed .tres of the wrong type: a garbage file would make the engine print a Parse Error, which run.sh treats as a crash
	file.store_string("[gd_resource type=\"Resource\" format=3]\n\n[resource]\n")
	file.close()
	_registry.load_registry()
	check_eq(_registry.get_all().size(), 3, "defaults loaded")
	check(_registry.save_error != "", "the problem is reported")
	_restore_path()


func test_failed_save_is_reported_and_keeps_the_edit() -> void:
	_use_tmp_path()
	_registry.user_path = "user://no_such_dir/chips.tres"
	var seen: Array[String] = []
	var on_error: Callable = func(message: String) -> void: seen.append(message)
	autoload("EventBus").chip_storage_error.connect(on_error)
	var chip: ChipRessource = _registry.add("persist_fail", "p")
	check(chip != null and _registry.get_from_id(chip.id) == chip, "the edit stays in memory")
	check(_registry.save_error != "", "save_error is set")
	check_eq(seen, [_registry.save_error], "chip_storage_error emitted once")
	_registry.update(chip.id, "persist_fail2", "", "p")
	check_eq(seen.size(), 1, "the same error is not repeated")
	_registry.user_path = TMP_PATH
	_registry.update(chip.id, "persist_fail3", "", "p")
	check_eq(_registry.save_error, "", "a good save clears the error")
	check_eq(seen.size(), 2, "recovery is reported")
	check_eq(seen[1], "", "with an empty message")
	autoload("EventBus").chip_storage_error.disconnect(on_error)
	_restore_path()


## The starter prompt reaches installs whose user file still holds an older one.
const OLD_COOLER_V1: String = """You control a Smelter. Working heats it up, and it explodes if it gets too hot.
- If temperature is 70 or higher, call set_cooling with on=true.
- If temperature is 40 or lower, call set_cooling with on=false.
- Otherwise do nothing. A status of "overheating" means you are late: turn the cooling on at once."""
const OLD_COOLER_V2: String = """You control a Smelter. Working heats it up, and it explodes if it gets too hot. Cooling only slows the heating while it works, so pausing is what saves it.
Check the state in this order and call at most one tool:
- If temperature is 110 or higher and enabled is true, call set_enabled with on=false (pause).
- If temperature is 40 or lower and enabled is false, call set_enabled with on=true (resume). Never resume above 40.
- If temperature is 60 or higher and cooling is false, call set_cooling with on=true.
- If temperature is 30 or lower and cooling is true, call set_cooling with on=false.
- Otherwise do nothing. The gaps between 110 and 40, and between 60 and 30, stop it from toggling every turn."""
const OLD_COOLER_V3: String = """You control a Smelter. Working heats it up, and it explodes if it gets too hot. Cooling is the normal way to manage the heat, but crafts take twice as long while it is on, so use it only when needed. Stopping is for emergencies only.
Check the state in this order and call at most one tool:
- If status is "overheating" and enabled is true, call set_enabled with on=false (emergency pause).
- If enabled is false and temperature is 80 or lower, call set_enabled with on=true (resume).
- If temperature is 60 or higher and cooling is false, call set_cooling with on=true.
- If temperature is 40 or lower and cooling is true, call set_cooling with on=false.
- Otherwise do nothing. Never pause for routine temperature control; the gap between 60 and 40 stops cooling from toggling every turn."""


func _save_user_library(smelter_prompt: String, smelter_name: String = "Smelter Cooler") -> void:
	var library: ChipLibrary = ChipLibrary.new()
	for chip: ChipRessource in _registry.get_all():
		var copy: ChipRessource = ChipRessource.new()
		copy.id = chip.id
		copy.name = chip.name
		copy.description = chip.description
		copy.prompt = chip.prompt
		if chip.id == 2:
			copy.name = smelter_name
			copy.prompt = smelter_prompt
		library.chips.append(copy)
	library.next_id = 10
	ResourceSaver.save(library, TMP_PATH)


func test_outdated_starter_prompt_is_replaced_and_saved() -> void:
	_use_tmp_path()
	var shipped: String = _smelter_cooler(_registry.get_all()).prompt
	for old: String in [OLD_COOLER_V1, OLD_COOLER_V2, OLD_COOLER_V3]:
		_save_user_library(old)
		_registry.load_registry()
		check_eq(_registry.get_from_id(2).prompt, shipped, "unedited older prompt upgraded")
		check_eq(_registry.save_error, "", "no error")
		_registry.load_registry()
		check_eq(_registry.get_from_id(2).prompt, shipped, "the upgrade was saved")
	_restore_path()


func test_edited_or_custom_prompts_are_never_overwritten() -> void:
	_use_tmp_path()
	_save_user_library(OLD_COOLER_V2 + "\nMy own rule.")
	_registry.load_registry()
	check_eq(_registry.get_from_id(2).prompt, OLD_COOLER_V2 + "\nMy own rule.", "edited prompt kept")
	_save_user_library(OLD_COOLER_V2, "My cooler")
	_registry.load_registry()
	check_eq(_registry.get_from_id(2).prompt, OLD_COOLER_V2, "a renamed chip with the old text is left alone")
	_save_user_library("custom")
	_registry.load_registry()
	check_eq(_registry.get_from_id(2).prompt, "custom", "custom prompt kept")
	_restore_path()
