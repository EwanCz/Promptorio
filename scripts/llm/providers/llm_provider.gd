class_name LLMProvider
extends RefCounted
## Base class for LLM providers. Only code in scripts/llm/providers/ knows wire formats.
##
## Tool schema (input to build_request), Anthropic-style:
##   {name: String, description: String, input_schema: {type: "object", properties: {...}}}
## Normalized tool call (output of parse_response): {name: String, args: Dictionary}


func requires_network() -> bool:
	return true


func simulated_latency() -> float:
	return 0.0


## A clear message when the provider is misconfigured and nothing may be sent, else "".
func config_error() -> String:
	return ""


## The relay origin configured for `provider_name` (Settings.get_base_url), else `official`.
func _origin(provider_name: String, official: String) -> String:
	var override: String = Settings.get_base_url(provider_name)
	return override if override != "" else official


## "" when the configured relay origin is usable. Only an https origin (host and optional port) passes:
## anything else could send the key somewhere unintended. The message never repeats the value.
## shortcut: no IPv6 literal hosts, use a hostname.
func _origin_error(provider_name: String, label: String) -> String:
	var override: String = Settings.get_base_url(provider_name)
	if override == "" or RegEx.create_from_string("^https://[A-Za-z0-9.-]+(:[0-9]{1,5})?$").search(override) != null:
		return ""
	return "the %s base URL must be an https origin such as https://relay.example.com (no path, query or credentials)" % label


func build_request(_system_prompt: String, _state: Dictionary, _tools: Array) -> Dictionary:
	return {"url": "", "headers": [], "body": {}}


## A free, authenticated request that only succeeds with a valid key (list models). Empty when no key is needed.
func build_check_request() -> Dictionary:
	return {}


func parse_response(_body: Dictionary) -> Array[Dictionary]:
	return []
