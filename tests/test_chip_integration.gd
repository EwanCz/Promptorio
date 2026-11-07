extends "res://tests/test_case.gd"
## Whole loop on the mock provider: chip timer -> LLMManager -> tool call -> machine.

const SCENES: Dictionary = {
	"miner": "res://scenes/machines/miner.tscn",
	"smelter": "res://scenes/machines/smelter.tscn",
	"assembler": "res://scenes/machines/assembler.tscn",
	"collector": "res://scenes/machines/collector.tscn",
	"conveyor": "res://scenes/machines/conveyor.tscn",
}

var _game: Node
var _nodes: Array[Node] = []
var _res: ChipRessource
var _saved_provider: String = ""
var _saved_cooldown: float = 5.0
var _saved_money: int = 0
var _logs: Array[String] = []


func before_each() -> void:
	var settings: Node = autoload("Settings")
	_game = autoload("GameState")
	_saved_provider = settings.provider
	_saved_cooldown = settings.chip_cooldown
	_saved_money = _game.money
	settings.provider = "mock"
	settings.chip_cooldown = 0.0
	_logs.clear()
	_res = autoload("ChipRegistry").add("integration", "Keep the smelter safe")
	autoload("EventBus").chip_log_added.connect(_on_log)


func after_each() -> void:
	var settings: Node = autoload("Settings")
	autoload("EventBus").chip_log_added.disconnect(_on_log)
	settings.provider = _saved_provider
	settings.chip_cooldown = _saved_cooldown
	for node: Node in _nodes:
		node.free()
	_nodes.clear()
	_game.money = _saved_money
	autoload("ChipRegistry").remove(_res.id)


func _on_log(_machine: Node, message: String) -> void:
	_logs.append(message)


func _put(type: String, cell: Vector2i) -> Machine:
	var machine: Machine = (load(SCENES[type]) as PackedScene).instantiate() as Machine
	machine.cell = cell
	tree.root.add_child(machine)
	_game.register_machine(machine, cell)
	_nodes.append(machine)
	return machine


func _ticks(count: int) -> void:
	for i: int in count:
		autoload("EventBus").tick_fired.emit(i)


func test_every_machine_exposes_valid_tool_schemas() -> void:
	for type: String in SCENES:
		var machine: Machine = (load(SCENES[type]) as PackedScene).instantiate() as Machine
		var tools: Array = machine.get_tool_schemas()
		check(tools.size() >= 1, "%s exposes tools" % type)
		for tool: Dictionary in tools:
			var name: String = tool.get("name", "")
			check(name != "" and tool.has("description") and tool.has("input_schema"), "%s/%s is well formed" % [type, name])
		check(machine.apply_tool_call("set_enabled", {"on": false}), "%s accepts set_enabled" % type)
		check(not machine.apply_tool_call("set_enabled", {"on": "yes"}), "%s rejects a bad arg" % type)
		check(not machine.apply_tool_call("not_a_tool", {}), "%s rejects an unknown tool" % type)
		machine.free()


func test_mock_answers_apply_on_every_machine() -> void:
	var provider: MockProvider = MockProvider.new()
	for type: String in SCENES:
		var machine: Machine = (load(SCENES[type]) as PackedScene).instantiate() as Machine
		var request: Dictionary = provider.build_request("", machine.get_state(), machine.get_tool_schemas())
		var calls: Array[Dictionary] = provider.parse_response(request["body"])
		check_eq(calls.size(), 1, "%s: mock picks a tool" % type)
		check(machine.apply_tool_call(calls[0]["name"], calls[0]["args"]), "%s: mock answer passes validation" % type)
		machine.free()


func test_chip_on_a_running_chain_decides_and_the_chain_keeps_working() -> void:
	_put("miner", Vector2i(0, 0))
	_put("conveyor", Vector2i(1, 0))
	var smelter: Machine = _put("smelter", Vector2i(2, 0))
	_put("conveyor", Vector2i(3, 0))
	var collector: Machine = _put("collector", Vector2i(4, 0))
	var chip: ChipComponent = smelter.attach_chip(_res.id, 30)
	var applied: Array[int] = []
	var on_applied: Callable = func(_reason: String, count: int) -> void: applied.append(count)
	chip.decision_applied.connect(on_applied)
	_game.money = 0
	_ticks(100)
	await wait_until(func() -> bool: return applied.size() > 0, 5.0)
	chip.decision_applied.disconnect(on_applied)
	check(applied.size() > 0, "the chip's timer reached the LLM and back")
	check_eq(applied[0], 1, "the mock tool call was applied to the smelter")
	check("set_enabled({\"on\":true})" in _logs, "the decision is in the chip log")
	check_eq(smelter.status, Machine.Status.NORMAL, "smelter still normal")
	_ticks(100)
	check(collector.sold >= 1, "ingots reached the collector")
	check(_game.money > 0, "and were sold")
