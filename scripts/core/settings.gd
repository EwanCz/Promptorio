extends Node
## Player settings, persisted in user://settings.cfg. Never log or print api_key or codex_api_key.
## A dev key can also come from a .env file (dev-only: read in the editor, never saved to settings.cfg).

const PATH: String = "user://settings.cfg"
const SECTION: String = "llm"
## .env variable holding each provider's key.
const ENV_VARS: Dictionary = {"anthropic": "ANTHROPIC_API_KEY", "codex": "OPENAI_API_KEY"}
## Optional dev override of the Anthropic origin, from the process environment or .env.
const BASE_URL_VAR: String = "ANTHROPIC_BASE_URL"
## Models offered per provider in the settings dialog.
const MODELS: Dictionary = {
	"anthropic": ["claude-haiku-5-5", "claude-sonnet-5-5", "claude-opus-5-5"],
	"codex": ["gpt-6.1-terra", "gpt-5.1-codex-mini", "gpt-5.6-luna", "gpt-6-luna", "codex-auto-review"],
}

var api_key: String = ""
var provider: String = "mock"
var model: String = "claude-haiku-5-5"
## Optional Anthropic-compatible relay origin entered in the Settings dialog. Blank: official endpoint.
var anthropic_base_url: String = ""
var codex_api_key: String = ""
var codex_model: String = "gpt-6.1-terra"
var max_concurrency: int = 4
var request_timeout: float = 20.0
var chip_cooldown: float = 5.0
var max_tokens: int = 300
## Dev key file at the project root. Tests point it elsewhere.
var env_path: String = "res://.env"

## Whether dev-only overrides (the Anthropic base URL) apply. Tests flip it to act like an export.
var editor_run: bool = OS.has_feature("editor")

var _env: Dictionary = {}


func _ready() -> void:
	load_settings()
	if OS.has_feature("editor"):
		load_env()


## The key the game sends for a provider: the one saved from the Settings dialog, else the .env one.
## Empty for the mock provider or when neither is set.
func get_api_key(provider_name: String) -> String:
	var saved: String = get_saved_api_key(provider_name)
	return saved if saved != "" else _get_env_key(provider_name)


## Anthropic relay origin, trailing slashes trimmed: the saved in-game setting, then (editor runs only)
## the process environment, then .env. "" means the official endpoint. Not validated here (see AnthropicProvider).
func get_anthropic_base_url() -> String:
	var value: String = anthropic_base_url.strip_edges()
	if value == "" and editor_run:
		value = OS.get_environment(BASE_URL_VAR).strip_edges()
		if value == "":
			value = str(_env.get(BASE_URL_VAR, "")).strip_edges()
	return value.rstrip("/")


## Only the key entered in the Settings dialog (what the dialog edits and what is saved to disk).
func get_saved_api_key(provider_name: String) -> String:
	match provider_name:
		"anthropic":
			return api_key
		"codex":
			return codex_api_key
	return ""


## Where get_api_key() comes from: "settings", ".env" or "" when there is no key.
func get_key_source(provider_name: String) -> String:
	if get_saved_api_key(provider_name) != "":
		return "settings"
	return ".env" if _get_env_key(provider_name) != "" else ""


## True when the selected provider calls a real API but no key is available (the mock needs none).
func needs_api_key() -> bool:
	return ENV_VARS.has(provider) and get_api_key(provider) == ""


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
	anthropic_base_url = cfg.get_value(SECTION, "anthropic_base_url", anthropic_base_url)
	codex_api_key = cfg.get_value(SECTION, "codex_api_key", codex_api_key)
	codex_model = cfg.get_value(SECTION, "codex_model", codex_model)
	max_concurrency = clampi(cfg.get_value(SECTION, "max_concurrency", max_concurrency), 1, 16)
	request_timeout = clampf(cfg.get_value(SECTION, "request_timeout", request_timeout), 1.0, 120.0)
	chip_cooldown = clampf(cfg.get_value(SECTION, "chip_cooldown", chip_cooldown), 0.0, 600.0)
	max_tokens = clampi(cfg.get_value(SECTION, "max_tokens", max_tokens), 16, 300)
	EventBus.settings_changed.emit()


## Reads `KEY=value` lines (blank lines and `#` comments skipped, optional `export `, optional quotes)
## from env_path. A missing file just means no .env keys. Nothing read here is ever saved or logged.
func load_env() -> void:
	_env.clear()
	var file: FileAccess = FileAccess.open(env_path, FileAccess.READ)
	if file == null:
		return
	while not file.eof_reached():
		var line: String = file.get_line().strip_edges().trim_prefix("export ")
		var equals: int = line.find("=")
		if line.begins_with("#") or equals <= 0:
			continue
		var value: String = line.substr(equals + 1).strip_edges()
		if value.length() >= 2 and value[0] in "\"'" and value[-1] == value[0]:
			value = value.substr(1, value.length() - 2)
		_env[line.substr(0, equals).strip_edges()] = value


func save_settings() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	cfg.set_value(SECTION, "api_key", api_key)
	cfg.set_value(SECTION, "provider", provider)
	cfg.set_value(SECTION, "model", model)
	cfg.set_value(SECTION, "anthropic_base_url", anthropic_base_url)
	cfg.set_value(SECTION, "codex_api_key", codex_api_key)
	cfg.set_value(SECTION, "codex_model", codex_model)
	cfg.set_value(SECTION, "max_concurrency", max_concurrency)
	cfg.set_value(SECTION, "request_timeout", request_timeout)
	cfg.set_value(SECTION, "chip_cooldown", chip_cooldown)
	cfg.set_value(SECTION, "max_tokens", max_tokens)
	if cfg.save(PATH) != OK:
		push_warning("Settings: could not save %s" % PATH)
	EventBus.settings_changed.emit()


func _get_env_key(provider_name: String) -> String:
	return str(_env.get(ENV_VARS.get(provider_name, ""), ""))
