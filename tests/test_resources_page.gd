extends "res://tests/test_case.gd"
## The Resources popup: every resource of the catalog, opened from the Bar.

var _nodes: Array[Node] = []


func after_each() -> void:
	for node: Node in _nodes:
		node.free()
	_nodes.clear()


func _page() -> ResourcesPage:
	var page: ResourcesPage = (load("res://scenes/ui/popups/resources_page.tscn") as PackedScene).instantiate() as ResourcesPage
	tree.root.add_child(page)
	_nodes.append(page)
	return page


func _cells(page: ResourcesPage) -> Array[String]:
	var texts: Array[String] = []
	for label: Node in page.get_node("%Grid").get_children():
		texts.append((label as Label).text)
	return texts


func test_starts_closed_and_opens_and_closes() -> void:
	var page: ResourcesPage = _page()
	check(not page.visible, "hidden at first")
	page.open()
	check(page.visible, "open shows it")
	page.get_node("%CloseButton").pressed.emit()
	check(not page.visible, "the Close button hides it")


func test_lists_every_resource_with_its_build() -> void:
	var page: ResourcesPage = _page()
	var cells: Array[String] = _cells(page)
	var columns: int = page.get_node("%Grid").columns
	check_eq(columns, ResourcesPage.HEADERS.size(), "one column per header")
	check_eq(cells.slice(0, columns), Array(ResourcesPage.HEADERS), "headers first")
	var catalog: ItemCatalog = ItemCatalog.shared()
	check_eq(cells.size(), columns * (catalog.items.size() + 1), "one row per resource")
	for i: int in catalog.items.size():
		var item: ItemData = catalog.items[i]
		var row: Array[String] = cells.slice(columns * (i + 1), columns * (i + 2))
		check_eq(row[0], item.display_name, "%s: name" % item.id)
		check_eq(row[1], item.machine.capitalize(), "%s: machine" % item.id)
		check_eq(row[2], page.needs_text(item), "%s: needs" % item.id)
		check_eq(row[4], str(item.price), "%s: price" % item.id)


func test_needs_text() -> void:
	var page: ResourcesPage = _page()
	var catalog: ItemCatalog = ItemCatalog.shared()
	check_eq(page.needs_text(catalog.get_item("ore")), "Mined", "a mined resource")
	check_eq(page.needs_text(catalog.get_item("spear")), "1 Wood + 1 Silver", "two inputs")
	check_eq(page.needs_text(catalog.get_item("part")), "2 Ingot", "a count above one")


func test_the_bar_button_opens_the_popup() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(main)
	_nodes.append(main)
	var page: ResourcesPage = main.get_node("%ResourcesPage")
	check(not page.visible, "closed at startup")
	main.get_node("%ResourcesButton").pressed.emit()
	check(page.visible, "the Resources button opens it")
