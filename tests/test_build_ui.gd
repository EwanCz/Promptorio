extends "res://tests/test_case.gd"
## Build page, placement costs, and the tooltip actions (rotate, destroy, current action).

var _main: Node
var _placement: Placement
var _grid: GridMap2D
var _page: BuildPage
var _tooltip: MachineTooltip
var _game: Node
var _saved_money: int = 0
var _registry: Node
var _chip_ids: Array[int] = []


func before_each() -> void:
	_game = autoload("GameState")
	_registry = autoload("ChipRegistry")
	_saved_money = _game.money
	_game.money = 100
	_main = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(_main)
	_placement = _main.get_node("Game/FactoryView/SubViewport/World/Placement")
	_grid = _main.get_node("%GridMap2D")
	_page = _main.get_node("%BuildPage")
	_tooltip = _main.get_node("%MachineTooltip")


func after_each() -> void:
	_main.free()
	for id: int in _chip_ids:
		_registry.remove(id)
	_chip_ids.clear()
	_game.money = _saved_money


func _buttons() -> Array[Button]:
	var result: Array[Button] = []
	for child: Node in _page.get_node("%List").get_children():
		result.append(child as Button)
	return result


func test_start_money_and_catalog() -> void:
	check(_game.START_MONEY > 0, "the game starts with some money")
	check_eq(Placement.COSTS, {"miner": 20, "smelter": 30, "assembler": 40, "conveyor": 2}, "catalog costs")


func test_page_lists_machines_with_cost_and_money() -> void:
	var buttons: Array[Button] = _buttons()
	check_eq(buttons.size(), 4, "one button per buildable machine")
	check_eq(buttons[0].text, "20", "the cost is just a number")
	var price_icon: Image = Icons.icon("money").get_image()
	price_icon.resize(Icons.SIZE * Icons.SCALE, Icons.SIZE * Icons.SCALE, Image.INTERPOLATE_NEAREST)
	for button: Button in buttons:
		var strip: Image = button.icon.get_image()
		var at: Vector2i = Vector2i(BuildPage.ART_SIZE + BuildPage.COIN_GAP, (BuildPage.ART_SIZE - price_icon.get_height()) / 2)
		check(strip.get_region(Rect2i(0, 0, BuildPage.ART_SIZE, BuildPage.ART_SIZE)).get_data() != Image.create_empty(BuildPage.ART_SIZE, BuildPage.ART_SIZE, false, Image.FORMAT_RGBA8).get_data(), "%s: the machine art is still there" % button.tooltip_text)
		check_eq(strip.get_region(Rect2i(at, price_icon.get_size())).get_data(), price_icon.get_data(), "%s: the money icon sits between the art and the number, so it reads as a price" % button.tooltip_text)
	check_eq([buttons[1].text, buttons[2].text, buttons[3].text], ["30", "40", "2"], "every cost beside its machine")
	for i: int in buttons.size():
		check(buttons[i].icon != null, "%s shows its machine art" % buttons[i].tooltip_text)
	check(buttons[0].get_combined_minimum_size().x < 200.0, "buttons stay small however many times the page is built")
	check_eq(buttons.map(func(b: Button) -> String: return b.tooltip_text), ["Miner", "Smelter", "Assembler", "Conveyor"], "names on hover")
	check_eq((_page.get_node("%MoneyLabel") as Label).text, "100", "money is a bare amount")
	var coin: TextureRect = _page.get_node("%MoneyIcon") as TextureRect
	check_eq(coin.texture.get_image().get_data(), Icons.icon("money").get_image().get_data(), "beside a coin icon")
	check_eq(coin.tooltip_text, "Money", "which explains itself on hover")
	check(not _page.find_children("*", "Label", true, false).any(func(l: Label) -> bool: return l.text.contains("Money") or l.text.contains("-")), "no money or cost words")


func test_unaffordable_machines_are_disabled() -> void:
	_game.add_money(-85)
	var buttons: Array[Button] = _buttons()
	check(buttons[0].disabled, "miner (20) too expensive with 15")
	check(buttons[3].disabled == false, "conveyor (2) still affordable")
	check_eq((_page.get_node("%MoneyLabel") as Label).text, "15", "money label follows money_changed")


func test_selecting_does_not_charge_and_toggles() -> void:
	var buttons: Array[Button] = _buttons()
	buttons[1].pressed.emit()
	check_eq(_placement.selected, "smelter", "button enters placement mode")
	check_eq(_game.money, 100, "selecting charges nothing")
	check(buttons[1].button_pressed, "selected type is highlighted")
	buttons[1].pressed.emit()
	check_eq(_placement.selected, "", "pressing it again cancels")


func test_selection_by_key_is_shown_on_the_page() -> void:
	_placement.select("assembler")
	check(_buttons()[2].button_pressed, "key selection highlights the same button")


func test_placing_charges_once_and_rejections_do_not() -> void:
	var rejected: Array[String] = []
	var on_rejected: Callable = func(reason: String) -> void: rejected.append(reason)
	_placement.placement_rejected.connect(on_rejected)
	check(_placement.try_place("smelter", Vector2i(8, 8)) is Smelter, "affordable placement works")
	check_eq(_game.money, 70, "charged exactly the cost")
	check(_placement.try_place("smelter", Vector2i(8, 8)) == null, "occupied cell refused")
	check(_placement.try_place("miner", Vector2i(9, 9)) == null, "miner off a minesite refused")
	check_eq(_game.money, 70, "rejections do not charge")
	_game.money = 10
	check(_placement.try_place("assembler", Vector2i(10, 10)) == null, "too expensive")
	check_eq(_game.money, 10, "money untouched when it cannot pay")
	check(_game.get_machine_at(Vector2i(10, 10)) == null, "registry untouched")
	check_eq(rejected.size(), 3, "each refusal gives feedback")
	_placement.placement_rejected.disconnect(on_rejected)


func test_click_charges_through_the_grid() -> void:
	var grid: GridMap2D = _main.get_node("%GridMap2D")
	_placement.select("conveyor")
	grid.cell_clicked.emit(Vector2i(8, 8))
	grid.cell_clicked.emit(Vector2i(9, 8))
	check_eq(_game.money, 96, "two conveyors charged 2 each, selection stays active")
	check_eq(_placement.selected, "conveyor", "selected type kept after placing")


func test_page_shows_rejection_feedback() -> void:
	_game.money = 0
	_placement.try_place("conveyor", Vector2i(8, 8))
	var icon: TextureRect = _page.get_node("%FeedbackIcon") as TextureRect
	check(icon.visible, "the refusal is shown as an icon")
	check(icon.tooltip_text.contains("Not enough money"), "hover gives the reason")
	check_eq(icon.texture.get_image().get_data(), Icons.icon("no_money").get_image().get_data(), "a coin icon for insufficient funds")
	_game.money = 100
	_placement.try_place("conveyor", Vector2i(16, 10))
	check_eq(icon.texture.get_image().get_data(), Icons.icon("blocked").get_image().get_data(), "another refusal gets the blocked icon")
	check(icon.tooltip_text.contains("Cannot place"), "with its own reason")
	check(_page.find_children("*", "Label", true, false).filter(func(n: Node) -> bool: return n.name == "FeedbackLabel").is_empty(), "no feedback text label")


func test_destroy_discards_contents_and_frees_the_cell() -> void:
	var smelter: Smelter = _placement.place("smelter", Vector2i(8, 8))
	smelter.receive("ore")
	var chip: ChipRessource = _registry.add("destroy_chip", "p")
	_chip_ids.append(chip.id)
	smelter.attach_chip(chip.id)
	check(smelter.destroy(), "destroy succeeds")
	check(_game.get_machine_at(Vector2i(8, 8)) == null, "cell freed immediately")
	check(smelter.stock.is_empty(), "stock discarded")
	check(smelter.chips.is_empty(), "chips detached")
	check(smelter.get_parent() == null, "removed from the scene")
	check_eq(_game.money, 100, "destroy() itself gives no money (the tooltip button does)")
	check(_placement.place("smelter", Vector2i(8, 8)) != null, "the cell can be rebuilt")


func test_destroy_clears_every_machine_kind() -> void:
	var miner: Miner = _placement.place("miner", _grid.minesites[0])
	miner._held = "ore"
	miner.destroy()
	check_eq(miner._held, "", "miner drops its held ore")
	var conveyor: Conveyor = _placement.place("conveyor", Vector2i(8, 8))
	conveyor.receive("ore")
	conveyor.destroy()
	check_eq(conveyor.held, "", "conveyor drops its item")


func test_collector_is_fixed() -> void:
	var collector: Machine = _game.get_machine_at(_game.GRID_SIZE / 2)
	check(not collector.is_removable(), "collector is not removable")
	check(not collector.can_rotate(), "collector has no facing")
	check(not collector.destroy(), "destroy refused")
	check(_game.get_machine_at(_game.GRID_SIZE / 2) == collector, "collector stays registered")


func test_rotate_is_clockwise_and_keeps_stock() -> void:
	var smelter: Smelter = _placement.place("smelter", Vector2i(8, 8))
	smelter.receive("ore")
	smelter.rotate_facing()
	check_eq(smelter.facing, Vector2i.DOWN, "right becomes down")
	check_eq(smelter.stock.get("ore"), 1, "stock unchanged")


func test_tooltip_destroy_and_rotate_buttons() -> void:
	var conveyor: Conveyor = _placement.place("conveyor", Vector2i(8, 8))
	_main.get_node("%GridMap2D").cell_clicked.emit(Vector2i(8, 8))
	check(_tooltip.is_open(), "tooltip opens on click")
	check(_tooltip.get_node("%RotateButton").visible, "conveyor can rotate")
	check(_tooltip.get_node("%DestroyButton").visible, "conveyor can be destroyed")
	check((_tooltip.get_node("%OpRow") as Control).visible, "the conveyor shows its facing as an icon")
	_tooltip.get_node("%RotateButton").pressed.emit()
	check_eq(conveyor.facing, Vector2i.DOWN, "rotate button rotates")
	_tooltip.get_node("%DestroyButton").pressed.emit()
	check(not _tooltip.is_open(), "tooltip closes")
	check(_game.get_machine_at(Vector2i(8, 8)) == null, "machine destroyed")
	check_eq(_game.money, 101, "half of the conveyor's price (2) came back")


func test_refund_is_half_the_price_rounded_down() -> void:
	check_eq(Placement.refund_for("miner"), 10, "miner")
	check_eq(Placement.refund_for("smelter"), 15, "smelter")
	check_eq(Placement.refund_for("assembler"), 20, "assembler")
	check_eq(Placement.refund_for("conveyor"), 1, "conveyor")
	check_eq(Placement.refund_for("collector"), 0, "the Collector is not for sale")


func test_destroying_through_the_tooltip_refunds_each_machine() -> void:
	_game.money = 0
	var smelter: Smelter = _placement.place("smelter", Vector2i(8, 8))
	_main.get_node("%GridMap2D").cell_clicked.emit(Vector2i(8, 8))
	_tooltip.get_node("%DestroyButton").pressed.emit()
	check(smelter.get_parent() == null, "the smelter is gone")
	check_eq(_game.money, 15, "half of 30 came back")
	_placement.place("assembler", Vector2i(10, 8))
	_main.get_node("%GridMap2D").cell_clicked.emit(Vector2i(10, 8))
	_tooltip.get_node("%DestroyButton").pressed.emit()
	check_eq(_game.money, 35, "then half of 40")
	check_eq((_page.get_node("%MoneyLabel") as Label).text, "35", "the Build page shows it beside the money icon")


func test_an_exploding_smelter_refunds_nothing() -> void:
	_game.money = 0
	var smelter: Smelter = _placement.place("smelter", Vector2i(8, 8))
	smelter.temperature = Smelter.EXPLODE_AT
	smelter._explode()
	await wait_until(func() -> bool: return _game.get_machine_at(Vector2i(8, 8)) == null, 3.0)
	check(_game.get_machine_at(Vector2i(8, 8)) == null, "the smelter was destroyed")
	check_eq(_game.money, 0, "an explosion gives nothing back")


func test_tooltip_hides_actions_for_the_collector() -> void:
	_placement.select("")
	_main.get_node("%GridMap2D").cell_clicked.emit(_game.GRID_SIZE / 2)
	check(not _tooltip.get_node("%RotateButton").visible, "no rotate on the collector")
	check(not _tooltip.get_node("%DestroyButton").visible, "no destroy on the collector")
	check((_tooltip.get_node("%OpRow") as Control).visible, "the collector shows its sales as icons")


func test_progress_and_blocked_per_machine() -> void:
	var miner: Miner = _placement.place("miner", _grid.minesites[0])
	check_eq(miner.get_progress(), 0.0, "a new miner has made no progress")
	_ticks(miner.mine_ticks / 2)
	check(miner.get_progress() > 0.3 and miner.get_progress() < 0.7, "about half way")
	var smelter: Smelter = _placement.place("smelter", Vector2i(8, 8))
	check_eq(smelter.get_progress(), 0.0, "an idle smelter has none")
	smelter.receive("ore")
	_ticks(1)
	var early: float = smelter.get_progress()
	_ticks(3)
	check(smelter.get_progress() > early and smelter.get_progress() < 1.0, "a craft fills as it goes")
	check_eq(_placement.place("conveyor", Vector2i(2, 2)).get_progress(), -1.0, "a conveyor has no job bar")
	check(not smelter.is_blocked(), "not blocked")


func _ticks(count: int) -> void:
	for i: int in count:
		autoload("EventBus").tick_fired.emit(i)


func test_destroyed_machine_closes_its_open_tooltip() -> void:
	var conveyor: Conveyor = _placement.place("conveyor", Vector2i(8, 8))
	_tooltip.open(conveyor)
	conveyor.destroy()
	check(not _tooltip.is_open(), "tooltip closes when the machine goes away")


func test_popups_consume_mouse_input() -> void:
	check_eq(_tooltip.mouse_filter, Control.MOUSE_FILTER_STOP, "tooltip blocks clicks to the map")
	check_eq((_main.get_node("%Bar") as Control).mouse_filter, Control.MOUSE_FILTER_STOP, "bar blocks clicks to the map")


func test_collector_cannot_be_built() -> void:
	var rejected: Array[String] = []
	var on_rejected: Callable = func(reason: String) -> void: rejected.append(reason)
	_placement.placement_rejected.connect(on_rejected)
	var before: int = _game.money
	check(_placement.try_place("collector", Vector2i(11, 11)) == null, "collector refused")
	check(_game.get_machine_at(Vector2i(11, 11)) == null, "nothing registered")
	check_eq(_game.money, before, "money untouched")
	check_eq(rejected.size(), 1, "refusal explained")
	_placement.placement_rejected.disconnect(on_rejected)
	for button: Button in _buttons():
		check(not button.text.begins_with("Collector"), "not on the build page")


func test_bar_switches_pages_with_named_buttons() -> void:
	var tabs: Node = _main.get_node("%PageTabs")
	check(tabs is HFlowContainer, "page markers are plain buttons, no scroll arrows")
	var names: Array[String] = []
	for button: Node in tabs.get_children():
		names.append((button as Button).text)
	check_eq(names, ["Build", "Chip Registry"], "buttons carry the page names")
	var pages: Node = _main.get_node("%Pages")
	check((pages.get_child(0) as Control).visible and not (pages.get_child(1) as Control).visible, "build page shown first")
	tabs.get_child(1).pressed.emit()
	check((pages.get_child(1) as Control).visible and not (pages.get_child(0) as Control).visible, "second button shows its page")
