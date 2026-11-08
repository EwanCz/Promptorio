extends "res://tests/test_case.gd"
## The Sound section of the Settings dialog: live apply, Save persists, Close reverts.
## Backs up and restores the real user://settings.cfg and the Master bus.

var _settings: Node
var _dialog: SettingsDialog
var _had_file: bool = false
var _original_file: PackedByteArray = PackedByteArray()
var _saved: Array = []
var _bus_db: float = 0.0
var _bus_mute: bool = false
var _sfx_bus_db: float = 0.0


func before_each() -> void:
	_settings = autoload("Settings")
	_had_file = FileAccess.file_exists(_settings.PATH)
	if _had_file:
		_original_file = FileAccess.get_file_as_bytes(_settings.PATH)
	_saved = [_settings.master_volume, _settings.sfx_volume, _settings.muted, _settings.provider]
	var master: int = AudioServer.get_bus_index("Master")
	_bus_db = AudioServer.get_bus_volume_db(master)
	_bus_mute = AudioServer.is_bus_mute(master)
	_sfx_bus_db = AudioServer.get_bus_volume_db(AudioServer.get_bus_index("SFX"))
	_settings.master_volume = 0.8
	_settings.sfx_volume = 1.0
	_settings.muted = false
	_settings.provider = "mock"
	_dialog = load("res://scenes/ui/popups/settings_dialog.tscn").instantiate()
	tree.root.add_child(_dialog)
	_dialog.open()


func after_each() -> void:
	_dialog.free()
	if _had_file:
		var file: FileAccess = FileAccess.open(_settings.PATH, FileAccess.WRITE)
		file.store_buffer(_original_file)
		file.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_settings.PATH))
	_settings.master_volume = _saved[0]
	_settings.sfx_volume = _saved[1]
	_settings.muted = _saved[2]
	_settings.provider = _saved[3]
	var master: int = AudioServer.get_bus_index("Master")
	AudioServer.set_bus_volume_db(master, _bus_db)
	AudioServer.set_bus_mute(master, _bus_mute)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("SFX"), _sfx_bus_db)


func _master_slider() -> HSlider:
	return _dialog.get_node("%MasterSlider")


func _sfx_slider() -> HSlider:
	return _dialog.get_node("%SfxSlider")


func _mute_check() -> CheckButton:
	return _dialog.get_node("%MuteCheck")


func test_controls_show_the_current_values() -> void:
	_settings.master_volume = 0.3
	_settings.sfx_volume = 0.6
	_settings.muted = true
	_dialog.open()
	check_eq([_master_slider().value, _sfx_slider().value, _mute_check().button_pressed], [0.3, 0.6, true], "sliders and mute show the settings")
	check_eq([_master_slider().min_value, _master_slider().max_value], [0.0, 1.0], "volume range is 0..1")


func test_dragging_applies_live_without_saving() -> void:
	var master: int = AudioServer.get_bus_index("Master")
	_master_slider().value = 0.4
	check_eq(_settings.master_volume, 0.4, "master volume changes while dragging")
	check(absf(AudioServer.get_bus_volume_db(master) - linear_to_db(0.4)) < 0.01, "the bus follows live")
	_sfx_slider().value = 0.2
	check_eq(_settings.sfx_volume, 0.2, "sfx volume changes while dragging")
	var effects: int = AudioServer.get_bus_index("SFX")
	check(effects >= 0 and absf(AudioServer.get_bus_volume_db(effects) - linear_to_db(0.2)) < 0.01, "effects bus follows live")
	_mute_check().button_pressed = true
	check(_settings.muted and AudioServer.is_bus_mute(master), "mute applies live")
	var cfg: ConfigFile = ConfigFile.new()
	var on_disk: float = 0.8
	if cfg.load(_settings.PATH) == OK:
		on_disk = cfg.get_value(_settings.AUDIO_SECTION, "master_volume", 0.8)
	check(on_disk != 0.4, "nothing is written before Save")


func test_save_persists_and_keeps_other_settings() -> void:
	_settings.provider = "openai"
	_dialog.open()
	_master_slider().value = 0.0
	_mute_check().button_pressed = true
	(_dialog.get_node("%SaveButton") as Button).pressed.emit()
	check(not _dialog.visible, "dialog closes after save")
	_settings.master_volume = 0.8
	_settings.muted = false
	_settings.load_settings()
	check_eq([_settings.master_volume, _settings.muted], [0.0, true], "audio persisted")
	check_eq(_settings.provider, "openai", "provider saved with it")


func test_close_reverts_unsaved_audio_edits() -> void:
	var master: int = AudioServer.get_bus_index("Master")
	_settings.apply_audio()
	_master_slider().value = 0.1
	_sfx_slider().value = 0.1
	_mute_check().button_pressed = true
	(_dialog.get_node("%CloseButton") as Button).pressed.emit()
	check(not _dialog.visible, "dialog closes")
	check_eq([_settings.master_volume, _settings.sfx_volume, _settings.muted], [0.8, 1.0, false], "settings back to the opened values")
	check(not AudioServer.is_bus_mute(master) and absf(AudioServer.get_bus_volume_db(master) - linear_to_db(0.8)) < 0.01, "the bus is restored")
	_dialog.open()
	check_eq([_master_slider().value, _mute_check().button_pressed], [0.8, false], "reopening shows the restored values")
