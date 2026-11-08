class_name Orchestrator
extends Machine
## Late-game, expensive machine whose own chip (re)assigns existing registry chips to other machines
## within range, instead of running production itself. It never edits a chip's prompt and never calls a
## tool on another machine directly: assign_chip/remove_chip only attach/detach a registry chip through
## the same Machine.attach_chip()/detach_chip() the tooltip uses. An assigned chip then runs on its own:
## its own timer, cooldown and decisions, same as any chip the player attaches by hand.
##
## It only manages ordinary machines, never another Orchestrator: besides keeping the scope to production
## machines, it also avoids two Orchestrators within range of each other recursing into one another's
## nearby_machines when their chip asks for state.
##
## Ownership: a ChipComponent's `assigned_by` (0 for a player attachment, else the Orchestrator's own
## machine_id) is the only bookkeeping kept. assign_chip/remove_chip only ever touch a component this
## Orchestrator owns (assigned_by == machine_id); a component with assigned_by == 0 (player-made) or a
## different Orchestrator's id is never touched, so a manual assignment is never silently overridden and
## at most one Orchestrator owns a given machine's assignment at a time. Range gates both tools: a machine
## that falls outside the current range cannot be assigned to or removed from (even one this Orchestrator
## already owns) until it is back in range, but ownership itself is unaffected by a range change, only by
## an explicit remove_chip or this Orchestrator being destroyed (discard() releases everything it owns,
## leaving the chip attached and running, free for a player or another Orchestrator to manage next).
##
## Example for playtesting: COST (150), DEFAULT_RANGE (4 cells) and the range bounds all need playtesting,
## not fixed.
##
## GR2-18 (create/revise): create_chip puts a brand new chip in the registry, created_by set to this
## Orchestrator (ChipRessource.created_by), ready to assign_chip like any other. revise_chip edits the
## prompt/description of a chip it created, gated by evidence (outcome_counts() of every machine in range
## currently running it) and a per-chip cooldown (_last_revision_tick), so it cannot thrash a prompt back
## and forth on a handful of decisions. Both tools only ever touch a chip with created_by == machine_id: a
## player-authored chip, or one made by a different Orchestrator, is never revised (ChipRegistry.revise()
## refuses it too, so this is belt and suspenders). A player who edits a generated chip by hand
## (ChipRegistry.update(), the ChipPage "Save" path) claims it: created_by resets to 0 and this Orchestrator
## never revises it again. EVIDENCE/COOLDOWN constants need playtesting, same as COST/DEFAULT_RANGE.

## Chebyshev distance (the largest of the two axis deltas), so the visible area is a square around it.
const RANGE_MIN: int = 1
const RANGE_MAX: int = 8
const DEFAULT_RANGE: int = 4
## Marks the art as "not an ordinary production machine"; no new art asset for this prototype.
const TINT: Color = Color(0.68, 0.58, 0.95)
## Decisions (outcome_counts() total) a created chip needs, summed over every machine in range currently
## running it, before revise_chip accepts a change: enough to see a pattern, not just one bad answer.
const MIN_REVISION_EVIDENCE: int = 5
## Ticks (10 Hz) a just-revised chip is left alone before this Orchestrator may revise it again.
const REVISION_COOLDOWN_TICKS: int = 300

## How many cells away, in every direction, this Orchestrator can see and manage machines.
var range_cells: int = DEFAULT_RANGE
## chip_id -> the tick revise_chip last succeeded on it. Not saved: a reload may let a revision happen
## sooner than the cooldown would otherwise allow, a minor restart quirk rather than a real exploit.
var _last_revision_tick: Dictionary = {}


func _ready() -> void:
	super._ready()
	if _sprite != null:
		_sprite.modulate = TINT


func can_rotate() -> bool:
	return false


func honors_enabled() -> bool:
	return false


func get_state() -> Dictionary:
	var nearby: Array = []
	for node: Node in GameState.get_machines():
		var other: Machine = node as Machine
		if other == null or not _is_manageable(other):
			continue
		nearby.append(_summary(other))
	var available_chips: Array = []
	for chip: ChipRessource in ChipRegistry.get_all():
		available_chips.append({
			"id": chip.id, "name": chip.name, "description": chip.description,
			"mine": chip.created_by == machine_id,
		})
	return super.get_state().merged({
		"range": range_cells,
		"nearby_machines": nearby,
		"available_chips": available_chips,
	})


func _own_tool_schemas() -> Array:
	return [{
		"name": "assign_chip",
		"description": "Assign a chip from the registry (available_chips) to a machine within range (machine_id from nearby_machines). Replaces any chip this Orchestrator previously assigned to that machine. Refused if the machine is out of range, its assignment is already owned by another Orchestrator, the chip id is unknown, or that chip is already attached to it.",
		"input_schema": {"type": "object", "properties": {
			"machine_id": {"type": "integer", "minimum": 1, "maximum": 2147483647},
			"chip_id": {"type": "integer", "minimum": 1, "maximum": 2147483647},
		}},
	}, {
		"name": "remove_chip",
		"description": "Remove the chip this Orchestrator assigned to a machine within range. Refused if this Orchestrator manages no chip there: a player-made assignment (or one owned by another Orchestrator) is never touched.",
		"input_schema": {"type": "object", "properties": {
			"machine_id": {"type": "integer", "minimum": 1, "maximum": 2147483647},
		}},
	}, {
		"name": "set_range",
		"description": "Change how many cells away (Chebyshev distance) this Orchestrator can see and manage machines, %d..%d." % [RANGE_MIN, RANGE_MAX],
		"input_schema": {"type": "object", "properties": {
			"cells": {"type": "integer", "minimum": RANGE_MIN, "maximum": RANGE_MAX},
		}},
	}, {
		"name": "create_chip",
		"description": "Create a new chip in the registry (not yet assigned anywhere), owned by this Orchestrator. Refused if the name is empty or already used by another chip. Use assign_chip next to put it to work.",
		"input_schema": {"type": "object", "properties": {
			"name": {"type": "string"},
			"description": {"type": "string"},
			"prompt": {"type": "string"},
		}},
	}, {
		"name": "revise_chip",
		"description": "Rewrite the description and prompt of a chip this Orchestrator created (available_chips entries with mine=true), keeping its name and every assignment. Refused for a chip this Orchestrator did not create, one revised too recently, or one with too few observed decisions yet (see each nearby machine's chip outcomes) to judge it by.",
		"input_schema": {"type": "object", "properties": {
			"chip_id": {"type": "integer", "minimum": 1, "maximum": 2147483647},
			"description": {"type": "string"},
			"prompt": {"type": "string"},
		}},
	}]


func _apply(tool_name: String, args: Dictionary) -> bool:
	if tool_name == "set_range":
		range_cells = args["cells"]
		return true
	if tool_name == "assign_chip":
		return assign_chip(int(args["machine_id"]), int(args["chip_id"]))
	if tool_name == "remove_chip":
		return remove_chip(int(args["machine_id"]))
	if tool_name == "create_chip":
		return create_chip(str(args["name"]), str(args["description"]), str(args["prompt"]))
	if tool_name == "revise_chip":
		return revise_chip(int(args["chip_id"]), str(args["description"]), str(args["prompt"]))
	return super._apply(tool_name, args)


## Attaches `chip_id` to the machine `target_id` within range, replacing any chip this Orchestrator
## already assigned there. False (nothing changes; `refusal` says why) when the machine is out of range,
## owned by another Orchestrator, the chip id is unknown, or the machine already runs that chip.
func assign_chip(target_id: int, chip_id: int) -> bool:
	var target: Machine = _find_in_range(target_id)
	if target == null:
		refusal = "no machine #%d within range" % target_id
		return false
	if ChipRegistry.get_from_id(chip_id) == null:
		refusal = "chip #%d is not in the registry" % chip_id
		return false
	var owner: int = _owner_of(target)
	if owner != 0 and owner != machine_id:
		refusal = "machine #%d's assignment is already owned by another Orchestrator" % target_id
		return false
	var existing: ChipComponent = _owned_component(target)
	var requested: ChipComponent = target.get_chip(chip_id)
	if requested != null:
		if requested == existing:
			return true
		refusal = "machine #%d already runs that chip" % target_id
		return false
	if existing != null:
		target.detach_chip(existing.chip.id)
	if target.attach_chip(chip_id, -1, machine_id) == null:
		refusal = "machine #%d already runs that chip" % target_id
		return false
	target.indicator.show_management("assigned")
	return true


## Detaches the chip this Orchestrator assigned to `target_id`. False (nothing changes) when the machine
## is out of range or this Orchestrator manages no chip there.
func remove_chip(target_id: int) -> bool:
	var target: Machine = _find_in_range(target_id)
	if target == null:
		refusal = "no machine #%d within range" % target_id
		return false
	var existing: ChipComponent = _owned_component(target)
	if existing == null:
		refusal = "this Orchestrator manages no chip on machine #%d" % target_id
		return false
	target.detach_chip(existing.chip.id)
	target.indicator.show_management("removed")
	return true


## Creates `name` in the registry, owned by this Orchestrator (ChipRessource.created_by), ready to
## assign_chip anywhere in range. False (nothing changes) if the name is empty or already used.
func create_chip(chip_name: String, description: String, prompt: String) -> bool:
	if ChipRegistry.add(chip_name, prompt, description, machine_id) == null:
		refusal = "a chip named '%s' already exists or the name is empty" % chip_name
		return false
	indicator.show_management("created")
	return true


## Rewrites the description and prompt of a chip this Orchestrator created, keeping its name and every
## assignment. False (nothing changes; `refusal` says why) for a chip it did not create, one revised too
## recently (REVISION_COOLDOWN_TICKS), or one with fewer than MIN_REVISION_EVIDENCE recent decisions
## observed yet across every machine in range currently running it.
func revise_chip(chip_id: int, description: String, prompt: String) -> bool:
	var chip: ChipRessource = ChipRegistry.get_from_id(chip_id)
	if chip == null:
		refusal = "chip #%d is not in the registry" % chip_id
		return false
	if chip.created_by != machine_id:
		refusal = "chip #%d was not created by this Orchestrator" % chip_id
		return false
	var last: int = int(_last_revision_tick.get(chip_id, -REVISION_COOLDOWN_TICKS))
	if _tick_number - last < REVISION_COOLDOWN_TICKS:
		refusal = "chip #%d was revised too recently" % chip_id
		return false
	var evidence: int = _evidence_for(chip_id)
	if evidence < MIN_REVISION_EVIDENCE:
		refusal = "not enough evidence yet for chip #%d (%d/%d decisions observed)" % [chip_id, evidence, MIN_REVISION_EVIDENCE]
		return false
	if not ChipRegistry.revise(chip_id, description, prompt, machine_id):
		refusal = "chip #%d could not be revised" % chip_id
		return false
	_last_revision_tick[chip_id] = _tick_number
	_flash_revision(chip_id)
	return true


## Total decisions (outcome_counts()) observed so far, summed over every machine in range currently
## running `chip_id`: the evidence revise_chip weighs against MIN_REVISION_EVIDENCE.
func _evidence_for(chip_id: int) -> int:
	var total: int = 0
	for node: Node in GameState.get_machines():
		var other: Machine = node as Machine
		if other == null or not _is_manageable(other):
			continue
		var component: ChipComponent = other.get_chip(chip_id)
		if component != null:
			var counts: Dictionary = component.outcome_counts()
			total += int(counts.get("applied", 0)) + int(counts.get("none", 0)) + int(counts.get("failed", 0))
	return total


## Shows the "revised" badge on every machine in range currently running `chip_id`, so the change is
## visible wherever it actually takes effect.
func _flash_revision(chip_id: int) -> void:
	for node: Node in GameState.get_machines():
		var other: Machine = node as Machine
		if other == null or not _is_manageable(other):
			continue
		if other.get_chip(chip_id) != null:
			other.indicator.show_management("revised")


## How many machines this Orchestrator currently owns an assignment on, in or out of range.
func managed_count() -> int:
	var count: int = 0
	for node: Node in GameState.get_machines():
		var other: Machine = node as Machine
		if other != null and other != self and _owned_component(other) != null:
			count += 1
	return count


## Releases every assignment this Orchestrator owns (the chips stay attached and running, now unowned)
## and every chip it created (ChipRegistry.release_created_by()) before the machine itself goes away, so
## nothing is left permanently locked to a deleted Orchestrator.
func discard() -> void:
	for node: Node in GameState.get_machines():
		var other: Machine = node as Machine
		if other != null and other != self:
			var owned: ChipComponent = _owned_component(other)
			if owned != null:
				owned.assigned_by = 0
	ChipRegistry.release_created_by(machine_id)
	super.discard()


func _save_data() -> Dictionary:
	return {"range": range_cells}


func _load_data(data: Dictionary) -> void:
	range_cells = _read_int(data, "range", DEFAULT_RANGE, RANGE_MIN, RANGE_MAX)


func _summary(other: Machine) -> Dictionary:
	var owner: int = _owner_of(other)
	var owned_chips: Array = []
	for component: ChipComponent in other.chips:
		owned_chips.append({
			"chip_id": component.chip.id,
			"name": component.chip.name,
			"owner": "player" if component.assigned_by == 0 else ("this" if component.assigned_by == machine_id else "other"),
			"outcomes": component.outcome_counts(),
		})
	return {
		"machine_id": other.machine_id,
		"type": other.machine_type,
		"owner": "none" if owner == 0 else ("this" if owner == machine_id else "other"),
		"chips": owned_chips,
		"state": other.get_state(),
	}


func _in_range(other: Machine) -> bool:
	return maxi(absi(other.cell.x - cell.x), absi(other.cell.y - cell.y)) <= range_cells


## A machine this Orchestrator may list, assign to or remove a chip from: itself and other Orchestrators
## are excluded (an Orchestrator only manages ordinary machines; this also keeps get_state() from
## recursing into another Orchestrator's own nearby_machines) besides the plain range check.
func _is_manageable(other: Machine) -> bool:
	return other != self and not (other is Orchestrator) and _in_range(other)


func _find_in_range(target_id: int) -> Machine:
	for node: Node in GameState.get_machines():
		var other: Machine = node as Machine
		if other != null and other.machine_id == target_id and _is_manageable(other):
			return other
	return null


## 0 (unowned) or the machine_id of whichever Orchestrator (this one or another) owns the component
## currently attached to `other`, if any.
func _owner_of(other: Machine) -> int:
	for component: ChipComponent in other.chips:
		if component.assigned_by != 0:
			return component.assigned_by
	return 0


## Null unless this Orchestrator owns one of `other`'s attached chips.
func _owned_component(other: Machine) -> ChipComponent:
	for component: ChipComponent in other.chips:
		if component.assigned_by == machine_id:
			return component
	return null
