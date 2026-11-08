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
		check(item.ticks > 0, "%s takes time" % item.id)
		if item.is_mined():
			check(item.inputs.is_empty(), "%s is mined, so it needs nothing" % item.id)
			check(item.ticks <= Miner.MAX_MINE_TICKS, "%s can still be mined at the slowest pace" % item.id)
		else:
			check(not item.inputs.is_empty(), "%s needs inputs" % item.id)
		for input: String in item.inputs:
			check(catalog.has_item(input), "%s needs %s, which exists" % [item.id, input])
			check(int(item.inputs[input]) > 0, "%s needs a positive count of %s" % [item.id, input])
		check(not _depends_on(catalog, item.id, item.id), "%s does not need itself" % item.id)
		var inputs_value: int = 0
		for input: String in item.inputs:
			inputs_value += catalog.price_of(input) * int(item.inputs[input])
		check(item.is_mined() or item.price > inputs_value, "%s sells for more than its inputs" % item.id)


func test_every_machine_type_that_builds_has_a_default() -> void:
	var catalog: ItemCatalog = ItemCatalog.shared()
	for type: String in ["miner", "smelter", "assembler"]:
		check(catalog.get_built_by(type).size() > 0, "%s builds something" % type)
		for item: ItemData in catalog.get_built_by(type):
			check_eq(item.machine, type, "%s is built by %s only" % [item.id, type])
	check_eq(catalog.get_built_by("collector"), [], "the collector builds nothing")


func test_the_mined_resources() -> void:
	check_eq(ItemCatalog.shared().get_built_by_ids("miner"), ["ore", "coal", "silver", "redstone", "diamond"], "what a miner can mine")
	check(not ItemCatalog.shared().has_item("wood") and not ItemCatalog.shared().has_item("spear"), "wood and what needed it are gone")


func test_the_chains_exist() -> void:
	var catalog: ItemCatalog = ItemCatalog.shared()
	check_eq(catalog.get_item("circuit").inputs, {"silver_bar": 1, "redstone": 2}, "a silver bar + 2 redstone make a circuit")
	check_eq(catalog.get_item("silver_bar").inputs, {"silver": 1}, "the silver bar is smelted silver")
	check_eq(catalog.get_item("gun").inputs, {"steel": 1, "circuit": 1, "power": 1}, "a gun")
	check_eq(catalog.get_item("steel").inputs, {"ingot": 2, "coal": 1}, "steel mixes ingots and coal")
	check_eq(catalog.get_item("robot").inputs, {"circuit": 2, "battery": 1, "part": 2}, "a robot")
	check(catalog.get_item("robot").price > catalog.get_item("gun").price, "the robot is the top of the tree")
	check(_depends_on(catalog, "robot", "ore") and _depends_on(catalog, "robot", "redstone"), "it needs both ore and redstone, mined further down")
	check(_depends_on(catalog, "drill", "diamond"), "diamond goes into the drill")


func test_lookups() -> void:
	var catalog: ItemCatalog = ItemCatalog.shared()
	check(catalog.get_item("nothing") == null, "unknown id gives null")
	check(not catalog.has_item("nothing"), "has_item is false")
	check_eq(catalog.price_of("nothing"), 0, "unknown id has no price")
	check_eq(catalog.price_of("ore"), 1, "ore price")
	check_eq(catalog.ticks_of("diamond"), catalog.get_item("diamond").ticks, "ticks_of reads the item")
	check_eq(catalog.ticks_of("nothing"), 0, "unknown id has no time")
	check(catalog.get_ids().has("gun"), "get_ids lists every resource")
	check_eq(catalog.get_built_by_ids("miner")[0], "ore", "the first resource of a type is its default")


# --- machines ---

func test_machines_start_on_their_default_resource() -> void:
	check_eq((_put("smelter", Vector2i(0, 0)) as CraftMachine).product_id, "ingot", "smelter")
	check_eq((_put("assembler", Vector2i(2, 0)) as CraftMachine).product_id, "part", "assembler")
	check_eq((_put("miner", Vector2i(4, 0)) as Miner).item, "ore", "miner")


func test_every_resource_has_its_own_mining_time() -> void:
	var miner: Miner = _put("miner", Vector2i(0, 0)) as Miner
	var collector: Collector = _put("collector", Vector2i(1, 0)) as Collector
	var catalog: ItemCatalog = ItemCatalog.shared()
	check(catalog.get_item("diamond").ticks > catalog.get_item("ore").ticks, "a diamond takes longer than ore")
	for item: ItemData in catalog.get_built_by("miner"):
		check(miner.set_mined_item(item.id), "%s can be mined" % item.id)
		check_eq(miner.mine_ticks, item.ticks, "%s starts at its own time" % item.id)
		check_eq(miner.get_state()["mine_ticks"], item.ticks, "the state shows it for %s" % item.id)
		collector.sold = 0
		miner.clear_contents()
		_ticks(item.ticks - 1)
		check_eq(collector.sold, 0, "%s is not ready one tick early" % item.id)
		_ticks(2)
		check_eq(collector.sold, 1, "%s is mined and delivered after its time" % item.id)


func test_a_chip_can_slow_mining_down_but_not_below_the_resource_time() -> void:
	var miner: Miner = _put("miner", Vector2i(0, 0)) as Miner
	miner.set_mined_item("diamond")
	var floor_ticks: int = ItemCatalog.shared().get_item("diamond").ticks
	check(miner.apply_tool_call("set_mine_ticks", {"ticks": 1}), "the call is valid")
	check_eq(miner.mine_ticks, floor_ticks, "but a diamond cannot be mined faster than its time")
	miner.apply_tool_call("set_mine_ticks", {"ticks": Miner.MAX_MINE_TICKS})
	check_eq(miner.mine_ticks, Miner.MAX_MINE_TICKS, "slowing down is allowed")
	miner.set_mined_item("ore")
	check_eq(miner.mine_ticks, ItemCatalog.shared().get_item("ore").ticks, "switching resource restarts at the new resource's time")
	check_eq(miner.get_min_mine_ticks(), ItemCatalog.shared().get_item("ore").ticks, "and the floor follows it")
	check(not miner.set_mined_item("ingot"), "a refused switch")
	check_eq(miner.mine_ticks, ItemCatalog.shared().get_item("ore").ticks, "leaves the pace alone")
	for schema: Dictionary in miner.get_tool_schemas():
		if schema["name"] == "set_mine_ticks":
			check_eq(schema["input_schema"]["properties"]["ticks"]["minimum"], miner.get_min_mine_ticks(), "the tool schema shows the floor")


func test_set_mined_item_changes_what_is_mined() -> void:
	var miner: Miner = _put("miner", Vector2i(0, 0)) as Miner
	var collector: Collector = _put("collector", Vector2i(1, 0)) as Collector
	_game.money = 0
	check(miner.set_mined_item("coal") and not miner.set_mined_item("ingot"), "set_mined_item checks it too")
	check(miner.apply_tool_call("set_mined_item", {"item": "silver"}), "a mined resource is accepted")
	check_eq(miner.get_state()["item"], "silver", "state shows it")
	_ticks(miner.mine_ticks + 1)
	check_eq(collector.sold, 1, "one unit mined")
	check_eq(_game.money, ItemCatalog.shared().price_of("silver"), "and sold at the silver price")
	check(not miner.apply_tool_call("set_mined_item", {"item": "ingot"}), "a smelted resource cannot be mined")
	check(not miner.apply_tool_call("set_mined_item", {"item": "nothing"}), "nor an unknown one")
	check_eq(miner.item, "silver", "a refused call changes nothing")


func test_set_product_checks_the_machine_may_build_it() -> void:
	var smelter: CraftMachine = _put("smelter", Vector2i(0, 0)) as CraftMachine
	check(smelter.set_product("power"), "a smelter may build power")
	check_eq(smelter.product_id, "power", "and the product is updated")
	check(not smelter.set_product("circuit"), "an assembler resource fails")
	check(not smelter.set_product("ore"), "a mined resource fails")
	check(not smelter.set_product("nothing"), "an unknown resource fails")
	check_eq(smelter.product_id, "power", "a failure leaves the product alone")
	var assembler: CraftMachine = _put("assembler", Vector2i(2, 0)) as CraftMachine
	check(assembler.set_product("gun") and not assembler.set_product("ingot"), "same rule on an assembler")


func test_a_machine_with_no_known_type_builds_nothing() -> void:
	var bare: CraftMachine = CraftMachine.new()
	_nodes.append(bare)
	check(not bare.set_product("ingot"), "no type, no product")
	check_eq(bare.product_id, "", "unchanged")
	var bare_miner: Miner = Miner.new()
	_nodes.append(bare_miner)
	check(not bare_miner.set_mined_item("coal"), "same for a miner")


func test_a_refused_tool_call_is_logged_and_not_reported_as_applied() -> void:
	var smelter: CraftMachine = _put("smelter", Vector2i(0, 0)) as CraftMachine
	var applied: Array[String] = []
	var lines: Array[String] = []
	smelter.tool_applied.connect(func(tool_name: String, _args: Dictionary) -> void: applied.append(tool_name))
	var on_log: Callable = func(machine: Node, message: String) -> void:
		if machine == smelter:
			lines.append(message)
	_bus.chip_log_added.connect(on_log)
	check(not smelter.apply_tool_call("set_product", {"item": "circuit"}), "the call fails")
	check(smelter.apply_tool_call("set_product", {"item": "power"}), "an allowed one works")
	_bus.chip_log_added.disconnect(on_log)
	check_eq(applied, ["set_product"], "tool_applied fired only for the allowed call")
	check_eq(lines.size(), 2, "one log line each")
	check(lines[0].begins_with("ignored set_product") and lines[0].contains("circuit"), "the refusal names the tool and the resource")
	check(lines[1].begins_with("set_product("), "the success is logged as applied")
	check(lines[0].contains("'circuit' cannot be made by this smelter: it is built by assemblers"), "the refusal explains why")
	check(not lines[0].contains("the machine refused it"), "instead of the generic message")


func test_set_product_only_offers_what_the_machine_builds() -> void:
	var smelter: CraftMachine = _put("smelter", Vector2i(0, 0)) as CraftMachine
	var assembler: CraftMachine = _put("assembler", Vector2i(2, 0)) as CraftMachine
	check(smelter.apply_tool_call("set_product", {"item": "power"}), "a smelter can build power")
	check_eq(smelter.get_product().id, "power", "product changed")
	check(not smelter.apply_tool_call("set_product", {"item": "circuit"}), "a smelter cannot build a circuit")
	check(not smelter.apply_tool_call("set_product", {"item": "ore"}), "a smelter cannot build a mined resource")
	check_eq(smelter.product_id, "power", "refused calls change nothing")
	check(assembler.apply_tool_call("set_product", {"item": "gun"}), "an assembler can build a gun")
	check(not assembler.apply_tool_call("set_product", {"item": "power"}), "an assembler cannot build power")
	check(not assembler.apply_tool_call("set_product", {"item": 3}), "a number is not a resource")


func test_crafting_needs_every_input_in_its_count() -> void:
	var assembler: CraftMachine = _put("assembler", Vector2i(0, 0)) as CraftMachine
	var collector: Collector = _put("collector", Vector2i(1, 0)) as Collector
	assembler.apply_tool_call("set_product", {"item": "circuit"})
	assembler.receive("silver_bar")
	_ticks(100)
	check_eq(collector.sold, 0, "a silver bar alone makes nothing")
	assembler.receive("redstone")
	_ticks(100)
	check_eq(collector.sold, 0, "one redstone is not the two it needs")
	assembler.receive("redstone")
	_ticks(100)
	check_eq(collector.sold, 1, "a silver bar + 2 redstone make a circuit")
	check_eq(assembler.stock.get("silver_bar", 0), 0, "the silver bar was consumed")
	check_eq(assembler.stock.get("redstone", 0), 0, "both redstone were consumed")


func test_a_smelter_can_mix_inputs() -> void:
	var smelter: CraftMachine = _put("smelter", Vector2i(0, 0)) as CraftMachine
	var collector: Collector = _put("collector", Vector2i(1, 0)) as Collector
	_game.money = 0
	check(smelter.set_product("steel"), "a smelter makes steel")
	smelter.receive("ingot")
	smelter.receive("ingot")
	_ticks(100)
	check_eq(collector.sold, 0, "two ingots without coal make nothing")
	smelter.receive("coal")
	_ticks(100)
	check_eq(collector.sold, 1, "two ingots + coal make steel")
	check_eq(_game.money, ItemCatalog.shared().price_of("steel"), "sold at the steel price")


func test_the_chain_reaches_a_gun() -> void:
	var smelter: CraftMachine = _put("smelter", Vector2i(0, 0)) as CraftMachine
	var assembler: CraftMachine = _put("assembler", Vector2i(1, 0)) as CraftMachine
	var collector: Collector = _put("collector", Vector2i(2, 0)) as Collector
	_game.money = 0
	smelter.apply_tool_call("set_product", {"item": "power"})
	assembler.apply_tool_call("set_product", {"item": "gun"})
	smelter.receive("coal")
	smelter.receive("coal")
	assembler.receive("steel")
	assembler.receive("circuit")
	_ticks(200)
	check_eq(collector.sold, 1, "a gun was built from steel, a circuit and the power made next door")
	check_eq(_game.money, ItemCatalog.shared().price_of("gun"), "and sold at the gun price")


func test_the_tool_lists_what_the_machine_can_build() -> void:
	var smelter: CraftMachine = _put("smelter", Vector2i(0, 0)) as CraftMachine
	for schema: Dictionary in smelter.get_tool_schemas():
		if schema["name"] == "set_product":
			check(schema["description"].contains("ingot, power"), "the description names the allowed resources")
			check(not schema["input_schema"]["properties"]["item"].has("enum"), "the check is the function's, not a schema list")


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
		smelter.receive("redstone")
	check(smelter.apply_tool_call("discard_stock", {"item": "redstone", "count": 2}), "tool accepted")
	check_eq(smelter.stock["redstone"], 1, "two units thrown away")
	smelter.apply_tool_call("discard_stock", {"item": "redstone", "count": 5})
	check(not smelter.stock.has("redstone"), "throwing away more than held empties the entry")
	check(smelter.apply_tool_call("discard_stock", {"item": "gun", "count": 1}), "discarding what is not held is harmless")
	check(not smelter.apply_tool_call("discard_stock", {"item": "nothing", "count": 1}), "an unknown resource is refused")
	check(not smelter.apply_tool_call("discard_stock", {"item": "redstone"}), "the count is required")
	smelter.receive("redstone")
	smelter.receive("redstone")
	smelter.apply_tool_call("discard_stock", {"item": "redstone", "count": 0})
	check_eq(smelter.stock["redstone"], 1, "a count below 1 is clamped to 1")


func test_a_full_stock_of_something_else_does_not_block_the_recipe() -> void:
	var smelter: CraftMachine = _put("smelter", Vector2i(0, 0)) as CraftMachine
	for i: int in CraftMachine.MAX_STOCK:
		smelter.receive("redstone")
	check(smelter.receive("ore"), "ore still fits")
	check(smelter.get_events().find("input_empty") == -1, "and the smelter can start")


func test_state_tells_the_chip_what_is_built_and_needed() -> void:
	var assembler: CraftMachine = _put("assembler", Vector2i(0, 0)) as CraftMachine
	assembler.apply_tool_call("set_product", {"item": "gun"})
	var state: Dictionary = assembler.get_state()
	check_eq(state["product"], "gun", "product")
	check_eq(state["needs"], {"steel": 1, "circuit": 1, "power": 1}, "needs")
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


func test_every_refusal_says_what_the_machine_cannot_build() -> void:
	var catalog: ItemCatalog = ItemCatalog.shared()
	check_eq(catalog.refusal_for("power", "smelter"), "", "no refusal when the machine builds it")
	check_eq(catalog.refusal_for("ore", "smelter"), "'ore' cannot be made by this smelter: it is built by miners", "a mined resource on a smelter")
	check_eq(catalog.refusal_for("gun", "miner"), "'gun' cannot be made by this miner: it is built by assemblers", "a crafted resource on a miner")
	check_eq(catalog.refusal_for("wood", "smelter"), "'wood' is not a resource of the game", "an unknown resource")
	var miner: Miner = _put("miner", Vector2i(0, 0)) as Miner
	var lines: Array[String] = []
	var on_log: Callable = func(machine: Node, message: String) -> void:
		if machine == miner:
			lines.append(message)
	_bus.chip_log_added.connect(on_log)
	check(not miner.apply_tool_call("set_mined_item", {"item": "ingot"}), "a miner cannot mine an ingot")
	check(not miner.apply_tool_call("set_mined_item", {"item": "wood"}), "nor an unknown resource")
	_bus.chip_log_added.disconnect(on_log)
	check_eq(lines.size(), 2, "one line each")
	check(lines[0].contains("'ingot' cannot be made by this miner: it is built by smelters"), "the miner log explains")
	check(lines[1].contains("'wood' is not a resource of the game"), "the unknown resource is explained")


func test_every_resource_has_a_pixel_icon() -> void:
	for item: ItemData in ItemCatalog.shared().items:
		check(item.icon != null, "%s has an icon" % item.id)
		if item.icon != null:
			check_eq(item.icon.get_size(), Vector2(32, 32), "%s icon is 32x32" % item.id)
