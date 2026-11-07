extends SceneTree
## Headless smoke test for the autoloads. Run: godot --headless -s tests/smoke_autoloads.gd
## Exits with code 1 if any check fails. Needs `godot --headless --import` once after new class_name scripts.

const TOOLS: Array = [{
	"name": "set_speed",
	"description": "Set speed",
	"input_schema": {"type": "object", "properties": {
		"value": {"type": "number", "minimum": 0.0, "maximum": 1.0},
		"on": {"type": "boolean"},
	}},
}]

var _failures: int = 0
var _bus: Node
var _game_state: Node
var _settings: Node
var _llm: Node
var _received: Dictionary = {}
var _failed: Dictionary = {}


func _initialize() -> void:
	await process_frame
	_bus = root.get_node("EventBus")
	_game_state = root.get_node("GameState")
	_settings = root.get_node("Settings")
	_llm = root.get_node("LLMManager")
	_llm.decision_received.connect(func(id: int, calls: Array[Dictionary]) -> void: _received[id] = calls)
	_llm.decision_failed.connect(func(id: int, reason: String) -> void: _failed[id] = reason)

	_test_grid()
	_test_money()
	await _test_tick()
	_test_settings()
	await _test_llm_mock()
	await _test_llm_superseded()
	await _test_llm_concurrency_cap()
	await _test_llm_unknown_provider()

	print("---")
	if _failures == 0:
		print("ALL PASSED")
	else:
		print("%d FAILED" % _failures)
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("ok   ", label)
	else:
		print("FAIL ", label)
		_failures += 1


func _wait_until(condition: Callable, timeout: float) -> void:
	var elapsed: float = 0.0
	while not condition.call() and elapsed < timeout:
		await process_frame
		elapsed += 1.0 / 60.0


func _test_grid() -> void:
	var cell: Vector2i = Vector2i(2, 3)
	var machine: Node = Node.new()
	var events: Array[int] = [0, 0]
	_bus.machine_registered.connect(func(_m: Node, _c: Vector2i) -> void: events[0] += 1)
	_bus.machine_unregistered.connect(func(_m: Node, _c: Vector2i) -> void: events[1] += 1)

	_check(_game_state.can_place(cell), "grid: free cell can be placed on")
	_check(not _game_state.can_place(Vector2i(-1, 0)), "grid: negative cell rejected")
	_check(not _game_state.can_place(_game_state.GRID_SIZE), "grid: cell past the edge rejected")
	_check(_game_state.register_machine(machine, cell), "grid: register succeeds")
	var intruder: Node = Node.new()
	_check(not _game_state.register_machine(intruder, cell), "grid: double register rejected")
	intruder.free()
	_check(_game_state.get_machine_at(cell) == machine, "grid: get_machine_at returns machine")
	_check(_game_state.get_machines().size() == 1, "grid: get_machines has one entry")
	_check(events[0] == 1, "grid: machine_registered emitted once")
	_game_state.unregister_machine(cell)
	_check(_game_state.get_machine_at(cell) == null, "grid: unregister frees the cell")
	_check(events[1] == 1, "grid: machine_unregistered emitted once")
	_game_state.unregister_machine(cell)
	_check(events[1] == 1, "grid: unregistering an empty cell emits nothing")
	var world: Vector2 = _game_state.cell_to_world(cell)
	_check(_game_state.world_to_cell(world + Vector2(1, 1)) == cell, "grid: cell/world conversion round-trips")
	machine.free()


func _test_money() -> void:
	var seen: Array[int] = [0]
	_bus.money_changed.connect(func(amount: int) -> void: seen[0] = amount)
	var before: int = _game_state.money
	_game_state.add_money(25)
	_check(_game_state.money == before + 25, "money: add_money updates total")
	_check(seen[0] == before + 25, "money: money_changed carries new total")
	_game_state.add_money(-25)


func _test_tick() -> void:
	var ticks: Array[int] = [0]
	var on_tick: Callable = func(_t: int) -> void: ticks[0] += 1
	_bus.tick_fired.connect(on_tick)
	var start: int = _game_state.tick_count
	await create_timer(1.0).timeout
	_bus.tick_fired.disconnect(on_tick)
	_check(ticks[0] >= 8 and ticks[0] <= 12, "tick: ~10 ticks in 1 s (got %d)" % ticks[0])
	_check(_game_state.tick_count - start == ticks[0], "tick: tick_count matches emitted signals")


func _test_settings() -> void:
	var path: String = _settings.PATH
	var original: PackedByteArray = PackedByteArray()
	var had_file: bool = FileAccess.file_exists(path)
	if had_file:
		original = FileAccess.get_file_as_bytes(path)
	var saved_key: String = _settings.api_key
	var saved_provider: String = _settings.provider
	var saved_conc: int = _settings.max_concurrency

	_settings.api_key = "test-key"
	_settings.provider = "test-provider"
	_settings.max_concurrency = 3
	_settings.save_settings()
	_settings.api_key = ""
	_settings.provider = "mock"
	_settings.max_concurrency = 1
	_settings.load_settings()
	_check(_settings.api_key == "test-key", "settings: api_key round-trips")
	_check(_settings.provider == "test-provider", "settings: provider round-trips")
	_check(_settings.max_concurrency == 3, "settings: max_concurrency round-trips")

	var cfg: ConfigFile = ConfigFile.new()
	cfg.load(path)
	cfg.set_value(_settings.SECTION, "max_concurrency", 9999)
	cfg.set_value(_settings.SECTION, "max_tokens", 99999)
	cfg.save(path)
	_settings.load_settings()
	_check(_settings.max_concurrency == 16, "settings: max_concurrency clamped on load")
	_check(_settings.max_tokens == 300, "settings: max_tokens clamped to 300 on load")

	if had_file:
		var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
		file.store_buffer(original)
		file.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_settings.api_key = saved_key
	_settings.provider = saved_provider
	_settings.max_concurrency = saved_conc
	_settings.max_tokens = 300


func _reset_llm_results() -> void:
	_received.clear()
	_failed.clear()


func _test_llm_mock() -> void:
	_reset_llm_results()
	_settings.provider = "mock"
	_settings.max_concurrency = 4
	_llm.request_decision(100, "prompt", {"temp": 50}, TOOLS)
	_llm.request_decision(101, "prompt", {}, [])
	await _wait_until(func() -> bool: return _received.has(100) and _received.has(101), 3.0)
	_check(_received.has(100), "llm mock: decision_received for requester 100")
	var calls: Array = _received.get(100, [])
	_check(calls.size() == 1 and calls[0]["name"] == "set_speed", "llm mock: normalized {name, args} call")
	if calls.size() == 1:
		var args: Dictionary = calls[0]["args"]
		var value: float = args.get("value", -1.0)
		_check(value >= 0.0 and value <= 1.0, "llm mock: number arg within schema range")
		_check(args.get("on") is bool, "llm mock: boolean arg generated")
	_check(_received.get(101, null) == [], "llm mock: empty tool list gives no calls")
	_check(_failed.is_empty(), "llm mock: no failures")


func _test_llm_superseded() -> void:
	_reset_llm_results()
	_settings.max_concurrency = 1
	_llm.request_decision(200, "p", {}, TOOLS)
	_llm.request_decision(201, "p", {}, TOOLS)
	_llm.request_decision(201, "p", {}, TOOLS)
	_check(_failed.get(201, "") == "superseded", "llm queue: older queued request from same requester superseded")
	await _wait_until(func() -> bool: return _received.has(200) and _received.has(201), 6.0)
	_check(_received.has(200) and _received.has(201), "llm queue: surviving requests still complete")
	_settings.max_concurrency = 4


func _test_llm_concurrency_cap() -> void:
	_reset_llm_results()
	_settings.max_concurrency = 1
	for id: int in [300, 301, 302]:
		_llm.request_decision(id, "p", {}, TOOLS)
	_check(_llm._in_flight == 1, "llm cap: only 1 in flight with max_concurrency 1")
	_check(_llm._queue.size() == 2, "llm cap: the other 2 are queued")
	await _wait_until(func() -> bool: return _received.size() == 3, 8.0)
	_check(_received.size() == 3, "llm cap: all 3 eventually complete")
	_check(_llm._in_flight == 0 and _llm._queue.is_empty(), "llm cap: nothing left in flight or queued")
	_settings.max_concurrency = 4


func _test_llm_unknown_provider() -> void:
	_reset_llm_results()
	_settings.provider = "bogus"
	_llm.request_decision(400, "p", {}, TOOLS)
	await _wait_until(func() -> bool: return _failed.has(400), 2.0)
	_check(_failed.has(400), "llm provider: unknown provider emits decision_failed")
	_check(not _received.has(400), "llm provider: no decision_received on failure")
	_check(_llm._in_flight == 0, "llm provider: failure releases the in-flight slot")
	_settings.provider = "mock"
