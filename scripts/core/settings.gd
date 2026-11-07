extends Node
## Player settings, persisted in user://settings.cfg. Never log or print api_key.

const PATH: String = "user://settings.cfg"
const SECTION: String = "llm"

var api_key: String = ""
var provider: String = "mock"
var model: String = "claude-haiku-5-5"
var max_concurrency: int = 4
var request_timeout: float = 20.0
var chip_cooldown: float = 5.0
var max_tokens: int = 300


func _ready() -> void:
	load_settings()


func load_settings() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	api_key = cfg.get_value(SECTION, "api_key", api_key)
	provider = cfg.get_value(SECTION, "provider", provider)
	model = cfg.get_value(SECTION, "model", model)
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
	cfg.set_value(SECTION, "max_concurrency", max_concurrency)
	cfg.set_value(SECTION, "request_timeout", request_timeout)
	cfg.set_value(SECTION, "chip_cooldown", chip_cooldown)
	cfg.set_value(SECTION, "max_tokens", max_tokens)
	if cfg.save(PATH) != OK:
		push_warning("Settings: could not save %s" % PATH)
	EventBus.settings_changed.emit()
