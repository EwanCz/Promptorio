class_name Icons
extends RefCounted
## Pixel-art status icons (12x12), drawn from the text grids below so they need no import step. Shown at
## SCALE with the nearest filter, like the 16 px machine art. Meaning is in the shape (a glyph on a colored
## badge), not only in the color. Use rect() in the UI: it adds the hover description.

const SIZE: int = 12
const SCALE: int = 2
const SPINNER_FRAMES: int = 8
const OUTLINE: Color = Color("14161c")
const WHITE: Color = Color("f4f6f8")
const FILLS: Dictionary = {
	"ok": Color("3fa34d"), "bad": Color("d6453d"), "warn": Color("e8912d"), "none": Color("7d8590"),
	"info": Color("4a8fd8"), "off": Color("4a4f57"), "coin": Color("e0b82e"),
}
## icon name -> [badge fill, glyph]. Glyphs are 8x8 and sit in the middle of the badge.
const BADGES: Dictionary = {
	"applied": ["ok", "check"],
	"none": ["none", "dash"],
	"failed": ["bad", "cross"],
	"info": ["info", "dot"],
	"warn": ["warn", "bang"],
	"unknown": ["warn", "question"],
	"blocked": ["bad", "dash"],
	"no_money": ["coin", "coin"],
	"state_normal": ["ok", "play"],
	"state_down": ["off", "cross"],
	"state_overheating": ["warn", "flame"],
	"state_paused": ["off", "pause"],
	"dir_right": ["info", "arrow_right"],
	"dir_down": ["info", "arrow_down"],
	"dir_left": ["info", "arrow_left"],
	"dir_up": ["info", "arrow_up"],
	"rotate": ["info", "rotate"],
	"destroy": ["bad", "trash"],
	"settings": ["none", "gear"],
	"menu": ["info", "home"],
	"resources": ["coin", "gem"],
	"save": ["ok", "tray"],
	"tools": ["warn", "hammer"],
	"add": ["ok", "plus"],
	"ask": ["warn", "bolt"],
	"log": ["none", "list"],
	"remove": ["warn", "dash"],
	"timer": ["info", "clock"],
	"money": ["ok", "coin"],
	"cooling_on": ["info", "snow"],
	"cooling_off": ["off", "snow"],
	"mode_fast": ["ok", "bolt"],
	"mode_normal": ["off", "bolt"],
}
const GLYPHS: Dictionary = {
	"check": ["........", "......#.", ".....##.", "#...##..", "##.##...", ".###....", "..#.....", "........"],
	"cross": ["........", ".#....#.", "..#..#..", "...##...", "...##...", "..#..#..", ".#....#.", "........"],
	"arrow_right": ["........", "...#....", "...##...", "########", "########", "...##...", "...#....", "........"],
	"arrow_down": ["...##...", "...##...", "...##...", ".######.", "..####..", "...##...", "...##...", "...##..."],
	"arrow_left": ["........", "....#...", "...##...", "########", "########", "...##...", "....#...", "........"],
	"arrow_up": ["...##...", "...##...", "...##...", "..####..", ".######.", "...##...", "...##...", "...##..."],
	"pause": ["........", ".##..##.", ".##..##.", ".##..##.", ".##..##.", ".##..##.", ".##..##.", "........"],
	"dash": ["........", "........", "........", ".######.", ".######.", "........", "........", "........"],
	"dot": ["...##...", "...##...", "........", "...##...", "...##...", "...##...", "...##...", "...##..."],
	"bang": ["...##...", "...##...", "...##...", "...##...", "...##...", "........", "...##...", "...##..."],
	"question": ["..####..", ".##..##.", ".....##.", "....##..", "...##...", "...##...", "........", "...##..."],
	"play": [".#......", ".###....", ".#####..", ".#######", ".#####..", ".###....", ".#......", "........"],
	"flame": ["....#...", "....##..", "...###..", "..#####.", ".#######", ".###.###", ".##...##", "..#####."],
	"rotate": ["..####..", ".#....#.", "#...###.", "#....#..", "#.......", "#......#", ".#....#.", "..####.."],
	"trash": ["..####..", "########", ".######.", ".#.##.#.", ".#.##.#.", ".#.##.#.", ".######.", "........"],
	"gear": [".#.##.#.", "########", ".##..##.", "###..###", "###..###", ".##..##.", "########", ".#.##.#."],
	"plus": ["........", "...##...", "...##...", ".######.", ".######.", "...##...", "...##...", "........"],
	"bolt": [".....##.", "....##..", "...##...", "..#####.", "....##..", "...##...", "..##....", ".##....."],
	"list": ["........", "##.#####", "........", "##.#####", "........", "##.#####", "........", "........"],
	"clock": ["..####..", ".#.##.#.", "#..##..#", "#..###.#", "#......#", "#......#", ".#....#.", "..####.."],
	"snow": ["...##...", "#.#..#.#", ".######.", "..####..", "..####..", ".######.", "#.#..#.#", "...##..."],
	"home": ["...##...", "..####..", ".######.", "########", ".######.", ".##..##.", ".##..##.", "........"],
	"gem": ["........", "..####..", ".#....#.", "########", ".#....#.", "..#..#..", "...##...", "........"],
	"hammer": ["..####..", ".######.", "..####..", "...##...", "...##...", "...##...", "...##...", "........"],
	"tray": ["...##...", "...##...", ".######.", "..####..", "...##...", "........", "#......#", "########"],
	"coin": ["..####..", ".##..##.", ".##.....", "..####..", ".....##.", ".##..##.", "..####..", "........"],
}
## The key drawn on its own, 12x12, in the coin color.
const KEY: Array = [
	"............", "..####......", ".#....#.....", ".#....#.....", ".#....#.....", "..####......",
	"....#.......", "....#.......", "....##......", "....#.......", "....##......", "............",
]
## Top-left of the 2x2 dots of the spinner, clockwise from the top.
const SPINNER_DOTS: Array[Vector2i] = [
	Vector2i(5, 1), Vector2i(8, 2), Vector2i(9, 5), Vector2i(8, 8),
	Vector2i(5, 9), Vector2i(2, 8), Vector2i(1, 5), Vector2i(2, 2),
]

## Pixel data by icon name. Raw bytes, not textures: a texture held in a static would leak at exit, so each
## caller gets its own texture.
static var _cache: Dictionary = {}


## Names of every icon except the spinner frames. "checking" is the first frame of the spinner.
static func names() -> Array[String]:
	var result: Array[String] = ["checking", "key"]
	for icon_name: String in BADGES:
		result.append(icon_name)
	return result


static func icon(icon_name: String) -> Texture2D:
	return _texture(icon_name, _build.bind(icon_name))


## The animation of "waiting for an answer".
static func spinner_frames() -> Array[Texture2D]:
	var frames: Array[Texture2D] = []
	for i: int in SPINNER_FRAMES:
		frames.append(_texture("spinner_%d" % i, _spinner.bind(i)))
	return frames


## A TextureRect showing the icon at SCALE, with `description` as its hover text.
static func rect(icon_name: String, description: String = "") -> TextureRect:
	var rect_node: TextureRect = TextureRect.new()
	apply(rect_node, icon_name, description)
	return rect_node


## The arrow icon for a facing (right, down, left or up).
static func direction(facing: Vector2i) -> String:
	if facing == Vector2i.DOWN:
		return "dir_down"
	if facing == Vector2i.LEFT:
		return "dir_left"
	if facing == Vector2i.UP:
		return "dir_up"
	return "dir_right"


## A thermometer for `fraction` (0..1) of its scale: the glass with a fill from the bulb up, green when
## cool, orange when hot, red when close to the top. Not cached (the fill changes).
static func thermometer(fraction: float) -> Texture2D:
	var image: Image = _blank()
	var level: int = roundi(clampf(fraction, 0.0, 1.0) * 7.0)
	var fill: Color = FILLS["ok"] if fraction < 0.4 else (FILLS["warn"] if fraction < 0.75 else FILLS["bad"])
	for y: int in range(1, 9):
		for x: int in range(4, 8):
			image.set_pixel(x, y, OUTLINE if x == 4 or x == 7 or y == 1 else (fill if 9 - y <= level else Color(0.2, 0.22, 0.26)))
	for y: int in range(9, 12):
		for x: int in range(3, 9):
			if not ((y == 9 or y == 11) and (x == 3 or x == 8)):
				image.set_pixel(x, y, fill if y > 9 or level > 0 else OUTLINE)
	return ImageTexture.create_from_image(image)


## A flat-looking icon-only Button (names are in the hover text). The icon is pre-scaled with the nearest
## filter, because a Button cannot scale its icon crisply.
static func button(icon_name: String, description: String) -> Button:
	var button_node: Button = Button.new()
	apply_button(button_node, icon_name, description)
	return button_node


## Turns an existing Button (e.g. one from a scene) into an icon-only button with a hover description.
static func apply_button(button_node: Button, icon_name: String, description: String) -> void:
	var image: Image = icon(icon_name).get_image()
	image.resize(SIZE * SCALE, SIZE * SCALE, Image.INTERPOLATE_NEAREST)
	button_node.icon = ImageTexture.create_from_image(image)
	button_node.text = ""
	button_node.tooltip_text = description
	button_node.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button_node.custom_minimum_size = Vector2(SIZE * SCALE + 6, SIZE * SCALE + 6)


## Sets an existing TextureRect (e.g. one from a scene) to the icon and its hover text.
static func apply(rect_node: TextureRect, icon_name: String, description: String = "") -> void:
	rect_node.texture = icon(icon_name)
	rect_node.tooltip_text = description
	rect_node.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	rect_node.custom_minimum_size = Vector2(SIZE * SCALE, SIZE * SCALE)
	rect_node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect_node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect_node.mouse_filter = Control.MOUSE_FILTER_STOP if description != "" else Control.MOUSE_FILTER_IGNORE


static func _build(icon_name: String) -> Image:
	if icon_name == "checking":
		return _spinner(0)
	if icon_name == "key":
		return _from_grid(KEY, FILLS["coin"])
	var spec: Array = BADGES[icon_name]
	return _badge(FILLS[spec[0]], GLYPHS[spec[1]])


## A fresh texture from the cached pixels of `key`, drawn by `draw` (returns an Image) the first time.
static func _texture(key: String, draw: Callable) -> Texture2D:
	if not _cache.has(key):
		_cache[key] = (draw.call() as Image).get_data()
	return ImageTexture.create_from_image(Image.create_from_data(SIZE, SIZE, false, Image.FORMAT_RGBA8, _cache[key]))


static func _blank() -> Image:
	return Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGBA8)


static func _from_grid(rows: Array, color: Color) -> Image:
	var image: Image = _blank()
	for y: int in SIZE:
		for x: int in SIZE:
			if (rows[y] as String)[x] == "#":
				image.set_pixel(x, y, color)
	return image


static func _badge(fill: Color, glyph: Array) -> Image:
	var image: Image = _blank()
	var center: float = (SIZE - 1) / 2.0
	for y: int in SIZE:
		for x: int in SIZE:
			var distance: float = Vector2(x - center, y - center).length()
			if distance <= 5.6:
				image.set_pixel(x, y, OUTLINE if distance > 4.6 else fill)
	var offset: int = (SIZE - 8) / 2
	for y: int in 8:
		for x: int in 8:
			if (glyph[y] as String)[x] == "#":
				image.set_pixel(x + offset, y + offset, WHITE)
	return image


static func _spinner(frame: int) -> Image:
	var image: Image = _blank()
	for i: int in SPINNER_FRAMES:
		var behind: int = posmod(frame - i, SPINNER_FRAMES)
		var color: Color = FILLS["off"]
		if behind == 0:
			color = WHITE
		elif behind == 1:
			color = FILLS["info"]
		elif behind == 2:
			color = FILLS["none"]
		var dot: Vector2i = SPINNER_DOTS[i]
		image.fill_rect(Rect2i(dot, Vector2i(2, 2)), color)
	return image
