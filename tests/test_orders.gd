extends "res://tests/test_case.gd"
## Orders and progression (GameState): fulfillment counting, reward payout and save/load restore.

var _game: Node
var _bus: Node
var _nodes: Array[Node] = []
var _saved_money: int = 0
var _saved_ticks: int = 0
var _saved_order: Dictionary = {}


func before_each() -> void:
	_game = autoload("GameState")
	_bus = autoload("EventBus")
	_saved_money = _game.money
	_saved_ticks = _game.tick_count
	_saved_order = {"product": _game.order_product, "quantity": _game.order_quantity, "progress": _game.order_progress, "reward": _game.order_reward}


func after_each() -> void:
	for node: Node in _nodes:
		node.free()
	_nodes.clear()
	_game.money = _saved_money
	_game.tick_count = _saved_ticks
	_game.restore_order(_saved_order["product"], _saved_order["quantity"], _saved_order["progress"], _saved_order["reward"])


func _collector() -> Collector:
	var collector: Collector = (load("res://scenes/machines/collector.tscn") as PackedScene).instantiate() as Collector
	collector.cell = Vector2i(0, 0)
	tree.root.add_child(collector)
	_nodes.append(collector)
	return collector


func test_a_new_game_starts_with_one_order() -> void:
	_game.reset()
	check_eq(_game.order_product, _game.STARTING_ORDER_PRODUCT, "the starting order's product")
	check_eq(_game.order_quantity, _game.ORDER_QUANTITY, "the starting order's quantity")
	check_eq(_game.order_progress, 0, "progress starts at 0")
	check_eq(_game.order_reward, ItemCatalog.shared().price_of(_game.STARTING_ORDER_PRODUCT) * _game.ORDER_QUANTITY * _game.ORDER_REWARD_MULTIPLIER, "the reward matches the catalog price")


func test_selling_the_ordered_product_advances_progress() -> void:
	_game.reset()
	var product: String = _game.order_product
	var seen: Array = []
	var on_progress: Callable = func(p: String, progress: int, quantity: int, reward: int) -> void: seen.append([p, progress, quantity, reward])
	_bus.order_progress_changed.connect(on_progress)
	var collector: Collector = _collector()
	check(collector.receive(product), "the sale is accepted")
	_bus.order_progress_changed.disconnect(on_progress)
	check_eq(_game.order_progress, 1, "one sale advances progress by one")
	check_eq(seen, [[product, 1, _game.order_quantity, _game.order_reward]], "order_progress_changed fires with the new progress")


func test_selling_something_else_does_not_advance_it() -> void:
	_game.reset()
	var other: String = "coal" if _game.order_product != "coal" else "silver"
	var collector: Collector = _collector()
	collector.receive(other)
	check_eq(_game.order_progress, 0, "selling something else does not count")


func test_a_refused_sale_does_not_advance_it() -> void:
	_game.reset()
	var collector: Collector = _collector()
	collector.accepting = false
	collector.receive(_game.order_product)
	check_eq(_game.order_progress, 0, "a refused sale is not counted")


func test_completing_the_order_pays_the_reward_and_starts_a_new_one() -> void:
	_game.reset()
	var product: String = _game.order_product
	var quantity: int = _game.order_quantity
	var reward: int = _game.order_reward
	var completed: Array = []
	var on_completed: Callable = func(p: String, r: int) -> void: completed.append([p, r])
	_bus.order_completed.connect(on_completed)
	var collector: Collector = _collector()
	var before: int = _game.money
	for i: int in quantity:
		collector.receive(product)
	_bus.order_completed.disconnect(on_completed)
	check_eq(completed, [[product, reward]], "order_completed fires once with the fulfilled product and reward")
	var expected_sales: int = ItemCatalog.shared().price_of(product) * quantity
	check_eq(_game.money, before + expected_sales + reward, "the reward is paid on top of the ordinary per-item sales")
	check_eq(_game.order_progress, 0, "a new order starts right away, progress back at 0")
	check(_game.order_quantity > 0, "the new order has a quantity")
	check(_game.order_reward > 0, "and a reward")


func test_record_order_sale_does_nothing_once_the_order_is_already_complete() -> void:
	_game.reset()
	_game.order_progress = _game.order_quantity
	var before_money: int = _game.money
	var completed: Array = []
	var on_completed: Callable = func(p: String, r: int) -> void: completed.append([p, r])
	_bus.order_completed.connect(on_completed)
	_game.record_order_sale(_game.order_product)
	_bus.order_completed.disconnect(on_completed)
	check_eq(_game.money, before_money, "no reward paid for a sale past the quantity")
	check(completed.is_empty(), "order_completed does not fire again")


func test_record_order_sale_is_a_no_op_with_no_active_order() -> void:
	_game.order_product = ""
	_game.order_progress = 0
	_game.record_order_sale("ingot")
	check_eq(_game.order_progress, 0, "nothing to advance without an active order")


func test_save_and_load_round_trips_order_state() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(main)
	var placement: Placement = main.get_node("Game/FactoryView/SubViewport/World/Placement")
	_game.reset()
	var product: String = _game.order_product
	var collector: Collector = _game.get_machine_at(_game.GRID_SIZE / 2) as Collector
	collector.receive(product)
	check_eq(_game.order_progress, 1, "progress before saving")
	var save: Dictionary = SaveGame.snapshot(placement)
	check_eq(save["order"], {"product": product, "quantity": _game.order_quantity, "progress": 1, "reward": _game.order_reward}, "the order is embedded in the save")
	_game.order_progress = 0
	_game.order_product = "coal"
	check_eq(SaveGame.restore(placement, save), "", "restore accepts its own snapshot")
	check_eq(_game.order_product, product, "product restored")
	check_eq(_game.order_progress, 1, "progress restored")
	check_eq(_game.order_quantity, save["order"]["quantity"], "quantity restored")
	check_eq(_game.order_reward, save["order"]["reward"], "reward restored")
	main.free()


func test_validate_rejects_a_malformed_order() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(main)
	var placement: Placement = main.get_node("Game/FactoryView/SubViewport/World/Placement")
	_game.reset()
	var save: Dictionary = SaveGame.snapshot(placement)
	for bad: Variant in ["not a dict", {"product": 3, "quantity": 1, "progress": 0, "reward": 0}, {"product": "ore", "quantity": -1, "progress": 0, "reward": 0}, {"product": "ore", "quantity": 1, "progress": 2, "reward": 0}, {"product": "ore", "quantity": 1, "progress": 0, "reward": -1}, {"product": "unknown", "quantity": 1, "progress": 0, "reward": 1}, {"product": "ore", "quantity": 0, "progress": 0, "reward": 0}, {"product": "ore", "quantity": 1, "progress": 1, "reward": 1}, {"product": "", "quantity": 1, "progress": 0, "reward": 0}]:
		save["order"] = bad
		check(SaveGame.validate(placement, save) != "", "rejected: %s" % str(bad))
	main.free()


func test_a_save_without_an_order_leaves_the_current_one_alone() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(main)
	var placement: Placement = main.get_node("Game/FactoryView/SubViewport/World/Placement")
	_game.reset()
	var save: Dictionary = SaveGame.snapshot(placement)
	save.erase("order")
	_game.order_progress = 3
	check_eq(SaveGame.restore(placement, save), "", "a save without an order is still accepted")
	check_eq(_game.order_progress, 3, "the current order is left untouched")
	main.free()
