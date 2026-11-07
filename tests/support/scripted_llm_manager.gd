extends "res://scripts/llm/llm_manager.gd"
## Test double: an LLMManager whose HTTP layer replays scripted responses (the last one repeats).

var responses: Array[Dictionary] = []
var sent_msec: Array[int] = []


func _send(_request: Dictionary) -> Dictionary:
	sent_msec.append(Time.get_ticks_msec())
	return responses.pop_front() if responses.size() > 1 else responses[0]
