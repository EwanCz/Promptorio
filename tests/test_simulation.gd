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
	check(_is_blocked(smelter), "the smelter holds its ingot, it cannot hand it over")
	check(not belt.receive("ore"), "so the conveyor stays full")
	check_eq(smelter.stock.get("ingot", 0), 0, "nothing went the other way either")


func test_turning_one_machine_away_lets_the_pair_flow_again() -> void:
	var smelter: Smelter = _put("smelter", Vector2i(0, 0), Vector2i.RIGHT) as Smelter
	var belt: Conveyor = _put("conveyor", Vector2i(1, 0), Vector2i.LEFT) as Conveyor
	var collector: Machine = _put("collector", Vector2i(1, 1))
	smelter.cooling = true
	smelter.receive("ore")
	_ticks(60)
	check(_is_blocked(smelter), "blocked while facing each other")
	belt.facing = Vector2i.DOWN
	_ticks(60)
	check(not _is_blocked(smelter), "the ingot moves once the conveyor turns away")
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


func _smelter_with_collector(cell: Vector2i) -> Array:
	var collector: Machine = _put("collector", cell)
	var smelter: Machine = _put("smelter", cell + Vector2i.DOWN, Vector2i.UP)
	return [smelter, collector]


func test_cooling_off_crafts_fast_and_cooling_on_crafts_slow() -> void:
	var plain: Machine = _smelter_with_collector(Vector2i(1, 0))[0]
	var cooled: Machine = _smelter_with_collector(Vector2i(5, 0))[0]
	cooled.apply_tool_call("set_cooling", {"on": true})
	plain.receive("ore")
	cooled.receive("ore")
	_ticks(1)
	check_eq(plain.progress, plain.recipe.ticks / Smelter.UNCOOLED_SPEEDUP, "cooling off: the recipe time divided by the speedup")
	check_eq(cooled.progress, plain.recipe.ticks * Smelter.COOLED_CRAFT_FACTOR, "cooling on: the recipe time times the factor")
	check_eq(cooled.progress / plain.progress, Smelter.UNCOOLED_SPEEDUP * Smelter.COOLED_CRAFT_FACTOR, "so cooling off is that many times faster")


## Same feed, same period, one smelter with cooling off and one with it on.
func _sold_over(ticks: int, cooling_on: bool) -> Array:
	var pair: Array = _smelter_with_collector(Vector2i(1, 0) if not cooling_on else Vector2i(5, 0))
	var smelter: Machine = pair[0]
	smelter.apply_tool_call("set_cooling", {"on": cooling_on})
	for i: int in ticks:
		smelter.receive("ore")
		_ticks(1)
	return [pair[1].sold, smelter]


func test_cooling_off_has_clearly_better_throughput_than_cooling_on() -> void:
	var fast: Array = _sold_over(150, false)
	var slow: Array = _sold_over(150, true)
	print("  throughput over 150 ticks: cooling off %d ingots, cooling on %d ingots" % [fast[0], slow[0]])
	check(slow[0] >= 3, "cooling on keeps producing")
	check(fast[0] >= 3 * slow[0], "cooling off makes at least three times as many ingots (%d vs %d)" % [fast[0], slow[0]])
	check(fast[1].temperature > Smelter.AMBIENT + 40.0, "and it runs hot (%d degrees)" % int(fast[1].temperature))
	check(slow[1].temperature < Smelter.OVERHEAT_AT and slow[1].status == Machine.Status.NORMAL, "while the cooled one stays safe")


func test_cooling_off_still_overheats_and_explodes_when_left_alone() -> void:
	var smelter: Machine = _smelter_with_collector(Vector2i(1, 0))[0]
	var saw_overheat: Array[bool] = [false]
	var ticks: Array[int] = [0]
	_feed(smelter, 600, func(m: Machine) -> bool:
		ticks[0] += 1
		saw_overheat[0] = saw_overheat[0] or m.status == Machine.Status.OVERHEATING
		return m.status == Machine.Status.DOWN)
	print("  unattended fast smelter exploded after %d ticks" % ticks[0])
	check(saw_overheat[0], "it overheats first")
	check_eq(smelter.status, Machine.Status.DOWN, "and explodes: the heat risk is real")
	check(ticks[0] > 150 and ticks[0] < 400, "after a demoable 15 to 40 s, not instantly (%d ticks)" % ticks[0])
	check_eq(_exploded, [smelter], "exploded once")


func test_a_fast_smelter_stopped_in_time_survives_and_resumes() -> void:
	var pair: Array = _smelter_with_collector(Vector2i(1, 0))
	var smelter: Machine = pair[0]
	_feed(smelter, 600, func(m: Machine) -> bool: return m.status == Machine.Status.OVERHEATING)
	check_eq(smelter.status, Machine.Status.OVERHEATING, "got hot")
	smelter.apply_tool_call("set_emergency_stop", {"on": true})
	_ticks(40)
	check(smelter.temperature < Smelter.EXPLODE_AT and _exploded.is_empty(), "the emergency stop saved it")
	_cool_down(smelter)
	smelter.apply_tool_call("set_emergency_stop", {"on": false})
	var sold: int = pair[1].sold
	_feed(smelter, 60)
	check(pair[1].sold > sold, "and it produces again at full speed")


func test_temperature_falls_during_cooled_production() -> void:
	var smelter: Machine = _smelter_with_collector(Vector2i(1, 0))[0]
	smelter.temperature = 80.0
	smelter.apply_tool_call("set_cooling", {"on": true})
	var working_ticks: int = 0
	var last: float = smelter.temperature
	var never_rose: bool = true
	for i: int in 100:
		smelter.receive("ore")
		working_ticks += 1 if smelter.is_working() else 0
		_ticks(1)
		never_rose = never_rose and smelter.temperature <= last
		last = smelter.temperature
	check(working_ticks > 50, "it was producing meanwhile")
	check(never_rose, "the temperature never rises while cooling")
	check(smelter.temperature < 80.0 - 15.0, "and ends well below where it started")


func test_cooled_production_never_explodes() -> void:
	var smelter: Machine = _smelter_with_collector(Vector2i(1, 0))[0]
	smelter.apply_tool_call("set_cooling", {"on": true})
	_feed(smelter, 1500)
	check_eq(smelter.status, Machine.Status.NORMAL, "stable with cooling on")
	check(_exploded.is_empty(), "nothing exploded")


func _run_until_overheating(smelter: Machine) -> void:
	_feed(smelter, 600, func(m: Machine) -> bool: return m.status == Machine.Status.OVERHEATING)
	check_eq(smelter.status, Machine.Status.OVERHEATING, "got hot")


func _cool_down(smelter: Machine) -> void:
	var ticks: int = 0
	while smelter.temperature > Smelter.SAFE_AT and ticks < 400:
		_ticks(1)
		ticks += 1
	check(smelter.temperature <= Smelter.SAFE_AT, "cooled to the resume point")


func test_the_coolers_own_emergency_stop_resumes() -> void:
	var pair: Array = _smelter_with_collector(Vector2i(1, 0))
	var smelter: Machine = pair[0]
	_run_until_overheating(smelter)
	check(smelter.apply_tool_call("set_emergency_stop", {"on": true}), "emergency stop applies")
	check(not smelter.enabled and smelter.get_state()["emergency_stop"], "stopped, and the state says it is an emergency stop")
	_cool_down(smelter)
	check(smelter.apply_tool_call("set_emergency_stop", {"on": false}), "resume applies")
	check(smelter.enabled and not smelter.get_state()["emergency_stop"], "running again, marker cleared")
	var sold: int = pair[1].sold
	smelter.apply_tool_call("set_cooling", {"on": true})
	_feed(smelter, 300)
	check(pair[1].sold > sold, "production resumed")
	check(_exploded.is_empty(), "never exploded")


func test_another_chips_pause_survives_the_coolers_resume() -> void:
	var smelter: Machine = _smelter_with_collector(Vector2i(1, 0))[0]
	_run_until_overheating(smelter)
	smelter.apply_tool_call("set_enabled", {"on": false})
	check(not smelter.get_state()["emergency_stop"], "not an emergency stop")
	_cool_down(smelter)
	check(smelter.apply_tool_call("set_emergency_stop", {"on": false}), "the Cooler's resume is accepted but does nothing")
	check(not smelter.enabled, "the other chip's pause stays in effect")


func test_a_later_set_enabled_takes_over_the_emergency_stop() -> void:
	var smelter: Machine = _smelter_with_collector(Vector2i(1, 0))[0]
	smelter.apply_tool_call("set_emergency_stop", {"on": true})
	smelter.apply_tool_call("set_enabled", {"on": false})
	check(not smelter.get_state()["emergency_stop"], "another chip pausing explicitly clears the marker")
	smelter.apply_tool_call("set_emergency_stop", {"on": false})
	check(not smelter.enabled, "so the Cooler no longer resumes it")
	smelter.apply_tool_call("set_emergency_stop", {"on": true})
	smelter.apply_tool_call("set_enabled", {"on": true})
	check(smelter.enabled and not smelter.get_state()["emergency_stop"], "resuming by hand clears it too")


func test_cooling_while_idle_speeds_recovery() -> void:
	var slow: Machine = _put("smelter", Vector2i(9, 9))
	var quick: Machine = _put("smelter", Vector2i(10, 9))
	slow.temperature = 90.0
	quick.temperature = 90.0
	quick.apply_tool_call("set_cooling", {"on": true})
	_ticks(30)
	check(quick.temperature < slow.temperature, "idle with cooling cools faster than idle without")
	check(slow.temperature < 90.0, "idle without cooling still cools")


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
	check("set_cooling" in names and "set_enabled" in names and "set_emergency_stop" in names, "exposes its three tools")
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


## True once a delivery attempt failed: the Miner's "blocked" state, a craft machine's "output blocked" text.
func _is_blocked(machine: Machine) -> bool:
	if machine is Miner:
		return machine.get_state()["blocked"]
	return machine.get_action_text().contains("output blocked")


## How often the machine turns blocked (false -> true) over `count` ticks.
func _blocked_rises(machine: Machine, count: int) -> int:
	var rises: int = 0
	var was_blocked: bool = _is_blocked(machine)
	for i: int in count:
		_ticks(1)
		var is_blocked: bool = _is_blocked(machine)
		if is_blocked and not was_blocked:
			rises += 1
		was_blocked = is_blocked
	return rises


func test_deliverable_miner_output_is_never_blocked() -> void:
	var miner: Miner = _put("miner", Vector2i(0, 0)) as Miner
	miner.mine_ticks = 5
	var collector: Machine = _put("collector", Vector2i(1, 0))
	check_eq(_blocked_rises(miner, 100), 0, "a deliverable ore does not turn blocked")
	check(not miner.get_state()["blocked"], "state is not blocked")
	check(not miner.get_action_text().contains("blocked"), "action text is not blocked")
	check(collector.sold >= 10, "ore flowed")


func test_miner_failed_delivery_turns_blocked_once_then_again_after_clearing() -> void:
	var miner: Miner = _put("miner", Vector2i(0, 0)) as Miner
	miner.mine_ticks = 5
	check_eq(_blocked_rises(miner, 5), 0, "a freshly mined ore is not blocked before a delivery attempt")
	check_eq(_blocked_rises(miner, 1), 1, "the failed delivery blocks it")
	check(miner.get_state()["blocked"], "state is blocked")
	check(miner.get_action_text().contains("output blocked"), "action text is blocked")
	check_eq(_blocked_rises(miner, 50), 0, "it does not repeat while still blocked")
	miner.clear_contents()
	check(not _is_blocked(miner), "clearing unblocks it")
	check(not miner.get_state()["blocked"], "and the blocked state")
	check(not miner.get_action_text().contains("blocked"), "and the action text")
	check_eq(_blocked_rises(miner, 10), 1, "the blockage coming back blocks it again")


func test_deliverable_craft_output_is_never_blocked() -> void:
	var smelter: Machine = _put("smelter", Vector2i(1, 1), Vector2i.UP)
	var collector: Machine = _put("collector", Vector2i(1, 0))
	for i: int in 3:
		smelter.receive("ore")
	check_eq(_blocked_rises(smelter, 100), 0, "a deliverable ingot does not turn blocked")
	check(not smelter.get_action_text().contains("blocked"), "action text is not blocked")
	check_eq(collector.sold, 3, "the ingots were delivered")


func test_craft_failed_delivery_turns_blocked_once_then_again_after_clearing() -> void:
	var smelter: Machine = _put("smelter", Vector2i(1, 1), Vector2i.UP)
	smelter.receive("ore")
	var ticks_to_craft: int = (smelter as Smelter).recipe.ticks / Smelter.UNCOOLED_SPEEDUP + 1
	check_eq(_blocked_rises(smelter, ticks_to_craft), 0, "a finished ingot is not blocked before a delivery attempt")
	check_eq(_blocked_rises(smelter, 1), 1, "the failed delivery blocks it")
	check(smelter.get_action_text().contains("output blocked"), "action text is blocked")
	check_eq(_blocked_rises(smelter, 50), 0, "it does not repeat while still blocked")
	smelter.clear_contents()
	check(not _is_blocked(smelter), "clearing removes the event")
	check(not smelter.get_action_text().contains("blocked"), "and the action text")
	smelter.receive("ore")
	check_eq(_blocked_rises(smelter, ticks_to_craft + 1), 1, "the blockage coming back blocks it again")


func test_set_cooling_description_matches_the_real_durations() -> void:
	var plain: Smelter = _put("smelter", Vector2i(1, 1)) as Smelter
	var cooled: Smelter = _put("smelter", Vector2i(5, 1)) as Smelter
	cooled.apply_tool_call("set_cooling", {"on": true})
	plain.receive("ore")
	cooled.receive("ore")
	_ticks(1)
	check_eq([plain.progress, cooled.progress], [10, 40], "10 ticks without cooling, 40 with it, for the current recipe")
	var description: String = ""
	for schema: Dictionary in cooled.get_tool_schemas():
		if schema["name"] == "set_cooling":
			description = schema["description"]
	check(description.contains("four times as long") and description.contains("40 ticks instead of 10"), "the tool says so")
	check(description.contains("when a craft starts"), "and that the duration is chosen when a craft starts")
	check(not description.contains("twice"), "no stale 'twice'")
	cooled.cooling = false
	check_eq(cooled.progress, 40, "a craft already started keeps the duration it started with")


## The trembling art. The machine node itself (grid position, facing) never moves: only the sprite does.
func _sprite_of(machine: Machine) -> Sprite2D:
	return machine.get_node("Sprite2D") as Sprite2D


func _shake_frames(smelter: Smelter, frames: int) -> Array[Vector2]:
	var seen: Array[Vector2] = []
	for i: int in frames:
		smelter._process(0.013)
		seen.append(_sprite_of(smelter).position)
	return seen


func test_shake_amplitude_starts_at_100_and_is_almost_invisible_until_120() -> void:
	check_eq(Smelter.SHAKE_FROM, 100.0, "it starts at the overheating line")
	for heat: float in [Smelter.AMBIENT, 60.0, 80.0, 99.0, 100.0]:
		check_eq(Smelter.shake_amplitude(heat), 0.0, "no shake at %d degrees" % int(heat))
	check(Smelter.shake_amplitude(101.0) > 0.0, "it starts right above 100")
	check_eq(Smelter.shake_amplitude(Smelter.EXPLODE_AT), Smelter.SHAKE_MAX_PIXELS, "full at the explosion point")
	check_eq(Smelter.shake_amplitude(Smelter.EXPLODE_AT + 50.0), Smelter.SHAKE_MAX_PIXELS, "never beyond the maximum")
	var last: float = 0.0
	for heat: int in range(101, 151, 3):
		var amplitude: float = Smelter.shake_amplitude(float(heat))
		check(amplitude > last, "stronger at %d degrees" % heat)
		last = amplitude
	check(Smelter.shake_amplitude(110.0) < 0.1, "a hair at 110 (%.3f px)" % Smelter.shake_amplitude(110.0))
	check(Smelter.shake_amplitude(120.0) < 0.3, "almost invisible at 120 (%.2f px, under a third of a pixel)" % Smelter.shake_amplitude(120.0))
	check(Smelter.shake_amplitude(135.0) > 1.0, "clearly there by 135")
	check(Smelter.SHAKE_MAX_PIXELS <= 4.0, "never more than a small fraction of a 64 px cell")


func test_a_cool_smelter_does_not_move_and_a_hot_one_trembles_within_its_amplitude() -> void:
	var smelter: Smelter = _put("smelter", Vector2i(4, 4)) as Smelter
	var sprite: Sprite2D = _sprite_of(smelter)
	var rest: Vector2 = sprite.position
	var machine_position: Vector2 = smelter.position
	check(_shake_frames(smelter, 20).all(func(p: Vector2) -> bool: return p == rest), "no movement when cool")
	smelter.temperature = 90.0
	check(_shake_frames(smelter, 20).all(func(p: Vector2) -> bool: return p == rest), "and not below 100 either (90 degrees)")
	smelter.temperature = 135.0
	var amplitude: float = Smelter.shake_amplitude(135.0)
	var frames: Array[Vector2] = _shake_frames(smelter, 60)
	check(frames.any(func(p: Vector2) -> bool: return p != rest), "it trembles when hot")
	check(frames.all(func(p: Vector2) -> bool: return absf(p.x - rest.x) <= amplitude + 0.001 and absf(p.y - rest.y) <= amplitude + 0.001), "never farther than the amplitude from rest (%.2f px)" % amplitude)
	check_eq(smelter.position, machine_position, "the machine itself stays on its cell")
	check_eq(smelter.cell, Vector2i(4, 4), "grid cell unchanged")
	check_eq(smelter.facing, Vector2i.RIGHT, "facing unchanged")


func test_the_shake_grows_and_shrinks_with_the_temperature_and_resets() -> void:
	var smelter: Smelter = _put("smelter", Vector2i(4, 4)) as Smelter
	var rest: Vector2 = _sprite_of(smelter).position
	var reach: Callable = func(heat: float) -> float:
		smelter.temperature = heat
		var farthest: float = 0.0
		for p: Vector2 in _shake_frames(smelter, 80):
			farthest = maxf(farthest, (p - rest).length())
		return farthest
	var mild: float = reach.call(110.0)
	var strong: float = reach.call(140.0)
	check(mild > 0.0 and strong > mild * 3.0, "stronger when hotter (%.2f then %.2f px)" % [mild, strong])
	var cooling_down: float = reach.call(110.0)
	check(cooling_down < strong / 3.0, "reduced again as it cools (%.2f px)" % cooling_down)
	smelter.temperature = Smelter.AMBIENT
	smelter._process(0.013)
	check_eq(_sprite_of(smelter).position, rest, "back exactly at rest, with nothing accumulated")
	for i: int in 200:
		smelter.temperature = 130.0 if i % 2 == 0 else Smelter.AMBIENT
		smelter._process(0.013)
	smelter.temperature = Smelter.AMBIENT
	smelter._process(0.013)
	check_eq(_sprite_of(smelter).position, rest, "and after many cycles too")


func test_the_shake_follows_the_machine_through_a_rotation() -> void:
	var smelter: Smelter = _put("smelter", Vector2i(4, 4), Vector2i.RIGHT) as Smelter
	var sprite: Sprite2D = _sprite_of(smelter)
	var rest_right: Vector2 = sprite.position
	smelter.temperature = 130.0
	_shake_frames(smelter, 10)
	smelter.facing = Vector2i.DOWN
	var rest_down: Vector2 = Vector2.ZERO
	smelter.temperature = Smelter.AMBIENT
	smelter._process(0.013)
	rest_down = sprite.position
	check(rest_down != rest_right, "the two facings rest in different places (the right-facing art is turned and moved)")
	smelter.temperature = 130.0
	var amplitude: float = Smelter.shake_amplitude(130.0)
	smelter.facing = Vector2i.RIGHT
	check(_shake_frames(smelter, 30).all(func(p: Vector2) -> bool: return (p - rest_right).length() <= amplitude * 1.5 + 0.001), "turned back while shaking: it trembles around the right place")
	smelter.facing = Vector2i.DOWN
	check(_shake_frames(smelter, 30).all(func(p: Vector2) -> bool: return (p - rest_down).length() <= amplitude * 1.5 + 0.001), "turned while shaking: it trembles around the new place, not the old one")
	smelter.temperature = Smelter.AMBIENT
	smelter._process(0.013)
	check_eq(sprite.position, rest_down, "and it rests at the new place once cool")


func test_the_shake_stops_when_it_explodes_and_removal_is_safe() -> void:
	var smelter: Smelter = _put("smelter", Vector2i(4, 4)) as Smelter
	var sprite: Sprite2D = _sprite_of(smelter)
	var rest: Vector2 = sprite.position
	smelter.temperature = Smelter.EXPLODE_AT - 1.0
	_shake_frames(smelter, 5)
	check(sprite.position != rest, "trembling right before the blast")
	smelter.temperature = Smelter.EXPLODE_AT + 1.0
	_ticks(1)
	check_eq(smelter.status, Machine.Status.DOWN, "it explodes")
	check_eq(sprite.position, rest, "the shake stops at once: the explosion starts from the resting place")
	check(_shake_frames(smelter, 10).all(func(p: Vector2) -> bool: return p == rest), "and stays still while it burns")
	var other: Smelter = _put("smelter", Vector2i(8, 8)) as Smelter
	other.temperature = 120.0
	_shake_frames(other, 5)
	_nodes.erase(other)
	other.destroy()
	check(other.is_queued_for_deletion(), "a shaking smelter can be removed")
	await tree.process_frame
	check(not is_instance_valid(other) or other.is_queued_for_deletion(), "without errors")
