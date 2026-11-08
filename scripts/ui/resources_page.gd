class_name ResourcesPage
extends PanelContainer
## Popup listing every resource of the catalog: the machine that builds it, what it needs, how long
## it takes to mine or build and what the Collector pays for it.

const HEADERS: PackedStringArray = ["Resource", "Built by", "Needs", "Ticks", "Price"]
const ICON_SIZE: int = 20

@onready var _grid: GridContainer = %Grid
@onready var _close_button: Button = %CloseButton


func _ready() -> void:
	visible = false
	_close_button.pressed.connect(close)
	for title: String in HEADERS:
		_add_cell(title)
	for item: ItemData in ItemCatalog.shared().items:
		_add_resource_cell(item)
		_add_cell(item.machine.capitalize())
		_add_cell(needs_text(item))
		_add_cell(str(item.ticks))
		_add_cell(str(item.price))


func open() -> void:
	visible = true


func close() -> void:
	visible = false


## "Mined" for a raw resource, else the inputs with their counts, e.g. "1 Silver Bar + 2 Redstone".
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


## The "Resource" column cell for one item: its catalog icon (crisp pixel art, no icon if it has none)
## followed by its display name, so the icon reads as part of the name rather than its own column.
func _add_resource_cell(item: ItemData) -> void:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	if item.icon != null:
		var icon_rect: TextureRect = TextureRect.new()
		icon_rect.texture = item.icon
		icon_rect.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
		icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		row.add_child(icon_rect)
	var label: Label = Label.new()
	label.text = item.display_name
	row.add_child(label)
	_grid.add_child(row)
