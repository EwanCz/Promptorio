extends "res://tests/test_case.gd"
## Backs up and restores the real user://settings.cfg so running tests never touches the player's key.

var _settings: Node
var _had_file: bool = false
var _original_file: PackedByteArray = PackedByteArray()
var _saved_values: Dictionary = {}


func before_each() -> void:
	_settings = autoload("Settings")
	_had_file = FileAccess.file_exists(_settings.PATH)
	if _had_file:
		_original_file = FileAccess.get_file_as_bytes(_settings.PATH)
	_saved_values = {
		"api_key": _settings.api_key,
		"provider": _settings.provider,
		"model": _settings.model,
		"max_concurrency": _settings.max_concurrency,
		"request_timeout": _settings.request_timeout,
		"chip_cooldown": _settings.chip_cooldown,
		"max_tokens": _settings.max_tokens,
	}


func after_each() -> void:
	if _had_file:
		var file: FileAccess = FileAccess.open(_settings.PATH, FileAccess.WRITE)
		file.store_buffer(_original_file)
		file.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_settings.PATH))
	for key: String in _saved_values:
		_settings.set(key, _saved_values[key])


func test_save_and_load_round_trip() -> void:
	_settings.api_key = "test-key"
	_settings.provider = "test-provider"
	_settings.max_concurrency = 3
	_settings.save_settings()
	_settings.api_key = ""
	_settings.provider = "mock"
	_settings.max_concurrency = 1
	_settings.load_settings()
	check_eq(_settings.api_key, "test-key", "api_key round-trips")
	check_eq(_settings.provider, "test-provider", "provider round-trips")
	check_eq(_settings.max_concurrency, 3, "max_concurrency round-trips")


func test_load_clamps_out_of_range_values() -> void:
	_settings.save_settings()
	var cfg: ConfigFile = ConfigFile.new()
	cfg.load(_settings.PATH)
	cfg.set_value(_settings.SECTION, "max_concurrency", 9999)
	cfg.set_value(_settings.SECTION, "max_tokens", 99999)
	cfg.save(_settings.PATH)
	_settings.load_settings()
	check_eq(_settings.max_concurrency, 16, "max_concurrency clamped to 16")
	check_eq(_settings.max_tokens, 300, "max_tokens clamped to 300")


func test_settings_changed_signal() -> void:
	var count: Array[int] = [0]
	var on_changed: Callable = func() -> void: count[0] += 1
	autoload("EventBus").settings_changed.connect(on_changed)
	_settings.save_settings()
	autoload("EventBus").settings_changed.disconnect(on_changed)
	check_eq(count[0], 1, "save_settings emits settings_changed once")
