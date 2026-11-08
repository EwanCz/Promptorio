class_name BarPanel
extends PanelContainer
## Right-hand Bar: one named button per page in `Pages`, plus the settings button.

signal settings_requested
signal saves_requested

var _verdict: String = ""
var _detail: String = ""

@onready var _key_status: PanelContainer = %KeyStatus
@onready var _key_label: Label = %KeyStatusLabel
@onready var _tabs: HFlowContainer = %PageTabs
@onready var _pages: Control = %Pages
@onready var _saves_button: Button = %SavesButton
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
	_saves_button.pressed.connect(saves_requested.emit)
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


## Hidden for providers without a key; otherwise says whether the key is missing, being checked,
## accepted, rejected, or could not be verified.
func _refresh_key_status() -> void:
	_key_status.visible = Settings.ENV_VARS.has(Settings.provider)
	if not _key_status.visible:
		return
	var text: String = "Checking the API key..."
	var tint: Color = Color(0.7, 0.7, 0.7)
	if Settings.needs_api_key():
		text = "No active API key: AI chips cannot reach the LLM. Add one in Settings."
		tint = Color(1, 0.55, 0.1)
	elif _verdict == "valid":
		text = "API key verified."
		tint = Color(0.35, 0.8, 0.35)
	elif _verdict == "invalid":
		text = "API key rejected (%s). Fix it in Settings." % _detail
		tint = Color(0.9, 0.25, 0.25)
	elif _verdict == "error":
		text = "Could not verify the API key (%s)." % _detail
		tint = Color(1, 0.55, 0.1)
	_key_label.text = text
	_key_status.self_modulate = tint
