extends "res://tests/test_case.gd"


func test_main_scene_layout() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	check(main.get_node_or_null("Game/FactoryView/SubViewport/World/Machines") != null, "world has Machines")
	check(main.get_node_or_null("Game/FactoryView/SubViewport/World/GridMap2D") is TileMapLayer, "world has GridMap2D")
	check(main.get_node_or_null("Game/FactoryView/SubViewport/World/Camera2D") != null, "world has Camera2D")
	check(main.get_node_or_null("Game/Bar/VBoxContainer/PageTabs") != null, "bar has PageTabs")
	var box: Node = main.get_node("Game/Bar/VBoxContainer")
	check_eq(box.get_child(0).name, &"PageTabs", "page tabs are at the top")
	check_eq(box.get_child(box.get_child_count() - 1).name, &"SettingsButton", "Settings button is at the bottom")
	check_eq([tabs.get_tab_title(0), tabs.get_tab_title(1)], ["Build", "Chip Registry"], "Build and Chip Registry tabs side by side")
	check(main.get_node_or_null("UI") is CanvasLayer, "UI layer exists")
	check(main.get_node_or_null("Game/Bar/VBoxContainer/Pages/ChipRegistryPage") != null, "bar has the chip registry page")
	for popup_name: String in ["ChipPage", "MachineTooltip", "ChipLog", "SettingsDialog"]:
		check(main.get_node_or_null("UI/" + popup_name) != null, "UI has " + popup_name)
	var factory: Control = main.get_node("Game/FactoryView")
	var bar: Control = main.get_node("Game/Bar")
	check_eq(factory.size_flags_stretch_ratio / bar.size_flags_stretch_ratio, 4.0, "factory:bar is 80:20")
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
