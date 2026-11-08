extends "res://scripts/llm/llm_manager.gd"
## Test double installed over the LLMManager autoload by the runner: the mock provider answers after a short
## random delay (still asynchronous, still a timer) instead of 0.3-1.5 s. Every other provider is untouched.

const MIN_LATENCY: float = 0.01
const MAX_LATENCY: float = 0.05


class FastMock extends MockProvider:
	func simulated_latency() -> float:
		return randf_range(MIN_LATENCY, MAX_LATENCY)


func _make_provider() -> LLMProvider:
	if Settings.provider == "mock":
		return FastMock.new()
	return super._make_provider()
