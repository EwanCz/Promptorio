extends "res://tests/test_case.gd"
## PixelButton: pack art when the three images exist, a text fallback otherwise.

var _button: PixelButton


func after_each() -> void:
	if _button != null:
		_button.free()
		_button = null


func _make(base: String, fallback: String) -> PixelButton:
	_button = PixelButton.new()
	_button.texture_base = base
	_button.fallback_text = fallback
	tree.root.add_child(_button)
	return _button


func test_art_replaces_the_text() -> void:
	var button: PixelButton = _make("res://assets/pixel_art_buttons_pack/btn_play", "PLAY")
	check(button.has_art, "the Play images are found")
	check_eq(button.text, "", "the label is part of the image")
	check_eq(button.custom_minimum_size, PixelButton.BUTTON_SIZE, "the art is drawn 4x bigger")
	check(button.get_theme_stylebox("normal") is StyleBoxTexture, "the normal state is a texture")
	check(button.get_theme_stylebox("hover") != button.get_theme_stylebox("normal"), "hover has its own image")
	check(button.get_theme_stylebox("pressed") is StyleBoxTexture, "so does pressed")


func test_pause_pack_art_is_found_too() -> void:
	for name: String in ["resume", "restart", "main_menu"]:
		var button: PixelButton = _make("res://assets/pixel_ui_pack/pause_" + name, name)
		check(button.has_art, "pause_%s has its images" % name)
		button.free()
		_button = null


func test_missing_art_falls_back_to_text() -> void:
	var button: PixelButton = _make("res://assets/pixel_art_buttons_pack/btn_no_such_button", "CHIPS")
	check(not button.has_art, "no images")
	check_eq(button.text, "CHIPS", "the fallback text shows")
	check(button.get_theme_stylebox("normal") is StyleBoxFlat, "in a flat box")
	check_eq(button.custom_minimum_size, PixelButton.BUTTON_SIZE, "at the same size")
