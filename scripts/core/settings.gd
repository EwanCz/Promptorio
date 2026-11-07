extends Node
## Player settings, persisted in user://settings.cfg. Never log or print api_key or codex_api_key.

const PATH: String = "user://settings.cfg"
const SECTION: String = "llm"
## Models offered per provider in the settings dialog.
const MODELS: Dictionary = {
	"anthropic": ["claude-haiku-5-5", "claude-sonnet-5-5", "claude-opus-5-5"],
	"codex": ["gpt-6.1-terra", "gpt-5.1-codex-mini", "gpt-5.6-luna", "gpt-6-luna", "codex-auto-review"],
}

var api_key: String = ""
var provider: String = "mock"
var model: String = "claude-haiku-5-5"
var codex_api_key: String = ""
var codex_model: String = "gpt-6.1-terra"
var max_concurrency: int = 4
var request_timeout: float = 20.0
var chip_cooldown: float = 5.0
var max_tokens: int = 300


func _ready() -> void:
	load_settings()


## Key of a provider ("anthropic" or "codex"). Empty for any other provider.
func get_api_key(provider_name: String) -> String:
	match provider_name:
		"anthropic":
			return api_key
		"codex":
			return codex_api_key
	return ""


func get_model(provider_name: String) -> String:
	return codex_model if provider_name == "codex" else model


## Sets key and model of a provider without saving. Other providers are ignored.
func set_provider_config(provider_name: String, key: String, model_name: String) -> void:
	match provider_name:
		"anthropic":
			api_key = key
			model = model_name
		"codex":
			codex_api_key = key
			codex_model = model_name


func load_settings() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	api_key = cfg.get_value(SECTION, "api_key", api_key)
	provider = cfg.get_value(SECTION, "provider", provider)
	model = cfg.get_value(SECTION, "model", model)
	codex_api_key = cfg.get_value(SECTION, "codex_api_key", codex_api_key)
	codex_model = cfg.get_value(SECTION, "codex_model", codex_model)
	max_concurrency = clampi(cfg.get_value(SECTION, "max_concurrency", max_concurrency), 1, 16)
	request_timeout = clampf(cfg.get_value(SECTION, "request_timeout", request_timeout), 1.0, 120.0)
	chip_cooldown = clampf(cfg.get_value(SECTION, "chip_cooldown", chip_cooldown), 0.0, 600.0)
	max_tokens = clampi(cfg.get_value(SECTION, "max_tokens", max_tokens), 16, 300)
	EventBus.settings_changed.emit()


func save_settings() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	cfg.set_value(SECTION, "api_key", api_key)
	cfg.set_value(SECTION, "provider", provider)
	cfg.set_value(SECTION, "model", model)
	cfg.set_value(SECTION, "codex_api_key", codex_api_key)
	cfg.set_value(SECTION, "codex_model", codex_model)
	cfg.set_value(SECTION, "max_concurrency", max_concurrency)
	cfg.set_value(SECTION, "request_timeout", request_timeout)
	cfg.set_value(SECTION, "chip_cooldown", chip_cooldown)
	cfg.set_value(SECTION, "max_tokens", max_tokens)
	if cfg.save(PATH) != OK:
		push_warning("Settings: could not save %s" % PATH)
	EventBus.settings_changed.emit()
