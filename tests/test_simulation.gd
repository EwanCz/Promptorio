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


func test_cooling_keeps_smelter_stable() -> void:
	_put("collector", Vector2i(1, 0))
	var smelter: Machine = _put("smelter", Vector2i(1, 1), Vector2i.UP)
	smelter.apply_tool_call("set_cooling", {"on": true})
	_feed(smelter, 800)
	check_eq(smelter.status, Machine.Status.NORMAL, "cooling on: still normal")
	check(smelter.temperature < Smelter.OVERHEAT_AT, "temperature stays under the limit")
	check(_exploded.is_empty(), "no explosion")


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
