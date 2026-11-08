class_name PixelButton
extends Button
## A pixel-art button whose label is part of its images. `texture_base` is the path without the state and
## size suffix: <base>_normal@8x.png, <base>_hover@8x.png and <base>_pressed@8x.png. When one is missing
## (a button whose art is not made yet) it is a plain text button showing `fallback_text` in the pack's colors.

## The art is 64x16 pixels, drawn 4 times bigger.
const BUTTON_SIZE: Vector2 = Vector2(256, 64)
const STATES: Array[String] = ["normal", "hover", "pressed"]
const FALLBACK_COLOR: Color = Color("2b2d42")
const FALLBACK_HOVER_COLOR: Color = Color("3d4166")
const FALLBACK_BORDER: Color = Color("6a7bd0")

@export var texture_base: String = ""
@export var fallback_text: String = ""

## True when the three images were found.
var has_art: bool = false


func _ready() -> void:
	custom_minimum_size = BUTTON_SIZE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var textures: Dictionary = _load_textures()
	has_art = textures.size() == STATES.size()
	if has_art:
		text = ""
		_apply_art(textures)
	else:
		text = fallback_text
		_apply_fallback()


func _load_textures() -> Dictionary:
	var textures: Dictionary = {}
	if texture_base == "":
		return textures
	for state: String in STATES:
		var path: String = "%s_%s@8x.png" % [texture_base, state]
		if ResourceLoader.exists(path):
			textures[state] = load(path)
	return textures


func _apply_art(textures: Dictionary) -> void:
	add_theme_stylebox_override("normal", _texture_box(textures["normal"]))
	add_theme_stylebox_override("hover", _texture_box(textures["hover"]))
	add_theme_stylebox_override("hover_pressed", _texture_box(textures["pressed"]))
	add_theme_stylebox_override("pressed", _texture_box(textures["pressed"]))
	add_theme_stylebox_override("focus", _texture_box(textures["hover"]))
	add_theme_stylebox_override("disabled", _texture_box(textures["normal"]))


func _apply_fallback() -> void:
	add_theme_stylebox_override("normal", _flat_box(FALLBACK_COLOR))
	add_theme_stylebox_override("hover", _flat_box(FALLBACK_HOVER_COLOR))
	add_theme_stylebox_override("pressed", _flat_box(FALLBACK_COLOR.darkened(0.4)))
	add_theme_stylebox_override("focus", _flat_box(FALLBACK_HOVER_COLOR))
	add_theme_font_size_override("font_size", 24)


func _texture_box(texture: Texture2D) -> StyleBoxTexture:
	var box: StyleBoxTexture = StyleBoxTexture.new()
	box.texture = texture
	return box


func _flat_box(color: Color) -> StyleBoxFlat:
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = color
	box.set_border_width_all(4)
	box.border_color = FALLBACK_BORDER
	return box
