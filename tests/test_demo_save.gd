extends "res://tests/test_case.gd"
## saves/Demo.json, the save shipped for the demo: it must load, hold every building and chips, and run.

const DEMO: String = "res://saves/Demo.json"

var _main: Node
var _placement: Placement
var _game: Node
var _registry: Node
var _saved_money: int = 0
var _saved_ticks: int = 0
var _saved_chips: Dictionary = {}


func before_each() -> void:
	_game = autoload("GameState")
	_registry = autoload("ChipRegistry")
	_saved_money = _game.money
	_saved_ticks = _game.tick_count
	for chip: ChipRessource in _registry.get_all():
		_saved_chips[chip.id] = [chip.name, chip.description, chip.prompt]
	_main = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(_main)
	_placement = _main.get_node("Game/FactoryView/SubViewport/World/Placement")


func after_each() -> void:
	_main.free()
	for chip: ChipRessource in _registry.get_all():
		if not _saved_chips.has(chip.id):
			_registry.remove(chip.id)
		else:
			var saved: Array = _saved_chips[chip.id]
			_registry.update(chip.id, saved[0], saved[1], saved[2])
	_saved_chips.clear()
	_game.money = _saved_money
	_game.tick_count = _saved_ticks


func test_the_demo_save_is_valid_and_holds_every_building_with_chips() -> void:
	var file: Dictionary = SaveGame.read(DEMO)
	check_eq(file["error"], "", "the file exists and parses")
	var data: Dictionary = file.get("data", {})
	check_eq(SaveGame.validate(_placement, data), "", "it passes the same validation as any save")
	var types: Dictionary = {}
	var chips_on: Dictionary = {}
	for machine: Dictionary in data["machines"]:
		types[machine["type"]] = int(types.get(machine["type"], 0)) + 1
		if not (machine["chips"] as Array).is_empty():
			chips_on[machine["type"]] = true
	for type: String in ["miner", "smelter", "assembler", "conveyor", "collector"]:
		check(types.has(type), "the demo has a %s" % type)
	for type: String in ["miner", "smelter", "assembler"]:
		check(chips_on.has(type), "its %s has a chip" % type)
	check((data["chips"] as Array).size() >= 3, "the chips are embedded (%d)" % (data["chips"] as Array).size())
	check(int(data["money"]) > 0, "it has money to build with")


func test_the_demo_save_restores_and_the_chain_keeps_selling() -> void:
	check_eq(SaveGame.restore(_placement, SaveGame.read(DEMO).get("data")), "", "it loads")
	var collectors: Array = _game.get_machines().filter(func(m: Node) -> bool: return m is Collector)
	var sold: int = (collectors[0] as Collector).sold
	for i: int in 400:
		autoload("EventBus").tick_fired.emit(i)
	check((collectors[0] as Collector).sold > sold, "ore still flows from the miners to the collector")
	var smelters: Array = _game.get_machines().filter(func(m: Node) -> bool: return m is Smelter)
	check(smelters.size() == 1 and (smelters[0] as Smelter).chips.size() == 1, "the smelter is back with its cooler chip")
	check((smelters[0] as Smelter).temperature > Smelter.AMBIENT, "and it is already warm, so the cooler has something to do")
