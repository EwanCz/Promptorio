class_name BarPanel
extends PanelContainer
## Right-hand Bar: one named button per page, plus resource, save, menu and settings controls.

signal resources_requested
signal tools_requested
signal settings_requested
signal saves_requested
signal menu_requested

## Order art is the same 32 px resource icons shown elsewhere in the Bar.
const ORDER_ICON_PX: int = 32

var _verdict: String = ""
var _spin_time: float = 0.0
var _frames: Array[Texture2D] = []
var _detail: String = ""

@onready var _key_status: PanelContainer = %KeyStatus
@onready var _key_icon: TextureRect = %KeyIcon
@onready var _key_badge: TextureRect = %KeyBadge
@onready var _order_status: PanelContainer = %OrderStatus
@onready var _order_icon: TextureRect = %OrderIcon
@onready var _order_progress_label: Label = %OrderProgressLabel
@onready var _order_reward_icon: TextureRect = %OrderRewardIcon
@onready var _order_reward_label: Label = %OrderRewardLabel
@onready var _tabs: HFlowContainer = %PageTabs
@onready var _pages: Control = %Pages
@onready var _resources_button: Button = %ResourcesButton
@onready var _tools_button: Button = %ToolsButton
@onready var _saves_button: Button = %SavesButton
@onready var _settings_button: Button = %SettingsButton
@onready var _menu_button: Button = %MenuButton


func _ready() -> void:
	var group: ButtonGroup = ButtonGroup.new()
	for page: Node in _pages.get_children():
		var button: Button = Button.new()
		button.text = page.name.trim_suffix("Page").capitalize()
		button.toggle_mode = true
		button.button_group = group
		button.pressed.connect(_show_page.bind(_tabs.get_child_count()))
		_tabs.add_child(button)
	Icons.apply_button(_resources_button, "resources", "Resources")
	_resources_button.pressed.connect(resources_requested.emit)
	Icons.apply_button(_tools_button, "tools", "Machine tools")
	_tools_button.pressed.connect(tools_requested.emit)
	Icons.apply_button(_saves_button, "save", "Save / Load")
	_saves_button.pressed.connect(saves_requested.emit)
	Icons.apply_button(_settings_button, "settings", "Settings")
	_settings_button.pressed.connect(settings_requested.emit)
	Icons.apply_button(_menu_button, "menu", "Menu")
	_menu_button.pressed.connect(menu_requested.emit)
	EventBus.settings_changed.connect(_on_settings_changed)
	EventBus.key_checked.connect(_on_key_checked)
	EventBus.order_progress_changed.connect(_on_order_progress_changed)
	_frames = Icons.spinner_frames()
	set_process(false)
	_refresh_key_status()
	_refresh_order()
	(_tabs.get_child(0) as Button).button_pressed = true
	_show_page(0)


func _show_page(index: int) -> void:
	var pages: Array[Node] = _pages.get_children()
	for i: int in pages.size():
		(pages[i] as Control).visible = i == index


func _on_settings_changed() -> void:
	_verdict = ""
	_refresh_key_status()


func _on_key_checked(state: String, detail: String) -> void:
	_verdict = state
	_detail = detail
	_refresh_key_status()


## Animates the checking spinner while a check is pending (the process only runs then).
func _process(delta: float) -> void:
	_spin_time += delta
	_key_badge.texture = _frames[int(_spin_time / ChipIndicator.FRAME_SECONDS) % _frames.size()]


## Hidden for providers without a key. Otherwise a key icon with a badge: "!" missing, spinner being checked,
## check accepted, cross rejected, "?" could not be verified. Hover for the explanation.
func _refresh_key_status() -> void:
	_key_status.visible = Settings.ENV_VARS.has(Settings.provider)
	set_process(false)
	if not _key_status.visible:
		return
	var badge: String = "checking"
	var text: String = "Checking the API key..."
	if Settings.needs_api_key():
		badge = "warn"
		text = "No active API key: AI chips cannot reach the LLM. Add one in Settings."
	elif _verdict == "valid":
		badge = "applied"
		text = "API key verified."
	elif _verdict == "invalid":
		badge = "failed"
		text = "API key rejected (%s). Fix it in Settings." % _detail
	elif _verdict == "error":
		badge = "unknown"
		text = "Could not verify the API key (%s)." % _detail
	Icons.apply(_key_icon, "key", text)
	Icons.apply(_key_badge, badge, text)
	_key_status.tooltip_text = text
	_spin_time = 0.0
	set_process(badge == "checking")


func _on_order_progress_changed(_product: String, _progress: int, _quantity: int, _reward: int) -> void:
	_refresh_order()


## Compact, icon-first order display: the ordered resource's own art, "progress/quantity", and the
## reward as a coin icon plus number. Hidden before the first order starts (main menu, no game yet).
func _refresh_order() -> void:
	_order_status.visible = GameState.order_product != ""
	if not _order_status.visible:
		return
	var item: ItemData = ItemCatalog.shared().get_item(GameState.order_product)
	var item_name: String = GameState.order_product if item == null else item.display_name
	var hint: String = "Order: %d / %d %s (reward %d money on completion)" % [GameState.order_progress, GameState.order_quantity, item_name, GameState.order_reward]
	_order_icon.texture = null if item == null else item.icon
	_order_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_order_icon.custom_minimum_size = Vector2(ORDER_ICON_PX, ORDER_ICON_PX)
	_order_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_order_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_order_icon.tooltip_text = hint
	_order_progress_label.text = "%d/%d" % [GameState.order_progress, GameState.order_quantity]
	_order_progress_label.tooltip_text = hint
	Icons.apply(_order_reward_icon, "money", hint)
	_order_reward_label.text = str(GameState.order_reward)
	_order_reward_label.tooltip_text = hint
