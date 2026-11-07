class_name BarPanel
extends PanelContainer
## Right-hand Bar: one named button per page in `Pages`, plus the settings button.

signal settings_requested

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
	(_tabs.get_child(0) as Button).button_pressed = true
	_show_page(0)


func _show_page(index: int) -> void:
	var pages: Array[Node] = _pages.get_children()
	for i: int in pages.size():
		(pages[i] as Control).visible = i == index
