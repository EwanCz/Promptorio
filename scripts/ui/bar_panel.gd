class_name BarPanel
extends PanelContainer
## Right-hand Bar: one named button per page, plus resource, save, menu and settings controls.

signal resources_requested
signal settings_requested
signal saves_requested
signal menu_requested

var _verdict: String = ""
var _spin_time: float = 0.0
var _frames: Array[Texture2D] = []
var _detail: String = ""

@onready var _key_status: PanelContainer = %KeyStatus
@onready var _key_icon: TextureRect = %KeyIcon
@onready var _key_badge: TextureRect = %KeyBadge
@onready var _tabs: HFlowContainer = %PageTabs
@onready var _pages: Control = %Pages
@onready var _resources_button: Button = %ResourcesButton
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
	_resources_button.pressed.connect(resources_requested.emit)
	_saves_button.pressed.connect(saves_requested.emit)
	Icons.apply_button(_settings_button, "settings", "Settings")
	_settings_button.pressed.connect(settings_requested.emit)
	_menu_button.pressed.connect(menu_requested.emit)
	EventBus.settings_changed.connect(_on_settings_changed)
	EventBus.key_checked.connect(_on_key_checked)
	_frames = Icons.spinner_frames()
	set_process(false)
	_refresh_key_status()
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
