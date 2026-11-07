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
