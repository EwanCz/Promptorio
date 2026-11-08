extends "res://tests/test_case.gd"
## Factory events -> sound cues (GR2-30). SfxEvents is tested against a recording stand-in for `Sfx`, with a
## hand-set clock for its own hold-offs. The engine's rules (cooldown, pause) and the shipped library are
## checked against the real `Sfx` autoload, which the engine tests already cover in depth.

const CLOCKED_EVENTS_SCRIPT: GDScript = preload("res://tests/support/clocked_sfx_events.gd")
const CUE_IDS: Array[StringName] = [&"place", &"remove", &"place_rejected", &"deliver", &"craft_done", &"sell", &"order_complete", &"chip_ok", &"chip_none", &"chip_fail", &"blocked", &"overheat_warn", &"explosion", &"ui_click"]
const SCENES: Dictionary = {
	"miner": "res://scenes/machines/miner.tscn",
	"smelter": "res://scenes/machines/smelter.tscn",
	"collector": "res://scenes/machines/collector.tscn",
}

var _game: Node
var _bus: Node
var _real_sfx: Node
var _recorder: Recorder
var _events: Node
var _placement: Placement
var _tooltip: MachineTooltip
var _real_played: Array[StringName] = []
var _nodes: Array[Node] = []


## Stands in for the `Sfx` autoload: remembers each request.
class Recorder extends Node:
	var calls: Array[Dictionary] = []

	func play(cue_id: StringName, position: Vector2 = Vector2.INF, pitch_scale: float = 1.0) -> bool:
		calls.append({"cue": cue_id, "position": position, "pitch": pitch_scale})
		return true

	func cues() -> Array[StringName]:
		var ids: Array[StringName] = []
		for entry: Dictionary in calls:
			ids.append(entry["cue"])
		return ids


func before_each() -> void:
	_game = autoload("GameState")
	_bus = autoload("EventBus")
	_real_sfx = autoload("Sfx")
	_real_sfx.stop_all()
	_real_sfx.reset_stats()
	_real_played.clear()
	_real_sfx.played.connect(_on_real_played)
	_recorder = Recorder.new()
	_placement = Placement.new()
	_tooltip = (load("res://scenes/ui/popups/machine_tooltip.tscn") as PackedScene).instantiate() as MachineTooltip
	_listen(_recorder)


func after_each() -> void:
	tree.paused = false
	_real_sfx.played.disconnect(_on_real_played)
	for node: Node in _nodes:
		node.free()
	_nodes.clear()
	_stop_listening()
	_placement.free()
	_tooltip.free()
	_recorder.free()


## Stops the real voices and gives the audio thread time to let go of them: a playing stream freed at exit
## is reported as a leak in headless runs.
func _settle() -> void:
	_real_sfx.stop_all()
	await wait_seconds(0.05)


## A fresh listener on this placement and tooltip sending to `target`, replacing the previous one.
func _listen(target: Node) -> void:
	_stop_listening()
	_events = CLOCKED_EVENTS_SCRIPT.new()
	_events.set("sfx", target)
	tree.root.add_child(_events)
	_events.call("setup", _placement, _tooltip)


func _stop_listening() -> void:
	if _events != null:
		tree.root.remove_child(_events)
		_events.free()
		_events = null


func _on_real_played(cue: StringName, _position: Vector2, _volume_db: float, _pitch_scale: float) -> void:
	_real_played.append(cue)


func _advance(msec: int) -> void:
	_events.set("now_msec", int(_events.get("now_msec")) + msec)


func _played() -> Array[StringName]:
	return _recorder.cues()


func _count(cue: StringName) -> int:
	return _recorder.cues().count(cue)


func _put(type: String, cell: Vector2i) -> Machine:
	var machine: Machine = (load(SCENES[type]) as PackedScene).instantiate() as Machine
	machine.cell = cell
	machine.position = _game.cell_to_world(cell)
	tree.root.add_child(machine)
	_game.register_machine(machine, cell)
	_nodes.append(machine)
	return machine


func _ticks(count: int) -> void:
	for i: int in count:
		_bus.tick_fired.emit(i)


func _new_main() -> Node:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(main)
	return main


func test_the_library_has_every_cue_and_each_stream_loads() -> void:
	var library: SfxLibrary = load(SfxLibrary.PATH) as SfxLibrary
	check(library != null, "data/sfx.tres loads as an SfxLibrary")
	check_eq(library.cues.size(), CUE_IDS.size(), "one cue per sound")
	for id: StringName in CUE_IDS:
		var cue: SfxCue = library.get_cue(id)
		check(cue != null and cue.stream != null and cue.stream.get_length() > 0.0, "%s has a stream with a length" % id)
		check(cue != null and cue.max_voices >= 1 and cue.cooldown > 0.0, "%s is rate limited" % id)
	check(library.get_cue(&"ui_click").ui and library.get_cue(&"place_rejected").ui, "ui_click and place_rejected play while paused")
	check(not library.get_cue(&"explosion").ui, "gameplay cues stop while paused")
	check(library.get_cue(&"overheat_warn").volume_db > library.get_cue(&"deliver").volume_db, "warnings are louder than deliveries")
	check(library.get_cue(&"explosion").volume_db > library.get_cue(&"craft_done").volume_db, "the explosion is louder than a craft")
	check(library.get_cue(&"deliver").cooldown >= library.get_cue(&"place").cooldown, "frequent cues have the longer cooldowns")
	check(_real_sfx.library.get_cue(&"place") != null, "the Sfx autoload found the shipped library")


func test_placement_and_removal_cues() -> void:
	var machine: Machine = _put("miner", Vector2i(0, 0))
	_placement.machine_placed.emit(machine)
	check_eq(_played(), [&"place"] as Array[StringName], "placing plays place once")
	check_eq(_recorder.calls[0]["position"], machine.global_position + Vector2.ONE * (_game.CELL_SIZE / 2.0), "at the machine center")
	_placement.placement_rejected.emit("no")
	check_eq(_count(&"place_rejected"), 1, "a refused placement plays place_rejected")
	_tooltip.machine_destroyed.emit(Vector2(10.0, 10.0))
	check_eq(_count(&"remove"), 1, "destroying plays remove")


func test_a_sale_plays_sell_pitched_by_price() -> void:
	var collector: Machine = _put("collector", Vector2i(0, 1))
	collector.receive("ore")
	collector.receive("robot")
	check_eq(_played(), [&"sell", &"sell"] as Array[StringName], "each sale asks for sell")
	check(float(_recorder.calls[1]["pitch"]) > float(_recorder.calls[0]["pitch"]), "a dearer item sounds higher")
	check(SfxEvents.pitch_for_price(1) < SfxEvents.pitch_for_price(15) and SfxEvents.pitch_for_price(15) < SfxEvents.pitch_for_price(200), "pitch grows with price")
	check_eq(SfxEvents.pitch_for_price(0), SfxEvents.SELL_PITCH_LOW, "a free item is the lowest pitch")
	check_eq(SfxEvents.pitch_for_price(100000), SfxEvents.SELL_PITCH_HIGH, "a huge price is capped")
	check(not collector.receive("nonsense") and _count(&"sell") == 2, "a refused item is not a sale")


func test_an_order_completion_plays_order_complete() -> void:
	_bus.order_completed.emit("ingot", 20)
	check_eq(_played(), [&"order_complete"] as Array[StringName], "order_complete once")


func test_production_plays_craft_done_for_crafts_and_deliver_for_mining() -> void:
	var smelter: Machine = _put("smelter", Vector2i(0, 2))
	var miner: Machine = _put("miner", Vector2i(2, 2))
	smelter.produced.emit()
	check_eq(_played(), [&"craft_done"] as Array[StringName], "a finished craft plays craft_done")
	miner.produced.emit()
	check_eq(_count(&"deliver"), 1, "a mined unit handed over plays deliver")


func test_chip_results_map_to_their_cues_and_share_a_throttle() -> void:
	var machine: Machine = _put("miner", Vector2i(0, 3))
	machine.chip_outcome_reported.emit("applied")
	check_eq(_played(), [&"chip_ok"] as Array[StringName], "applied is chip_ok")
	machine.chip_outcome_reported.emit("none")
	machine.chip_outcome_reported.emit("failed")
	check_eq(_recorder.calls.size(), 1, "results inside the throttle stay silent")
	_advance(SfxEvents.CHIP_MIN_GAP_MSEC)
	machine.chip_outcome_reported.emit("none")
	_advance(SfxEvents.CHIP_MIN_GAP_MSEC)
	machine.chip_outcome_reported.emit("failed")
	check_eq(_played(), [&"chip_ok", &"chip_none", &"chip_fail"] as Array[StringName], "none and failed have their own cues")
	_advance(SfxEvents.CHIP_MIN_GAP_MSEC)
	machine.chip_outcome_reported.emit("checking")
	check_eq(_recorder.calls.size(), 3, "a request starting is not a result")


func test_a_real_chip_activity_signal_reaches_the_machine_signal() -> void:
	var machine: Machine = _put("smelter", Vector2i(0, 4))
	var seen: Array[String] = []
	var on_outcome: Callable = func(outcome: String) -> void: seen.append(outcome)
	machine.chip_outcome_reported.connect(on_outcome)
	machine._on_chip_activity("checking")
	machine._on_chip_activity("none")
	machine._on_chip_activity("")
	machine.chip_outcome_reported.disconnect(on_outcome)
	check_eq(seen, ["none"] as Array[String], "only a finished request is reported")


func test_a_chip_outcome_is_reported_while_another_chip_is_pending() -> void:
	var machine: Machine = _put("smelter", Vector2i(0, 4))
	var pending: ChipComponent = ChipComponent.new()
	pending.pending = true
	machine.chips.append(pending)
	machine._on_chip_activity("failed")
	check_eq(_played(), [&"chip_fail"] as Array[StringName], "a completed request sounds even while another is pending")
	machine.chips.erase(pending)
	pending.free()


func test_a_stalled_machine_plays_blocked_once_with_a_long_hold_off() -> void:
	var miner: Machine = _put("miner", Vector2i(0, 5))
	_ticks(miner.mine_ticks + 2)
	check_eq(miner.get_production_state(), Machine.ProductionState.STALLED, "the miner is stuck")
	check_eq(_count(&"blocked"), 1, "entering STALLED plays blocked")
	_ticks(100)
	check_eq(_count(&"blocked"), 1, "staying stalled is silent")
	miner.clear_contents()
	_ticks(1)
	_advance(10000)
	_ticks(miner.mine_ticks + 2)
	check_eq(_count(&"blocked"), 1, "stalling again within the hold-off is silent")
	miner.clear_contents()
	_ticks(1)
	_advance(SfxEvents.BLOCKED_HOLD_OFF_MSEC)
	_ticks(miner.mine_ticks + 2)
	check_eq(_count(&"blocked"), 2, "after the hold-off it may sound again")
	check(SfxEvents.BLOCKED_HOLD_OFF_MSEC >= 20000, "the hold-off is at least 20 s")


func test_overheating_warns_on_entry_then_at_most_every_few_seconds() -> void:
	var smelter: Smelter = _put("smelter", Vector2i(0, 6)) as Smelter
	_ticks(1)
	smelter.temperature = Smelter.OVERHEAT_AT + 5.0
	smelter.status = Machine.Status.OVERHEATING
	_ticks(1)
	check_eq(_count(&"overheat_warn"), 1, "entering OVERHEATING warns")
	_ticks(30)
	check_eq(_count(&"overheat_warn"), 1, "no repeat inside the interval")
	_advance(SfxEvents.OVERHEAT_REPEAT_MSEC)
	_ticks(1)
	_ticks(1)
	check_eq(_count(&"overheat_warn"), 2, "it repeats once the interval passed, while still hot")
	smelter.status = Machine.Status.NORMAL
	_ticks(1)
	_advance(SfxEvents.OVERHEAT_REPEAT_MSEC * 3)
	_ticks(5)
	check_eq(_count(&"overheat_warn"), 2, "silent once nothing is overheating")


func test_an_explosion_plays_explosion() -> void:
	var smelter: Machine = _put("smelter", Vector2i(0, 7))
	_bus.machine_exploded.emit(smelter)
	check_eq(_played(), [&"explosion"] as Array[StringName], "explosion once")


func test_a_machine_already_in_trouble_when_listened_to_is_silent() -> void:
	var smelter: Smelter = _put("smelter", Vector2i(0, 14)) as Smelter
	smelter.temperature = Smelter.OVERHEAT_AT + 5.0
	smelter.status = Machine.Status.OVERHEATING
	_listen(_recorder)
	_ticks(5)
	check(_recorder.calls.is_empty(), "adopting an overheating machine is silent")
	_advance(SfxEvents.OVERHEAT_REPEAT_MSEC)
	_ticks(1)
	check_eq(_count(&"overheat_warn"), 1, "its reminder comes later")


func test_a_removed_machine_is_forgotten() -> void:
	var miner: Machine = _put("miner", Vector2i(0, 15))
	_ticks(1)
	check(miner.destroy(), "the machine is destroyed")
	_nodes.erase(miner)
	_ticks(5)
	check(_recorder.calls.is_empty(), "nothing sounds for a machine that is gone")


func test_the_real_sfx_cools_down_and_a_big_factory_stays_bounded() -> void:
	_listen(_real_sfx)
	var smelters: Array[Machine] = []
	var miners: Array[Machine] = []
	for i: int in 20:
		smelters.append(_put("smelter", Vector2i(i, 10)))
		miners.append(_put("miner", Vector2i(i, 11)))
	for i: int in 10:
		miners.append(_put("miner", Vector2i(i, 12)))
	for step: int in 10:
		for machine: Machine in smelters + miners:
			machine.produced.emit()
			machine.chip_outcome_reported.emit("applied")
		_advance(100)
	_ticks(miners[0].mine_ticks + 2)
	var all: Array[StringName] = _real_played
	check(all.count(&"craft_done") <= 1, "craft_done is limited by its cooldown (%d)" % all.count(&"craft_done"))
	check(all.count(&"deliver") <= 1, "deliver is limited by its cooldown (%d)" % all.count(&"deliver"))
	check(all.count(&"chip_ok") <= 1, "chip_ok is limited by its cooldown (%d)" % all.count(&"chip_ok"))
	check_eq(all.count(&"blocked"), 1, "30 machines jamming together make one knock")
	check(_real_sfx.active_voices() <= 6, "few voices sound at once (%d)" % _real_sfx.active_voices())
	check(all.size() <= 6, "a whole burst stays under a handful of sounds (%d)" % all.size())
	check(int(_real_sfx.stats["requested"]) > all.size(), "most of the requests were dropped by the engine")
	await _settle()


func test_paused_plays_no_gameplay_cue() -> void:
	_listen(_real_sfx)
	var machine: Machine = _put("miner", Vector2i(0, 13))
	tree.paused = true
	_placement.machine_placed.emit(machine)
	_bus.order_completed.emit("ingot", 20)
	_bus.machine_exploded.emit(machine)
	check(_real_played.is_empty(), "nothing plays while paused")
	check_eq(_real_sfx.stats["paused"], 3, "the engine dropped the three requests")
	_placement.placement_rejected.emit("no")
	check_eq(_real_played, [&"place_rejected"] as Array[StringName], "the ui cue still does")
	await _settle()


func test_loading_a_save_and_resetting_play_nothing() -> void:
	var main: Node = _new_main()
	var placement: Placement = main.get_node("Game/FactoryView/SubViewport/World/Placement")
	placement.place("miner", Vector2i(4, 4))
	var smelter: Smelter = placement.place("smelter", Vector2i(6, 4)) as Smelter
	smelter.temperature = Smelter.OVERHEAT_AT + 5.0
	smelter.status = Machine.Status.OVERHEATING
	placement.place("conveyor", Vector2i(8, 4))
	var save: Dictionary = SaveGame.snapshot(placement)
	check_eq(SaveGame.restore(placement, save), "", "the save restores")
	_game.reset()
	_ticks(3)
	check(_real_played.is_empty(), "restore and reset made no sound: %s" % [_real_played])
	check_eq(_real_sfx.stats["requested"], 0, "and asked the engine for none")
	main.free()
	await _settle()


func test_building_through_the_real_placement_flow() -> void:
	var main: Node = _new_main()
	var placement: Placement = main.get_node("Game/FactoryView/SubViewport/World/Placement")
	var tooltip: MachineTooltip = main.get_node("%MachineTooltip")
	var money: int = _game.money
	_game.money = 1000
	var machine: Machine = placement.try_place("smelter", Vector2i(4, 4))
	check(machine != null, "the smelter is built")
	check_eq(_real_played, [&"place"] as Array[StringName], "building plays place")
	placement.try_place("smelter", Vector2i(4, 4))
	check_eq(_real_played.count(&"place_rejected"), 1, "a taken cell plays place_rejected")
	_bus.machine_selected.emit(machine)
	check(tooltip.destroy_machine(), "the machine is destroyed")
	check_eq(_real_played.count(&"remove"), 1, "destroying plays remove")
	_game.money = money
	main.free()
	await _settle()


func test_a_button_click_plays_ui_click_on_the_autoload() -> void:
	var button: Button = Button.new()
	SfxEvents.attach_click(button)
	tree.root.add_child(button)
	button.pressed.emit()
	check_eq(_real_played, [&"ui_click"] as Array[StringName], "pressing a button clicks")
	button.free()
	await _settle()


func test_the_bar_and_menu_buttons_click() -> void:
	var main: Node = _new_main()
	var buttons: Node = main.get_node("%BarButtons")
	var clicked: int = 0
	for child: Node in buttons.get_children():
		var button: BaseButton = child as BaseButton
		if button != null:
			_real_sfx.reset_stats()
			_real_played.clear()
			button.pressed.emit()
			clicked += _real_played.count(&"ui_click")
	check_eq(clicked, buttons.get_child_count(), "every Bar button clicks")
	main.free()
	await _settle()
	var menu: Node = (load("res://scenes/menu/main_menu.tscn") as PackedScene).instantiate()
	tree.root.add_child(menu)
	_real_played.clear()
	_real_sfx.reset_stats()
	menu.get_node("%OptionsButton").pressed.emit()
	check_eq(_real_played, [&"ui_click"] as Array[StringName], "a main menu button clicks")
	menu.free()
	await _settle()
