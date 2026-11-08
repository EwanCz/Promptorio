extends "res://tests/test_case.gd"
## Covers GR2-6 (key-free first experience): PredefinedBehaviors (the fixed table), the component
## that reapplies its tool calls through Machine.apply_tool_call on a fixed schedule, selection and
## attach/detach through Machine, and that no LLM/HTTP request is ever made on this path.

const MINER_SCENE: String = "res://scenes/machines/miner.tscn"
const SMELTER_SCENE: String = "res://scenes/machines/smelter.tscn"

var _miner: Miner
var _smelter: Smelter
var _saved_provider: String = ""
var _saved_api_key: String = ""


func _new_miner() -> Miner:
	var machine: Miner = (load(MINER_SCENE) as PackedScene).instantiate() as Miner
	tree.root.add_child(machine)
	return machine


func _new_smelter() -> Smelter:
	var machine: Smelter = (load(SMELTER_SCENE) as PackedScene).instantiate() as Smelter
	tree.root.add_child(machine)
	return machine


func before_each() -> void:
	var settings: Node = autoload("Settings")
	_saved_provider = settings.provider
	_saved_api_key = settings.api_key
	_miner = _new_miner()
	_smelter = _new_smelter()


func after_each() -> void:
	var settings: Node = autoload("Settings")
	settings.provider = _saved_provider
	settings.api_key = _saved_api_key
	_miner.free()
	_smelter.free()


func _tick(count: int) -> void:
	var bus: Node = autoload("EventBus")
	for i: int in count:
		bus.tick_fired.emit(i)


func test_table_offers_miner_and_smelter_only() -> void:
	check_eq(PredefinedBehaviors.for_machine_type("miner").size(), 2, "miner has a small fixed list")
	check_eq(PredefinedBehaviors.for_machine_type("smelter").size(), 2, "smelter has a small fixed list")
	check(PredefinedBehaviors.for_machine_type("collector").is_empty(), "a type with none offers none")
	check(PredefinedBehaviors.for_machine_type("nonsense").is_empty(), "an unknown type offers none")


func test_get_behavior_is_scoped_per_machine_type() -> void:
	check(not PredefinedBehaviors.get_behavior("miner", 1).is_empty(), "miner id 1 exists")
	check(PredefinedBehaviors.get_behavior("miner", 999).is_empty(), "unknown id is empty")
	check(PredefinedBehaviors.get_behavior("nonsense", 1).is_empty(), "unknown type is empty")


func test_attach_unknown_or_wrong_type_behavior_is_refused() -> void:
	check(_miner.attach_predefined_behavior(999) == null, "unknown id refused")
	check_eq(_miner.predefined_behaviors.size(), 0, "nothing attached")


func test_attach_and_detach_selection() -> void:
	var component: PredefinedBehaviorComponent = _miner.attach_predefined_behavior(1)
	check(component != null, "a listed behavior attaches")
	check_eq(_miner.predefined_behaviors.size(), 1, "tracked on the machine")
	check(_miner.get_predefined_behavior(1) == component, "lookup finds it")
	check(_miner.attach_predefined_behavior(1) == null, "attaching the same one twice is refused")
	check_eq(_miner.predefined_behaviors.size(), 1, "still only one")
	_miner.detach_predefined_behavior(1)
	check(_miner.get_predefined_behavior(1) == null, "removed")
	check_eq(_miner.predefined_behaviors.size(), 0, "untracked after removal")


func test_fast_pace_reapplies_through_apply_tool_call_and_is_clamped() -> void:
	_miner.mine_ticks = 50
	_miner.attach_predefined_behavior(2)
	_tick(149)
	check_eq(_miner.mine_ticks, 50, "not fired one tick early")
	_tick(1)
	check_eq(_miner.mine_ticks, _miner.get_min_mine_ticks(), "clamped to the machine's own minimum, not the raw ticks=1 the behavior asked for")


func test_prospector_starts_prospecting_on_a_fixed_timer() -> void:
	_miner.attach_predefined_behavior(1)
	_tick(Miner.PROSPECT_TICKS + Miner.BOOST_TICKS + 9)
	check_eq(_miner.mode, Miner.Mode.MINING, "not fired one tick early")
	_tick(1)
	check_eq(_miner.mode, Miner.Mode.PROSPECTING, "fired on the exact tick")
	check_eq(_miner.mode_ticks_left, Miner.PROSPECT_TICKS, "a fresh prospecting span")


func test_cool_runner_and_overheat_risk_set_cooling() -> void:
	_smelter.attach_predefined_behavior(1)
	check_eq(_smelter.cooling, false, "starts off")
	_tick(1)
	check_eq(_smelter.cooling, true, "Cool Runner turns cooling on at the next tick")
	_smelter.detach_predefined_behavior(1)
	_smelter.cooling = true
	_smelter.attach_predefined_behavior(2)
	_tick(1)
	check_eq(_smelter.cooling, false, "Overheat Risk turns cooling off")


func test_behavior_reapplies_every_interval_not_once() -> void:
	_smelter.attach_predefined_behavior(1)
	_tick(150)
	check_eq(_smelter.cooling, true, "applied the first time")
	_smelter.cooling = false
	_tick(150)
	check_eq(_smelter.cooling, true, "reapplied on the next interval, not a one-shot")


func test_detached_component_stops_acting() -> void:
	_smelter.attach_predefined_behavior(1)
	_smelter.detach_predefined_behavior(1)
	_tick(150)
	check_eq(_smelter.cooling, false, "no longer applies immediately after detaching")


func test_discard_frees_predefined_behavior_components() -> void:
	_miner.attach_predefined_behavior(1)
	var machine: Machine = _miner
	_miner = _new_miner()
	check_eq(machine.predefined_behaviors.size(), 1, "attached before discard")
	machine.discard()
	await tree.process_frame
	check(not is_instance_valid(machine), "discard frees the machine and its predefined behavior children with it")


func test_save_and_load_round_trip() -> void:
	_smelter.attach_predefined_behavior(2)
	var saved: Dictionary = _smelter.to_dict()
	var restored: Smelter = _new_smelter()
	restored.load_dict(saved)
	check_eq(restored.predefined_behaviors.size(), 1, "predefined behavior id survives a save/load round trip")
	check(restored.get_predefined_behavior(2) != null, "same behavior id reattached")
	restored.free()


func test_no_llm_or_http_request_is_ever_made() -> void:
	var settings: Node = autoload("Settings")
	settings.provider = "anthropic"
	settings.api_key = ""
	var llm: Node = autoload("LLMManager")
	var decisions: Array = []
	var failures: Array = []
	var on_received: Callable = func(id: int, _calls: Array[Dictionary]) -> void: decisions.append(id)
	var on_failed: Callable = func(id: int, _reason: String) -> void: failures.append(id)
	llm.decision_received.connect(on_received)
	llm.decision_failed.connect(on_failed)
	_miner.attach_predefined_behavior(1)
	_miner.attach_predefined_behavior(2)
	_smelter.attach_predefined_behavior(1)
	_tick(400)
	llm.decision_received.disconnect(on_received)
	llm.decision_failed.disconnect(on_failed)
	check_eq(decisions.size(), 0, "no decision ever received")
	check_eq(failures.size(), 0, "no decision ever failed (none was ever requested)")
	check_eq(llm._in_flight, 0, "LLMManager never had an in-flight request")
	check(llm._queue.is_empty(), "LLMManager queue stayed empty")
	check(_miner.mode == Miner.Mode.PROSPECTING or _miner.mine_ticks == _miner.get_min_mine_ticks(), "the behaviors still visibly acted, with no key and no network")
