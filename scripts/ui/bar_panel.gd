class_name BarPanel
extends PanelContainer
## Right-hand Bar: one named button per page in `Pages`, plus the settings button.

signal settings_requested

var _verdict: String = ""
var _detail: String = ""

@onready var _key_status: PanelContainer = %KeyStatus
@onready var _key_icon: TextureRect = %KeyIcon
@onready var _key_badge: TextureRect = %KeyBadge
@onready var _tabs: HFlowContainer = %PageTabs
@onready var _pages: Control = %Pages
@onready var _settings_button: Button = %SettingsButton


func _ready() -> void:
	var group: ButtonGroup = ButtonGroup.new()
	for page: Node in _pages.get_children():
		var button: Button = Button.new()
		button.text = page.name.trim_suffix("Page").capitalize()
		button.toggle_mode = true
		button.button_group = group
		button.pressed.connect(_show_page.bind(_tabs.get_child_count()))
		_tabs.add_child(button)
	_settings_button.pressed.connect(settings_requested.emit)
	EventBus.settings_changed.connect(_on_settings_changed)
	EventBus.key_checked.connect(_on_key_checked)
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


## Hidden for providers without a key. Otherwise a key icon with a badge: "!" missing, spinner being checked,
## check accepted, cross rejected, "?" could not be verified. Hover for the explanation.
func _refresh_key_status() -> void:
	_key_status.visible = Settings.ENV_VARS.has(Settings.provider)
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
