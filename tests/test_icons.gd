extends "res://tests/test_case.gd"
## The pixel-art icon set.


func _data(texture: Texture2D) -> PackedByteArray:
	return texture.get_image().get_data()


func test_every_icon_is_12_by_12_and_not_empty() -> void:
	for icon_name: String in Icons.names():
		var image: Image = Icons.icon(icon_name).get_image()
		check_eq(image.get_size(), Vector2i(Icons.SIZE, Icons.SIZE), "%s size" % icon_name)
		var opaque: int = 0
		for y: int in Icons.SIZE:
			for x: int in Icons.SIZE:
				opaque += 1 if image.get_pixel(x, y).a > 0.0 else 0
		check(opaque > 10, "%s draws something" % icon_name)


func test_icons_are_distinct() -> void:
	var seen: Dictionary = {}
	for icon_name: String in Icons.names():
		var data: PackedByteArray = _data(Icons.icon(icon_name))
		check(not seen.has(data), "%s differs from %s" % [icon_name, seen.get(data, "-")])
		seen[data] = icon_name


func test_glyph_grids_are_well_formed() -> void:
	for glyph: String in Icons.GLYPHS:
		var rows: Array = Icons.GLYPHS[glyph]
		check_eq(rows.size(), 8, "%s has 8 rows" % glyph)
		for row: String in rows:
			check_eq(row.length(), 8, "%s rows are 8 wide" % glyph)
	check_eq(Icons.KEY.size(), Icons.SIZE, "key rows")
	for row: String in Icons.KEY:
		check_eq(row.length(), Icons.SIZE, "key row width")
	for icon_name: String in Icons.BADGES:
		check(Icons.FILLS.has(Icons.BADGES[icon_name][0]) and Icons.GLYPHS.has(Icons.BADGES[icon_name][1]), "%s uses known parts" % icon_name)


func test_spinner_frames_all_differ() -> void:
	var frames: Array[Texture2D] = Icons.spinner_frames()
	check_eq(frames.size(), Icons.SPINNER_FRAMES, "frame count")
	var seen: Dictionary = {}
	for frame: Texture2D in frames:
		seen[_data(frame)] = true
	check_eq(seen.size(), Icons.SPINNER_FRAMES, "every frame is different, so it animates")


func test_rect_sets_hover_text_and_pixel_filter() -> void:
	var with_hint: TextureRect = Icons.rect("failed", "Request failed")
	var without: TextureRect = Icons.rect("failed")
	check_eq(with_hint.tooltip_text, "Request failed", "hover text")
	check_eq(with_hint.mouse_filter, Control.MOUSE_FILTER_STOP, "can show the hover")
	check_eq(without.mouse_filter, Control.MOUSE_FILTER_IGNORE, "decoration does not catch the mouse")
	check_eq(with_hint.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST, "crisp pixels")
	check_eq(with_hint.custom_minimum_size, Vector2(Icons.SIZE * Icons.SCALE, Icons.SIZE * Icons.SCALE), "scaled up")
	with_hint.free()
	without.free()


func test_action_icons_make_square_buttons_with_a_hover() -> void:
	for icon_name: String in ["rotate", "destroy", "settings", "add", "ask", "log", "remove"]:
		var button: Button = Icons.button(icon_name, "hint %s" % icon_name)
		check(button.icon != null and button.icon.get_size() == Vector2(Icons.SIZE * Icons.SCALE, Icons.SIZE * Icons.SCALE), "%s icon is pre-scaled" % icon_name)
		check(button.text == "" and button.tooltip_text == "hint %s" % icon_name, "%s: icon only, with a hover" % icon_name)
		button.free()
