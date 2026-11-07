class_name ResourcesPage
extends PanelContainer
## Popup listing every resource of the catalog: the machine that builds it, what it needs, how long
## it takes and what the Collector pays for it.

const HEADERS: PackedStringArray = ["Resource", "Built by", "Needs", "Ticks", "Price"]

@onready var _grid: GridContainer = %Grid
@onready var _close_button: Button = %CloseButton


func _ready() -> void:
	visible = false
	_close_button.pressed.connect(close)
	for title: String in HEADERS:
		_add_cell(title)
	for item: ItemData in ItemCatalog.shared().items:
		_add_cell(item.display_name)
		_add_cell(item.machine.capitalize())
		_add_cell(needs_text(item))
		_add_cell("-" if item.is_mined() else str(item.ticks))
		_add_cell(str(item.price))


func open() -> void:
	visible = true


func close() -> void:
	visible = false


## "Mined" for a raw resource, else the inputs with their counts, e.g. "1 Wood + 1 Silver".
func needs_text(item: ItemData) -> String:
	if item.inputs.is_empty():
		return "Mined"
	var parts: PackedStringArray = []
	for id: String in item.inputs:
		var input: ItemData = ItemCatalog.shared().get_item(id)
		parts.append("%d %s" % [int(item.inputs[id]), id if input == null else input.display_name])
	return " + ".join(parts)


func _add_cell(text: String) -> void:
	var label: Label = Label.new()
	label.text = text
	_grid.add_child(label)
