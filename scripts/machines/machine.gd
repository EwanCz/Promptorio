class_name Machine
extends Node2D
## Base machine. Subclasses override _own_tool_schemas(), get_state() and _apply().
## apply_tool_call() is the only way LLM output touches a machine.

signal tool_applied(tool_name: String, args: Dictionary)
signal chip_decision_applied(chip_id: int, reason: String, applied: int)

enum Status { NORMAL, DOWN, OVERHEATING }

@export var machine_type: String = "machine"
## Art seen from the front: used for every facing except up. Unset on the bare base machine.
@export var front_texture: Texture2D
## Art seen from behind, used while facing up. Machines without one keep the front art.
@export var back_texture: Texture2D
## Turns the front art a quarter turn to face left or right, so its doorway points where the machine
## outputs. Off: the front art stays upright for those facings.
@export var turn_front_sideways: bool = false

var machine_id: int = 0
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

@onready var _label: Label = get_node_or_null("StatusLabel") as Label
@onready var _sprite: Sprite2D = get_node_or_null("Sprite2D") as Sprite2D


func _ready() -> void:
	EventBus.tick_fired.connect(_on_tick)
	indicator = ChipIndicator.new()
	indicator.position = Vector2(GameState.CELL_SIZE / 2.0, -Icons.SIZE * Icons.SCALE / 2.0 - 2.0)
	add_child(indicator)
	_update_sprite()


func _exit_tree() -> void:
	EventBus.tick_fired.disconnect(_on_tick)
	if GameState.get_machine_at(cell) == self:
		GameState.unregister_machine(cell)


## Adds a ChipComponent child running the registry chip. Null for an unknown id or a chip already attached.
func attach_chip(chip_id: int, timeout_ticks: int = ChipComponent.DEFAULT_TIMEOUT) -> ChipComponent:
	var chip: ChipRessource = ChipRegistry.get_from_id(chip_id)
	if chip == null or get_chip(chip_id) != null:
		return null
	var component: ChipComponent = ChipComponent.new()
	component.chip = chip
	component.set_timeout(timeout_ticks)
	component.decision_applied.connect(_on_chip_decision_applied.bind(chip_id))
	component.activity_changed.connect(_on_chip_activity)
	add_child(component)
	chips.append(component)
	return component


func detach_chip(chip_id: int) -> void:
	var component: ChipComponent = get_chip(chip_id)
	if component == null:
		return
	chips.erase(component)
	component.queue_free()
	_on_chip_activity("")


## Null if the chip is not attached.
func get_chip(chip_id: int) -> ChipComponent:
	for component: ChipComponent in chips:
		if component.chip.id == chip_id:
			return component
	return null


## False for the fixed Collector.
func is_removable() -> bool:
	return true


## False for machines with no output direction (the Collector).
func can_rotate() -> bool:
	return true


## Clockwise: right, down, left, up. Only changes where future output goes.
func rotate_facing() -> void:
	facing = Vector2i(-facing.y, facing.x)


## One line for the tooltip: what the machine is doing right now. Subclasses override.
func get_action_text() -> String:
	return ""


## Discards everything the machine holds (stock, held item, attached chips), frees its grid cell
## immediately and removes it from the scene. False if the machine is fixed.
func destroy() -> bool:
	if not is_removable():
		return false
	clear_contents()
	for component: ChipComponent in chips.duplicate():
		detach_chip(component.chip.id)
	if GameState.get_machine_at(cell) == self:
		GameState.unregister_machine(cell)
	if get_parent() != null:
		get_parent().remove_child(self)
	queue_free()
	return true


## Takes one item from an upstream machine. True if accepted. Machines that take nothing keep the default.
func receive(_item: String) -> bool:
	return false


## Every tool the LLM may call on this machine: the shared ones first, then the ones unique to its type.
func get_tool_schemas() -> Array:
	return _shared_tool_schemas() + _own_tool_schemas()


## Compact state sent to the LLM. Only fields the chip needs.
func get_state() -> Dictionary:
	return {"type": machine_type, "enabled": enabled, "status": Status.keys()[status].to_lower()}


## Named conditions that can wake a chip (it is asked when one appears). Subclasses add theirs.
func get_events() -> Array[String]:
	var events: Array[String] = []
	if status != Status.NORMAL:
		events.append("error")
	return events


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
	_apply(tool_name, clean)
	log_chip("%s(%s)" % [tool_name, JSON.stringify(clean)])
	tool_applied.emit(tool_name, clean)
	return true


func log_chip(message: String) -> void:
	EventBus.chip_log_added.emit(self, message)


## Drops the machine's stock and held items. Subclasses with contents override.
func clear_contents() -> void:
	pass


## Simulation step, called once per GameState tick unless the machine is DOWN. Override in subclasses.
func _tick() -> void:
	pass


## Picks the sprite for the current facing. Conveyors override it. Runs before _ready too
## (placement sets facing first), when there is no sprite yet.
func _update_sprite() -> void:
	if _sprite == null or front_texture == null:
		return
	_sprite.texture = back_texture if facing == Vector2i.UP and back_texture != null else front_texture
	_sprite.rotation = 0.0
	_sprite.position = Vector2.ZERO
	if turn_front_sideways and facing.y == 0:
		# The front art has its doorway at the bottom. The sprite turns around its top-left corner,
		# so it is moved back over the cell: right is a quarter turn counter-clockwise, left clockwise.
		var span: Vector2 = front_texture.get_size() * _sprite.scale
		_sprite.rotation = -PI / 2.0 if facing == Vector2i.RIGHT else PI / 2.0
		_sprite.position = Vector2(0.0, span.y) if facing == Vector2i.RIGHT else Vector2(span.x, 0.0)


## Text drawn over the machine. Empty by default: the machine's name is not shown there.
func _status_text() -> String:
	return ""


## Hands an item to the machine in front. False if there is none or it refuses. Two machines facing
## each other (a head-on pair) pass nothing to one another. The Collector has no facing, so it never counts.
func _push(item: String) -> bool:
	var target: Machine = GameState.get_machine_at(cell + facing) as Machine
	if target == null or (target.can_rotate() and target.facing == -facing):
		return false
	return target.receive(item)


func _on_tick(_tick_number: int) -> void:
	if status != Status.DOWN:
		_tick()
	if _label != null:
		_label.text = _status_text()


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


func _apply(tool_name: String, args: Dictionary) -> void:
	if tool_name == "set_enabled":
		enabled = args["on"]


func _find_schema(tool_name: String) -> Dictionary:
	for schema: Dictionary in get_tool_schemas():
		if schema.get("name", "") == tool_name:
			return schema
	return {}


## Returns the clamped value, or null if the type is wrong.
func _sanitize(prop: Dictionary, value: Variant) -> Variant:
	match prop.get("type", ""):
		"boolean":
			return value if typeof(value) == TYPE_BOOL else null
		"integer":
			if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
				return null
			return clampi(int(value), int(prop.get("minimum", -2147483648)), int(prop.get("maximum", 2147483647)))
		"number":
			if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
				return null
			return clampf(float(value), float(prop.get("minimum", -INF)), float(prop.get("maximum", INF)))
	return null
