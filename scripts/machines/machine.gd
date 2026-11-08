class_name Machine
extends Node2D
## Base machine. Subclasses override _own_tool_schemas(), get_state() and _apply().
## apply_tool_call() is the only way LLM output touches a machine.

signal tool_applied(tool_name: String, args: Dictionary)
signal chip_decision_applied(chip_id: int, reason: String, applied: int)
signal chips_changed

enum Status { NORMAL, DOWN, OVERHEATING }
## PRODUCING: enabled and a job is in progress. STALLED: its output cannot be delivered (wins over
## PRODUCING, e.g. a full conveyor ahead). IDLE: switched off, or nothing to do right now.
enum ProductionState { PRODUCING, STALLED, IDLE }
## Window get_production_rate() reports over, in simulated seconds (so the number reads as items per minute).
const PRODUCTION_WINDOW_SECONDS: float = 60.0

@export var machine_type: String = "machine"
## Art seen from the front: used for every facing except up. Unset on the bare base machine.
@export var front_texture: Texture2D
## Art seen from behind, used while facing up. Machines without one keep the front art.
@export var back_texture: Texture2D
## Turns the front art a quarter turn to face left or right, so its doorway points where the machine
## outputs. Off: the front art stays upright for those facings.
@export var turn_front_sideways: bool = false

var machine_id: int = 0
## The last tick this machine handled.
var _tick_number: int = 0
## Why the last tool call was refused by _apply(): the sentence written to the log. Set by the machine before it returns false.
var refusal: String = ""
var cell: Vector2i = Vector2i.ZERO
var status: Status = Status.NORMAL
var enabled: bool = true
## Cell the machine hands its output to (miners, craft machines, conveyors). Setting it redraws the sprite.
var facing: Vector2i = Vector2i.RIGHT:
	set(value):
		facing = value
		_update_sprite()

## Chips running on this machine, in attach order. Each is a ChipComponent child.
var chips: Array[ChipComponent] = []
## The icon above the machine: a spinner while any chip waits for an answer, then the last result.
var indicator: ChipIndicator
## In-world feedback for production_state(): particles while producing, a badge while blocked.
var production_effect: ProductionEffect
## The icon at the corner of the machine's cell showing its production state. Null for machines whose
## shows_production_feedback() is false (they have no timed job to report).
var production_indicator: ProductionIndicator

## Where the sprite rests for the current facing, and the temporary offset an effect (the Smelter's shake)
## adds on top. The sprite always sits at home + offset, so an offset never accumulates or fights a rotation.
var _sprite_home: Vector2 = Vector2.ZERO
var _sprite_offset: Vector2 = Vector2.ZERO
## Ticks this machine completed a unit of production on, trimmed to PRODUCTION_WINDOW_SECONDS.
var _production_ticks: Array[int] = []

@onready var _label: Label = get_node_or_null("StatusLabel") as Label
@onready var _sprite: Sprite2D = get_node_or_null("Sprite2D") as Sprite2D


func _ready() -> void:
	EventBus.tick_fired.connect(_on_tick)
	indicator = ChipIndicator.new()
	indicator.position = Vector2(GameState.CELL_SIZE / 2.0, -Icons.SIZE * Icons.SCALE / 2.0 - 2.0)
	add_child(indicator)
	production_effect = ProductionEffect.new()
	production_effect.show_blocked_badge = not shows_production_feedback()
	add_child(production_effect)
	if shows_production_feedback():
		production_indicator = ProductionIndicator.new()
		var corner: float = GameState.CELL_SIZE - Icons.SIZE * Icons.SCALE / 2.0 - 2.0
		production_indicator.position = Vector2(corner, corner)
		add_child(production_indicator)
		production_indicator.refresh(get_production_state(), get_production_rate())
	_update_sprite()


func _exit_tree() -> void:
	EventBus.tick_fired.disconnect(_on_tick)
	if GameState.get_machine_at(cell) == self:
		GameState.unregister_machine(cell)


## Adds a ChipComponent child running the registry chip. Null for an unknown id or a chip already attached.
## `assigned_by` is 0 for a player-made attachment (the default: the tooltip's "add chip" never passes
## anything else), else the machine_id of the Orchestrator that made it (see ChipComponent.assigned_by).
func attach_chip(chip_id: int, timeout_ticks: int = ChipComponent.DEFAULT_TIMEOUT, assigned_by: int = 0) -> ChipComponent:
	var chip: ChipRessource = ChipRegistry.get_from_id(chip_id)
	if chip == null or get_chip(chip_id) != null:
		return null
	var component: ChipComponent = ChipComponent.new()
	component.chip = chip
	component.set_timeout(timeout_ticks)
	component.assigned_by = assigned_by
	component.decision_applied.connect(_on_chip_decision_applied.bind(chip_id))
	component.activity_changed.connect(_on_chip_activity)
	add_child(component)
	chips.append(component)
	chips_changed.emit()
	return component


func detach_chip(chip_id: int) -> void:
	var component: ChipComponent = get_chip(chip_id)
	if component == null:
		return
	chips.erase(component)
	component.queue_free()
	_on_chip_activity("")
	chips_changed.emit()


## Null if the chip is not attached.
func get_chip(chip_id: int) -> ChipComponent:
	for component: ChipComponent in chips:
		if component.chip.id == chip_id:
			return component
	return null


## False for the fixed Collector.
func is_removable() -> bool:
	return true


## False for machines whose logic ignores `enabled` (Conveyor, Collector): set_enabled is accepted but does nothing.
func honors_enabled() -> bool:
	return true


## False for machines with no output direction (the Collector).
func can_rotate() -> bool:
	return true


## Clockwise: right, down, left, up. Only changes where future output goes.
func rotate_facing() -> void:
	facing = Vector2i(-facing.y, facing.x)


## How far the current job is, 0..1 (Miner: the next unit, craft machines: the current craft). -1 for
## machines with no such job.
func get_progress() -> float:
	return -1.0


## True once a delivery of the output failed and the machine is waiting for the way to clear.
func is_blocked() -> bool:
	return false


## "producing", "idle" or "blocked": drives the in-world production_effect. A machine that is DOWN always
## reads idle (it is inert, not stuck). Subclasses report active work through is_producing(), not this.
func production_state() -> String:
	if status == Status.DOWN:
		return "idle"
	if is_blocked():
		return "blocked"
	if is_producing():
		return "producing"
	return "idle"


## True while the machine is actively working toward an output this tick. The base machine never counts;
## subclasses with a job (Miner, CraftMachine, Conveyor, Collector) override it.
func is_producing() -> bool:
	return false


## True for machines that complete a timed production job (Miner, Smelter, Assembler): they get a
## production_indicator and a production state. False for the Collector and Conveyor, which only move or
## sell what reaches them and have no such job to report.
func shows_production_feedback() -> bool:
	return false


## STALLED wins over PRODUCING: a machine blocked mid-delivery is not making progress even if `enabled`.
func get_production_state() -> ProductionState:
	if is_blocked():
		return ProductionState.STALLED
	if enabled and get_progress() > 0.0:
		return ProductionState.PRODUCING
	return ProductionState.IDLE


## Units this machine has completed and handed off in the last PRODUCTION_WINDOW_SECONDS of simulated
## time, as an items-per-minute figure. 0 for a machine that never calls _note_produced().
func get_production_rate() -> float:
	return float(_production_ticks.size()) * (60.0 / PRODUCTION_WINDOW_SECONDS)


## Discards everything the machine holds (stock, held item, attached chips), frees its grid cell
## immediately and removes it from the scene. False if the machine is fixed.
func destroy() -> bool:
	if not is_removable():
		return false
	discard()
	return true


## Same as destroy() but for any machine, fixed or not. Used when a save replaces the whole map.
func discard() -> void:
	clear_contents()
	for component: ChipComponent in chips.duplicate():
		detach_chip(component.chip.id)
	if GameState.get_machine_at(cell) == self:
		GameState.unregister_machine(cell)
	if get_parent() != null:
		get_parent().remove_child(self)
	queue_free()


## False for a machine that is about to disappear (an exploding Smelter): a save skips it.
func is_saveable() -> bool:
	return true


## Everything a save file keeps about this machine, as plain JSON types.
func to_dict() -> Dictionary:
	var chip_list: Array = []
	for component: ChipComponent in chips:
		chip_list.append({
			"id": component.chip.id,
			"timeout": component.timeout,
			"assigned_by": component.assigned_by,
		})
	return {
		"type": machine_type,
		"id": machine_id,
		"cell": [cell.x, cell.y],
		"facing": [facing.x, facing.y],
		"enabled": enabled,
		"status": status,
		"chips": chip_list,
		"data": _save_data(),
	}


## Applies a saved machine (see to_dict) onto a freshly placed one. The file is not trusted: every value
## is clamped or ignored. Chips whose id is not in the registry are skipped.
func load_dict(data: Dictionary) -> void:
	enabled = data.get("enabled", true) == true
	status = _read_int(data, "status", Status.NORMAL, 0, Status.size() - 1) as Status
	var saved_data: Variant = data.get("data")
	if typeof(saved_data) == TYPE_DICTIONARY:
		_load_data(saved_data)
	var chip_list: Variant = data.get("chips")
	if typeof(chip_list) != TYPE_ARRAY:
		return
	for entry: Variant in chip_list:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		attach_chip(
			_read_int(entry, "id", 0, 0, 2147483647),
			_read_int(entry, "timeout", ChipComponent.DEFAULT_TIMEOUT, 1, 100000),
			_read_int(entry, "assigned_by", 0, 0, 2147483647))


## Takes one item from an upstream machine. True if accepted. Machines that take nothing keep the default.
func receive(_item: String) -> bool:
	return false


## Every tool the LLM may call on this machine: the shared ones first, then the ones unique to its type.
func get_tool_schemas() -> Array:
	return _shared_tool_schemas() + _own_tool_schemas()


## Compact state sent to the LLM. Only fields the chip needs.
func get_state() -> Dictionary:
	return {"type": machine_type, "enabled": enabled, "status": Status.keys()[status].to_lower()}


## Validates a tool call against get_tool_schemas(), clamps args, then applies it.
## Returns false (and logs to the ChipLog) for unknown tools or malformed args.
func apply_tool_call(tool_name: String, args: Dictionary) -> bool:
	var schema: Dictionary = _find_schema(tool_name)
	if schema.is_empty():
		log_chip("ignored unknown tool '%s'" % tool_name)
		return false
	var clean: Dictionary = {}
	var props: Dictionary = schema.get("input_schema", {}).get("properties", {})
	for key: String in props:
		if not args.has(key):
			log_chip("ignored %s: missing '%s'" % [tool_name, key])
			return false
		var value: Variant = _sanitize(props[key], args[key])
		if value == null:
			log_chip("ignored %s: bad value for '%s'" % [tool_name, key])
			return false
		clean[key] = value
	refusal = ""
	if not _apply(tool_name, clean):
		log_chip("ignored %s(%s): %s" % [tool_name, JSON.stringify(clean), refusal if refusal != "" else "the machine refused it"])
		return false
	log_chip("%s(%s)" % [tool_name, JSON.stringify(clean)])
	tool_applied.emit(tool_name, clean)
	return true


func log_chip(message: String) -> void:
	EventBus.chip_log_added.emit(self, message)


## Drops the machine's stock and held items. Subclasses with contents override.
func clear_contents() -> void:
	pass


## State specific to the machine type, saved under "data". Subclasses with state override it.
func _save_data() -> Dictionary:
	return {}


## Reads what _save_data() wrote. Use the _read_* helpers: the values come from a file.
func _load_data(_data: Dictionary) -> void:
	pass


## A whole number clamped to [low, high], or the fallback when the value is missing or not a number.
static func _read_int(data: Dictionary, key: String, fallback: int, low: int, high: int) -> int:
	var value: Variant = data.get(key)
	if typeof(value) == TYPE_INT:
		return clampi(value, low, high)
	if typeof(value) == TYPE_FLOAT and is_finite(value):
		return clampi(int(value), low, high)
	return fallback


static func _read_float(data: Dictionary, key: String, fallback: float, low: float, high: float) -> float:
	var value: Variant = data.get(key)
	if (typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT) and is_finite(float(value)):
		return clampf(float(value), low, high)
	return fallback


## The saved item name when it is one of `allowed`, else "" (no item).
static func _read_item(data: Dictionary, key: String, allowed: Array) -> String:
	var value: Variant = data.get(key)
	return value if typeof(value) == TYPE_STRING and allowed.has(value) else ""


## Simulation step, called once per GameState tick unless the machine is DOWN. Override in subclasses.
func _tick() -> void:
	pass


## Marks one completed, delivered unit of production right now. Call it only for something the machine
## itself made (not merely moved, like a Conveyor), right after a successful hand-off.
func _note_produced() -> void:
	_production_ticks.append(_tick_number)
	var window: int = int(PRODUCTION_WINDOW_SECONDS) * GameState.TICK_RATE
	while not _production_ticks.is_empty() and _production_ticks[0] <= _tick_number - window:
		_production_ticks.pop_front()


## Picks the sprite for the current facing. Conveyors override it. Runs before _ready too
## (placement sets facing first), when there is no sprite yet.
func _update_sprite() -> void:
	if _sprite == null or front_texture == null:
		return
	_sprite.texture = back_texture if facing == Vector2i.UP and back_texture != null else front_texture
	_sprite.rotation = 0.0
	_sprite_home = Vector2.ZERO
	if turn_front_sideways and facing.y == 0:
		# The front art has its doorway at the bottom. The sprite turns around its top-left corner,
		# so it is moved back over the cell: right is a quarter turn counter-clockwise, left clockwise.
		var span: Vector2 = front_texture.get_size() * _sprite.scale
		_sprite.rotation = -PI / 2.0 if facing == Vector2i.RIGHT else PI / 2.0
		_sprite_home = Vector2(0.0, span.y) if facing == Vector2i.RIGHT else Vector2(span.x, 0.0)
	_place_sprite()


## Puts the sprite at its home position plus the current offset.
func _place_sprite() -> void:
	if _sprite != null:
		_sprite.position = _sprite_home + _sprite_offset


## Text drawn over the machine. Empty by default: the machine's name is not shown there.
func _status_text() -> String:
	return ""


## Hands an item to the machine in front. False if there is none or it refuses. Two machines facing
## each other (a head-on pair) pass nothing to one another. The Collector has no facing, so it never counts.
func _push(item: String) -> bool:
	var target: Machine = GameState.get_machine_at(cell + facing) as Machine
	if target == null or (target.can_rotate() and target.facing == -facing):
		return false
	if not target.receive(item):
		return false
	target.note_sender(cell, _tick_number)
	return true


## Called on the receiver right after it accepted an item pushed by the machine on `sender_cell` during tick
## `sender_tick`. Machines that animate the item coming in override it.
func note_sender(_sender_cell: Vector2i, _sender_tick: int) -> void:
	pass


func _on_tick(tick_number: int) -> void:
	_tick_number = tick_number
	if status != Status.DOWN:
		_tick()
	if production_indicator != null:
		production_indicator.refresh(get_production_state(), get_production_rate())
	if _label != null:
		_label.text = _status_text()
	production_effect.set_state(production_state())


## Spinner while any chip is pending (one chip finishing never hides another still running), otherwise the
## result of the one that just finished.
func _on_chip_activity(outcome: String) -> void:
	for component: ChipComponent in chips:
		if component.pending:
			indicator.show_pending()
			return
	if outcome == "":
		indicator.clear()
	else:
		indicator.show_result(outcome)


func _on_chip_decision_applied(reason: String, applied: int, chip_id: int) -> void:
	chip_decision_applied.emit(chip_id, reason, applied)


## Tools all machines share.
func _shared_tool_schemas() -> Array:
	return [{
		"name": "set_enabled",
		"description": "Turn the machine on or off.",
		"input_schema": {"type": "object", "properties": {"on": {"type": "boolean"}}},
	}]


## Tools unique to this machine type. Every subclass overrides this with its own list,
## and their names must not clash with the shared tools. Handle them in `_apply`.
func _own_tool_schemas() -> Array:
	return []


## Applies a validated tool call. Returns false when the machine refuses it (nothing changed).
func _apply(tool_name: String, args: Dictionary) -> bool:
	if tool_name == "set_enabled":
		enabled = args["on"]
		return true
	return false


func _find_schema(tool_name: String) -> Dictionary:
	for schema: Dictionary in get_tool_schemas():
		if schema.get("name", "") == tool_name:
			return schema
	return {}


## Returns the clamped value, or null if the type is wrong (or a string is not one of the schema's "enum" list, when it has one).
func _sanitize(prop: Dictionary, value: Variant) -> Variant:
	match prop.get("type", ""):
		"boolean":
			return value if typeof(value) == TYPE_BOOL else null
		"string":
			if typeof(value) != TYPE_STRING:
				return null
			var allowed: Array = prop.get("enum", [])
			return value if allowed.is_empty() or allowed.has(value) else null
		"integer":
			if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
				return null
			return clampi(int(value), int(prop.get("minimum", -2147483648)), int(prop.get("maximum", 2147483647)))
		"number":
			if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
				return null
			return clampf(float(value), float(prop.get("minimum", -INF)), float(prop.get("maximum", INF)))
	return null
