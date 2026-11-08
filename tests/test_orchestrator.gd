extends "res://tests/test_case.gd"
## Orchestrator (GR2-16): assigns/removes existing registry chips on nearby machines, protects
## player-made (and other Orchestrators') assignments, and gates everything by range.

const SCENES: Dictionary = {
	"orchestrator": "res://scenes/machines/orchestrator.tscn",
	"miner": "res://scenes/machines/miner.tscn",
	"collector": "res://scenes/machines/collector.tscn",
}

var _game: Node
var _registry: Node
var _nodes: Array[Node] = []
var _chip_ids: Array[int] = []


func before_each() -> void:
	_game = autoload("GameState")
	_registry = autoload("ChipRegistry")


func after_each() -> void:
	for node: Node in _nodes:
		node.free()
	_nodes.clear()
	for id: int in _chip_ids:
		_registry.remove(id)
	_chip_ids.clear()


func _put(type: String, cell: Vector2i, id: int) -> Machine:
	var machine: Machine = (load(SCENES[type]) as PackedScene).instantiate() as Machine
	machine.cell = cell
	machine.machine_id = id
	tree.root.add_child(machine)
	_game.register_machine(machine, cell)
	_nodes.append(machine)
	return machine


func _chip(chip_name: String) -> ChipRessource:
	var chip: ChipRessource = _registry.add(chip_name, "p")
	_chip_ids.append(chip.id)
	return chip


## The chip create_chip() just added to the registry, found by name (create_chip only returns a bool).
func _created(chip_name: String) -> ChipRessource:
	for chip: ChipRessource in _registry.get_all():
		if chip.name == chip_name:
			_chip_ids.append(chip.id)
			return chip
	return null


## Feeds `component` `count` decisions of the given outcome ("applied", "none" or "failed"), the evidence
## revise_chip weighs. Goes through the public LLMManager signals, same as a real answer arriving.
func _give_evidence(component: ChipComponent, count: int, outcome: String) -> void:
	var llm: Node = autoload("LLMManager")
	for i: int in count:
		if outcome == "failed":
			llm.decision_failed.emit(component.get_instance_id(), "HTTP 500")
		elif outcome == "none":
			llm.decision_received.emit(component.get_instance_id(), [] as Array[Dictionary])
		else:
			llm.decision_received.emit(component.get_instance_id(), [{"name": "set_enabled", "args": {"on": true}}] as Array[Dictionary])


func test_default_range_and_nearby_machines_listed() -> void:
	var orchestrator: Orchestrator = _put("orchestrator", Vector2i(10, 10), 1) as Orchestrator
	check_eq(orchestrator.range_cells, Orchestrator.DEFAULT_RANGE, "default range")
	var near: Machine = _put("miner", Vector2i(11, 10), 2)
	var far: Machine = _put("miner", Vector2i(10 + Orchestrator.DEFAULT_RANGE + 1, 10), 3)
	var state: Dictionary = orchestrator.get_state()
	var ids: Array = (state["nearby_machines"] as Array).map(func(entry: Dictionary) -> int: return entry["machine_id"])
	check(ids.has(near.machine_id), "a machine within range is listed")
	check(not ids.has(far.machine_id), "a machine outside range is not listed")
	check(not ids.has(orchestrator.machine_id), "the Orchestrator does not list itself")


func test_nearby_machine_state_exposes_the_miner_mode_generically() -> void:
	var orchestrator: Orchestrator = _put("orchestrator", Vector2i(5, 5), 1) as Orchestrator
	var miner: Miner = _put("miner", Vector2i(6, 5), 2) as Miner
	miner.start_prospecting()
	var state: Dictionary = orchestrator.get_state()
	var entry: Dictionary = (state["nearby_machines"] as Array).filter(func(m: Dictionary) -> bool: return m["machine_id"] == miner.machine_id)[0]
	check_eq((entry["state"] as Dictionary)["mode"], "prospecting", "the Orchestrator sees the Miner's mode without any special case")


func test_assign_chip_attaches_it_and_marks_ownership() -> void:
	var orchestrator: Orchestrator = _put("orchestrator", Vector2i(5, 5), 1) as Orchestrator
	var miner: Machine = _put("miner", Vector2i(6, 5), 2)
	var chip: ChipRessource = _chip("production")
	check(orchestrator.apply_tool_call("assign_chip", {"machine_id": miner.machine_id, "chip_id": chip.id}), "assignment applied")
	var component: ChipComponent = miner.get_chip(chip.id)
	check(component != null, "the chip is attached")
	check_eq(component.assigned_by, orchestrator.machine_id, "ownership recorded")


func test_remove_chip_detaches_an_owned_assignment() -> void:
	var orchestrator: Orchestrator = _put("orchestrator", Vector2i(5, 5), 1) as Orchestrator
	var miner: Machine = _put("miner", Vector2i(6, 5), 2)
	var chip: ChipRessource = _chip("production")
	orchestrator.assign_chip(miner.machine_id, chip.id)
	check(orchestrator.apply_tool_call("remove_chip", {"machine_id": miner.machine_id}), "removal applied")
	check(miner.get_chip(chip.id) == null, "the chip is gone")


func test_assign_refused_outside_range() -> void:
	var orchestrator: Orchestrator = _put("orchestrator", Vector2i(5, 5), 1) as Orchestrator
	var far: Machine = _put("miner", Vector2i(5 + Orchestrator.DEFAULT_RANGE + 1, 5), 2)
	var chip: ChipRessource = _chip("production")
	check(not orchestrator.assign_chip(far.machine_id, chip.id), "out of range is refused")
	check(far.get_chip(chip.id) == null, "nothing attached")


func test_assign_refused_for_unknown_chip_id() -> void:
	var orchestrator: Orchestrator = _put("orchestrator", Vector2i(5, 5), 1) as Orchestrator
	var miner: Machine = _put("miner", Vector2i(6, 5), 2)
	check(not orchestrator.assign_chip(miner.machine_id, 999999), "unknown chip refused")
	check(miner.chips.is_empty(), "nothing attached")


func test_player_made_assignment_is_never_overridden_or_removable() -> void:
	var orchestrator: Orchestrator = _put("orchestrator", Vector2i(5, 5), 1) as Orchestrator
	var miner: Machine = _put("miner", Vector2i(6, 5), 2)
	var player_chip: ChipRessource = _chip("player_made")
	miner.attach_chip(player_chip.id)
	var other_chip: ChipRessource = _chip("other")
	check(not orchestrator.remove_chip(miner.machine_id), "cannot remove a player-made assignment")
	check(miner.get_chip(player_chip.id) != null, "the player's chip is untouched")
	check(orchestrator.assign_chip(miner.machine_id, other_chip.id), "a separate assignment of its own is still allowed")
	check(miner.get_chip(player_chip.id) != null, "the player's chip is still there")
	check(miner.get_chip(other_chip.id).assigned_by == orchestrator.machine_id, "its own chip is owned by it")


func test_overlapping_orchestrator_cannot_touch_an_assignment_it_does_not_own() -> void:
	var first: Orchestrator = _put("orchestrator", Vector2i(5, 5), 1) as Orchestrator
	var second: Orchestrator = _put("orchestrator", Vector2i(7, 5), 2) as Orchestrator
	var miner: Machine = _put("miner", Vector2i(6, 5), 3)
	var first_ids: Array = (first.get_state()["nearby_machines"] as Array).map(func(m: Dictionary) -> int: return m["machine_id"])
	var second_ids: Array = (second.get_state()["nearby_machines"] as Array).map(func(m: Dictionary) -> int: return m["machine_id"])
	check(first_ids.has(miner.machine_id) and second_ids.has(miner.machine_id), "both see the same machine")
	var chip: ChipRessource = _chip("production")
	check(first.assign_chip(miner.machine_id, chip.id), "the first Orchestrator claims it")
	check(not second.assign_chip(miner.machine_id, _chip("backup").id), "the second is refused: already owned")
	check(not second.remove_chip(miner.machine_id), "the second cannot remove it either")
	check_eq(miner.get_chip(chip.id).assigned_by, first.machine_id, "ownership stays with the first")


func test_orchestrators_do_not_list_or_manage_each_other() -> void:
	var first: Orchestrator = _put("orchestrator", Vector2i(5, 5), 1) as Orchestrator
	var second: Orchestrator = _put("orchestrator", Vector2i(6, 5), 2) as Orchestrator
	var state: Dictionary = first.get_state()
	var ids: Array = (state["nearby_machines"] as Array).map(func(m: Dictionary) -> int: return m["machine_id"])
	check(not ids.has(second.machine_id), "an Orchestrator does not list another Orchestrator, even in range")
	check(not first.assign_chip(second.machine_id, _chip("production").id), "and cannot assign a chip to it either")


func test_reassigning_replaces_its_own_previous_chip() -> void:
	var orchestrator: Orchestrator = _put("orchestrator", Vector2i(5, 5), 1) as Orchestrator
	var miner: Machine = _put("miner", Vector2i(6, 5), 2)
	var first_chip: ChipRessource = _chip("first")
	var second_chip: ChipRessource = _chip("second")
	orchestrator.assign_chip(miner.machine_id, first_chip.id)
	check(orchestrator.assign_chip(miner.machine_id, second_chip.id), "reassignment succeeds")
	check(miner.get_chip(first_chip.id) == null, "the old chip is gone")
	check(miner.get_chip(second_chip.id) != null, "the new chip is attached")
	check_eq(miner.chips.size(), 1, "only one chip owned by this Orchestrator at a time")


func test_repeated_and_rejected_assignments_preserve_existing_chip() -> void:
	var orchestrator: Orchestrator = _put("orchestrator", Vector2i(5, 5), 1) as Orchestrator
	var miner: Machine = _put("miner", Vector2i(6, 5), 2)
	var owned: ChipRessource = _chip("owned")
	var manual: ChipRessource = _chip("manual")
	miner.attach_chip(manual.id)
	orchestrator.assign_chip(miner.machine_id, owned.id)
	var component: ChipComponent = miner.get_chip(owned.id)
	component.set_timeout(42)
	component.pending = true
	check(orchestrator.assign_chip(miner.machine_id, owned.id), "repeated assignment succeeds")
	check(miner.get_chip(owned.id) == component and component.pending and component.timeout == 42, "same component and pending request retained")
	check(not orchestrator.assign_chip(miner.machine_id, manual.id), "player chip cannot be reassigned")
	check(miner.get_chip(owned.id) == component and miner.get_chip(manual.id) != null, "rejected replacement leaves both chips intact")


func test_open_tooltip_tracks_automatic_assignments() -> void:
	var orchestrator: Orchestrator = _put("orchestrator", Vector2i(5, 5), 1) as Orchestrator
	var miner: Machine = _put("miner", Vector2i(6, 5), 2)
	var chip: ChipRessource = _chip("tooltip_chip")
	var tooltip: MachineTooltip = load("res://scenes/ui/popups/machine_tooltip.tscn").instantiate() as MachineTooltip
	tree.root.add_child(tooltip)
	_nodes.append(tooltip)
	tooltip.open(miner)
	check_eq(tooltip.get_node("%ChipsList").get_child_count(), 0, "starts empty")
	orchestrator.assign_chip(miner.machine_id, chip.id)
	check_eq(tooltip.get_node("%ChipsList").get_child_count(), 1, "automatic assignment appears immediately")
	orchestrator.remove_chip(miner.machine_id)
	check_eq(tooltip.get_node("%ChipsList").get_child_count(), 0, "automatic removal clears the row")
	tooltip.close()


func test_shrinking_range_blocks_managing_an_owned_machine_until_it_grows_back() -> void:
	var orchestrator: Orchestrator = _put("orchestrator", Vector2i(5, 5), 1) as Orchestrator
	var miner: Machine = _put("miner", Vector2i(7, 5), 2)
	var chip: ChipRessource = _chip("production")
	check(orchestrator.assign_chip(miner.machine_id, chip.id), "in range at first")
	check(orchestrator.apply_tool_call("set_range", {"cells": 1}), "range shrinks")
	check(not orchestrator.remove_chip(miner.machine_id), "now out of range: cannot even remove its own assignment")
	check_eq(miner.get_chip(chip.id).assigned_by, orchestrator.machine_id, "ownership is unaffected by the range change")
	check(orchestrator.apply_tool_call("set_range", {"cells": 4}), "range grows back")
	check(orchestrator.remove_chip(miner.machine_id), "managing it again now that it is back in range")


func test_discard_releases_every_assignment_it_owns() -> void:
	var orchestrator: Orchestrator = _put("orchestrator", Vector2i(5, 5), 1) as Orchestrator
	var miner: Machine = _put("miner", Vector2i(6, 5), 2)
	var chip: ChipRessource = _chip("production")
	orchestrator.assign_chip(miner.machine_id, chip.id)
	_nodes.erase(orchestrator)
	orchestrator.discard()
	check(miner.get_chip(chip.id) != null, "the chip stays attached and running")
	check_eq(miner.get_chip(chip.id).assigned_by, 0, "but ownership is released")


func test_assign_refused_when_the_chip_was_removed_from_the_registry_mid_flight() -> void:
	var orchestrator: Orchestrator = _put("orchestrator", Vector2i(5, 5), 1) as Orchestrator
	var miner: Machine = _put("miner", Vector2i(6, 5), 2)
	var chip: ChipRessource = _chip("production")
	var stale_id: int = chip.id
	_registry.remove(stale_id)
	_chip_ids.erase(stale_id)
	check(not orchestrator.apply_tool_call("assign_chip", {"machine_id": miner.machine_id, "chip_id": stale_id}), "stale chip id refused at apply time")
	check(miner.chips.is_empty(), "nothing attached")


func test_removing_the_target_machine_leaves_assignment_calls_harmless() -> void:
	var orchestrator: Orchestrator = _put("orchestrator", Vector2i(5, 5), 1) as Orchestrator
	var miner: Machine = _put("miner", Vector2i(6, 5), 2)
	var chip: ChipRessource = _chip("production")
	var stale_id: int = miner.machine_id
	_nodes.erase(miner)
	miner.destroy()
	check(not orchestrator.apply_tool_call("assign_chip", {"machine_id": stale_id, "chip_id": chip.id}), "no crash, just refused")
	check(not orchestrator.apply_tool_call("remove_chip", {"machine_id": stale_id}), "same for removal")


func test_range_and_ownership_persist_across_save_and_load() -> void:
	var orchestrator: Orchestrator = _put("orchestrator", Vector2i(5, 5), 1) as Orchestrator
	var miner: Machine = _put("miner", Vector2i(6, 5), 2)
	var chip: ChipRessource = _chip("production")
	orchestrator.assign_chip(miner.machine_id, chip.id)
	orchestrator.apply_tool_call("set_range", {"cells": 6})
	var saved_orchestrator: Dictionary = orchestrator.to_dict()
	var saved_miner: Dictionary = miner.to_dict()
	_nodes.erase(orchestrator)
	_nodes.erase(miner)
	orchestrator.free()
	miner.free()
	var restored_orchestrator: Orchestrator = _put("orchestrator", Vector2i(20, 20), 1) as Orchestrator
	var restored_miner: Machine = _put("miner", Vector2i(21, 20), 2)
	restored_orchestrator.load_dict(saved_orchestrator)
	restored_miner.load_dict(saved_miner)
	check_eq(restored_orchestrator.range_cells, 6, "range restored")
	var component: ChipComponent = restored_miner.get_chip(chip.id)
	check(component != null, "the assigned chip is restored")
	check_eq(component.assigned_by, restored_orchestrator.machine_id, "ownership restored by matching machine id")


## GR2-18: creating and revising its own chips.

func test_create_chip_adds_to_the_registry_owned_by_this_orchestrator() -> void:
	var orchestrator: Orchestrator = _put("orchestrator", Vector2i(5, 5), 1) as Orchestrator
	check(orchestrator.apply_tool_call("create_chip", {"name": "generated", "description": "d", "prompt": "p"}), "creation applied")
	var created: ChipRessource = _created("generated")
	check(created != null, "the chip exists in the registry")
	check_eq(created.created_by, orchestrator.machine_id, "ownership recorded on the chip resource")
	check_eq(created.prompt, "p", "prompt stored")
	var available: Array = orchestrator.get_state()["available_chips"]
	var mine: Array = available.filter(func(entry: Dictionary) -> bool: return entry["id"] == created.id and entry["mine"])
	check_eq(mine.size(), 1, "available_chips marks it mine")


func test_create_chip_refused_for_empty_or_duplicate_name() -> void:
	var orchestrator: Orchestrator = _put("orchestrator", Vector2i(5, 5), 1) as Orchestrator
	check(not orchestrator.create_chip("", "d", "p"), "empty name refused")
	_chip("dup_name")
	check(not orchestrator.create_chip("dup_name", "d", "p"), "duplicate name refused")


func test_created_chip_can_be_assigned_like_any_other() -> void:
	var orchestrator: Orchestrator = _put("orchestrator", Vector2i(5, 5), 1) as Orchestrator
	var miner: Machine = _put("miner", Vector2i(6, 5), 2)
	check(orchestrator.create_chip("generated_assign", "d", "p"), "created")
	var created: ChipRessource = _created("generated_assign")
	check(orchestrator.assign_chip(miner.machine_id, created.id), "assignable like any registry chip")
	check_eq(miner.get_chip(created.id).assigned_by, orchestrator.machine_id, "assignment ownership recorded too")


func test_revise_chip_refused_without_enough_evidence() -> void:
	var orchestrator: Orchestrator = _put("orchestrator", Vector2i(5, 5), 1) as Orchestrator
	var miner: Machine = _put("miner", Vector2i(6, 5), 2)
	orchestrator.create_chip("revise_target", "d", "p")
	var chip: ChipRessource = _created("revise_target")
	orchestrator.assign_chip(miner.machine_id, chip.id)
	_give_evidence(miner.get_chip(chip.id), Orchestrator.MIN_REVISION_EVIDENCE - 1, "failed")
	check(not orchestrator.revise_chip(chip.id, "new d", "new p"), "not enough evidence yet")
	check_eq(chip.prompt, "p", "prompt unchanged")


func test_revise_chip_succeeds_with_enough_evidence_and_keeps_the_name() -> void:
	var orchestrator: Orchestrator = _put("orchestrator", Vector2i(5, 5), 1) as Orchestrator
	var miner: Machine = _put("miner", Vector2i(6, 5), 2)
	orchestrator.create_chip("revise_ok", "d", "p")
	var chip: ChipRessource = _created("revise_ok")
	orchestrator.assign_chip(miner.machine_id, chip.id)
	_give_evidence(miner.get_chip(chip.id), Orchestrator.MIN_REVISION_EVIDENCE, "failed")
	check(orchestrator.revise_chip(chip.id, "new d", "new p"), "revision applied")
	check_eq(chip.name, "revise_ok", "name unchanged")
	check_eq(chip.description, "new d", "description updated")
	check_eq(chip.prompt, "new p", "prompt updated")


func test_revise_chip_refused_during_cooldown_right_after_a_revision() -> void:
	var orchestrator: Orchestrator = _put("orchestrator", Vector2i(5, 5), 1) as Orchestrator
	var miner: Machine = _put("miner", Vector2i(6, 5), 2)
	orchestrator.create_chip("revise_cooldown", "d", "p")
	var chip: ChipRessource = _created("revise_cooldown")
	orchestrator.assign_chip(miner.machine_id, chip.id)
	var component: ChipComponent = miner.get_chip(chip.id)
	_give_evidence(component, Orchestrator.MIN_REVISION_EVIDENCE, "failed")
	check(orchestrator.revise_chip(chip.id, "new d", "new p"), "first revision applied")
	_give_evidence(component, Orchestrator.MIN_REVISION_EVIDENCE, "failed")
	check(not orchestrator.revise_chip(chip.id, "again", "again"), "too soon after the last revision")
	check_eq(chip.prompt, "new p", "the first revision's prompt stands")


func test_revise_chip_refused_for_a_chip_it_did_not_create() -> void:
	var orchestrator: Orchestrator = _put("orchestrator", Vector2i(5, 5), 1) as Orchestrator
	var miner: Machine = _put("miner", Vector2i(6, 5), 2)
	var player_chip: ChipRessource = _chip("player_owned_prompt")
	miner.attach_chip(player_chip.id)
	_give_evidence(miner.get_chip(player_chip.id), Orchestrator.MIN_REVISION_EVIDENCE, "failed")
	check(not orchestrator.revise_chip(player_chip.id, "new d", "new p"), "a player-authored chip is never revised")
	check_eq(player_chip.prompt, "p", "untouched")


func test_player_edit_claims_a_generated_chip_from_further_revision() -> void:
	var orchestrator: Orchestrator = _put("orchestrator", Vector2i(5, 5), 1) as Orchestrator
	var miner: Machine = _put("miner", Vector2i(6, 5), 2)
	orchestrator.create_chip("claimed", "d", "p")
	var chip: ChipRessource = _created("claimed")
	orchestrator.assign_chip(miner.machine_id, chip.id)
	_give_evidence(miner.get_chip(chip.id), Orchestrator.MIN_REVISION_EVIDENCE, "failed")
	check(_registry.update(chip.id, "claimed", "edited by player", "edited prompt"), "the player saves an edit")
	check_eq(chip.created_by, 0, "ownership released to the player")
	check(not orchestrator.revise_chip(chip.id, "attempted", "attempted"), "the Orchestrator can no longer revise it")
	check_eq(chip.prompt, "edited prompt", "the player's edit stands")


func test_discard_releases_created_chips_too() -> void:
	var orchestrator: Orchestrator = _put("orchestrator", Vector2i(5, 5), 1) as Orchestrator
	orchestrator.create_chip("released_on_discard", "d", "p")
	var chip: ChipRessource = _created("released_on_discard")
	_nodes.erase(orchestrator)
	orchestrator.discard()
	check_eq(chip.created_by, 0, "no longer locked to the deleted Orchestrator")


func test_assign_remove_create_revise_flash_the_management_icon() -> void:
	var orchestrator: Orchestrator = _put("orchestrator", Vector2i(5, 5), 1) as Orchestrator
	var miner: Machine = _put("miner", Vector2i(6, 5), 2)
	orchestrator.indicator.result_seconds = 999.0
	miner.indicator.result_seconds = 999.0
	check(orchestrator.create_chip("flash_created", "d", "p"), "created")
	check_eq(orchestrator.indicator.state, "managed_created", "flash on itself for a creation")
	var chip: ChipRessource = _created("flash_created")
	check(orchestrator.assign_chip(miner.machine_id, chip.id), "assigned")
	check_eq(miner.indicator.state, "managed_assigned", "flash on the target for an assignment")
	_give_evidence(miner.get_chip(chip.id), Orchestrator.MIN_REVISION_EVIDENCE, "failed")
	check(orchestrator.revise_chip(chip.id, "d2", "p2"), "revised")
	check_eq(miner.indicator.state, "managed_revised", "flash on the machine running the revised chip")
	check(orchestrator.remove_chip(miner.machine_id), "removed")
	check_eq(miner.indicator.state, "managed_removed", "flash on the target for a removal")
