extends "res://tests/test_case.gd"
## The Bar's API key status: missing, being checked, verified, rejected or unverified.

var _settings: Node
var _main: Node
var _panel: Control
var _label: Label
var _saved: Dictionary = {}


func before_each() -> void:
	_settings = autoload("Settings")
	_saved = {
		"provider": _settings.provider,
		"api_key": _settings.api_key,
		"openai_api_key": _settings.openai_api_key,
		"env_path": _settings.env_path,
	}
	_settings.env_path = "user://missing.env"
	_settings.load_env()
	_settings.provider = "anthropic"
	_settings.api_key = ""
	_settings.openai_api_key = ""
	_main = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(_main)
	_panel = _main.get_node("%KeyStatus")
	_label = _main.get_node("%KeyStatusLabel")


func after_each() -> void:
	_main.free()
	_settings.provider = _saved["provider"]
	_settings.api_key = _saved["api_key"]
	_settings.openai_api_key = _saved["openai_api_key"]
	_settings.env_path = _saved["env_path"]
	_settings.load_env()


func _changed() -> void:
	autoload("EventBus").settings_changed.emit()


func _checked(state: String, detail: String = "") -> void:
	autoload("EventBus").key_checked.emit(state, detail)


func test_missing_key_is_reported() -> void:
	check(_settings.needs_api_key(), "anthropic without a key needs one")
	check(_panel.visible, "panel is visible at startup")
	check(_label.text.contains("No active API key"), "says so")


func test_mock_provider_needs_no_key() -> void:
	_settings.provider = "mock"
	_changed()
	check(not _settings.needs_api_key(), "mock needs no key")
	check(not _panel.visible, "no panel for the mock provider")


func test_a_key_is_being_checked_until_the_verdict() -> void:
	_settings.api_key = "sk-test"
	_changed()
	check(_panel.visible and _label.text.contains("Checking"), "not claimed good before it is checked")


func test_verdicts_are_shown() -> void:
	_settings.api_key = "sk-test"
	_changed()
	_checked("valid")
	check(_label.text.contains("verified"), "valid key")
	_checked("invalid", "HTTP 401 (authentication_error)")
	check(_label.text.contains("rejected") and _label.text.contains("HTTP 401"), "rejected key with its cause")
	_checked("error", "network error (result 2)")
	check(_label.text.contains("Could not verify") and not _label.text.contains("rejected"), "unverified is not rejected")


func test_changing_settings_discards_the_old_verdict() -> void:
	_settings.api_key = "sk-test"
	_changed()
	_checked("valid")
	_settings.api_key = "sk-other"
	_changed()
	check(_label.text.contains("Checking"), "the new key is not covered by the old verdict")


func test_removing_the_key_overrides_a_verdict() -> void:
	_settings.api_key = "sk-test"
	_changed()
	_checked("valid")
	_settings.api_key = ""
	_changed()
	check(_label.text.contains("No active API key"), "missing again")


func test_follows_the_selected_provider() -> void:
	_settings.provider = "openai"
	_settings.openai_api_key = "sk-openai"
	_changed()
	check(_label.text.contains("Checking"), "the key of the selected provider counts")
	_settings.provider = "anthropic"
	_changed()
	check(_label.text.contains("No active API key"), "another provider's key does not")


func test_a_dev_env_key_counts_as_present() -> void:
	var path: String = "user://test_key_status.env"
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_line("ANTHROPIC_API_KEY=sk-env")
	file.close()
	_settings.env_path = path
	_settings.load_env()
	_changed()
	check(_label.text.contains("Checking"), "a .env key is checked like any other")
	DirAccess.remove_absolute(path)
