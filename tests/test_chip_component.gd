extends "res://tests/test_case.gd"

var _machine: Machine
var _chip: ChipComponent
var _saved_provider: String = ""
var _saved_cooldown: float = 5.0
var _applied: int = -1


func before_each() -> void:
	var settings: Node = autoload("Settings")
	_saved_provider = settings.provider
	_saved_cooldown = settings.chip_cooldown
	settings.provider = "mock"
	settings.chip_cooldown = 0.0
	_applied = -1
	_machine = Machine.new()
	_chip = ChipComponent.new()
	_machine.add_child(_chip)
	tree.root.add_child(_machine)
	_chip.add_prompt("production", "Keep running", 60.0)
	_chip.decision_applied.connect(_on_applied)


func after_each() -> void:
	var settings: Node = autoload("Settings")
	settings.provider = _saved_provider
	settings.chip_cooldown = _saved_cooldown
	_chip.decision_applied.disconnect(_on_applied)
	_machine.free()


func _on_applied(_reason: String, applied: int) -> void:
	_applied = applied


func test_request_round_trip() -> void:
	check(_chip.request_decision("manual"), "request sent")
	check(_chip.pending, "pending while in flight")
	await wait_until(func() -> bool: return not _chip.pending)
	check(not _chip.pending, "pending cleared")
	check(_applied >= 0, "decision applied")


func test_second_request_ignored_while_pending() -> void:
	_chip.request_decision("manual")
	check(not _chip.request_decision("manual"), "ignored while pending")
	await wait_until(func() -> bool: return not _chip.pending)


func test_cooldown_blocks_request() -> void:
	autoload("Settings").chip_cooldown = 60.0
	check(_chip.request_decision("manual"), "first request passes")
	await wait_until(func() -> bool: return not _chip.pending)
	check(not _chip.request_decision("manual"), "second blocked by cooldown")


func test_no_prompt_no_request() -> void:
	_chip.remove_prompt("production")
	check(not _chip.request_decision("manual"), "nothing to ask without a prompt")


func test_prompt_timeout_fires_request() -> void:
	_chip.add_prompt("fast", "Be quick", 1.0)
	for i: int in _tick_rate():
		autoload("EventBus").tick_fired.emit(i)
	check(_chip.pending, "timer triggered a request")
	await wait_until(func() -> bool: return not _chip.pending)


func test_machine_freed_while_pending_is_safe() -> void:
	var llm: Node = autoload("LLMManager")
	var chip_id: int = _chip.get_instance_id()
	var delivered: Array[int] = []
	var on_received: Callable = func(id: int, _calls: Array[Dictionary]) -> void:
		if id == chip_id:
			delivered.append(id)
	llm.decision_received.connect(on_received)
	check(_chip.request_decision("manual"), "request sent")
	_chip.decision_applied.disconnect(_on_applied)
	_machine.free()
	await wait_until(func() -> bool: return llm._in_flight == 0, 3.0)
	llm.decision_received.disconnect(on_received)
	check_eq(llm._in_flight, 0, "LLMManager released the slot")
	check_eq(delivered.size(), 0, "nothing delivered to a freed chip")
	_machine = Machine.new()
	_chip = ChipComponent.new()
	_machine.add_child(_chip)
	_chip.decision_applied.connect(_on_applied)


func test_timer_fires_at_exact_timeout() -> void:
	_chip.add_prompt("fast", "Be quick", 1.0)
	for i: int in _tick_rate() - 1:
		autoload("EventBus").tick_fired.emit(i)
	check(not _chip.pending, "not fired one tick early")
	autoload("EventBus").tick_fired.emit(0)
	check(_chip.pending, "fired on the exact timeout tick")
	await wait_until(func() -> bool: return not _chip.pending)


func test_overdue_prompts_are_served_in_order() -> void:
	var event_bus: Node = autoload("EventBus")
	event_bus.tick_fired.disconnect(_chip._on_tick)
	_chip.remove_prompt("production")
	_chip.add_prompt("first", "First prompt", 1.0)
	_chip.add_prompt("second", "Second prompt", 1.0)
	autoload("Settings").chip_cooldown = 60.0
	for i: int in _tick_rate():
		_chip._on_tick(i)
	check(_chip.pending, "first timer sent a request")
	await wait_until(func() -> bool: return not _chip.pending)
	for i: int in _tick_rate():
		_chip._on_tick(i)
	autoload("Settings").chip_cooldown = 0.0
	_chip._on_tick(0)
	check(_chip.pending, "an overdue timer sent a request")
	check_eq(_chip._elapsed["second"], 0, "longest overdue prompt was served")
	await wait_until(func() -> bool: return not _chip.pending)
	event_bus.tick_fired.connect(_chip._on_tick)


func _tick_rate() -> int:
	return autoload("GameState").TICK_RATE
