class_name SfxEvents
extends Node
## The one listener that turns factory events into sound cues (`Sfx.play`). Machines and the UI only emit
## their normal signals; nothing else in the game calls `Sfx` for gameplay. Created by `Main`.
## Cue ids are the file names in `assets/audio/sfx/`. Per-cue rate limits live in the cue data
## (`data/sfx.tres`: cooldown and voice count); what a cooldown cannot express lives here:
## the per-machine "blocked" hold-off, the overheat reminder and one shared throttle for the chip cues.
## Restoring a save, `GameState.reset()` and the Collector placed at start emit none of the signals used
## here, and a machine that is already stalled or overheating when it appears is adopted silently.

const PLACE: StringName = &"place"
const REMOVE: StringName = &"remove"
const PLACE_REJECTED: StringName = &"place_rejected"
const DELIVER: StringName = &"deliver"
const CRAFT_DONE: StringName = &"craft_done"
const SELL: StringName = &"sell"
const ORDER_COMPLETE: StringName = &"order_complete"
const CHIP_OK: StringName = &"chip_ok"
const CHIP_NONE: StringName = &"chip_none"
const CHIP_FAIL: StringName = &"chip_fail"
const BLOCKED: StringName = &"blocked"
const OVERHEAT_WARN: StringName = &"overheat_warn"
const EXPLOSION: StringName = &"explosion"
const UI_CLICK: StringName = &"ui_click"

## A machine that keeps being stuck is announced once per this long, so a jammed line is not a drone.
const BLOCKED_HOLD_OFF_MSEC: int = 25000
## While any machine stays overheating, the warning repeats at most this often.
const OVERHEAT_REPEAT_MSEC: int = 6000
## Shortest gap between two chip cues of any kind (about two per second overall).
const CHIP_MIN_GAP_MSEC: int = 500
## A sale pitches between these scales according to the item's price (cheapest to dearest, on a log scale).
const SELL_PITCH_LOW: float = 0.85
const SELL_PITCH_HIGH: float = 1.3
const NEVER_MSEC: int = -1000000000

## Where cues go. The `Sfx` autoload unless a test sets another node.
var sfx: Node

var _machines: Array[Machine] = []
var _stalled: Dictionary = {}
var _overheating: Dictionary = {}
var _blocked_until: Dictionary = {}
var _last_overheat_msec: int = NEVER_MSEC
var _last_chip_msec: int = NEVER_MSEC


func _ready() -> void:
	if sfx == null:
		sfx = Sfx
	EventBus.machine_registered.connect(_on_machine_registered)
	EventBus.machine_unregistered.connect(_on_machine_unregistered)
	EventBus.machine_exploded.connect(_on_machine_exploded)
	EventBus.order_completed.connect(_on_order_completed)
	EventBus.tick_fired.connect(_on_tick)


func _exit_tree() -> void:
	EventBus.machine_registered.disconnect(_on_machine_registered)
	EventBus.machine_unregistered.disconnect(_on_machine_unregistered)
	EventBus.machine_exploded.disconnect(_on_machine_exploded)
	EventBus.order_completed.disconnect(_on_order_completed)
	EventBus.tick_fired.disconnect(_on_tick)


## Lets a button click: plays `ui_click` on the autoload when it is pressed.
static func attach_click(button: BaseButton) -> void:
	button.pressed.connect(Sfx.play.bind(UI_CLICK))


## The scale a sale of this price is pitched by.
static func pitch_for_price(price: int) -> float:
	var prices: Array[int] = []
	for item: ItemData in ItemCatalog.shared().items:
		prices.append(item.price)
	if prices.is_empty():
		return 1.0
	var low: float = float(prices.min())
	var high: float = float(prices.max())
	if high <= low:
		return 1.0
	var fraction: float = log(maxf(float(price), low) / low) / log(high / low)
	return lerpf(SELL_PITCH_LOW, SELL_PITCH_HIGH, clampf(fraction, 0.0, 1.0))


## Listens to the build flow and the machine panel, and adopts the machines that already exist.
func setup(placement: Placement, tooltip: MachineTooltip) -> void:
	placement.machine_placed.connect(_on_machine_placed)
	placement.placement_rejected.connect(_on_placement_rejected)
	tooltip.machine_destroyed.connect(_on_machine_destroyed)
	for node: Node in GameState.get_machines():
		var machine: Machine = node as Machine
		if machine != null:
			_adopt(machine)


## Milliseconds clock for the hold-offs. Tests override it.
func _now_msec() -> int:
	return Time.get_ticks_msec()


func _adopt(machine: Machine) -> void:
	if _machines.has(machine):
		return
	_machines.append(machine)
	machine.produced.connect(_on_machine_produced.bind(machine))
	machine.chip_outcome_reported.connect(_on_chip_outcome)
	var collector: Collector = machine as Collector
	if collector != null:
		collector.item_sold.connect(_on_item_sold.bind(collector))


func _is_stalled(machine: Machine) -> bool:
	return machine.shows_production_feedback() and machine.get_production_state() == Machine.ProductionState.STALLED


func _center_of(node: Node2D) -> Vector2:
	return node.global_position + Vector2.ONE * (GameState.CELL_SIZE / 2.0)


func _on_machine_registered(machine: Node, _cell: Vector2i) -> void:
	var typed: Machine = machine as Machine
	if typed != null:
		_adopt(typed)


func _on_machine_unregistered(machine: Node, _cell: Vector2i) -> void:
	_machines.erase(machine)
	_stalled.erase(machine)
	_overheating.erase(machine)
	_blocked_until.erase(machine)


func _on_machine_placed(machine: Machine) -> void:
	sfx.call("play", PLACE, _center_of(machine))


func _on_placement_rejected(_reason: String) -> void:
	sfx.call("play", PLACE_REJECTED)


func _on_machine_destroyed(world_position: Vector2) -> void:
	sfx.call("play", REMOVE, world_position)


func _on_item_sold(_item: String, price: int, collector: Collector) -> void:
	sfx.call("play", SELL, _center_of(collector), pitch_for_price(price))


func _on_order_completed(_product: String, _reward: int) -> void:
	sfx.call("play", ORDER_COMPLETE)


## A craft machine finishing a unit is a craft; a miner handing over ore is a (much quieter) delivery.
func _on_machine_produced(machine: Machine) -> void:
	sfx.call("play", CRAFT_DONE if machine is CraftMachine else DELIVER, _center_of(machine))


func _on_chip_outcome(outcome: String) -> void:
	var cue: StringName = &""
	match outcome:
		"applied":
			cue = CHIP_OK
		"none":
			cue = CHIP_NONE
		"failed":
			cue = CHIP_FAIL
		_:
			return
	var now: int = _now_msec()
	if now - _last_chip_msec < CHIP_MIN_GAP_MSEC:
		return
	_last_chip_msec = now
	sfx.call("play", cue)


func _on_machine_exploded(machine: Node) -> void:
	var node: Node2D = machine as Node2D
	if node != null:
		sfx.call("play", EXPLOSION, _center_of(node))


## Watches machine states once per tick: a state is announced when a machine enters it. A machine's first
## tick only records its state: a save sets the state of a machine right after it appears, which is not news.
func _on_tick(_tick: int) -> void:
	var now: int = _now_msec()
	var any_overheating: bool = false
	for machine: Machine in _machines:
		var stalled: bool = _is_stalled(machine)
		var hot: bool = machine.status == Machine.Status.OVERHEATING
		if not _stalled.has(machine):
			_stalled[machine] = stalled
			_overheating[machine] = hot
			any_overheating = any_overheating or hot
			if hot:
				_last_overheat_msec = now
			continue
		if stalled and not _stalled[machine] and now >= int(_blocked_until.get(machine, NEVER_MSEC)):
			_blocked_until[machine] = now + BLOCKED_HOLD_OFF_MSEC
			sfx.call("play", BLOCKED, _center_of(machine))
		_stalled[machine] = stalled
		if hot and not _overheating[machine]:
			_last_overheat_msec = now
			sfx.call("play", OVERHEAT_WARN, _center_of(machine))
		_overheating[machine] = hot
		any_overheating = any_overheating or hot
	if any_overheating and now - _last_overheat_msec >= OVERHEAT_REPEAT_MSEC:
		_last_overheat_msec = now
		sfx.call("play", OVERHEAT_WARN)
