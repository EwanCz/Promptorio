extends "res://tests/test_case.gd"
## Miner prospecting and the automatic production boost that follows it (GR2-14).

const SCENES: Dictionary = {
	"miner": "res://scenes/machines/miner.tscn",
	"collector": "res://scenes/machines/collector.tscn",
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


func test_state_reports_mining_mode_by_default() -> void:
	var miner: Miner = _put("miner", Vector2i(0, 0)) as Miner
	check_eq(miner.get_state()["mode"], "mining", "default mode")
	check_eq(miner.get_state()["mode_ticks_left"], 0, "no timer while mining")


func test_start_prospecting_pauses_mining_and_exposes_mode() -> void:
	var miner: Miner = _put("miner", Vector2i(0, 0)) as Miner
	check(miner.apply_tool_call("start_prospecting", {}), "prospecting starts")
	check_eq(miner.mode, Miner.Mode.PROSPECTING, "mode is prospecting")
	check_eq(miner.mode_ticks_left, Miner.PROSPECT_TICKS, "full prospecting timer")
	check_eq(miner.get_state()["mode"], "prospecting", "state shows it")
	check_eq(miner.get_state()["mode_ticks_left"], Miner.PROSPECT_TICKS, "state shows the timer")
	_ticks(Miner.PROSPECT_TICKS - 1)
	check_eq(miner.mode, Miner.Mode.PROSPECTING, "still prospecting one tick before it ends")


func test_prospecting_preserves_partial_mining_progress() -> void:
	var miner: Miner = _put("miner", Vector2i(0, 0)) as Miner
	_ticks(18)
	check_eq(miner.get_progress(), 0.9, "ore is almost finished")
	miner.start_prospecting()
	_ticks(Miner.PROSPECT_TICKS - 1)
	check_eq(miner.get_progress(), 0.9, "prospecting preserves the unfinished unit")
	check_eq(miner.get_production_state(), Machine.ProductionState.IDLE, "prospecting is idle even with unfinished mining progress")
	_ticks(1)
	check_eq(miner.get_progress(), 0.9, "progress is rescaled when boost starts")
	_ticks(1)
	check_eq(miner.get_progress(), 0.0, "the boosted unit finishes on the next tick")


func test_expiring_boost_preserves_partial_progress() -> void:
	var miner: Miner = _put("miner", Vector2i(0, 0)) as Miner
	var saved: Dictionary = miner.to_dict()
	saved["data"]["mode"] = Miner.Mode.BOOST
	saved["data"]["mode_ticks_left"] = 1
	saved["data"]["progress"] = 3
	miner.load_dict(saved)
	_ticks(1)
	check_eq(miner.mode, Miner.Mode.MINING, "boost expires")
	check_eq(miner.get_progress(), 0.4, "last boosted tick is counted before rescaling")


func test_mode_badge_does_not_overlap_chip_indicator() -> void:
	var miner: Miner = _put("miner", Vector2i(0, 0)) as Miner
	miner.start_prospecting()
	_ticks(1)
	var badge: Sprite2D = null
	for child: Node in miner.get_children():
		if child is Sprite2D and child != miner.indicator:
			var sprite: Sprite2D = child as Sprite2D
			if sprite.texture != null and sprite.texture.get_image().get_data() == Icons.icon("prospecting").get_image().get_data():
				badge = sprite
	check(badge != null, "prospecting badge is visible")
	if badge != null:
		var badge_rect: Rect2 = Rect2(badge.position - Vector2.ONE * Icons.SIZE, Vector2.ONE * Icons.SIZE * Icons.SCALE)
		var chip_rect: Rect2 = Rect2(miner.indicator.position - Vector2.ONE * Icons.SIZE, Vector2.ONE * Icons.SIZE * Icons.SCALE)
		check(not badge_rect.intersects(chip_rect), "badge and chip indicator do not overlap")
		var production_rect: Rect2 = Rect2(miner.production_indicator.position - Vector2.ONE * Icons.SIZE, Vector2.ONE * Icons.SIZE * Icons.SCALE)
		check(not badge_rect.intersects(production_rect), "badge and production indicator do not overlap")


func test_cannot_restart_prospecting_while_prospecting_or_boosted() -> void:
	var miner: Miner = _put("miner", Vector2i(0, 0)) as Miner
	miner.start_prospecting()
	check(not miner.apply_tool_call("start_prospecting", {}), "refused mid-prospect")
	_ticks(Miner.PROSPECT_TICKS)
	check_eq(miner.mode, Miner.Mode.BOOST, "now boosted")
	check(not miner.apply_tool_call("start_prospecting", {}), "refused mid-boost")


func test_mined_item_locked_during_the_cycle() -> void:
	var miner: Miner = _put("miner", Vector2i(0, 0)) as Miner
	miner.start_prospecting()
	check(not miner.set_mined_item("coal"), "the resource cannot change mid-prospect")
	check_eq(miner.item, "ore", "unchanged")
	_ticks(Miner.PROSPECT_TICKS)
	check(not miner.set_mined_item("coal"), "nor mid-boost")


func test_prospecting_transitions_to_boost_and_back_to_mining() -> void:
	var miner: Miner = _put("miner", Vector2i(0, 0)) as Miner
	miner.mine_ticks = 10
	miner.start_prospecting()
	_ticks(Miner.PROSPECT_TICKS)
	check_eq(miner.mode, Miner.Mode.BOOST, "boost starts automatically")
	check_eq(miner.mode_ticks_left, Miner.BOOST_TICKS, "full boost timer")
	_ticks(Miner.BOOST_TICKS)
	check_eq(miner.mode, Miner.Mode.MINING, "boost ends automatically")
	check_eq(miner.mode_ticks_left, 0, "timer cleared")
	check(miner.set_mined_item("coal"), "the resource can change again once mining resumes")


func test_boost_mines_faster_than_the_configured_rate() -> void:
	var miner: Miner = _put("miner", Vector2i(0, 0)) as Miner
	var collector: Collector = _put("collector", Vector2i(1, 0)) as Collector
	miner.mine_ticks = 20
	_game.money = 0
	_ticks(100)
	var normal_sold: int = collector.sold
	collector.sold = 0
	_game.money = 0
	miner.start_prospecting()
	_ticks(Miner.PROSPECT_TICKS + 100)
	check(collector.sold > normal_sold, "boosted mining outproduces the normal rate over an equal span")


func test_boost_expires_on_schedule_even_while_output_is_blocked() -> void:
	var miner: Miner = _put("miner", Vector2i(0, 0)) as Miner
	miner.mine_ticks = 5
	miner.start_prospecting()
	_ticks(Miner.PROSPECT_TICKS)
	check_eq(miner.mode, Miner.Mode.BOOST, "boost begins")
	_ticks(3)
	check(miner.is_blocked(), "nothing is placed in front, so the mined unit cannot be delivered")
	_ticks(Miner.BOOST_TICKS - 3)
	check_eq(miner.mode, Miner.Mode.MINING, "the boost still expired on schedule while blocked")
	check(miner.is_blocked(), "still blocked: the held unit still has nowhere to go")


func test_disabled_miner_freezes_the_mode_timer_too() -> void:
	var miner: Miner = _put("miner", Vector2i(0, 0)) as Miner
	miner.start_prospecting()
	_ticks(10)
	var remaining: int = miner.mode_ticks_left
	miner.apply_tool_call("set_enabled", {"on": false})
	_ticks(50)
	check_eq(miner.mode, Miner.Mode.PROSPECTING, "still prospecting, frozen while disabled")
	check_eq(miner.mode_ticks_left, remaining, "the timer did not move while disabled")
	miner.apply_tool_call("set_enabled", {"on": true})
	_ticks(remaining)
	check_eq(miner.mode, Miner.Mode.BOOST, "resumes counting down once re-enabled")


func test_mode_and_timer_persist_across_save_and_load() -> void:
	var miner: Miner = _put("miner", Vector2i(0, 0)) as Miner
	miner.start_prospecting()
	_ticks(30)
	var saved: Dictionary = miner.to_dict()
	var restored: Miner = _put("miner", Vector2i(2, 2)) as Miner
	restored.load_dict(saved)
	check_eq(restored.mode, Miner.Mode.PROSPECTING, "mode restored")
	check_eq(restored.mode_ticks_left, miner.mode_ticks_left, "timer restored")
	_ticks(Miner.PROSPECT_TICKS - 30)
	check_eq(restored.mode, Miner.Mode.BOOST, "the restored miner continues the cycle")
