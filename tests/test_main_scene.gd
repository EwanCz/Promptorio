extends "res://tests/test_case.gd"


func test_main_scene_layout() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	check(main.get_node_or_null("Game/FactoryView/SubViewport/World/Machines") != null, "world has Machines")
	check(main.get_node_or_null("Game/FactoryView/SubViewport/World/GridMap2D") is TileMapLayer, "world has GridMap2D")
	check(main.get_node_or_null("Game/FactoryView/SubViewport/World/Camera2D") != null, "world has Camera2D")
	check(main.get_node_or_null("Game/Bar/VBoxContainer/TopHalf/PageTabs") != null, "bar has PageTabs")
	check(main.get_node_or_null("UI") is CanvasLayer, "UI layer exists")
	check(main.get_node_or_null("Game/Bar/VBoxContainer/TopHalf/PageScroll/Pages/BuildPage") != null, "bar has the build page")
	check(main.get_node_or_null("Game/Bar/VBoxContainer/TopHalf/PageScroll/Pages/ChipRegistryPage") != null, "bar has the chip registry page")
	for popup_name: String in ["ChipPage", "ChipLog", "ResourcesPage", "SettingsDialog", "SaveDialog"]:
		check(main.get_node_or_null("UI/" + popup_name) != null, "UI has " + popup_name)
	var factory: Control = main.get_node("Game/FactoryView")
	var bar: Control = main.get_node("Game/Bar")
	check_eq(factory.size_flags_stretch_ratio / bar.size_flags_stretch_ratio, 4.0, "factory:bar is 80:20")
	main.free()


func test_bar_is_split_into_pages_machine_info_and_settings() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	var column: Node = main.get_node("Game/Bar/VBoxContainer")
	var top: Control = column.get_node("TopHalf")
	var info: Control = main.get_node("%MachineTooltip")
	check(info.get_parent() == column, "machine info sits in the Bar, not in a popup")
	check_eq(top.size_flags_stretch_ratio, info.size_flags_stretch_ratio, "the two halves share the height equally")
	check(top.size_flags_vertical & Control.SIZE_EXPAND != 0 and info.size_flags_vertical & Control.SIZE_EXPAND != 0, "both halves expand")
	check(top.get_node("PageScroll") is ScrollContainer, "the pages scroll")
	check(main.get_node("%Pages").get_parent() == top.get_node("PageScroll"), "the pages live in that scroll")
	var buttons: Control = main.get_node("%BarButtons")
	check(column.get_child(column.get_child_count() - 1) == buttons, "the buttons row stays at the very bottom")
	check(info.get_index() < buttons.get_index(), "the buttons sit under the machine info")
	check(top.get_index() < info.get_index() and info.get_index() < buttons.get_index(), "pages, then machine info, then the buttons")
	check(buttons is HBoxContainer, "the buttons are side by side")
	check(buttons.get_child(buttons.get_child_count() - 1) == main.get_node("%SettingsButton"), "Settings stays last, at the right end")
	main.free()


func test_toggle_bar_action() -> void:
	check(InputMap.has_action("toggle_bar"), "toggle_bar action exists")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	var bar: Control = main.get_node("Game/Bar")
	var press: InputEventAction = InputEventAction.new()
	press.action = "toggle_bar"
	press.pressed = true
	(Engine.get_main_loop() as SceneTree).root.add_child(main)
	main._unhandled_input(press)
	check(not bar.visible, "action hides the bar")
	main._unhandled_input(press)
	check(bar.visible, "action shows the bar again")
	main.free()


func test_settings_is_an_icon_button_with_a_hover() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(main)
	var button: Button = main.get_node("%SettingsButton") as Button
	check_eq(button.text, "", "no text")
	check(button.icon != null, "an icon")
	check_eq(button.tooltip_text, "Settings", "the hover names it")
	main.free()


func test_menu_resources_and_save_buttons_look_like_settings() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(main)
	var settings: Button = main.get_node("%SettingsButton") as Button
	var hovers: Dictionary = {"%MenuButton": "Menu", "%ResourcesButton": "Resources", "%SavesButton": "Save / Load"}
	var seen: Dictionary = {}
	for path: String in hovers:
		var button: Button = main.get_node(path) as Button
		check_eq(button.text, "", "%s has no text" % path)
		check(button.icon != null, "%s has an icon" % path)
		check_eq(button.tooltip_text, hovers[path], "%s names itself on hover" % path)
		check_eq(button.size_flags_horizontal, settings.size_flags_horizontal, "%s is aligned like Settings" % path)
		check_eq(button.custom_minimum_size, settings.custom_minimum_size, "%s is as big as Settings" % path)
		check(not seen.has(button.icon.get_image().get_data()) and button.icon.get_image().get_data() != settings.icon.get_image().get_data(), "%s has its own icon" % path)
		seen[button.icon.get_image().get_data()] = true
	main.free()


func test_the_four_bar_buttons_share_one_row() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	var row: Control = main.get_node("%BarButtons")
	var names: Array[String] = []
	for child: Node in row.get_children():
		names.append(str(child.name))
	check_eq(names, ["MenuButton", "ResourcesButton", "SavesButton", "SettingsButton"] as Array[String], "Menu, Resources, Save / Load, Settings, left to right")
	check_eq((row as BoxContainer).alignment, BoxContainer.ALIGNMENT_END, "pushed to the right, where Settings used to sit")
	main.free()
