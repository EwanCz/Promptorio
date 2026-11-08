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

## Chebyshev distance (the largest of the two axis deltas), so the visible area is a square around it.
const RANGE_MIN: int = 1
const RANGE_MAX: int = 8
const DEFAULT_RANGE: int = 4
## Marks the art as "not an ordinary production machine"; no new art asset for this prototype.
const TINT: Color = Color(0.68, 0.58, 0.95)

## How many cells away, in every direction, this Orchestrator can see and manage machines.
var range_cells: int = DEFAULT_RANGE


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
		available_chips.append({"id": chip.id, "name": chip.name, "description": chip.description})
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
	}]


func _apply(tool_name: String, args: Dictionary) -> bool:
	if tool_name == "set_range":
		range_cells = args["cells"]
		return true
	if tool_name == "assign_chip":
		return assign_chip(int(args["machine_id"]), int(args["chip_id"]))
	if tool_name == "remove_chip":
		return remove_chip(int(args["machine_id"]))
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
	if existing != null:
		target.detach_chip(existing.chip.id)
	if target.attach_chip(chip_id, ChipComponent.DEFAULT_TIMEOUT, machine_id) == null:
		refusal = "machine #%d already runs that chip" % target_id
		return false
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
	return true


## How many machines this Orchestrator currently owns an assignment on, in or out of range.
func managed_count() -> int:
	var count: int = 0
	for node: Node in GameState.get_machines():
		var other: Machine = node as Machine
		if other != null and other != self and _owned_component(other) != null:
			count += 1
	return count


## Releases every assignment this Orchestrator owns (the chips stay attached and running, now unowned)
## before the machine itself goes away, so nothing is left permanently locked to a deleted Orchestrator.
func discard() -> void:
	for node: Node in GameState.get_machines():
		var other: Machine = node as Machine
		if other != null and other != self:
			var owned: ChipComponent = _owned_component(other)
			if owned != null:
				owned.assigned_by = 0
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
