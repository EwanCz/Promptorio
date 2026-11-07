class_name BarPanel
extends PanelContainer
## Right-hand Bar: one tab per page in `Pages`, plus the settings button.

signal settings_requested

@onready var _tabs: TabBar = %PageTabs
@onready var _pages: Control = %Pages
@onready var _settings_button: Button = %SettingsButton


func _ready() -> void:
	for page: Node in _pages.get_children():
		_tabs.add_tab(page.name.capitalize().trim_suffix(" Page"))
	_tabs.tab_changed.connect(_show_page)
	_settings_button.pressed.connect(settings_requested.emit)
	_show_page(_tabs.current_tab)


func _show_page(index: int) -> void:
	var pages: Array[Node] = _pages.get_children()
	for i: int in pages.size():
		(pages[i] as Control).visible = i == index
