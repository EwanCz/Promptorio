extends "res://tests/test_case.gd"

var _registry: Node
var _root: Node
var _ids: Array[int] = []
var _nodes: Array[Node] = []


func before_each() -> void:
	_registry = autoload("ChipRegistry")
	_root = tree.root
	_ids.clear()
	_nodes.clear()


func after_each() -> void:
	tree.paused = false
	for node: Node in _nodes:
		node.free()
	for id: int in _ids:
		_registry.remove(id)


func _spawn(path: String) -> Node:
	var node: Node = load(path).instantiate()
	_root.add_child(node)
	_nodes.append(node)
	return node


func _add(chip_name: String, prompt: String = "p") -> ChipRessource:
	var chip: ChipRessource = _registry.add(chip_name, prompt, "")
	_ids.append(chip.id)
	return chip


func test_registry_page_lists_chips_and_requests_blank() -> void:
	var page: ChipRegistryPage = _spawn("res://scenes/ui/pages/chip_registry_page.tscn")
	var list: Node = page.get_node("%List")
	var before: int = list.get_child_count()
	var chip: ChipRessource = _add("ui_listed")
	check_eq(list.get_child_count(), before + 1, "list grows when a chip is registered")
	var requested: Array = []
	var on_requested: Callable = func(c: ChipRessource) -> void: requested.append(c)
	page.chip_requested.connect(on_requested)
	(page.get_node("%NewButton") as Button).pressed.emit()
	list.get_child(list.get_child_count() - 1).emit_signal("pressed")
	check_eq(requested, [null, chip], "new button asks for null, a list button for its chip")
	_registry.remove(chip.id)
	check_eq(list.get_child_count(), before, "list shrinks when a chip is removed")
	page.chip_requested.disconnect(on_requested)


func test_chip_page_pauses_and_saves_new_chip() -> void:
	var popup: ChipPage = _spawn("res://scenes/ui/popups/chip_page.tscn")
	popup.open(null)
	check(tree.paused, "opening pauses the game")
	check_eq((popup.get_node("%NameEdit") as LineEdit).text, "Blank", "blank chip is named Blank")
	check((popup.get_node("%RemoveButton") as Button).disabled, "a draft cannot be removed")
	(popup.get_node("%NameEdit") as LineEdit).text = "ui_new"
	(popup.get_node("%PromptEdit") as TextEdit).text = "do things"
	(popup.get_node("%SaveButton") as Button).pressed.emit()
	var created: ChipRessource = null
	for chip: ChipRessource in _registry.get_all():
		if chip.name == "ui_new":
			created = chip
	check(created != null, "chip saved in the registry")
	if created != null:
		_ids.append(created.id)
		check_eq(created.prompt, "do things", "prompt saved")
	check(not tree.paused and not popup.visible, "saving closes and resumes")


func test_chip_page_edit_remove_and_errors() -> void:
	var chip: ChipRessource = _add("ui_edit")
	_add("ui_taken")
	var popup: ChipPage = _spawn("res://scenes/ui/popups/chip_page.tscn")
	popup.open(chip)
	(popup.get_node("%NameEdit") as LineEdit).text = "ui_taken"
	(popup.get_node("%SaveButton") as Button).pressed.emit()
	check(popup.visible and (popup.get_node("%ErrorLabel") as Label).text != "", "duplicate name shows an error")
	check_eq(chip.name, "ui_edit", "chip unchanged after the error")
	(popup.get_node("%NameEdit") as LineEdit).text = "ui_renamed"
	(popup.get_node("%SaveButton") as Button).pressed.emit()
	check_eq(chip.name, "ui_renamed", "existing chip updated")
	popup.open(chip)
	(popup.get_node("%RemoveButton") as Button).pressed.emit()
	check(_registry.get_from_id(chip.id) == null, "remove deletes the chip")
	check(not tree.paused, "remove resumes the game")


func test_tooltip_toggle_and_chips() -> void:
	var tooltip: MachineTooltip = _spawn("res://scenes/ui/popups/machine_tooltip.tscn")
	var machine: Machine = _spawn("res://scenes/machines/machine.tscn")
	var bus: Node = autoload("EventBus")
	var chip: ChipRessource = _add("ui_tip", "prompt text")
	bus.machine_selected.emit(machine)
	check(tooltip.is_open(), "selecting a machine opens the tooltip")
	check_eq((tooltip.get_node("%TypeLabel") as Label).text, "Type: machine", "type shown")
	check_eq((tooltip.get_node("%StatusLabel") as Label).text, "State: normal", "state shown")
	(tooltip.get_node("%AddButton") as Button).pressed.emit()
	check_eq(machine.chips.size(), 1, "add chip attaches the picked chip")
	check_eq(tooltip.get_node("%ChipsList").get_child_count(), 1, "attached chip listed")
	var row: Node = tooltip.get_node("%ChipsList").get_child(0)
	var main_row: Node = row.get_child(1)
	(main_row.get_child(0) as SpinBox).value = 7
	check_eq(machine.chips[0].timeout, 7, "timeout edited from the tooltip")
	(main_row.get_child(1) as Button).pressed.emit()
	check_eq(machine.chips.size(), 0, "remove button detaches the chip")
	var logged: Array = []
	var on_log: Callable = func(m: Machine) -> void: logged.append(m)
	tooltip.log_requested.connect(on_log)
	(tooltip.get_node("%LogButton") as Button).pressed.emit()
	check_eq(logged, [machine], "log button requests the machine log")
	tooltip.log_requested.disconnect(on_log)
	bus.machine_selected.emit(machine)
	check(not tooltip.is_open(), "selecting the same machine closes the tooltip")
	bus.machine_selected.emit(machine)
	bus.machine_selected.emit(null)
	check(not tooltip.is_open(), "an empty cell closes the tooltip")
	check(chip != null, "chip fixture exists")


func test_chip_log_capture_and_cap() -> void:
	var log: ChipLog = _spawn("res://scenes/ui/popups/chip_log.tscn")
	var machine: Machine = _spawn("res://scenes/machines/machine.tscn")
	var other: Machine = _spawn("res://scenes/machines/machine.tscn")
	machine.log_chip("first")
	other.log_chip("elsewhere")
	check_eq(log.get_lines(machine), ["first"] as Array[String], "lines kept per machine")
	for i: int in ChipLog.MAX_LINES + 5:
		machine.log_chip("line %d" % i)
	check_eq(log.get_lines(machine).size(), ChipLog.MAX_LINES, "log capped")
	log.show_machine(machine)
	check(log.visible, "show_machine opens the log")


func test_settings_dialog_saves_per_provider() -> void:
	var settings: Node = autoload("Settings")
	var backup: Array = [settings.api_key, settings.provider, settings.model, settings.openai_api_key, settings.openai_model]
	var had_file: bool = FileAccess.file_exists(settings.PATH)
	var file_backup: String = FileAccess.get_file_as_string(settings.PATH) if had_file else ""
	var dialog: SettingsDialog = _spawn("res://scenes/ui/popups/settings_dialog.tscn")
	var providers: OptionButton = dialog.get_node("%ProviderPicker")
	var models: OptionButton = dialog.get_node("%ModelPicker")
	dialog.open()
	providers.select(SettingsDialog.PROVIDERS.find("openai"))
	providers.item_selected.emit(providers.selected)
	check_eq(models.item_count, Settings.MODELS["openai"].size(), "openai models listed")
	check_eq(models.get_item_text(models.selected), settings.openai_model, "saved openai model preselected")
	(dialog.get_node("%KeyEdit") as LineEdit).text = " k-test "
	models.select(3)
	(dialog.get_node("%SaveButton") as Button).pressed.emit()
	check_eq([settings.openai_api_key, settings.provider, settings.openai_model], ["k-test", "openai", Settings.MODELS["openai"][3]], "openai settings written")
	check_eq([settings.api_key, settings.model], [backup[0], backup[2]], "anthropic settings untouched")
	check(not dialog.visible, "dialog closes after save")
	dialog.open()
	providers.select(0)
	providers.item_selected.emit(0)
	check(not (dialog.get_node("%Credentials") as Control).visible, "mock shows no key or model")
	settings.api_key = backup[0]
	settings.provider = backup[1]
	settings.model = backup[2]
	settings.openai_api_key = backup[3]
	settings.openai_model = backup[4]
	if had_file:
		var file: FileAccess = FileAccess.open(settings.PATH, FileAccess.WRITE)
		file.store_string(file_backup)
	else:
		DirAccess.remove_absolute(settings.PATH)


func test_settings_dialog_edits_each_providers_base_url() -> void:
	var settings: Node = autoload("Settings")
	var backup: Array = [settings.anthropic_base_url, settings.openai_base_url, settings.provider]
	var had_file: bool = FileAccess.file_exists(settings.PATH)
	var file_backup: String = FileAccess.get_file_as_string(settings.PATH) if had_file else ""
	var dialog: SettingsDialog = _spawn("res://scenes/ui/popups/settings_dialog.tscn")
	var providers: OptionButton = dialog.get_node("%ProviderPicker")
	var box: Control = dialog.get_node("%BaseUrl")
	var edit: LineEdit = dialog.get_node("%BaseUrlEdit")
	settings.anthropic_base_url = ""
	settings.openai_base_url = ""
	dialog.open()
	providers.select(0)
	providers.item_selected.emit(0)
	check(not box.visible, "no base URL field for mock")
	for provider: String in ["anthropic", "openai"]:
		providers.select(SettingsDialog.PROVIDERS.find(provider))
		providers.item_selected.emit(providers.selected)
		check(box.visible and edit.text == "", "%s: blank by default" % provider)
		edit.text = "  https://%s.example.com/  " % provider
		(dialog.get_node("%SaveButton") as Button).pressed.emit()
		dialog.open()
	check_eq(settings.anthropic_base_url, "https://anthropic.example.com/", "anthropic saved trimmed")
	check_eq(settings.openai_base_url, "https://openai.example.com/", "openai saved separately")
	check_eq(settings.get_base_url("openai"), "https://openai.example.com", "resolved without the trailing slash")
	check_eq(edit.text, "https://openai.example.com/", "reopened with the saved value")
	settings.anthropic_base_url = backup[0]
	settings.openai_base_url = backup[1]
	settings.provider = backup[2]
	if had_file:
		var file: FileAccess = FileAccess.open(settings.PATH, FileAccess.WRITE)
		file.store_string(file_backup)
	else:
		DirAccess.remove_absolute(settings.PATH)


func test_settings_dialog_uses_the_env_key_without_saving_it() -> void:
	var settings: Node = autoload("Settings")
	var backup: Array = [settings.api_key, settings.provider, settings.model, settings.env_path]
	var had_file: bool = FileAccess.file_exists(settings.PATH)
	var file_backup: String = FileAccess.get_file_as_string(settings.PATH) if had_file else ""
	var env_file: FileAccess = FileAccess.open("user://test_dialog.env", FileAccess.WRITE)
	env_file.store_line("ANTHROPIC_API_KEY=env-only")
	env_file.close()
	settings.env_path = "user://test_dialog.env"
	settings.load_env()
	settings.api_key = ""
	var dialog: SettingsDialog = _spawn("res://scenes/ui/popups/settings_dialog.tscn")
	var providers: OptionButton = dialog.get_node("%ProviderPicker")
	var key_edit: LineEdit = dialog.get_node("%KeyEdit")
	dialog.open()
	providers.select(SettingsDialog.PROVIDERS.find("anthropic"))
	providers.item_selected.emit(providers.selected)
	check_eq(key_edit.text, "", "the .env key is not shown in the field")
	check(key_edit.placeholder_text.contains(".env"), "the field says the .env key is in use")
	(dialog.get_node("%SaveButton") as Button).pressed.emit()
	check_eq(settings.api_key, "", "saving does not copy the .env key")
	check_eq(settings.get_api_key("anthropic"), "env-only", "the .env key is still used")
	DirAccess.remove_absolute("user://test_dialog.env")
	settings.api_key = backup[0]
	settings.provider = backup[1]
	settings.model = backup[2]
	settings.env_path = backup[3]
	settings.load_env()
	if had_file:
		var file: FileAccess = FileAccess.open(settings.PATH, FileAccess.WRITE)
		file.store_string(file_backup)
	else:
		DirAccess.remove_absolute(settings.PATH)


func test_tooltip_ask_now_and_threshold() -> void:
	var tooltip: MachineTooltip = _spawn("res://scenes/ui/popups/machine_tooltip.tscn")
	var machine: Machine = _spawn("res://scenes/machines/smelter.tscn")
	var chip: ChipRessource = _add("ui_ask", "prompt text")
	machine.attach_chip(chip.id)
	var settings: Node = autoload("Settings")
	var saved: Array = [settings.provider, settings.chip_cooldown]
	settings.provider = "mock"
	settings.chip_cooldown = 0.0
	autoload("EventBus").machine_selected.emit(machine)
	var box: Node = tooltip.get_node("%ChipsList").get_child(0)
	(box.get_child(1).get_child(2) as Button).pressed.emit()
	check(machine.chips[0].pending, "Ask now sends a request")
	var watch: Node = box.get_child(2)
	var keys: OptionButton = watch.get_child(1) as OptionButton
	var index: int = -1
	for i: int in keys.item_count:
		if keys.get_item_text(i) == "temperature":
			index = i
	check(index > 0, "numeric state values are offered")
	keys.select(index)
	keys.item_selected.emit(index)
	(watch.get_child(2) as SpinBox).value = 90
	check_eq(machine.chips[0].threshold_key, "temperature", "watched value set from the tooltip")
	check_eq(machine.chips[0].threshold, 90.0, "limit set from the tooltip")
	keys.select(0)
	keys.item_selected.emit(0)
	check_eq(machine.chips[0].threshold_key, "", "never turns the trigger off")
	await wait_until(func() -> bool: return not machine.chips[0].pending)
	settings.provider = saved[0]
	settings.chip_cooldown = saved[1]


func test_registry_page_shows_a_save_error() -> void:
	var page: ChipRegistryPage = _spawn("res://scenes/ui/pages/chip_registry_page.tscn")
	var label: Label = page.get_node("%ErrorLabel")
	check(not label.visible, "no error: label hidden")
	var saved_path: String = _registry.user_path
	_registry.user_path = "user://no_such_dir/chips.tres"
	var chip: ChipRessource = _add("ui_save_fail", "p")
	check(label.visible and label.text != "", "failed save is visible on the page")
	_registry.user_path = saved_path
	_registry.update(chip.id, "ui_save_fail", "", "p")
	check(not label.visible, "label hides after a good save")
