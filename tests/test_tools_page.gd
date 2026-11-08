extends "res://tests/test_case.gd"
## The Tools popup: every tool of every machine type, opened from the Bar.

var _nodes: Array[Node] = []


func after_each() -> void:
	for node: Node in _nodes:
		node.free()
	_nodes.clear()


func _page() -> ToolsPage:
	var page: ToolsPage = (load("res://scenes/ui/popups/tools_page.tscn") as PackedScene).instantiate() as ToolsPage
	tree.root.add_child(page)
	_nodes.append(page)
	return page


func _texts(page: ToolsPage) -> Array[String]:
	var texts: Array[String] = []
	for node: Node in page.get_node("%List").get_children():
		if node is Label:
			texts.append((node as Label).text.strip_edges())
	return texts


func test_starts_closed_and_opens_and_closes() -> void:
	var page: ToolsPage = _page()
	check(not page.visible, "hidden at first")
	page.open()
	check(page.visible, "open shows it")
	page.get_node("%CloseButton").pressed.emit()
	check(not page.visible, "the Close button hides it")


func test_lists_every_machine_type_and_all_its_tools() -> void:
	var texts: Array[String] = _texts(_page())
	for type: String in Placement.SCENES:
		check(texts.has(type.capitalize()), "%s has a section" % type)
		var machine: Machine = (Placement.SCENES[type] as PackedScene).instantiate() as Machine
		for schema: Dictionary in machine.get_tool_schemas():
			check(texts.has(ToolsPage.signature(schema)), "%s lists %s" % [type, schema["name"]])
			check(texts.has(str(schema["description"]).strip_edges()), "%s explains %s" % [type, schema["name"]])
		machine.free()


func test_sections_follow_the_build_order_and_hold_their_own_tools() -> void:
	var texts: Array[String] = _texts(_page())
	var smelter: int = texts.find("Smelter")
	var assembler: int = texts.find("Assembler")
	check(texts.find("Miner") < smelter and smelter < assembler, "machine types are in the build order")
	check(texts.find("set_cooling(on: boolean)") > smelter and texts.find("set_cooling(on: boolean)") < assembler, "set_cooling is under the Smelter only")
	check_eq(texts.count("set_enabled(on: boolean)"), Placement.SCENES.size(), "the shared tool is listed for every type")


func test_signature_shows_arguments_ranges_and_choices() -> void:
	check_eq(ToolsPage.signature({"name": "set_enabled", "input_schema": {"properties": {"on": {"type": "boolean"}}}}), "set_enabled(on: boolean)", "a flag")
	check_eq(ToolsPage.signature({"name": "set_stock_limit", "input_schema": {"properties": {"limit": {"type": "integer", "minimum": 1, "maximum": 10}}}}), "set_stock_limit(limit: integer 1..10)", "a range")
	check_eq(ToolsPage.signature({"name": "discard_stock", "input_schema": {"properties": {"item": {"type": "string", "enum": ["a", "b", "c"]}, "count": {"type": "integer", "minimum": 1, "maximum": 10}}}}), "discard_stock(item: string (one of 3), count: integer 1..10)", "choices and a range")
	check_eq(ToolsPage.signature({"name": "ping"}), "ping()", "no arguments")


func test_the_bar_button_opens_the_popup() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(main)
	_nodes.append(main)
	var page: ToolsPage = main.get_node("%ToolsPage")
	check(not page.visible, "closed at startup")
	main.get_node("%ToolsButton").pressed.emit()
	check(page.visible, "the Tools button opens it")
