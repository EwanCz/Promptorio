extends Node
## Root script: toggles the Bar with the `toggle_bar` action.

@onready var _bar: Control = %Bar


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_bar"):
		_bar.visible = not _bar.visible
		get_viewport().set_input_as_handled()
