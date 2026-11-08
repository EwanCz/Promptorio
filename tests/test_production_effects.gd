extends "res://tests/test_case.gd"
## production_state()/is_producing() per machine type, and the in-world ProductionEffect they drive.

const SCENES: Dictionary = {
	"miner": "res://scenes/machines/miner.tscn",
	"smelter": "res://scenes/machines/smelter.tscn",
	"collector": "res://scenes/machines/collector.tscn",
	"conveyor": "res://scenes/machines/conveyor.tscn",
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


func test_idle_machine_shows_no_effect() -> void:
	var smelter: Machine = _put("smelter", Vector2i(8, 8))
	_ticks(1)
	check_eq(smelter.production_state(), "idle", "no product and no stock: idle")
	check_eq(smelter.production_effect.state, "idle", "the effect follows the state")


func test_working_craft_machine_reports_producing() -> void:
	var smelter: Smelter = _put("smelter", Vector2i(8, 8))
	smelter.set_product("ingot")
	smelter.receive("ore")
	_ticks(1)
	check(smelter.is_working(), "a craft started")
	check_eq(smelter.production_state(), "producing", "a craft in progress is producing")
	check_eq(smelter.production_effect.state, "producing", "the effect shows it")


func test_down_machine_is_idle_not_blocked() -> void:
	var smelter: Smelter = _put("smelter", Vector2i(8, 8))
	smelter.set_product("ingot")
	smelter.receive("ore")
	_ticks(1)
	smelter.status = Machine.Status.DOWN
	check_eq(smelter.production_state(), "idle", "a down machine is inert, not stuck")


func test_blocked_conveyor_overrides_producing() -> void:
	var conveyor: Conveyor = _put("conveyor", Vector2i(8, 8))
	conveyor.receive("ore")
	_ticks(Conveyor.MOVE_TICKS + 1)
	check(conveyor.is_blocked(), "nothing ahead to take the item")
	check(conveyor.is_producing(), "the item is still held, which alone would read as producing")
	check_eq(conveyor.production_state(), "blocked", "blocked wins over producing")
	check_eq(conveyor.production_effect.state, "blocked", "the effect shows the badge, not particles")


func test_miner_producing_pauses_while_prospecting() -> void:
	var miner: Miner = _put("miner", Vector2i(8, 8))
	check(miner.is_producing(), "mining normally")
	miner.start_prospecting()
	check(not miner.is_producing(), "paused to prospect")
	check_eq(miner.production_state(), "idle", "prospecting shows idle, not blocked")


func test_collector_pulses_after_a_sale() -> void:
	var collector: Collector = _put("collector", Vector2i(8, 8))
	check(not collector.is_producing(), "nothing sold yet")
	collector.receive("ore")
	check(collector.is_producing(), "just sold: a brief pulse")
	_ticks(Collector.PULSE_TICKS)
	check(not collector.is_producing(), "the pulse fades after PULSE_TICKS")


func test_effect_toggles_particles_and_badge_per_state() -> void:
	var effect: ProductionEffect = ProductionEffect.new()
	tree.root.add_child(effect)
	effect.set_state("producing")
	check(effect._particles.emitting, "producing emits particles")
	check(not effect._badge.visible, "no blocked badge while producing")
	effect.set_state("blocked")
	check(not effect._particles.emitting, "particles stop once blocked")
	check(effect._badge.visible, "the blocked badge shows")
	effect.set_state("idle")
	check(not effect._particles.emitting, "idle emits nothing")
	check(not effect._badge.visible, "idle shows no badge either")
	effect.free()
