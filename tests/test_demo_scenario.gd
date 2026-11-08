extends "res://tests/test_case.gd"
## saves/SmelterStable.json and saves/SmelterExplosion.json: the good/bad smelter demo scenario
## (GR2-5). Same layout (one Miner feeding a Smelter feeding a Collector, directly adjacent, no
## conveyors), differing only in the Smelter's starting cooling/temperature/stock, so the two
## outcomes are reproducible under the mock provider without depending on a chip ever deciding
## anything (see docs/IMPLEMENTATION.md, "Demo scenario: good vs bad chip prompt").

const STABLE: String = "res://saves/SmelterStable.json"
const EXPLOSION: String = "res://saves/SmelterExplosion.json"

var _main: Node
var _placement: Placement
var _game: Node
var _registry: Node
var _bus: Node
var _saved_money: int = 0
var _saved_ticks: int = 0
var _saved_chips: Dictionary = {}
var _exploded: Array = []


func before_each() -> void:
	_game = autoload("GameState")
	_registry = autoload("ChipRegistry")
	_bus = autoload("EventBus")
	_saved_money = _game.money
	_saved_ticks = _game.tick_count
	for chip: ChipRessource in _registry.get_all():
		_saved_chips[chip.id] = [chip.name, chip.description, chip.prompt]
	_exploded.clear()
	_bus.machine_exploded.connect(_on_exploded)
	_main = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(_main)
	_placement = _main.get_node("Game/FactoryView/SubViewport/World/Placement")


func after_each() -> void:
	_bus.machine_exploded.disconnect(_on_exploded)
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


func _on_exploded(machine: Node) -> void:
	_exploded.append(machine)


func _load(path: String) -> void:
	var file: Dictionary = SaveGame.read(path)
	check_eq(file["error"], "", "%s exists and parses" % path)
	var data: Dictionary = file.get("data", {})
	check_eq(SaveGame.validate(_placement, data), "", "%s passes save validation" % path)
	check_eq(SaveGame.restore(_placement, data), "", "%s restores" % path)


func _smelter() -> Smelter:
	var smelters: Array = _game.get_machines().filter(func(m: Node) -> bool: return m is Smelter)
	return smelters[0] as Smelter if not smelters.is_empty() else null


func _collector() -> Collector:
	var collectors: Array = _game.get_machines().filter(func(m: Node) -> bool: return m is Collector)
	return collectors[0] as Collector


func test_the_stable_scenario_loads_and_never_explodes() -> void:
	_load(STABLE)
	var smelter: Smelter = _smelter()
	check(smelter != null and smelter.cooling, "the smelter starts cooled")
	for i: int in 400:
		_bus.tick_fired.emit(i)
	check(_exploded.is_empty(), "nothing exploded")
	smelter = _smelter()
	check(smelter != null and smelter.status != Machine.Status.DOWN, "the smelter is still standing")
	check(smelter.temperature < Smelter.OVERHEAT_AT, "and well clear of overheating (%d°)" % roundi(smelter.temperature))
	check(_collector().sold > 0, "ore still flows all the way to a sale")


func test_the_explosion_scenario_loads_and_overheats_to_a_demoable_explosion() -> void:
	_load(EXPLOSION)
	var smelter: Smelter = _smelter()
	check(smelter != null and not smelter.cooling, "the smelter starts uncooled")
	var sold_before_explosion: int = 0
	var ticks: int = 0
	for i: int in 400:
		_bus.tick_fired.emit(i)
		ticks += 1
		if not _exploded.is_empty():
			sold_before_explosion = _collector().sold
			break
	check_eq(_exploded.size(), 1, "it exploded exactly once")
	check(ticks > 150 and ticks < 400, "within a demoable window, not instantly (%d ticks)" % ticks)
	check(sold_before_explosion > 0, "it sold at least one ingot before failing, so the loop ran first")
