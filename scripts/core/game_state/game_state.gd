extends Node
## Grid, machine registry, tick clock and money.

const TICK_RATE: int = 10
## Simulation speed-up range: how many simulated seconds pass per real second. Real time itself (chip
## cooldowns, request latency, the mock provider's delay) is untouched; only the tick clock speeds up.
const MIN_TIME_SCALE: float = 1.0
const MAX_TIME_SCALE: float = 4.0
const GRID_SIZE: Vector2i = Vector2i(32, 20)
const CELL_SIZE: int = 64
const START_MONEY: int = 100
## The first order of a new game: an Ore -> Ingot chain, buildable with the starting money (Miner 20 +
## Smelter 30), so a new game has a reachable goal right away.
const STARTING_ORDER_PRODUCT: String = "ingot"
const ORDER_QUANTITY: int = 5
## The reward on top of the ordered items' own Collector sale price, so fulfilling an order pays more
## than selling the same items without one.
const ORDER_REWARD_MULTIPLIER: int = 2

var tick_count: int = 0
## How many simulated seconds pass per real second (clamped to [MIN_TIME_SCALE, MAX_TIME_SCALE]), set
## through set_time_scale(). A UI control (the Bar's speed button) is the only writer.
var time_scale: float = MIN_TIME_SCALE
var money: int = START_MONEY
## "" while no order is active (only true before the first reset(), e.g. at the main menu).
var order_product: String = ""
var order_quantity: int = 0
var order_progress: int = 0
var order_reward: int = 0

var _machines: Dictionary = {}
var _last_tick_time_usec: int = 0
var _tick_accumulator: float = 0.0


func _ready() -> void:
	_last_tick_time_usec = Time.get_ticks_usec()


func _physics_process(_delta: float) -> void:
	var now: int = Time.get_ticks_usec()
	_advance_clock(float(now - _last_tick_time_usec) / 1000000.0 * time_scale)
	_last_tick_time_usec = now


## Clamped to [MIN_TIME_SCALE, MAX_TIME_SCALE].
func set_time_scale(value: float) -> void:
	time_scale = clampf(value, MIN_TIME_SCALE, MAX_TIME_SCALE)


func _notification(what: int) -> void:
	if what == NOTIFICATION_UNPAUSED:
		_last_tick_time_usec = Time.get_ticks_usec()


## How far the clock is into the current tick, 0 to 1, up to this very frame (the clock itself only moves
## with the physics steps, so a frame in between would otherwise show the same value twice). Lets visuals
## glide between two ticks. Frozen while the game is paused.
func tick_fraction() -> float:
	var elapsed: float = 0.0
	if not get_tree().paused:
		elapsed = float(Time.get_ticks_usec() - _last_tick_time_usec) / 1000000.0 * time_scale
	return clampf((_tick_accumulator + elapsed) * TICK_RATE, 0.0, 1.0)


## Back to the start of a new game: starting money, a stopped clock and a fresh order. Machines unregister
## themselves when their scene leaves the tree.
func reset() -> void:
	ChipRegistry.release_all_creators()
	tick_count = 0
	_tick_accumulator = 0.0
	_last_tick_time_usec = Time.get_ticks_usec()
	money = START_MONEY
	EventBus.money_changed.emit(money)
	_start_order(STARTING_ORDER_PRODUCT, ORDER_QUANTITY)


func is_in_grid(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < GRID_SIZE.x and cell.y < GRID_SIZE.y


func can_place(cell: Vector2i) -> bool:
	return is_in_grid(cell) and not _machines.has(cell)


func register_machine(machine: Node, cell: Vector2i) -> bool:
	if not can_place(cell):
		return false
	_machines[cell] = machine
	EventBus.machine_registered.emit(machine, cell)
	return true


func unregister_machine(cell: Vector2i) -> void:
	if not _machines.has(cell):
		return
	var machine: Node = _machines[cell]
	_machines.erase(cell)
	EventBus.machine_unregistered.emit(machine, cell)


func get_machine_at(cell: Vector2i) -> Node:
	return _machines.get(cell, null)


func get_machines() -> Array:
	return _machines.values()


func cell_to_world(cell: Vector2i) -> Vector2:
	return Vector2(cell * CELL_SIZE)


func world_to_cell(pos: Vector2) -> Vector2i:
	return Vector2i((pos / CELL_SIZE).floor())


func add_money(amount: int) -> void:
	money += amount
	EventBus.money_changed.emit(money)


## Counts a Collector sale of `item` toward the current order. A no-op with no active order, an order
## already complete, or a sale of something else. Pays the reward through add_money, distinct from the
## item's own sale price, and starts the next order once the quantity is reached.
func record_order_sale(item: String) -> void:
	if order_product == "" or item != order_product or order_progress >= order_quantity:
		return
	order_progress += 1
	EventBus.order_progress_changed.emit(order_product, order_progress, order_quantity, order_reward)
	if order_progress < order_quantity:
		return
	var fulfilled: String = order_product
	var reward: int = order_reward
	add_money(reward)
	EventBus.order_completed.emit(fulfilled, reward)
	_start_next_order()


## Restores order state saved by SaveGame. Does not touch money: a saved reward already paid is part of
## the saved money total.
func restore_order(product: String, quantity: int, progress: int, reward: int) -> void:
	order_product = product
	order_quantity = quantity
	order_progress = progress
	order_reward = reward
	EventBus.order_progress_changed.emit(order_product, order_progress, order_quantity, order_reward)


## A new order for `quantity` of `product`, progress at 0, reward computed from the catalog price.
func _start_order(product: String, quantity: int) -> void:
	order_product = product
	order_quantity = quantity
	order_progress = 0
	order_reward = ItemCatalog.shared().price_of(product) * quantity * ORDER_REWARD_MULTIPLIER
	EventBus.order_progress_changed.emit(order_product, order_progress, order_quantity, order_reward)


## The simplest follow-up that still demos well: a new order starts right away, for a resource picked at
## random from the whole catalog, so the goal keeps changing without needing a player trigger.
func _start_next_order() -> void:
	var ids: Array[String] = ItemCatalog.shared().get_ids()
	_start_order(ids[randi() % ids.size()] if not ids.is_empty() else "", ORDER_QUANTITY)


func _advance_clock(elapsed: float) -> void:
	_tick_accumulator += elapsed
	var interval: float = 1.0 / TICK_RATE
	while _tick_accumulator >= interval:
		_tick_accumulator -= interval
		tick_count += 1
		EventBus.tick_fired.emit(tick_count)
