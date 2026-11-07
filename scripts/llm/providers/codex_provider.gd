class_name CodexProvider
extends LLMProvider
## OpenAI Responses API (Codex models). Forces tool use; the API key comes only from Settings.

const URL: String = "https://api.openai.com/v1/responses"


func build_request(system_prompt: String, state: Dictionary, tools: Array) -> Dictionary:
	return {
		"url": URL,
		"headers": [
			"content-type: application/json",
			"authorization: Bearer %s" % Settings.codex_api_key,
		],
		"body": {
			"model": Settings.codex_model,
			"max_output_tokens": Settings.max_tokens,
			"instructions": system_prompt,
			"input": JSON.stringify(state),
			"tools": _convert_tools(tools),
			"tool_choice": "required",
		},
	}


func parse_response(body: Dictionary) -> Array[Dictionary]:
	var calls: Array[Dictionary] = []
	var output: Variant = body.get("output", [])
	if typeof(output) != TYPE_ARRAY:
		return calls
	for item: Variant in output:
		if typeof(item) != TYPE_DICTIONARY or item.get("type", "") != "function_call":
			continue
		var json: JSON = JSON.new()
		var args: Variant = json.data if json.parse(str(item.get("arguments", ""))) == OK else null
		calls.append({"name": str(item.get("name", "")), "args": args if typeof(args) == TYPE_DICTIONARY else {}})
	return calls


## Anthropic-style schemas to Responses API function tools. Every property is required.
func _convert_tools(tools: Array) -> Array[Dictionary]:
	var converted: Array[Dictionary] = []
	for tool: Dictionary in tools:
		var schema: Dictionary = tool.get("input_schema", {"type": "object", "properties": {}}).duplicate(true)
		schema["required"] = schema.get("properties", {}).keys()
		converted.append({
			"type": "function",
			"name": tool.get("name", ""),
			"description": tool.get("description", ""),
			"parameters": schema,
		})
	return converted
