extends "res://scripts/llm/llm_manager.gd"
## Test double: an LLMManager whose HTTP layer replays scripted responses (the last one repeats)
## and whose 429 backoff records the requested delays instead of waiting.

var responses: Array[Dictionary] = []
var sent: int = 0
var delays: Array[float] = []


func _send(_request: Dictionary) -> Dictionary:
	sent += 1
	return responses.pop_front() if responses.size() > 1 else responses[0]


func _wait_backoff(seconds: float) -> void:
	delays.append(seconds)
