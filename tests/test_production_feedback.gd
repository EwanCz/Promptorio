extends "res://tests/test_case.gd"
## Production-rate and stalled-machine feedback (GR2-8): Machine.get_production_state() /
## get_production_rate(), the in-world ProductionIndicator badge they drive, and the machine tooltip's
## matching row. See docs/UI.md, "Visual feedback rule".

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


func before_each() -> void:
	_game = autoload("GameState")
	_bus = autoload("EventBus")


func after_each() -> void:
	for node: Node in _nodes:
		node.free()
	_nodes.clear()


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


func _hints(row: Node) -> Array[String]:
	var found: Array[String] = []
	for cell: Node in row.get_children():
		found.append((cell.get_child(0) as TextureRect).tooltip_text)
	return found


func test_timed_producers_opt_in_others_dont() -> void:
	check(_put("miner", Vector2i(0, 0)).shows_production_feedback(), "miner has a timed job")
	check(_put("smelter", Vector2i(1, 0)).shows_production_feedback(), "smelter has a timed job")
	check(_put("assembler", Vector2i(2, 0)).shows_production_feedback(), "assembler has a timed job")
	check(not _put("collector", Vector2i(3, 0)).shows_production_feedback(), "collector only sells on arrival")
	check(not _put("conveyor", Vector2i(4, 0)).shows_production_feedback(), "conveyor only moves what it is given")


func test_only_producers_get_an_indicator() -> void:
	var miner: Machine = _put("miner", Vector2i(0, 0))
	var belt: Machine = _put("conveyor", Vector2i(1, 0))
	check(miner.production_indicator != null, "a producer gets the badge")
	check(belt.production_indicator == null, "a conveyor does not")


func test_a_flowing_miner_eventually_reports_producing_with_a_rate() -> void:
	var miner: Machine = _put("miner", Vector2i(0, 1))
	_put("conveyor", Vector2i(1, 1))
	_put("collector", Vector2i(2, 1))
	var saw_producing: bool = false
	for i: int in 150:
		_bus.tick_fired.emit(i)
		if miner.get_production_state() == Machine.ProductionState.PRODUCING:
			saw_producing = true
	check(saw_producing, "the miner reads producing while a cycle is in progress")
	check(miner.get_production_rate() > 0.0, "and has delivered at least one ore in the last minute")


func test_a_blocked_miner_reports_stalled_not_idle() -> void:
	var miner: Machine = _put("miner", Vector2i(0, 0))
	_ticks(miner.mine_ticks + 2)
	check(miner.is_blocked(), "nothing collects its ore")
	check_eq(miner.get_production_state(), Machine.ProductionState.STALLED, "stalled wins over idle")
	check_eq(miner.get_production_rate(), 0.0, "the one it is holding was never delivered")


func test_a_disabled_machine_is_idle_with_no_rate() -> void:
	var miner: Machine = _put("miner", Vector2i(0, 0))
	miner.apply_tool_call("set_enabled", {"on": false})
	_ticks(100)
	check_eq(miner.get_production_state(), Machine.ProductionState.IDLE, "switched off, nothing is produced")
	check_eq(miner.get_production_rate(), 0.0, "it has never produced")


func test_a_craft_machine_with_no_stock_is_idle_not_stalled() -> void:
	var smelter: Machine = _put("smelter", Vector2i(0, 0))
	_ticks(50)
	check_eq(smelter.get_production_state(), Machine.ProductionState.IDLE, "waiting for ore is not a stall")
	check(not smelter.is_blocked(), "it has nothing to deliver yet")


func test_production_rate_resets_when_contents_clear() -> void:
	var miner: Machine = _put("miner", Vector2i(0, 2))
	_put("collector", Vector2i(1, 2))
	_ticks(150)
	check(miner.get_production_rate() > 0.0, "it has produced something")
	miner.clear_contents()
	check_eq(miner.get_production_rate(), 0.0, "cleared along with everything else it holds")


func test_indicator_icon_tracks_the_state() -> void:
	var miner: Machine = _put("miner", Vector2i(0, 3))
	_put("collector", Vector2i(1, 3))
	var indicator: ProductionIndicator = miner.production_indicator
	check_eq(indicator.state, Machine.ProductionState.IDLE, "nothing has happened yet")
	var confirmed_producing: bool = false
	var tick: int = 0
	while tick < 100 and not confirmed_producing:
		_bus.tick_fired.emit(tick)
		tick += 1
		if indicator.state == Machine.ProductionState.PRODUCING:
			check_eq(indicator.texture.get_image().get_data(), Icons.icon("state_normal").get_image().get_data(), "green play icon while producing")
			confirmed_producing = true
	check(confirmed_producing, "the badge reaches the producing state")
	miner.apply_tool_call("set_enabled", {"on": false})
	_bus.tick_fired.emit(tick)
	check_eq(indicator.state, Machine.ProductionState.IDLE, "switching off updates the badge")
	check_eq(indicator.texture.get_image().get_data(), Icons.icon("state_paused").get_image().get_data(), "the pause icon")


func test_tooltip_shows_the_rate_then_the_existing_blocked_icon() -> void:
	var tooltip: MachineTooltip = (load("res://scenes/ui/popups/machine_tooltip.tscn") as PackedScene).instantiate() as MachineTooltip
	tree.root.add_child(tooltip)
	_nodes.append(tooltip)
	var miner: Machine = _put("miner", Vector2i(0, 4))
	_bus.machine_selected.emit(miner)
	var saw_rate: bool = false
	for i: int in miner.mine_ticks:
		_bus.tick_fired.emit(i)
		if _hints(tooltip.get_node("%OpRow")).any(func(h: String) -> bool: return h.begins_with("Producing")):
			saw_rate = true
	check(saw_rate, "the row shows the rate while a cycle runs (nothing is placed to collect it yet)")
	for i: int in 5:
		_bus.tick_fired.emit(miner.mine_ticks + i)
	check(_hints(tooltip.get_node("%OpRow")).has("Output blocked: nothing takes it"), "then the existing blocked icon once nothing collects it")
