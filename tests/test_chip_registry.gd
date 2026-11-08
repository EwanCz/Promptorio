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


## created_by (GR2-18): 0 for a player chip, else the Orchestrator machine_id that generated it with
## create_chip. See ChipRessource.created_by for the ownership rules this enforces.
func test_add_records_created_by() -> void:
	var player_made: ChipRessource = _add("reg_player")
	var generated: ChipRessource = _registry.add("reg_generated", "p", "", 7)
	_ids.append(generated.id)
	check_eq(player_made.created_by, 0, "the default (ChipPage never passes anything else) is a player chip")
	check_eq(generated.created_by, 7, "the Orchestrator's machine_id is recorded on the chip itself")


func test_update_always_clears_created_by() -> void:
	var generated: ChipRessource = _registry.add("reg_claim", "p", "", 7)
	_ids.append(generated.id)
	check(_registry.update(generated.id, "reg_claim", "edited", "edited"), "the player saves an edit")
	check_eq(generated.created_by, 0, "saving through ChipPage claims it: no longer the Orchestrator's to revise")


func test_revise_only_touches_a_chip_this_creator_made() -> void:
	var generated: ChipRessource = _registry.add("reg_revise", "p", "d", 7)
	_ids.append(generated.id)
	var player_made: ChipRessource = _add("reg_not_mine")
	check(not _registry.revise(99999, "x", "x", 7), "unknown id refused")
	check(not _registry.revise(player_made.id, "x", "x", 7), "a player chip is never revised")
	check(not _registry.revise(generated.id, "x", "x", 8), "a different Orchestrator's id is refused")
	check_eq([player_made.prompt, generated.prompt], ["p", "p"], "nothing changed by the refused calls")
	check(_registry.revise(generated.id, "new desc", "new prompt", 7), "the actual creator succeeds")
	check_eq([generated.name, generated.description, generated.prompt], ["reg_revise", "new desc", "new prompt"], "name kept, description/prompt updated")


func test_release_created_by_only_clears_the_matching_creator() -> void:
	var mine: ChipRessource = _registry.add("reg_release_a", "p", "", 7)
	var other: ChipRessource = _registry.add("reg_release_b", "p", "", 8)
	_ids.append_array([mine.id, other.id])
	_registry.release_created_by(7)
	check_eq(mine.created_by, 0, "released")
	check_eq(other.created_by, 8, "a different creator's chip is untouched")


func test_import_chip_carries_created_by() -> void:
	var imported: ChipRessource = _registry.import_chip(555001, "reg_import", "d", "p", 9)
	_ids.append(imported.id)
	check_eq(imported.created_by, 9, "ownership round-trips through a save file import")


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
	check_eq(chips.size(), 4, "four starter chips")
	for chip: ChipRessource in chips:
		check(chip.id > 0 and chip.name != "" and chip.description != "" and chip.prompt != "", "starter chip %s is complete" % chip.name)
	check(not FileAccess.file_exists(TMP_PATH), "loading defaults writes nothing")
	check_eq(_registry.save_error, "", "no error")
	_restore_path()


func test_starter_prompts_only_use_real_tools() -> void:
	_use_tmp_path()
	var known: Array[String] = []
	for scene: String in ["miner", "smelter", "assembler", "orchestrator"]:
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


func test_factory_manager_starter_assigns_miner_pacer() -> void:
	_use_tmp_path()
	var manager: ChipRessource = _registry.get_from_id(4)
	check(manager != null and manager.name == "Factory Manager", "manager is in the default registry")
	if manager != null:
		check(manager.prompt.contains("assign_chip") and manager.prompt.contains("Miner Pacer"), "prompt assigns the existing Miner chip")
		check(manager.prompt.contains("Do not remove or replace"), "prompt preserves other assignments")
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
	check(prompt.contains("state does not say why it was disabled") and prompt.contains("keep it disabled"), "unknown pauses are left alone without assuming their cause")
	check(prompt.contains("never set_enabled"), "it does not use the plain pause")
	var cool_on: int = 100
	var cool_off: int = 70
	var emergency_stop_at: int = 130
	for number: int in [cool_on, cool_off, emergency_stop_at, int(Smelter.SAFE_AT)]:
		check(prompt.contains(str(number)), "prompt states %d" % number)
	check(prompt.contains("temperature is 130 or higher") and not prompt.contains("status is \"overheating\""), "emergency stop is delayed beyond the OVERHEATING status")
	check(prompt.contains("Never pause for routine temperature control"), "no routine pausing")
	check(cool_off < cool_on and cool_on == Smelter.OVERHEAT_AT and emergency_stop_at < Smelter.EXPLODE_AT, "cooling starts at overheating and emergency stop precedes explosion")
	_restore_path()


## A Smelter heats at HEAT_PER_TICK while working continuously (0.6/tick), and the shipped Cooler only
## starts cooling at 100deg, 50deg below EXPLODE_AT (150). The component's own default timeout (100 ticks,
## 10s) alone lets temperature climb 60deg between two polls, more than that margin, so the registry ships
## this chip with a tighter default_timeout instead (see ChipRessource.default_timeout).
func test_smelter_cooler_ships_with_a_safe_default_timeout() -> void:
	_use_tmp_path()
	var cooler: ChipRessource = _smelter_cooler(_registry.get_all())
	check(cooler.default_timeout > 0 and cooler.default_timeout < ChipComponent.DEFAULT_TIMEOUT, "tighter than the component default")
	var margin: float = Smelter.EXPLODE_AT - Smelter.OVERHEAT_AT
	check(cooler.default_timeout * Smelter.HEAT_PER_TICK < margin, "one full poll interval heats less than the cooling margin")
	var smelter: Machine = load("res://scenes/machines/smelter.tscn").instantiate()
	tree.root.add_child(smelter)
	var component: ChipComponent = smelter.attach_chip(cooler.id)
	check_eq(component.timeout, cooler.default_timeout, "a fresh attachment from the registry starts at the safe default, not the component's")
	smelter.free()
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
	check_eq(_registry.get_all().size(), 4, "4 defaults - 1 removed + 1 added")
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
	check_eq(_registry.get_all().size(), 4, "defaults loaded")
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
const OLD_MINER: String = """You control a Miner. Every decision, check the state.
- If "blocked" is true (ore is waiting for a free output), call set_mine_ticks with 40 so it slows down.
- If "blocked" is false and mine_ticks is above 10, call set_mine_ticks with 10 to mine faster.
- Otherwise do nothing. Call at most one tool."""
const OLD_MINER_PACER: String = """You control a Miner. Every decision, check the state and the allowed range of set_mine_ticks for the current resource.
- If blocked is true and mine_ticks is below the allowed maximum, set it to that maximum.
- If blocked is false and mine_ticks is above the allowed minimum, set it to that minimum.
- Otherwise do nothing. Call at most one tool."""
const OLD_ASSEMBLER_STOCKER: String = """You control an Assembler. It needs several inputs, so a small stock keeps one item from starving the others.
- If status is not "normal", do nothing.
- If stock_limit is above 6, call set_stock_limit with 6.
- Otherwise do nothing."""
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
const OLD_COOLER_V4: String = """You control a Smelter. Working heats it up, and it explodes if it gets too hot. Cooling is the normal way to manage the heat, but crafts take twice as long while it is on, so use it only when needed. Stopping is for emergencies only, and it is done with set_emergency_stop, never set_enabled.
Check the state in this order and call at most one tool:
- If status is "overheating" and enabled is true, call set_emergency_stop with on=true (emergency pause).
- If emergency_stop is true and temperature is 80 or lower, call set_emergency_stop with on=false (resume). Only resume your own emergency stop: if enabled is false but emergency_stop is false, another chip paused the smelter on purpose, so leave it disabled.
- If temperature is 60 or higher and cooling is false, call set_cooling with on=true.
- If temperature is 40 or lower and cooling is true, call set_cooling with on=false.
- Otherwise do nothing. Never pause for routine temperature control; the gap between 60 and 40 stops cooling from toggling every turn."""


const OLD_COOLER_V5: String = """You control a Smelter. Working heats it up, and it explodes if it gets too hot. Cooling is the normal way to manage the heat, but crafts take twice as long while it is on, so use it only when needed. Stopping is for emergencies only, and it is done with set_emergency_stop, never set_enabled.
Check the state in this order and call at most one tool:
- If temperature is 130 or higher and enabled is true, call set_emergency_stop with on=true (emergency pause).
- If emergency_stop is true and temperature is 80 or lower, call set_emergency_stop with on=false (resume your emergency pause). If enabled is false while emergency_stop is false, keep it disabled; the state does not say why it was disabled.
- If temperature is 100 or higher and cooling is false, call set_cooling with on=true.
- If temperature is 70 or lower and cooling is true, call set_cooling with on=false.
- Otherwise do nothing. Never pause for routine temperature control; the gap between 100 and 70 stops cooling from toggling every turn."""


func _save_user_library(smelter_prompt: String, smelter_name: String = "Smelter Cooler", miner_prompt: String = "", assembler_prompt: String = "", assembler_name: String = "Assembler Stocker") -> void:
	var library: ChipLibrary = ChipLibrary.new()
	for chip: ChipRessource in _registry.get_all():
		var copy: ChipRessource = ChipRessource.new()
		copy.id = chip.id
		copy.name = chip.name
		copy.description = chip.description
		copy.prompt = chip.prompt
		if chip.id == 1 and miner_prompt != "":
			copy.prompt = miner_prompt
		if chip.id == 2:
			copy.name = smelter_name
			copy.prompt = smelter_prompt
		if chip.id == 3 and assembler_prompt != "":
			copy.name = assembler_name
			copy.prompt = assembler_prompt
		library.chips.append(copy)
	library.next_id = 10
	ResourceSaver.save(library, TMP_PATH)


func test_miner_starter_upgrade_respects_resource_limits_and_custom_edits() -> void:
	_use_tmp_path()
	var shipped: String = _registry.get_from_id(1).prompt
	var smelter_prompt: String = _registry.get_from_id(2).prompt
	check(shipped.contains("allowed minimum") and shipped.contains("current resource"), "starter follows the current resource's tool range")
	_save_user_library(smelter_prompt, "Smelter Cooler", OLD_MINER)
	_registry.load_registry()
	check_eq(_registry.get_from_id(1).prompt, shipped, "unedited old Miner starter upgraded")
	_save_user_library(smelter_prompt, "Smelter Cooler", OLD_MINER + "\nMy own rule.")
	_registry.load_registry()
	check_eq(_registry.get_from_id(1).prompt, OLD_MINER + "\nMy own rule.", "custom Miner prompt kept")
	_restore_path()


func test_updated_machine_starters_upgrade_only_unedited_saved_prompts() -> void:
	_use_tmp_path()
	var miner: String = _registry.get_from_id(1).prompt
	var smelter: String = _registry.get_from_id(2).prompt
	var assembler: String = _registry.get_from_id(3).prompt
	check(miner.contains("start_prospecting") and miner.contains("blocked") and miner.contains("mode is prospecting or boost"), "Miner starter handles prospecting and blockage")
	check(assembler.contains("set_mode") and assembler.contains("twice each quantity in needs"), "Assembler starter considers fast mode inputs")
	check(assembler.contains("needs reflects the selected mode") and assembler.contains("set_stock_limit"), "Assembler starter accounts for scaled needs and retains its stock policy")
	_save_user_library(smelter, "Smelter Cooler", OLD_MINER_PACER, OLD_ASSEMBLER_STOCKER)
	_registry.load_registry()
	check_eq(_registry.get_from_id(1).prompt, miner, "unedited Miner prompt upgraded")
	check_eq(_registry.get_from_id(3).prompt, assembler, "unedited Assembler prompt upgraded")
	_registry.load_registry()
	check_eq(_registry.get_from_id(1).prompt, miner, "Miner upgrade persisted")
	check_eq(_registry.get_from_id(3).prompt, assembler, "Assembler upgrade persisted")
	_save_user_library(smelter, "Smelter Cooler", OLD_MINER_PACER + "\nMy rule.", OLD_ASSEMBLER_STOCKER + "\nMy rule.")
	_registry.load_registry()
	check_eq(_registry.get_from_id(1).prompt, OLD_MINER_PACER + "\nMy rule.", "edited Miner prompt kept")
	check_eq(_registry.get_from_id(3).prompt, OLD_ASSEMBLER_STOCKER + "\nMy rule.", "edited Assembler prompt kept")
	_save_user_library(smelter, "Smelter Cooler", "", OLD_ASSEMBLER_STOCKER, "My assembler")
	_registry.load_registry()
	check_eq(_registry.get_from_id(3).prompt, OLD_ASSEMBLER_STOCKER, "renamed Assembler prompt kept")
	_restore_path()


func test_outdated_starter_prompt_is_replaced_and_saved() -> void:
	_use_tmp_path()
	var shipped: String = _smelter_cooler(_registry.get_all()).prompt
	for old: String in [OLD_COOLER_V1, OLD_COOLER_V2, OLD_COOLER_V3, OLD_COOLER_V4, OLD_COOLER_V5]:
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
