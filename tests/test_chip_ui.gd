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
	check_eq((tooltip.get_node("%IdLabel") as Label).text, "Machine #%d" % machine.machine_id, "type and id in one title")
	var state: TextureRect = tooltip.get_node("%StatusIcon") as TextureRect
	check_eq(state.texture.get_image().get_data(), Icons.icon("state_normal").get_image().get_data(), "state shown as an icon")
	check(state.tooltip_text.contains("normally"), "hover explains it")
	(tooltip.get_node("%AddButton") as Button).pressed.emit()
	check_eq(machine.chips.size(), 1, "add chip attaches the picked chip")
	check_eq(tooltip.get_node("%ChipsList").get_child_count(), 1, "attached chip listed")
	var row: Node = tooltip.get_node("%ChipsList").get_child(0)
	(row.find_child("Timeout", true, false) as SpinBox).value = 7
	check_eq(machine.chips[0].timeout, 7, "timeout edited from the tooltip")
	(row.find_child("Remove", true, false) as Button).pressed.emit()
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


func _shown(log: ChipLog, machine: Machine, message: String) -> String:
	machine.log_chip(message)
	var lines: Array[String] = log.get_lines(machine)
	return lines[lines.size() - 1]


func test_chip_log_shows_short_plain_language_entries() -> void:
	var log: ChipLog = _spawn("res://scenes/ui/popups/chip_log.tscn")
	var machine: Machine = _spawn("res://scenes/machines/machine.tscn")
	log.show_machine(machine)
	check_eq(_shown(log, machine, "asking chip Smelter Cooler (event:error)"), "Checking: Smelter Cooler", "request, without the trigger name")
	check_eq(_shown(log, machine, "asking chip Cooler (v2) (threshold:temperature)"), "Checking: Cooler (v2)", "a chip name with parentheses survives")
	check_eq(_shown(log, machine, "no tool calls"), "No action", "no-action answer")
	check_eq(_shown(log, machine, "set_cooling({\"on\":true})"), "Cooling set on", "cooling")
	check_eq(_shown(log, machine, "set_enabled({\"on\":false})"), "Machine set to paused", "pause")
	check_eq(_shown(log, machine, "set_mine_ticks({\"ticks\":40})"), "Mining pace set to 40 ticks per ore", "mining pace")
	check_eq(_shown(log, machine, "set_emergency_stop({\"on\":false})"), "Emergency stop release requested", "a release that may be a no-op is not claimed as done")
	check_eq(_shown(log, machine, "ignored set_cooling: bad value for 'on'"), "Action rejected", "rejected action")
	check_eq(_shown(log, machine, "ignored unknown tool 'launch_missiles'"), "Action rejected", "unknown tool")
	check_eq(_shown(log, machine, "chip request failed: HTTP 401 (authentication_error)"), "Request failed", "failure")
	check_eq(_shown(log, machine, "exploded at 150°"), "exploded at 150°", "other messages are untouched")


func test_chip_log_is_an_icon_timeline_with_hover_text() -> void:
	var log: ChipLog = _spawn("res://scenes/ui/popups/chip_log.tscn")
	var machine: Machine = _spawn("res://scenes/machines/machine.tscn")
	var other: Machine = _spawn("res://scenes/machines/machine.tscn")
	log.show_machine(machine)
	machine.log_chip("asking chip Smelter Cooler (event:error)")
	machine.log_chip("set_cooling({\"on\":true})")
	machine.log_chip("no tool calls")
	machine.log_chip("ignored set_cooling: bad value for 'on'")
	machine.log_chip("chip request failed: HTTP 500")
	machine.log_chip("exploded at 150°")
	other.log_chip("set_enabled({\"on\":false})")
	var timeline: Container = log.get_node("%Timeline") as Container
	check_eq(timeline.get_child_count(), 6, "one icon per entry of the selected machine, in order")
	check_eq(log.get_kinds(machine), ["checking", "applied", "none", "failed", "failed", "info"] as Array[String], "the kinds, oldest first")
	var tips: Array[String] = []
	for icon: Node in timeline.get_children():
		tips.append((icon as TextureRect).tooltip_text)
		check((icon as TextureRect).texture != null and (icon as Control).mouse_filter == Control.MOUSE_FILTER_STOP, "each icon has art and can show its hover")
	check_eq(tips, ["Checking: Smelter Cooler", "Cooling set on", "No action", "Action rejected", "Request failed", "exploded at 150°"] as Array[String], "hover text explains each icon")
	check_eq(log.find_children("*", "Label", true, false).size() - 1, 0, "no text entries beyond the title")
	var first: Image = (timeline.get_child(0) as TextureRect).texture.get_image()
	check_eq(first.get_data(), Icons.icon("checking").get_image().get_data(), "a check shows the checking icon")
	machine.log_chip("set_cooling({\"on\":false})")
	check_eq(timeline.get_child_count(), 7, "new entries appear while it is open")


func test_chip_log_never_shows_raw_tool_names_or_json() -> void:
	var log: ChipLog = _spawn("res://scenes/ui/popups/chip_log.tscn")
	var machine: Machine = _spawn("res://scenes/machines/machine.tscn")
	log.show_machine(machine)
	for message: String in ["set_stock_limit({\"limit\":6})", "set_direction({\"direction\":2})", "set_accepting({\"on\":true})", "set_unheard_of({\"x\":1})", "set_cooling({broken})"]:
		var shown: String = _shown(log, machine, message)
		check(not shown.contains("set_") and not shown.contains("{") and not shown.contains("\""), "readable: %s" % shown)
	check_eq(_shown(log, machine, "set_unheard_of({\"x\":1})"), "Action requested", "an unknown call is not claimed as applied")
	check(not " ".join(log.get_lines(machine)).contains("event:"), "no raw trigger reasons")


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


func _same_icon(a: Texture2D, icon_name: String) -> bool:
	var expected: Image = Icons.icon(icon_name).get_image()
	expected.resize(Icons.SIZE * Icons.SCALE, Icons.SIZE * Icons.SCALE, Image.INTERPOLATE_NEAREST)
	return a.get_image().get_data() == expected.get_data()


func _texts(root: Node) -> Array[String]:
	var found: Array[String] = []
	for node: Node in root.find_children("*", "Label", true, false):
		found.append((node as Label).text)
	for node: Node in root.find_children("*", "Button", true, false):
		if (node as Button).text != "":
			found.append((node as Button).text)
	return found


func test_details_panel_is_compact_and_icon_driven() -> void:
	var tooltip: MachineTooltip = _spawn("res://scenes/ui/popups/machine_tooltip.tscn")
	var machine: Machine = _spawn("res://scenes/machines/smelter.tscn")
	var chip: ChipRessource = _add("ui_compact", "A long prompt that explains everything the chip does in detail")
	machine.attach_chip(chip.id)
	autoload("EventBus").machine_selected.emit(machine)
	check_eq((tooltip.get_node("%IdLabel") as Label).text, "Smelter #%d" % machine.machine_id, "title: type and id")
	for pair: Array in [["%LogButton", "log", "Chip log"], ["%RotateButton", "rotate", "Rotate"], ["%DestroyButton", "destroy", "Destroy this machine"], ["%AddButton", "add", "Add the chosen chip"]]:
		var button: Button = tooltip.get_node(pair[0]) as Button
		check_eq(button.text, "", "%s has no text" % pair[0])
		check(button.icon != null and _same_icon(button.icon, pair[1]), "%s shows the %s icon" % [pair[0], pair[1]])
		check_eq(button.tooltip_text, pair[2], "%s explains itself on hover" % pair[0])
	var row: Node = tooltip.get_node("%ChipsList").get_child(0)
	var name_label: Label = row.find_child("Name", true, false) as Label
	check_eq(name_label.text, "ui_compact", "the chip is identified by its name only")
	check(name_label.tooltip_text.begins_with("A long prompt"), "the prompt is on hover, not in the panel")
	for pair: Array in [["Ask", "ask", "Ask the chip now"], ["Remove", "remove", "Remove this chip"]]:
		var button: Button = row.find_child(pair[0], true, false) as Button
		check(button.text == "" and _same_icon(button.icon, pair[1]) and button.tooltip_text == pair[2], "%s is an icon button with a hover" % pair[0])
	var texts: Array[String] = _texts(tooltip)
	for gone: String in ["Type: smelter", "Chips", "Ask when", "Add chip", "Ask now", "Log", "Rotate", "Destroy", "X", "State: normal"]:
		check(not gone in texts, "no '%s' text" % gone)
	check(texts.has("ui_compact"), "names stay as text")
	check(texts.has("20°"), "the temperature value stays as text, without a caption")
	check(tooltip.get_combined_minimum_size().x <= 260.0, "narrow enough for the Bar at small window sizes (%d)" % int(tooltip.get_combined_minimum_size().x))


func _same_raw(a: Texture2D, b: Texture2D) -> bool:
	return a.get_image().get_data() == b.get_image().get_data()


func test_smelter_heat_is_a_thermometer_and_a_cooling_icon() -> void:
	var tooltip: MachineTooltip = _spawn("res://scenes/ui/popups/machine_tooltip.tscn")
	var smelter: Smelter = _spawn("res://scenes/machines/smelter.tscn") as Smelter
	var heat: Control = tooltip.get_node("%HeatRow") as Control
	var thermo: TextureRect = tooltip.get_node("%ThermoIcon") as TextureRect
	var cool: TextureRect = tooltip.get_node("%CoolIcon") as TextureRect
	autoload("EventBus").machine_selected.emit(smelter)
	check(heat.visible, "a smelter shows its heat row")
	check_eq((tooltip.get_node("%TempLabel") as Label).text, "20°", "current value as a number")
	check(_same_raw(cool.texture, Icons.icon("cooling_off")) and cool.tooltip_text == "Cooling off", "cooling off: the dim snowflake")
	var cool_off_look: Texture2D = thermo.texture
	smelter.apply_tool_call("set_cooling", {"on": true})
	smelter.temperature = 120.0
	autoload("EventBus").machine_selected.emit(null)
	autoload("EventBus").machine_selected.emit(smelter)
	check_eq((tooltip.get_node("%TempLabel") as Label).text, "120°", "the number follows the temperature")
	check(_same_raw(cool.texture, Icons.icon("cooling_on")) and cool.tooltip_text == "Cooling on", "cooling on: the lit snowflake")
	check(not _same_raw(cool.texture, Icons.icon("cooling_off")), "the two states differ")
	check(not _same_raw(thermo.texture, cool_off_look), "the thermometer fills as it heats up")
	check(thermo.tooltip_text.begins_with("Temperature"), "and explains itself on hover")
	var miner: Machine = _spawn("res://scenes/machines/miner.tscn")
	autoload("EventBus").machine_selected.emit(miner)
	check(not heat.visible, "other machines have no heat row")


func test_collector_panel_hides_rotate_and_destroy_icons() -> void:
	var tooltip: MachineTooltip = _spawn("res://scenes/ui/popups/machine_tooltip.tscn")
	var collector: Machine = _spawn("res://scenes/machines/collector.tscn")
	autoload("EventBus").machine_selected.emit(collector)
	check(not (tooltip.get_node("%RotateButton") as Button).visible and not (tooltip.get_node("%DestroyButton") as Button).visible, "fixed machine: no rotate, no destroy")
	check((tooltip.get_node("%LogButton") as Button).visible, "but its log is still there")


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
	(box.find_child("Ask", true, false) as Button).pressed.emit()
	check(machine.chips[0].pending, "Ask now sends a request")
	var keys: OptionButton = box.find_child("Key", true, false) as OptionButton
	var index: int = -1
	for i: int in keys.item_count:
		if keys.get_item_text(i) == "temperature":
			index = i
	check(index > 0, "numeric state values are offered")
	keys.select(index)
	keys.item_selected.emit(index)
	(box.find_child("Limit", true, false) as SpinBox).value = 90
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
