class_name SettingsDialog
extends PanelContainer
## Edits Settings: provider, then that provider's API key and model (and the Anthropic base URL). Keys are never logged or printed.
## A key from .env is not shown: the empty key field says it is in use, and saving never copies it to disk.

const PROVIDERS: Array[String] = ["mock", "anthropic", "codex"]

@onready var _provider_picker: OptionButton = %ProviderPicker
@onready var _credentials: Control = %Credentials
@onready var _key_edit: LineEdit = %KeyEdit
@onready var _base_url: Control = %BaseUrl
@onready var _base_url_edit: LineEdit = %BaseUrlEdit
@onready var _model_picker: OptionButton = %ModelPicker
@onready var _save_button: Button = %SaveButton
@onready var _close_button: Button = %CloseButton


func _ready() -> void:
	visible = false
	for provider: String in PROVIDERS:
		_provider_picker.add_item(provider)
	_provider_picker.item_selected.connect(_on_provider_selected)
	_save_button.pressed.connect(_on_save_pressed)
	_close_button.pressed.connect(close)


func open() -> void:
	_provider_picker.select(maxi(PROVIDERS.find(Settings.provider), 0))
	_load_provider(PROVIDERS[_provider_picker.selected])
	visible = true


func close() -> void:
	visible = false


## Shows the saved key and model of a provider. The mock provider has neither.
func _load_provider(provider: String) -> void:
	_credentials.visible = Settings.MODELS.has(provider)
	_key_edit.text = Settings.get_saved_api_key(provider)
	_key_edit.placeholder_text = "using the key from .env" if Settings.get_key_source(provider) == ".env" else "API key"
	_base_url.visible = provider == "anthropic"
	_base_url_edit.text = Settings.anthropic_base_url
	_model_picker.clear()
	var models: Array = Settings.MODELS.get(provider, [])
	for model_name: String in models:
		_model_picker.add_item(model_name)
	var current: String = Settings.get_model(provider)
	if current != "" and not models.has(current):
		_model_picker.add_item(current)
	if _model_picker.item_count > 0:
		_model_picker.select(_find_model(current))


func _find_model(model_name: String) -> int:
	for i: int in _model_picker.item_count:
		if _model_picker.get_item_text(i) == model_name:
			return i
	return 0


func _on_provider_selected(index: int) -> void:
	_load_provider(PROVIDERS[index])


func _on_save_pressed() -> void:
	var provider: String = PROVIDERS[_provider_picker.selected]
	Settings.provider = provider
	if Settings.MODELS.has(provider) and _model_picker.item_count > 0:
		Settings.set_provider_config(provider, _key_edit.text.strip_edges(), _model_picker.get_item_text(_model_picker.selected))
	if provider == "anthropic":
		Settings.anthropic_base_url = _base_url_edit.text.strip_edges()
	Settings.save_settings()
	close()
