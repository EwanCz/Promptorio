extends "res://tests/test_case.gd"
## The resource catalog (data/items.tres) and how machines and the Collector use it.

const SCENES: Dictionary = {
	"miner": "res://scenes/machines/miner.tscn",
	"smelter": "res://scenes/machines/smelter.tscn",
	"assembler": "res://scenes/machines/assembler.tscn",
	"collector": "res://scenes/machines/collector.tscn",
}

var _game: Node
var _bus: Node
var _nodes: Array[Node] = []
var _saved_money: int = 0


func before_each() -> void:
	_game = autoload("GameState")
	_bus = autoload("EventBus")
	_saved_money = _game.money


func after_each() -> void:
	for node: Node in _nodes:
		node.free()
	_nodes.clear()
	_game.money = _saved_money


func _put(type: String, cell: Vector2i, facing: Vector2i = Vector2i.RIGHT) -> Machine:
	var machine: Machine = (load(SCENES[type]) as PackedScene).instantiate() as Machine
	machine.cell = cell
	machine.facing = facing
	tree.root.add_child(machine)
	_game.register_machine(machine, cell)
	_nodes.append(machine)
	return machine


func _ticks(count: int) -> void:
	for i: int in count:
		_bus.tick_fired.emit(i)


func _depends_on(catalog: ItemCatalog, id: String, target: String) -> bool:
	for input: String in catalog.get_item(id).inputs:
		if input == target or _depends_on(catalog, input, target):
			return true
	return false


# --- the catalog data ---

func test_catalog_is_valid() -> void:
	var catalog: ItemCatalog = ItemCatalog.shared()
	check(catalog.items.size() > 0, "the catalog is not empty")
	var seen: Array[String] = []
	for item: ItemData in catalog.items:
		check(item.id != "" and not item.id in seen, "%s has a unique id" % item.id)
		seen.append(item.id)
		check(item.display_name != "", "%s has a name" % item.id)
		check(item.price > 0, "%s has a price" % item.id)
		check(item.machine in ["miner", "smelter", "assembler"], "%s is built by a machine type that builds things" % item.id)
		if item.is_mined():
			check(item.inputs.is_empty(), "%s is mined, so it needs nothing" % item.id)
		else:
			check(not item.inputs.is_empty() and item.ticks > 0, "%s needs inputs and time" % item.id)
		for input: String in item.inputs:
			check(catalog.has_item(input), "%s needs %s, which exists" % [item.id, input])
			check(int(item.inputs[input]) > 0, "%s needs a positive count of %s" % [item.id, input])
		check(not _depends_on(catalog, item.id, item.id), "%s does not need itself" % item.id)


func test_every_machine_type_that_builds_has_a_default() -> void:
	var catalog: ItemCatalog = ItemCatalog.shared()
	for type: String in ["miner", "smelter", "assembler"]:
		check(catalog.get_built_by(type).size() > 0, "%s builds something" % type)
		for item: ItemData in catalog.get_built_by(type):
			check_eq(item.machine, type, "%s is built by %s only" % [item.id, type])
	check_eq(catalog.get_built_by("collector"), [], "the collector builds nothing")


func test_the_example_chain_exists() -> void:
	var catalog: ItemCatalog = ItemCatalog.shared()
	check_eq(catalog.get_item("spear").inputs, {"wood": 1, "silver": 1}, "wood + silver make a spear")
	check_eq(catalog.get_item("spear").machine, "assembler", "in an assembler")
	check_eq(catalog.get_item("gun").inputs, {"spear": 1, "power": 1}, "a spear + power make a gun")
	check_eq(catalog.get_item("power").machine, "smelter", "power comes from a smelter")
	check(catalog.get_item("gun").price > catalog.price_of("spear") + catalog.price_of("power"), "a gun sells for more than its parts")


func test_lookups() -> void:
	var catalog: ItemCatalog = ItemCatalog.shared()
	check(catalog.get_item("nothing") == null, "unknown id gives null")
	check(not catalog.has_item("nothing"), "has_item is false")
	check_eq(catalog.price_of("nothing"), 0, "unknown id has no price")
	check_eq(catalog.price_of("ore"), 1, "ore price")
	check(catalog.get_ids().has("gun"), "get_ids lists every resource")
	check_eq(catalog.get_built_by_ids("miner")[0], "ore", "the first resource of a type is its default")


# --- machines ---

func test_machines_start_on_their_default_resource() -> void:
	check_eq((_put("smelter", Vector2i(0, 0)) as CraftMachine).product_id, "ingot", "smelter")
	check_eq((_put("assembler", Vector2i(2, 0)) as CraftMachine).product_id, "part", "assembler")
	check_eq((_put("miner", Vector2i(4, 0)) as Miner).item, "ore", "miner")


func test_set_mined_item_changes_what_is_mined() -> void:
	var miner: Miner = _put("miner", Vector2i(0, 0)) as Miner
	var collector: Collector = _put("collector", Vector2i(1, 0)) as Collector
	_game.money = 0
	check(miner.apply_tool_call("set_mined_item", {"item": "silver"}), "a mined resource is accepted")
	check_eq(miner.get_state()["item"], "silver", "state shows it")
	_ticks(miner.mine_ticks + 1)
	check_eq(collector.sold, 1, "one unit mined")
	check_eq(_game.money, ItemCatalog.shared().price_of("silver"), "and sold at the silver price")
	check(not miner.apply_tool_call("set_mined_item", {"item": "ingot"}), "a smelted resource cannot be mined")
	check(not miner.apply_tool_call("set_mined_item", {"item": "nothing"}), "nor an unknown one")
	check_eq(miner.item, "silver", "a refused call changes nothing")


func test_set_product_only_offers_what_the_machine_builds() -> void:
	var smelter: CraftMachine = _put("smelter", Vector2i(0, 0)) as CraftMachine
	var assembler: CraftMachine = _put("assembler", Vector2i(2, 0)) as CraftMachine
	check(smelter.apply_tool_call("set_product", {"item": "power"}), "a smelter can build power")
	check_eq(smelter.get_product().id, "power", "product changed")
	check(not smelter.apply_tool_call("set_product", {"item": "spear"}), "a smelter cannot build a spear")
	check(not smelter.apply_tool_call("set_product", {"item": "ore"}), "a smelter cannot build a mined resource")
	check_eq(smelter.product_id, "power", "refused calls change nothing")
	check(assembler.apply_tool_call("set_product", {"item": "gun"}), "an assembler can build a gun")
	check(not assembler.apply_tool_call("set_product", {"item": "power"}), "an assembler cannot build power")
	check(not assembler.apply_tool_call("set_product", {"item": 3}), "a number is not a resource")


func test_crafting_needs_every_input_in_its_count() -> void:
	var assembler: CraftMachine = _put("assembler", Vector2i(0, 0)) as CraftMachine
	var collector: Collector = _put("collector", Vector2i(1, 0)) as Collector
	assembler.apply_tool_call("set_product", {"item": "spear"})
	assembler.receive("wood")
	_ticks(100)
	check_eq(collector.sold, 0, "wood alone makes nothing")
	assembler.receive("silver")
	_ticks(100)
	check_eq(collector.sold, 1, "wood + silver make a spear")
	check_eq(assembler.stock.get("wood", 0), 0, "the wood was consumed")
	check_eq(assembler.stock.get("silver", 0), 0, "the silver was consumed")


func test_the_chain_reaches_a_gun() -> void:
	var smelter: CraftMachine = _put("smelter", Vector2i(0, 0)) as CraftMachine
	var assembler: CraftMachine = _put("assembler", Vector2i(1, 0)) as CraftMachine
	var collector: Collector = _put("collector", Vector2i(2, 0)) as Collector
	_game.money = 0
	smelter.apply_tool_call("set_product", {"item": "power"})
	assembler.apply_tool_call("set_product", {"item": "gun"})
	smelter.receive("coal")
	smelter.receive("coal")
	assembler.receive("spear")
	_ticks(200)
	check_eq(collector.sold, 1, "a gun was built from a spear and power made next door")
	check_eq(_game.money, ItemCatalog.shared().price_of("gun"), "and sold at the gun price")


func test_changing_product_lets_the_running_craft_finish() -> void:
	var smelter: CraftMachine = _put("smelter", Vector2i(0, 0)) as CraftMachine
	var collector: Collector = _put("collector", Vector2i(1, 0)) as Collector
	_game.money = 0
	smelter.receive("ore")
	_ticks(1)
	check(smelter.progress > 0, "an ingot is being smelted")
	smelter.apply_tool_call("set_product", {"item": "power"})
	_ticks(100)
	check_eq(collector.sold, 1, "the running craft finished")
	check_eq(_game.money, ItemCatalog.shared().price_of("ingot"), "as an ingot, not as the new product")


func test_discard_stock_removes_units() -> void:
	var smelter: CraftMachine = _put("smelter", Vector2i(0, 0)) as CraftMachine
	for i: int in 3:
		smelter.receive("wood")
	check(smelter.apply_tool_call("discard_stock", {"item": "wood", "count": 2}), "tool accepted")
	check_eq(smelter.stock["wood"], 1, "two units thrown away")
	smelter.apply_tool_call("discard_stock", {"item": "wood", "count": 5})
	check(not smelter.stock.has("wood"), "throwing away more than held empties the entry")
	check(smelter.apply_tool_call("discard_stock", {"item": "gun", "count": 1}), "discarding what is not held is harmless")
	check(not smelter.apply_tool_call("discard_stock", {"item": "nothing", "count": 1}), "an unknown resource is refused")
	check(not smelter.apply_tool_call("discard_stock", {"item": "wood"}), "the count is required")
	smelter.receive("wood")
	smelter.receive("wood")
	smelter.apply_tool_call("discard_stock", {"item": "wood", "count": 0})
	check_eq(smelter.stock["wood"], 1, "a count below 1 is clamped to 1")


func test_a_full_stock_of_something_else_does_not_block_the_recipe() -> void:
	var smelter: CraftMachine = _put("smelter", Vector2i(0, 0)) as CraftMachine
	for i: int in CraftMachine.MAX_STOCK:
		smelter.receive("wood")
	check(smelter.receive("ore"), "ore still fits")
	check(smelter.get_events().find("input_empty") == -1, "and the smelter can start")


func test_state_tells_the_chip_what_is_built_and_needed() -> void:
	var assembler: CraftMachine = _put("assembler", Vector2i(0, 0)) as CraftMachine
	assembler.apply_tool_call("set_product", {"item": "gun"})
	var state: Dictionary = assembler.get_state()
	check_eq(state["product"], "gun", "product")
	check_eq(state["needs"], {"spear": 1, "power": 1}, "needs")
	check(assembler.get_action_text().contains("gun"), "the action text names the product")


func test_an_unknown_product_builds_nothing() -> void:
	var smelter: CraftMachine = _put("smelter", Vector2i(0, 0)) as CraftMachine
	smelter.product_id = "nothing"
	smelter.receive("ore")
	_ticks(100)
	check_eq(smelter.progress, 0, "no craft starts")
	check(smelter.get_action_text().begins_with("No product"), "action text")
	check_eq(smelter.get_state()["needs"], {}, "needs nothing")


# --- selling ---

func test_collector_pays_the_catalog_price() -> void:
	var collector: Collector = _put("collector", Vector2i(0, 0)) as Collector
	_game.money = 0
	var expected: int = 0
	for item: ItemData in ItemCatalog.shared().items:
		check(collector.receive(item.id), "%s is bought" % item.id)
		expected += item.price
	check_eq(_game.money, expected, "every resource sold for its price")
	check_eq(collector.earned, expected, "earnings match")


func test_collector_refuses_what_is_not_a_resource() -> void:
	var collector: Collector = _put("collector", Vector2i(0, 0)) as Collector
	_game.money = 0
	check(not collector.receive("nothing"), "refused")
	check_eq(_game.money, 0, "and not paid")
	check_eq(collector.sold, 0, "nor counted")
