class_name BuildPage
extends VBoxContainer
## Build page: money (coin icon and amount), one button per buildable machine (its art and the cost as a
## number, the name on hover, disabled when unaffordable), the selected type and an icon for the last
## placement refusal (hover for the reason). Selecting only enters placement mode.

const ART_SIZE: int = 32
const COIN_GAP: int = 4

var _placement: Placement = null
var _buttons: Dictionary = {}

@onready var _money_icon: TextureRect = %MoneyIcon
@onready var _money_label: Label = %MoneyLabel
@onready var _list: HFlowContainer = %List
@onready var _feedback_icon: TextureRect = %FeedbackIcon


func _ready() -> void:
	for type: String in Placement.COSTS:
		var button: Button = Button.new()
		button.toggle_mode = true
		button.tooltip_text = type.capitalize()
		button.icon = _art(type)
		button.pressed.connect(_on_button_pressed.bind(type))
		_list.add_child(button)
		_buttons[type] = button
	Icons.apply(_money_icon, "money", "Money")
	EventBus.money_changed.connect(_on_money_changed)
	_refresh()


func _exit_tree() -> void:
	EventBus.money_changed.disconnect(_on_money_changed)


## Connects the page to the placement flow it drives.
func setup(placement: Placement) -> void:
	_placement = placement
	placement.selection_changed.connect(_on_selection_changed)
	placement.placement_rejected.connect(_on_placement_rejected)
	_refresh()


func _refresh() -> void:
	_money_label.text = str(GameState.money)
	for type: String in _buttons:
		var button: Button = _buttons[type]
		button.text = str(Placement.COSTS[type])
		button.disabled = GameState.money < Placement.COSTS[type]
		button.set_pressed_no_signal(_placement != null and _placement.selected == type)


func _on_button_pressed(type: String) -> void:
	if _placement == null:
		return
	_feedback_icon.visible = false
	_placement.select("" if _placement.selected == type else type)


func _on_selection_changed(_type: String) -> void:
	_refresh()


func _on_money_changed(_amount: int) -> void:
	_refresh()


func _on_placement_rejected(reason: String) -> void:
	Icons.apply(_feedback_icon, "no_money" if reason.begins_with("Not enough money") else "blocked", reason)
	_feedback_icon.visible = true


## The machine's own art (the conveyor's belt for the conveyor), scaled to ART_SIZE with the nearest filter,
## with the money icon beside it so the number after it reads as a price. Works on a copy: the texture's
## image can be shared.
func _art(type: String) -> Texture2D:
	var machine: Machine = (Placement.SCENES[type] as PackedScene).instantiate() as Machine
	var texture: Texture2D = machine.front_texture if machine.front_texture != null else (machine.get("side_texture") as Texture2D)
	machine.free()
	if texture == null:
		return null
	var image: Image = texture.get_image().duplicate()
	image.convert(Image.FORMAT_RGBA8)
	image.resize(ART_SIZE, ART_SIZE, Image.INTERPOLATE_NEAREST)
	var coin: Image = Icons.icon("money").get_image()
	coin.resize(Icons.SIZE * Icons.SCALE, Icons.SIZE * Icons.SCALE, Image.INTERPOLATE_NEAREST)
	var both: Image = Image.create_empty(ART_SIZE + COIN_GAP + coin.get_width(), ART_SIZE, false, Image.FORMAT_RGBA8)
	both.blit_rect(image, Rect2i(Vector2i.ZERO, image.get_size()), Vector2i.ZERO)
	both.blend_rect(coin, Rect2i(Vector2i.ZERO, coin.get_size()), Vector2i(ART_SIZE + COIN_GAP, (ART_SIZE - coin.get_height()) / 2))
	return ImageTexture.create_from_image(both)
