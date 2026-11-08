extends "res://tests/test_case.gd"

const MINER: String = "res://scenes/machines/miner.tscn"
const SMELTER: String = "res://scenes/machines/smelter.tscn"
const ASSEMBLER: String = "res://scenes/machines/assembler.tscn"

var _machine: Machine
var _res: ChipRessource
var _saved_provider: String = ""
var _saved_cooldown: float = 5.0
var _reason: String = ""


func before_each() -> void:
	var settings: Node = autoload("Settings")
	_saved_provider = settings.provider
	_saved_cooldown = settings.chip_cooldown
	settings.provider = "mock"
	settings.chip_cooldown = 0.0
	_reason = ""
	_res = autoload("ChipRegistry").add("trigger_test", "Keep it running")


func after_each() -> void:
	var settings: Node = autoload("Settings")
	settings.provider = _saved_provider
	settings.chip_cooldown = _saved_cooldown
	if _machine != null:
		_machine.free()
		_machine = null
	autoload("ChipRegistry").remove(_res.id)


func _spawn(path: String) -> ChipComponent:
	if _machine != null:
		_machine.free()
	_machine = (load(path) as PackedScene).instantiate() as Machine
	tree.root.add_child(_machine)
	var chip: ChipComponent = _machine.attach_chip(_res.id, 100000)
	chip.decision_applied.connect(_on_applied)
	return chip


func _on_applied(reason: String, _applied: int) -> void:
	_reason = reason


func _tick(count: int) -> void:
	for i: int in count:
		autoload("EventBus").tick_fired.emit(i)


func _finish(chip: ChipComponent) -> void:
	await wait_until(func() -> bool: return not chip.pending)


var _started: int = 0


func _on_started(_id: int) -> void:
	_started += 1


func test_state_and_status_changes_never_wake_a_chip() -> void:
	var bus: Node = autoload("EventBus")
	_started = 0
	bus.llm_request_started.connect(_on_started)
	var chip: ChipComponent = _spawn(SMELTER)
	var smelter: Smelter = _machine as Smelter
	var before: Array = [smelter.enabled, smelter.cooling, smelter.emergency_stop]
	smelter.temperature = 90.0
	_tick(3)
	check(not chip.pending, "a temperature rise does not wake the chip")
	smelter.temperature = Smelter.OVERHEAT_AT + 5.0
	_tick(3)
	check_eq(smelter.status, Machine.Status.OVERHEATING, "the smelter really is overheating")
	check(not chip.pending, "becoming OVERHEATING does not wake it either")
	smelter.status = Machine.Status.DOWN
	_tick(3)
	check(not chip.pending, "nor a machine going down")
	check_eq([smelter.enabled, smelter.cooling, smelter.emergency_stop], before, "no machine setting changed")
	var miner: ChipComponent = _spawn(MINER)
	_tick((_machine as Miner).mine_ticks + 5)
	check(_machine.get_state()["blocked"] and not miner.pending, "a blocked output does not wake a chip")
	var assembler: ChipComponent = _spawn(ASSEMBLER)
	_tick(3)
	check(not assembler.pending, "nor an empty input")
	bus.llm_request_started.disconnect(_on_started)
	check_eq(_started, 0, "the LLM was never called")
	check_eq(_reason, "", "no decision was ever asked for")


func test_there_is_no_event_or_threshold_api() -> void:
	var chip: ChipComponent = _spawn(SMELTER)
	check(not chip.has_method("set_threshold") and not "threshold_key" in chip, "no threshold trigger")
	check(not _machine.has_method("get_events"), "no machine events")


func test_timer_trigger_still_fires() -> void:
	var chip: ChipComponent = _spawn(MINER)
	chip.set_timeout(5)
	_tick(4)
	check(not chip.pending, "not before the timeout")
	_tick(1)
	check(chip.pending, "the timer wakes the chip")
	await _finish(chip)
	check_eq(_reason, "timer", "reason is timer")


func test_state_is_sent_when_the_chip_is_asked() -> void:
	var chip: ChipComponent = _spawn(SMELTER)
	(_machine as Smelter).temperature = 90.0
	var seen: Array[Dictionary] = []
	var on_started: Callable = func(_id: int) -> void: seen.append(_machine.get_state())
	autoload("EventBus").llm_request_started.connect(on_started)
	chip.set_timeout(2)
	_tick(2)
	autoload("EventBus").llm_request_started.disconnect(on_started)
	check_eq(_reason, "", "not applied yet")
	await _finish(chip)
	check_eq(_reason, "timer", "the timer asked")
	check(seen.size() == 1 and seen[0].has("temperature") and seen[0].has("status") and seen[0].has("enabled") and seen[0].has("cooling") and seen[0].has("emergency_stop"), "temperature, status, enabled, cooling and emergency_stop are in the state")


func test_manual_trigger_uses_cooldown() -> void:
	var chip: ChipComponent = _spawn(MINER)
	autoload("Settings").chip_cooldown = 60.0
	check(chip.call_llm("manual"), "manual request sent")
	await _finish(chip)
	check_eq(_reason, "manual", "reason is manual")
	check(not chip.call_llm("manual"), "manual request obeys the cooldown")
