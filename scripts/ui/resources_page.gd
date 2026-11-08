class_name ResourcesPage
extends PanelContainer
## Popup listing every resource of the catalog: the machine that builds it, what it needs, how long
## it takes to mine or build and what the Collector pays for it.

const HEADERS: PackedStringArray = ["Resource", "Built by", "Needs", "Ticks", "Price"]
const ICON_PX: int = 32

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


## The "Resource" cell: the item's icon (nearest filter, same as every other pixel-art icon) immediately
## before its display name. A missing icon leaves the texture empty rather than showing a placeholder.
func _add_resource_cell(item: ItemData) -> void:
	var cell: HBoxContainer = HBoxContainer.new()
	cell.add_theme_constant_override("separation", 4)
	var picture: TextureRect = TextureRect.new()
	picture.texture = item.icon
	picture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	picture.custom_minimum_size = Vector2(ICON_PX, ICON_PX)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	cell.add_child(picture)
	var label: Label = Label.new()
	label.text = item.display_name
	cell.add_child(label)
	_grid.add_child(cell)
