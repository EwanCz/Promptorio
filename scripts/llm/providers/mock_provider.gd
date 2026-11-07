class_name MockProvider
extends LLMProvider
## Offline provider: picks a random tool and random in-range args after a random delay.


func requires_network() -> bool:
	return false


func simulated_latency() -> float:
	return randf_range(0.3, 1.5)


func build_request(_system_prompt: String, _state: Dictionary, tools: Array) -> Dictionary:
	return {"url": "", "headers": [], "body": {"tools": tools}}


func parse_response(body: Dictionary) -> Array[Dictionary]:
	var calls: Array[Dictionary] = []
	var tools: Array = body.get("tools", [])
	if tools.is_empty():
		return calls
	var chosen: Dictionary = tools.pick_random()
	var schema: Dictionary = chosen.get("input_schema", {})
	calls.append({"name": chosen.get("name", ""), "args": _random_args(schema)})
	return calls


func _random_args(schema: Dictionary) -> Dictionary:
	var args: Dictionary = {}
	var props: Dictionary = schema.get("properties", {})
	for key: String in props:
		var prop: Dictionary = props[key]
		var kind: String = prop.get("type", "")
		match kind:
			"boolean":
				args[key] = randf() < 0.5
			"integer":
				args[key] = randi_range(int(prop.get("minimum", 0)), int(prop.get("maximum", 1)))
			"number":
				args[key] = randf_range(float(prop.get("minimum", 0.0)), float(prop.get("maximum", 1.0)))
	return args
