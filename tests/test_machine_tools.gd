extends "res://tests/test_case.gd"
## Each machine type has its own tool list on top of the tools all machines share.

const SCENES: Dictionary = {
	"miner": "res://scenes/machines/miner.tscn",
	"smelter": "res://scenes/machines/smelter.tscn",
	"assembler": "res://scenes/machines/assembler.tscn",
	"collector": "res://scenes/machines/collector.tscn",
	"conveyor": "res://scenes/machines/conveyor.tscn",
}
const EXPECTED_OWN: Dictionary = {
	"miner": ["set_mine_ticks", "set_mined_item"],
	"smelter": ["set_cooling", "set_emergency_stop", "set_product", "discard_stock"],
	"assembler": ["set_mode", "set_stock_limit", "set_product", "discard_stock"],
	"collector": ["set_accepting"],
	"conveyor": ["set_direction"],
}

var _nodes: Array[Node] = []
var _saved_money: int = 0


func before_each() -> void:
	_saved_money = autoload("GameState").money


func after_each() -> void:
	for node: Node in _nodes:
		node.free()
	_nodes.clear()
	autoload("GameState").money = _saved_money


func _make(type: String) -> Machine:
	var machine: Machine = (load(SCENES[type]) as PackedScene).instantiate() as Machine
	_nodes.append(machine)
	return machine


func _names(machine: Machine) -> Array[String]:
	var names: Array[String] = []
	for schema: Dictionary in machine.get_tool_schemas():
		names.append(schema["name"])
	return names


func test_every_type_has_the_shared_tool_and_its_own() -> void:
	for type: String in SCENES:
		var names: Array[String] = _names(_make(type))
		check_eq(names[0], "set_enabled", "%s starts with the shared tool" % type)
		check_eq(names.slice(1), EXPECTED_OWN[type], "%s has exactly its own tools after the shared one" % type)


func test_own_tools_are_unique_to_their_type() -> void:
	for type: String in SCENES:
		for tool: String in EXPECTED_OWN[type]:
			for other: String in SCENES:
				if not tool in EXPECTED_OWN[other]:
					check(not tool in _names(_make(other)), "%s is not offered on a %s" % [tool, other])


func test_own_tool_of_another_type_is_refused() -> void:
	var miner: Machine = _make("miner")
	check(not miner.apply_tool_call("set_cooling", {"on": true}), "a miner cannot cool")
	check(not _make("collector").apply_tool_call("set_mine_ticks", {"ticks": 10}), "a collector cannot mine")


func test_miner_mine_ticks_clamped() -> void:
	var miner: Miner = _make("miner") as Miner
	check(miner.apply_tool_call("set_mine_ticks", {"ticks": 40}), "valid ticks accepted")
	check_eq(miner.mine_ticks, 40, "mine_ticks set")
	check_eq(miner.get_state()["mine_ticks"], 40, "state shows it")
	miner.apply_tool_call("set_mine_ticks", {"ticks": 1})
	check_eq(miner.mine_ticks, miner.get_min_mine_ticks(), "clamped to the mining time of the resource")
	miner.apply_tool_call("set_mine_ticks", {"ticks": 9999})
	check_eq(miner.mine_ticks, Miner.MAX_MINE_TICKS, "clamped to the maximum")
	check(not miner.apply_tool_call("set_mine_ticks", {"ticks": "fast"}), "text rejected")


func test_assembler_stock_limit_caps_inputs() -> void:
	var assembler: Assembler = _make("assembler") as Assembler
	check(assembler.apply_tool_call("set_stock_limit", {"limit": 2}), "limit accepted")
	check(assembler.receive("ingot") and assembler.receive("ingot"), "two ingots fit")
	check(not assembler.receive("ingot"), "a third is refused")
	check_eq(assembler.get_state()["stock_limit"], 2, "state shows the limit")
	assembler.apply_tool_call("set_stock_limit", {"limit": 99})
	check_eq(assembler.stock_limit, CraftMachine.MAX_STOCK, "limit clamped to the maximum stock")
	assembler.apply_tool_call("set_stock_limit", {"limit": 0})
	check_eq(assembler.stock_limit, 1, "limit clamped to 1")


func test_conveyor_direction() -> void:
	var conveyor: Conveyor = _make("conveyor") as Conveyor
	check_eq(conveyor.get_state()["direction"], 0, "starts facing right")
	check(conveyor.apply_tool_call("set_direction", {"direction": 2}), "direction accepted")
	check_eq(conveyor.facing, Vector2i.LEFT, "faces left")
	check_eq(conveyor.get_state()["direction"], 2, "state shows it")
	conveyor.apply_tool_call("set_direction", {"direction": 9})
	check_eq(conveyor.facing, Vector2i.UP, "clamped to the last direction")
	conveyor.apply_tool_call("set_direction", {"direction": -3})
	check_eq(conveyor.facing, Vector2i.RIGHT, "clamped to the first direction")


func test_collector_can_refuse_items() -> void:
	var game: Node = autoload("GameState")
	game.money = 0
	var collector: Collector = _make("collector") as Collector
	check(collector.receive("ore"), "accepts by default")
	check(collector.apply_tool_call("set_accepting", {"on": false}), "tool accepted")
	check(not collector.receive("ore"), "refuses once switched off")
	check_eq(game.money, 1, "a refused item is not sold")
	check_eq(collector.get_state()["accepting"], false, "state shows it")
	collector.apply_tool_call("set_accepting", {"on": true})
	check(collector.receive("ore"), "accepts again")
