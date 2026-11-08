extends "res://tests/test_case.gd"

var _game_state: Node
var _bus: Node


func before_each() -> void:
	_game_state = autoload("GameState")
	_bus = autoload("EventBus")


func test_grid_bounds() -> void:
	check(_game_state.can_place(Vector2i(2, 3)), "free cell can be placed on")
	check(not _game_state.can_place(Vector2i(-1, 0)), "negative cell rejected")
	check(not _game_state.can_place(_game_state.GRID_SIZE), "cell past the edge rejected")


func test_register_and_unregister() -> void:
	var cell: Vector2i = Vector2i(2, 3)
	var machine: Node = Node.new()
	var intruder: Node = Node.new()
	var events: Array[int] = [0, 0]
	var on_registered: Callable = func(_m: Node, _c: Vector2i) -> void: events[0] += 1
	var on_unregistered: Callable = func(_m: Node, _c: Vector2i) -> void: events[1] += 1
	_bus.machine_registered.connect(on_registered)
	_bus.machine_unregistered.connect(on_unregistered)

	check(_game_state.register_machine(machine, cell), "register succeeds")
	check(not _game_state.register_machine(intruder, cell), "double register rejected")
	check_eq(_game_state.get_machine_at(cell), machine, "get_machine_at returns the machine")
	check_eq(_game_state.get_machines().size(), 1, "get_machines has one entry")
	check_eq(events[0], 1, "machine_registered emitted once")
	_game_state.unregister_machine(cell)
	check_eq(_game_state.get_machine_at(cell), null, "unregister frees the cell")
	check_eq(events[1], 1, "machine_unregistered emitted once")
	_game_state.unregister_machine(cell)
	check_eq(events[1], 1, "unregistering an empty cell emits nothing")

	_bus.machine_registered.disconnect(on_registered)
	_bus.machine_unregistered.disconnect(on_unregistered)
	machine.free()
	intruder.free()


func test_cell_world_conversion() -> void:
	var cell: Vector2i = Vector2i(5, 7)
	var world: Vector2 = _game_state.cell_to_world(cell)
	check_eq(_game_state.world_to_cell(world + Vector2(1, 1)), cell, "cell/world conversion round-trips")


func test_money() -> void:
	var seen: Array[int] = [0]
	var on_money: Callable = func(amount: int) -> void: seen[0] = amount
	_bus.money_changed.connect(on_money)
	var before: int = _game_state.money
	_game_state.add_money(25)
	check_eq(_game_state.money, before + 25, "add_money updates the total")
	check_eq(seen[0], before + 25, "money_changed carries the new total")
	_game_state.add_money(-25)
	_bus.money_changed.disconnect(on_money)


func test_tick_rate() -> void:
	var ticks: Array[int] = [0]
	var on_tick: Callable = func(_t: int) -> void: ticks[0] += 1
	_bus.tick_fired.connect(on_tick)
	var start: int = _game_state.tick_count
	await wait_seconds(1.0)
	_bus.tick_fired.disconnect(on_tick)
	check(ticks[0] >= 8 and ticks[0] <= 12, "about 10 ticks in 1 s (got %d)" % ticks[0])
	check_eq(_game_state.tick_count - start, ticks[0], "tick_count matches emitted signals")


func test_clock_catches_up_after_stall() -> void:
	var start: int = _game_state.tick_count
	var previous_accumulator: float = _game_state._tick_accumulator
	_game_state._tick_accumulator = 0.0
	_game_state._advance_clock(0.55)
	check_eq(_game_state.tick_count - start, 5, "a long interval emits every elapsed tick")
	_game_state._tick_accumulator = previous_accumulator


func test_reset_starts_a_new_game() -> void:
	var saved_money: int = _game_state.money
	var saved_ticks: int = _game_state.tick_count
	var saved_product: String = _game_state.order_product
	var saved_quantity: int = _game_state.order_quantity
	var saved_progress: int = _game_state.order_progress
	var saved_reward: int = _game_state.order_reward
	var seen: Array[int] = []
	var on_money: Callable = func(amount: int) -> void: seen.append(amount)
	_bus.money_changed.connect(on_money)
	_game_state.money = 5
	_game_state.tick_count = 99
	_game_state.reset()
	_bus.money_changed.disconnect(on_money)
	check_eq(_game_state.money, _game_state.START_MONEY, "money is back to the start value")
	check_eq(_game_state.tick_count, 0, "the clock restarts")
	check_eq(seen, [_game_state.START_MONEY], "money_changed announces it")
	check_eq(_game_state.order_product, _game_state.STARTING_ORDER_PRODUCT, "a fresh order starts too")
	check_eq(_game_state.order_progress, 0, "at zero progress")
	_game_state.money = saved_money
	_game_state.tick_count = saved_ticks
	_game_state.order_product = saved_product
	_game_state.order_quantity = saved_quantity
	_game_state.order_progress = saved_progress
	_game_state.order_reward = saved_reward
