extends "res://tests/test_case.gd"

const SCENES: Dictionary = {
	"miner": "res://scenes/machines/miner.tscn",
	"smelter": "res://scenes/machines/smelter.tscn",
	"assembler": "res://scenes/machines/assembler.tscn",
	"collector": "res://scenes/machines/collector.tscn",
	"conveyor": "res://scenes/machines/conveyor.tscn",
}

var _game: Node
var _bus: Node
var _nodes: Array[Node] = []
var _saved_money: int = 0
var _exploded: Array = []


func before_each() -> void:
	_game = autoload("GameState")
	_bus = autoload("EventBus")
	_saved_money = _game.money
	_exploded.clear()
	_bus.machine_exploded.connect(_on_exploded)


func after_each() -> void:
	_bus.machine_exploded.disconnect(_on_exploded)
	for node: Node in _nodes:
		node.free()
	_nodes.clear()
	_game.money = _saved_money


func _on_exploded(machine: Node) -> void:
	_exploded.append(machine)


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


func test_miner_to_collector_sells_ore() -> void:
	_put("miner", Vector2i(0, 0))
	_put("conveyor", Vector2i(1, 0))
	var collector: Machine = _put("collector", Vector2i(2, 0))
	_game.money = 0
	_ticks(100)
	check(collector.sold >= 3, "collector received several ores")
	check_eq(_game.money, collector.sold, "each ore sells for 1")


func test_full_chain_makes_and_sells_parts() -> void:
	var cells: Array = ["miner", "conveyor", "smelter", "conveyor", "assembler", "conveyor", "collector"]
	var machines: Array[Machine] = []
	for i: int in cells.size():
		machines.append(_put(cells[i], Vector2i(i, 0)))
	_game.money = 0
	_ticks(400)
	var collector: Machine = machines[6]
	check(collector.sold >= 2, "parts reach the collector")
	check(_game.money >= 2 * Collector.PRICES["part"], "parts sell for the part price")


func test_blocked_output_stalls_and_resumes() -> void:
	var miner: Machine = _put("miner", Vector2i(0, 1))
	var belt: Machine = _put("conveyor", Vector2i(1, 1), Vector2i.UP)
	_ticks(200)
	check_eq(belt.held, "ore", "conveyor holds the ore it cannot hand over")
	check(not belt.receive("ore"), "a full conveyor refuses more")
	check(miner.get_state()["blocked"], "miner is blocked, not producing")
	var collector: Machine = _put("collector", Vector2i(1, 0))
	_ticks(30)
	check(collector.sold >= 1, "flow resumes once the way is free")


func test_disabled_miner_produces_nothing() -> void:
	var miner: Machine = _put("miner", Vector2i(0, 0))
	var collector: Machine = _put("collector", Vector2i(1, 0))
	miner.apply_tool_call("set_enabled", {"on": false})
	_ticks(100)
	check_eq(collector.sold, 0, "nothing mined while disabled")


func test_craft_machine_filters_and_caps_input() -> void:
	var smelter: Machine = _put("smelter", Vector2i(0, 0))
	check(not smelter.receive("ingot"), "item outside the recipe is refused")
	for i: int in CraftMachine.MAX_STOCK:
		check(smelter.receive("ore"), "ore %d accepted" % i)
	check(not smelter.receive("ore"), "stock is capped")


func test_assembler_needs_all_inputs() -> void:
	var assembler: Machine = _put("assembler", Vector2i(0, 0))
	var collector: Machine = _put("collector", Vector2i(1, 0))
	assembler.receive("ingot")
	_ticks(100)
	check_eq(collector.sold, 0, "one ingot is not enough")
	assembler.receive("ingot")
	_ticks(100)
	check_eq(collector.sold, 1, "two ingots make one part")


## A smelter with an outlet (collector above it) so it keeps working. Feeds it ore for up to
## max_ticks, stopping early on `until` (a Callable taking the smelter).
func _run_smelter(max_ticks: int, until: Callable = Callable()) -> Machine:
	_put("collector", Vector2i(1, 0))
	var smelter: Machine = _put("smelter", Vector2i(1, 1), Vector2i.UP)
	_feed(smelter, max_ticks, until)
	return smelter


func _feed(smelter: Machine, max_ticks: int, until: Callable = Callable()) -> void:
	for i: int in max_ticks:
		smelter.receive("ore")
		_ticks(1)
		if until.is_valid() and until.call(smelter):
			return


func test_unattended_smelter_overheats_then_explodes() -> void:
	var saw_overheat: Array[bool] = [false]
	var smelter: Machine = _run_smelter(600, func(m: Machine) -> bool:
		saw_overheat[0] = saw_overheat[0] or m.status == Machine.Status.OVERHEATING
		return m.status == Machine.Status.DOWN)
	check(saw_overheat[0], "passes through OVERHEATING first")
	check_eq(smelter.status, Machine.Status.DOWN, "explodes")
	check_eq(_exploded, [smelter], "machine_exploded emitted once")
	check(smelter.temperature >= Smelter.EXPLODE_AT, "at explosion temperature")
	check(not smelter.receive("ore"), "a destroyed smelter takes nothing")
	check_eq(smelter.stock, {}, "stock is lost")
	var temp: float = smelter.temperature
	_ticks(20)
	check_eq(smelter.temperature, temp, "a destroyed smelter stops simulating")


func test_smelter_turns_redder_as_it_heats_up() -> void:
	var smelter: Smelter = _put("smelter", Vector2i(0, 0)) as Smelter
	var sprite: Sprite2D = smelter.get_node("Sprite2D") as Sprite2D
	_ticks(1)
	check_eq(sprite.modulate, Color.WHITE, "a cool smelter keeps its own colours")
	var last_green: float = 1.0
	for temperature: float in [70.0, 90.0, 110.0, 140.0]:
		smelter.temperature = temperature
		smelter.apply_tool_call("set_enabled", {"on": false})
		_ticks(1)
		check_eq(sprite.modulate.r, 1.0, "red stays full at %d°" % int(temperature))
		check(sprite.modulate.g < last_green, "greener channels drop as it reaches %d°" % int(temperature))
		last_green = sprite.modulate.g
	check(last_green < 0.5, "close to exploding it is clearly red")


func test_exploding_smelter_is_destroyed_and_frees_its_cell() -> void:
	var cell: Vector2i = Vector2i(3, 3)
	var smelter: Smelter = _put("smelter", cell) as Smelter
	# It frees itself, so the test must not free it again in after_each.
	_nodes.erase(smelter)
	var ref: WeakRef = weakref(smelter)
	smelter.temperature = Smelter.EXPLODE_AT + 5.0
	_ticks(1)
	check_eq(smelter.status, Machine.Status.DOWN, "it explodes first")
	check_eq(_exploded, [smelter], "machine_exploded is emitted")
	check_eq(_game.get_machine_at(cell), smelter, "the cell is still held while it burns")
	var gone: Callable = func() -> bool: return ref.get_ref() == null or (ref.get_ref() as Node).get_parent() == null
	await wait_until(gone, 3.0)
	check(gone.call(), "the smelter is removed from the world after the explosion")
	check_eq(_game.get_machine_at(cell), null, "its cell is free again")
	await tree.process_frame
	check(ref.get_ref() == null, "and freed")


func test_machines_facing_each_other_pass_nothing() -> void:
	var smelter: Smelter = _put("smelter", Vector2i(0, 0), Vector2i.RIGHT) as Smelter
	var belt: Conveyor = _put("conveyor", Vector2i(1, 0), Vector2i.LEFT) as Conveyor
	smelter.cooling = true
	smelter.receive("ore")
	belt.receive("ore")
	_ticks(60)
	check_eq(belt.held, "ore", "the conveyor keeps its item: it faces the smelter, which faces it")
	check_eq(smelter.stock.get("ore", 0), 0, "the smelter crafted its ore")
	check(smelter.get_events().has("output_full"), "the smelter holds its ingot, it cannot hand it over")
	check(not belt.receive("ore"), "so the conveyor stays full")
	check_eq(smelter.stock.get("ingot", 0), 0, "nothing went the other way either")


func test_turning_one_machine_away_lets_the_pair_flow_again() -> void:
	var smelter: Smelter = _put("smelter", Vector2i(0, 0), Vector2i.RIGHT) as Smelter
	var belt: Conveyor = _put("conveyor", Vector2i(1, 0), Vector2i.LEFT) as Conveyor
	var collector: Machine = _put("collector", Vector2i(1, 1))
	smelter.cooling = true
	smelter.receive("ore")
	_ticks(60)
	check(smelter.get_events().has("output_full"), "blocked while facing each other")
	belt.facing = Vector2i.DOWN
	_ticks(60)
	check(not smelter.get_events().has("output_full"), "the ingot moves once the conveyor turns away")
	check(collector.sold >= 1, "and reaches the collector")


func test_head_to_tail_still_flows_and_the_collector_never_blocks() -> void:
	_put("miner", Vector2i(0, 0), Vector2i.RIGHT)
	_put("conveyor", Vector2i(1, 0), Vector2i.RIGHT)
	var collector: Machine = _put("collector", Vector2i(2, 0))
	_ticks(100)
	check(collector.sold >= 1, "head to tail still flows")
	# The collector's default facing points right, at the miner: that must not count as facing it.
	var left_collector: Machine = _put("collector", Vector2i(5, 5))
	_put("miner", Vector2i(6, 5), Vector2i.LEFT)
	check_eq(left_collector.facing, Vector2i.RIGHT, "the collector 'faces' the miner")
	_ticks(100)
	check(left_collector.sold >= 1, "yet the miner still delivers to it")


func _smelter_with_collector(cell: Vector2i) -> Array:
	var collector: Machine = _put("collector", cell)
	var smelter: Machine = _put("smelter", cell + Vector2i.DOWN, Vector2i.UP)
	return [smelter, collector]


func test_cooling_doubles_the_craft_duration() -> void:
	var plain: Machine = _smelter_with_collector(Vector2i(1, 0))[0]
	var cooled: Machine = _smelter_with_collector(Vector2i(5, 0))[0]
	cooled.apply_tool_call("set_cooling", {"on": true})
	plain.receive("ore")
	cooled.receive("ore")
	_ticks(1)
	check_eq(plain.progress, plain.recipe.ticks, "a craft takes the recipe's ticks")
	check_eq(cooled.progress, plain.recipe.ticks * 2, "twice as long while cooling")


func test_cooled_smelter_keeps_producing_at_reduced_throughput() -> void:
	var plain_pair: Array = _smelter_with_collector(Vector2i(1, 0))
	var cooled_pair: Array = _smelter_with_collector(Vector2i(5, 0))
	var plain: Machine = plain_pair[0]
	var cooled: Machine = cooled_pair[0]
	cooled.apply_tool_call("set_cooling", {"on": true})
	for i: int in 150:
		plain.receive("ore")
		cooled.receive("ore")
		_ticks(1)
	var plain_sold: int = plain_pair[1].sold
	var cooled_sold: int = cooled_pair[1].sold
	check(cooled_sold >= 2, "it keeps producing")
	check(cooled_sold < plain_sold, "but slower than an uncooled smelter")
	check(absi(plain_sold - 2 * cooled_sold) <= 2, "about half the throughput (%d vs %d)" % [cooled_sold, plain_sold])
	check_eq(plain.status, Machine.Status.NORMAL, "still within limits after 15 s")


func test_temperature_falls_during_cooled_production() -> void:
	var smelter: Machine = _smelter_with_collector(Vector2i(1, 0))[0]
	smelter.temperature = 80.0
	smelter.apply_tool_call("set_cooling", {"on": true})
	var working_ticks: int = 0
	var last: float = smelter.temperature
	var never_rose: bool = true
	for i: int in 100:
		smelter.receive("ore")
		working_ticks += 1 if smelter.is_working() else 0
		_ticks(1)
		never_rose = never_rose and smelter.temperature <= last
		last = smelter.temperature
	check(working_ticks > 50, "it was producing meanwhile")
	check(never_rose, "the temperature never rises while cooling")
	check(smelter.temperature < 80.0 - 15.0, "and ends well below where it started")


func test_cooled_production_never_explodes() -> void:
	var smelter: Machine = _smelter_with_collector(Vector2i(1, 0))[0]
	smelter.apply_tool_call("set_cooling", {"on": true})
	_feed(smelter, 1500)
	check_eq(smelter.status, Machine.Status.NORMAL, "stable with cooling on")
	check(_exploded.is_empty(), "nothing exploded")


func test_emergency_pause_recovers_and_production_resumes() -> void:
	var pair: Array = _smelter_with_collector(Vector2i(1, 0))
	var smelter: Machine = pair[0]
	var collector: Machine = pair[1]
	_feed(smelter, 600, func(m: Machine) -> bool: return m.status == Machine.Status.OVERHEATING)
	check_eq(smelter.status, Machine.Status.OVERHEATING, "an uncooled smelter overheats")
	smelter.apply_tool_call("set_enabled", {"on": false})
	smelter.apply_tool_call("set_cooling", {"on": true})
	var ticks: int = 0
	while smelter.temperature > Smelter.SAFE_AT and ticks < 300:
		_ticks(1)
		ticks += 1
	check_eq(smelter.status, Machine.Status.NORMAL, "back to normal at %d degrees or less" % int(Smelter.SAFE_AT))
	check(smelter.temperature <= Smelter.SAFE_AT, "cooled down to the resume point")
	smelter.apply_tool_call("set_enabled", {"on": true})
	var sold_before: int = collector.sold
	_feed(smelter, 400)
	check(collector.sold > sold_before, "production resumed")
	check_eq(smelter.status, Machine.Status.NORMAL, "and stays within limits while cooling")
	check(_exploded.is_empty(), "never exploded")


func test_cooling_while_idle_speeds_recovery() -> void:
	var slow: Machine = _put("smelter", Vector2i(9, 9))
	var quick: Machine = _put("smelter", Vector2i(10, 9))
	slow.temperature = 90.0
	quick.temperature = 90.0
	quick.apply_tool_call("set_cooling", {"on": true})
	_ticks(30)
	check(quick.temperature < slow.temperature, "idle with cooling cools faster than idle without")
	check(slow.temperature < 90.0, "idle without cooling still cools")


func test_disabling_an_overheating_smelter_recovers() -> void:
	var smelter: Machine = _run_smelter(600, func(m: Machine) -> bool: return m.status == Machine.Status.OVERHEATING)
	check_eq(smelter.status, Machine.Status.OVERHEATING, "got hot")
	smelter.apply_tool_call("set_enabled", {"on": false})
	_ticks(300)
	check_eq(smelter.status, Machine.Status.NORMAL, "back to normal after cooling down")
	check(_exploded.is_empty(), "never exploded")


func test_smelter_tools_and_state() -> void:
	var smelter: Machine = _put("smelter", Vector2i(0, 0))
	var names: Array = smelter.get_tool_schemas().map(func(s: Dictionary) -> String: return s["name"])
	check("set_cooling" in names and "set_enabled" in names, "exposes set_cooling and set_enabled")
	check(not smelter.apply_tool_call("set_cooling", {"on": "yes"}), "bad arg type rejected")
	check(smelter.apply_tool_call("set_cooling", {"on": true}) and smelter.cooling, "set_cooling applies")
	var state: Dictionary = smelter.get_state()
	check(state.has("temperature") and state.has("cooling") and state.has("stock"), "state has temperature, cooling, stock")


func test_machine_unregisters_when_freed() -> void:
	var machine: Machine = _put("conveyor", Vector2i(3, 3))
	check(_game.get_machine_at(Vector2i(3, 3)) == machine, "registered")
	_nodes.erase(machine)
	machine.free()
	check(_game.get_machine_at(Vector2i(3, 3)) == null, "cell freed with the machine")


## Counts how often "output_full" appears (false -> true) over `count` ticks, and whether it is on at the end.
func _output_full_rises(machine: Machine, count: int) -> int:
	var rises: int = 0
	var was_on: bool = machine.get_events().has("output_full")
	for i: int in count:
		_ticks(1)
		var is_on: bool = machine.get_events().has("output_full")
		if is_on and not was_on:
			rises += 1
		was_on = is_on
	return rises


func test_deliverable_miner_output_is_never_blocked() -> void:
	var miner: Miner = _put("miner", Vector2i(0, 0)) as Miner
	miner.mine_ticks = 5
	var collector: Machine = _put("collector", Vector2i(1, 0))
	check_eq(_output_full_rises(miner, 100), 0, "a deliverable ore does not raise output_full")
	check(not miner.get_events().has("output_full"), "and none is shown at the end")
	check(not miner.get_state()["blocked"], "state is not blocked")
	check(not miner.get_action_text().contains("blocked"), "action text is not blocked")
	check(collector.sold >= 10, "ore flowed")


func test_miner_failed_delivery_raises_output_full_once_then_again_after_clearing() -> void:
	var miner: Miner = _put("miner", Vector2i(0, 0)) as Miner
	miner.mine_ticks = 5
	check_eq(_output_full_rises(miner, 5), 0, "a freshly mined ore is not blocked before a delivery attempt")
	check_eq(_output_full_rises(miner, 1), 1, "the failed delivery raises it")
	check(miner.get_state()["blocked"], "state is blocked")
	check(miner.get_action_text().contains("output blocked"), "action text is blocked")
	check_eq(_output_full_rises(miner, 50), 0, "it does not repeat while still blocked")
	miner.clear_contents()
	check(not miner.get_events().has("output_full"), "clearing removes the event")
	check(not miner.get_state()["blocked"], "and the blocked state")
	check(not miner.get_action_text().contains("blocked"), "and the action text")
	check_eq(_output_full_rises(miner, 10), 1, "the blockage coming back raises it again")


func test_deliverable_craft_output_is_never_blocked() -> void:
	var smelter: Machine = _put("smelter", Vector2i(1, 1), Vector2i.UP)
	var collector: Machine = _put("collector", Vector2i(1, 0))
	for i: int in 3:
		smelter.receive("ore")
	check_eq(_output_full_rises(smelter, 100), 0, "a deliverable ingot does not raise output_full")
	check(not smelter.get_action_text().contains("blocked"), "action text is not blocked")
	check_eq(collector.sold, 3, "the ingots were delivered")


func test_craft_failed_delivery_raises_output_full_once_then_again_after_clearing() -> void:
	var smelter: Machine = _put("smelter", Vector2i(1, 1), Vector2i.UP)
	smelter.receive("ore")
	var ticks_to_craft: int = (smelter as Smelter).recipe.ticks + 1
	check_eq(_output_full_rises(smelter, ticks_to_craft), 0, "a finished ingot is not blocked before a delivery attempt")
	check_eq(_output_full_rises(smelter, 1), 1, "the failed delivery raises it")
	check(smelter.get_action_text().contains("output blocked"), "action text is blocked")
	check_eq(_output_full_rises(smelter, 50), 0, "it does not repeat while still blocked")
	smelter.clear_contents()
	check(not smelter.get_events().has("output_full"), "clearing removes the event")
	check(not smelter.get_action_text().contains("blocked"), "and the action text")
	smelter.receive("ore")
	check_eq(_output_full_rises(smelter, ticks_to_craft + 1), 1, "the blockage coming back raises it again")
