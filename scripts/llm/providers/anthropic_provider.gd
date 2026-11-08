class_name AnthropicProvider
extends LLMProvider
## Anthropic Messages API. Forces tool use; the API key comes only from Settings (or .env).

const OFFICIAL_ORIGIN: String = "https://api.anthropic.com"
const URL: String = OFFICIAL_ORIGIN + "/v1/messages"
const API_VERSION: String = "2023-06-01"


func config_error() -> String:
	return _origin_error("anthropic", "Anthropic")


func build_request(system_prompt: String, state: Dictionary, tools: Array) -> Dictionary:
	return {
		"url": _origin("anthropic", OFFICIAL_ORIGIN) + "/v1/messages",
		"headers": [
			"content-type: application/json",
			"x-api-key: %s" % Settings.get_api_key("anthropic"),
			"anthropic-version: %s" % API_VERSION,
		],
		"body": {
			"model": Settings.model,
			"max_tokens": Settings.max_tokens,
			"system": system_prompt,
			"messages": [{"role": "user", "content": JSON.stringify(state)}],
			"tools": tools,
			"tool_choice": {"type": "auto"},
		},
	}


func build_check_request() -> Dictionary:
	return {
		"method": HTTPClient.METHOD_GET,
		"url": _origin("anthropic", OFFICIAL_ORIGIN) + "/v1/models?limit=1",
		"headers": ["x-api-key: %s" % Settings.get_api_key("anthropic"), "anthropic-version: %s" % API_VERSION],
	}


func parse_response(body: Dictionary) -> Array[Dictionary]:
	var calls: Array[Dictionary] = []
	var content: Variant = body.get("content", [])
	if typeof(content) != TYPE_ARRAY:
		return calls
	for block: Variant in content:
		if typeof(block) != TYPE_DICTIONARY or block.get("type", "") != "tool_use":
			continue
		var args: Variant = block.get("input", {})
		calls.append({"name": str(block.get("name", "")), "args": args if typeof(args) == TYPE_DICTIONARY else {}})
	return calls
