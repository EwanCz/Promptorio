extends "res://tests/test_case.gd"
## GR2-6: saves/KeyFreeIntro.json is the dedicated key-free introductory scenario — a Miner (Prospector)
## and a Smelter (Cool Runner) feeding a Collector directly, the same Ore -> Ingot chain and starting
## order as a brand-new game, with no chip anywhere in the file. Loading it and running it end-to-end
## with no provider key configured must never touch LLMManager, and must still fulfill the order through
## Machine.apply_tool_call like any chip-driven run would.

const INTRO: String = "res://saves/KeyFreeIntro.json"

var _main: Node
var _placement: Placement
var _game: Node
var _bus: Node
var _llm: Node
var _saved_money: int = 0
var _saved_ticks: int = 0
var _saved_provider: String = ""
var _saved_api_key: String = ""
var _decisions: Array = []
var _failures: Array = []
var _completed_orders: Array = []


func before_each() -> void:
	_game = autoload("GameState")
	_bus = autoload("EventBus")
	_llm = autoload("LLMManager")
	var settings: Node = autoload("Settings")
	_saved_provider = settings.provider
	_saved_api_key = settings.api_key
	settings.provider = "anthropic"
	settings.api_key = ""
	_saved_money = _game.money
	_saved_ticks = _game.tick_count
	_decisions.clear()
	_failures.clear()
	_completed_orders.clear()
	_llm.decision_received.connect(_on_decision)
	_llm.decision_failed.connect(_on_failed)
	_bus.order_completed.connect(_on_order_completed)
	_main = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(_main)
	_placement = _main.get_node("Game/FactoryView/SubViewport/World/Placement")


func after_each() -> void:
	_llm.decision_received.disconnect(_on_decision)
	_llm.decision_failed.disconnect(_on_failed)
	_bus.order_completed.disconnect(_on_order_completed)
	_main.free()
	_game.money = _saved_money
	_game.tick_count = _saved_ticks
	var settings: Node = autoload("Settings")
	settings.provider = _saved_provider
	settings.api_key = _saved_api_key


func _on_decision(id: int, _calls: Array[Dictionary]) -> void:
	_decisions.append(id)


func _on_failed(id: int, _reason: String) -> void:
	_failures.append(id)


func _on_order_completed(product: String, reward: int) -> void:
	_completed_orders.append([product, reward])


func _load() -> void:
	var file: Dictionary = SaveGame.read(INTRO)
	check_eq(file["error"], "", "the intro scenario exists and parses")
	var data: Dictionary = file.get("data", {})
	check_eq(SaveGame.validate(_placement, data), "", "the intro scenario passes save validation")
	check_eq(SaveGame.restore(_placement, data), "", "the intro scenario restores")


func _miner() -> Miner:
	var miners: Array = _game.get_machines().filter(func(m: Node) -> bool: return m is Miner)
	return miners[0] as Miner if not miners.is_empty() else null


func _smelter() -> Smelter:
	var smelters: Array = _game.get_machines().filter(func(m: Node) -> bool: return m is Smelter)
	return smelters[0] as Smelter if not smelters.is_empty() else null


func _collector() -> Collector:
	var collectors: Array = _game.get_machines().filter(func(m: Node) -> bool: return m is Collector)
	return collectors[0] as Collector


func test_the_intro_scenario_uses_predefined_behaviors_not_chips() -> void:
	_load()
	var miner: Miner = _miner()
	var smelter: Smelter = _smelter()
	check(miner != null and miner.chips.is_empty(), "the miner carries no chip")
	check(miner != null and miner.predefined_behaviors.size() == 1, "the miner has one predefined behavior")
	check(smelter != null and smelter.chips.is_empty(), "the smelter carries no chip")
	check(smelter != null and smelter.predefined_behaviors.size() == 1, "the smelter has one predefined behavior")


func test_the_intro_scenario_fulfills_the_starting_order_with_no_key_and_no_network() -> void:
	_load()
	check_eq(_game.order_product, "ingot", "the usual new-game order")
	check_eq(_game.order_quantity, 5, "the usual new-game order size")
	var money_before: int = _game.money
	var ticks: int = 0
	for i: int in 1000:
		_bus.tick_fired.emit(i)
		ticks += 1
		if not _completed_orders.is_empty():
			break
	check(ticks < 1000, "the starting order completed on predefined behaviors alone, within a demoable window (%d ticks)" % ticks)
	check_eq(_completed_orders.size(), 1, "exactly one order completed by the time the loop stopped")
	if not _completed_orders.is_empty():
		check_eq(_completed_orders[0][0], "ingot", "the fulfilled order was the starting one")
		check_eq(_completed_orders[0][1], 30, "paid the order's own reward")
	check(_game.money > money_before, "the order reward was paid")
	check(_collector().sold >= 5, "every ordered ingot actually reached the collector")
	check_eq(_decisions.size(), 0, "no LLM decision was ever received")
	check_eq(_failures.size(), 0, "no LLM decision ever failed (none was ever requested)")
	check_eq(_llm._in_flight, 0, "LLMManager never had an in-flight request")
	check(_llm._queue.is_empty(), "LLMManager queue stayed empty for the whole playthrough")
