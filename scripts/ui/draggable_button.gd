class_name DraggableButton
extends Button
## A Build/Chip Registry button that still behaves like a plain Button (pressed signal, toggle_mode) but can
## also be dragged: starting a drag carries drag_payload to whatever Control accepts it (see FactoryView),
## with a small floating copy of this button's icon or text following the pointer.

## Carried to the drop target as-is. Empty: this button cannot be dragged.
var drag_payload: Dictionary = {}


func _get_drag_data(_at_position: Vector2) -> Variant:
	if drag_payload.is_empty():
		return null
	set_drag_preview(_make_preview())
	return drag_payload


func _make_preview() -> Control:
	var wrapper: Control = Control.new()
	wrapper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var content: Control
	if icon != null:
		var rect: TextureRect = TextureRect.new()
		rect.texture = icon
		rect.custom_minimum_size = icon.get_size()
		content = rect
	else:
		var label: Label = Label.new()
		label.text = text
		content = label
	content.modulate.a = 0.85
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrapper.add_child(content)
	content.position = -content.custom_minimum_size / 2.0 if content is TextureRect else Vector2.ZERO
	return wrapper
