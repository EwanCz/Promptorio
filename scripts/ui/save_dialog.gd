class_name SaveDialog
extends PanelContainer
## Popup to save and load the game. Slots live in `SaveGame.save_dir`; Export and Import move a save to or
## from any file on the disk. Pauses the game while open (not in menu mode, see use_as_menu()). Messages never show a path or the file content.

## Menu mode only: the player picked a valid save; the game has not started yet.
signal save_picked(data: Dictionary)

var _placement: Placement = null
## True in the main menu: no game to save or restore, loading hands the save over with save_picked.
var _menu_mode: bool = false
var _file_dialog: FileDialog = null
var _exporting: bool = false

@onready var _name_label: Label = %NameLabel
@onready var _name_row: HBoxContainer = %NameRow
@onready var _name_edit: LineEdit = %NameEdit
@onready var _save_button: Button = %SaveButton
@onready var _slot_list: VBoxContainer = %SlotList
@onready var _empty_label: Label = %EmptyLabel
@onready var _import_button: Button = %ImportButton
@onready var _export_button: Button = %ExportButton
@onready var _status_label: Label = %StatusLabel
@onready var _close_button: Button = %CloseButton


func _ready() -> void:
	visible = false
	_save_button.pressed.connect(_on_save_pressed)
	_import_button.pressed.connect(_on_import_pressed)
	_export_button.pressed.connect(_on_export_pressed)
	_close_button.pressed.connect(close)
	_file_dialog = FileDialog.new()
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.use_native_dialog = true
	_file_dialog.filters = PackedStringArray(["*.json ; Promptorio save"])
	_file_dialog.file_selected.connect(_on_file_selected)
	add_child(_file_dialog)


## Connects the dialog to the placement flow it saves and restores.
func setup(placement: Placement) -> void:
	_placement = placement


## The main menu's version: only loading (slots and Import), no pause. Picking a save emits save_picked.
func use_as_menu() -> void:
	_menu_mode = true
	_name_label.visible = false
	_name_row.visible = false
	_export_button.visible = false


func open() -> void:
	_status_label.text = ""
	_refresh()
	visible = true
	if not _menu_mode:
		get_tree().paused = true


func close() -> void:
	visible = false
	if not _menu_mode:
		get_tree().paused = false


## Writes the game to a slot. True on success.
func save_slot(slot_name: String) -> bool:
	var path: String = SaveGame.slot_path(slot_name)
	if path == "":
		_say("Pick a name without special characters (40 letters at most).")
		return false
	if not _write(path):
		return false
	_say("Saved \"%s\"." % slot_name.strip_edges())
	_refresh()
	return true


## Replaces the game with a slot. True on success; the dialog closes then.
func load_slot(slot_name: String) -> bool:
	return _load(SaveGame.slot_path(slot_name), "Loaded \"%s\"." % slot_name.strip_edges())


func delete_slot(slot_name: String) -> void:
	if SaveGame.delete_slot(slot_name):
		_say("Deleted \"%s\"." % slot_name)
	_refresh()


## Writes the game to any file (the Export button).
func export_to(path: String) -> bool:
	if not _write(path):
		return false
	_say("Exported the save.")
	return true


## Replaces the game with any save file (the Import button); the dialog closes then.
func import_from(path: String) -> bool:
	return _load(path, "Imported the save.")


func _write(path: String) -> bool:
	if _placement == null:
		return false
	var error: Error = SaveGame.write(path, SaveGame.snapshot(_placement))
	if error != OK:
		_say("The save could not be written (%s)." % error_string(error))
		return false
	return true


func _load(path: String, success_message: String) -> bool:
	if (_placement == null and not _menu_mode) or path == "":
		_say("There is no such save.")
		return false
	var result: Dictionary = SaveGame.read(path)
	var error: String = str(result["error"])
	if error == "":
		error = SaveGame.validate(null, result["data"]) if _menu_mode else SaveGame.restore(_placement, result["data"])
	if error != "":
		_say(error)
		return false
	_say(success_message)
	close()
	if _menu_mode:
		save_picked.emit(result["data"])
	return true


func _say(message: String) -> void:
	_status_label.text = message


func _refresh() -> void:
	for child: Node in _slot_list.get_children():
		_slot_list.remove_child(child)
		child.queue_free()
	var slots: Array[Dictionary] = SaveGame.list_slots()
	_empty_label.visible = slots.is_empty()
	for slot: Dictionary in slots:
		_slot_list.add_child(_make_row(slot))


func _make_row(slot: Dictionary) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	var label: Label = Label.new()
	label.text = "%s  (%s)" % [slot["name"], _format_time(int(slot["modified"]))]
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.clip_text = true
	row.add_child(label)
	var load_button: Button = Button.new()
	load_button.text = "Load"
	load_button.pressed.connect(load_slot.bind(slot["name"]))
	row.add_child(load_button)
	var delete_button: Button = Button.new()
	delete_button.text = "Delete"
	delete_button.pressed.connect(delete_slot.bind(slot["name"]))
	row.add_child(delete_button)
	return row


## Local time, to the minute.
func _format_time(unix_time: int) -> String:
	var local: int = unix_time + int(Time.get_time_zone_from_system()["bias"]) * 60
	return Time.get_datetime_string_from_unix_time(local, true).left(16)


func _on_save_pressed() -> void:
	save_slot(_name_edit.text)


func _on_import_pressed() -> void:
	_exporting = false
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.title = "Import a save"
	_file_dialog.popup_centered_ratio(0.7)


func _on_export_pressed() -> void:
	_exporting = true
	_file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_file_dialog.title = "Export the save"
	_file_dialog.current_file = "promptorio_save.json"
	_file_dialog.popup_centered_ratio(0.7)


func _on_file_selected(path: String) -> void:
	if _exporting:
		export_to(path)
	else:
		import_from(path)
