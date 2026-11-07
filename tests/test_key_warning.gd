extends "res://tests/test_case.gd"
## The Bar's warning that the selected provider has no API key.

var _settings: Node
var _main: Node
var _warning: Control
var _saved: Dictionary = {}


func before_each() -> void:
	_settings = autoload("Settings")
	_saved = {
		"provider": _settings.provider,
		"api_key": _settings.api_key,
		"codex_api_key": _settings.codex_api_key,
		"env_path": _settings.env_path,
	}
	_settings.env_path = "user://missing.env"
	_settings.load_env()
	_settings.provider = "anthropic"
	_settings.api_key = ""
	_settings.codex_api_key = ""
	_main = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(_main)
	_warning = _main.get_node("%KeyWarning")


func after_each() -> void:
	_main.free()
	_settings.provider = _saved["provider"]
	_settings.api_key = _saved["api_key"]
	_settings.codex_api_key = _saved["codex_api_key"]
	_settings.env_path = _saved["env_path"]
	_settings.load_env()


func _changed() -> void:
	autoload("EventBus").settings_changed.emit()


func test_shown_when_a_real_provider_has_no_key() -> void:
	check(_settings.needs_api_key(), "anthropic without a key needs one")
	check(_warning.visible, "warning is visible at startup")
	check((_warning.get_child(0) as Label).text.contains("No active API key"), "says so")


func test_mock_provider_needs_no_key() -> void:
	_settings.provider = "mock"
	_changed()
	check(not _settings.needs_api_key(), "mock needs no key")
	check(not _warning.visible, "no warning for the mock provider")


func test_follows_the_key_and_the_provider() -> void:
	_settings.api_key = "sk-test"
	_changed()
	check(not _warning.visible, "hidden once a key is set")
	_settings.api_key = ""
	_changed()
	check(_warning.visible, "back when the key is removed")
	_settings.provider = "codex"
	_settings.codex_api_key = "sk-codex"
	_changed()
	check(not _warning.visible, "the key of the selected provider counts")
	_settings.provider = "anthropic"
	_changed()
	check(_warning.visible, "another provider's key does not")


func test_a_dev_env_key_counts_as_active() -> void:
	var path: String = "user://test_key_warning.env"
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_line("ANTHROPIC_API_KEY=sk-env")
	file.close()
	_settings.env_path = path
	_settings.load_env()
	_changed()
	check(not _warning.visible, "a .env key hides the warning")
	DirAccess.remove_absolute(path)
