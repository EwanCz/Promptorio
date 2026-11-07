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


func build_request(_system_prompt: String, _state: Dictionary, _tools: Array) -> Dictionary:
	return {"url": "", "headers": [], "body": {}}


## A free, authenticated request that only succeeds with a valid key (list models). Empty when no key is needed.
func build_check_request() -> Dictionary:
	return {}


func parse_response(_body: Dictionary) -> Array[Dictionary]:
	return []
