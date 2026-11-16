extends RefCounted

const FONT: FontFile = preload("res://ui/clash_pixel.fnt")
# one ui pixel is U screen pixels
const U := 2.0
const GLYPH_H := 7

const INK := Color(0.102, 0.086, 0.125)
const WELL := Color(0.227, 0.204, 0.259)
const PAPER := Color(0.945, 0.89, 0.741)
const PAPER_LIGHT := Color(1.0, 0.969, 0.878)
const PAPER_DARK := Color(0.827, 0.749, 0.561)
const MUTED := Color(0.502, 0.427, 0.302)
const BLUE := Color(0.184, 0.498, 0.839)
const RED := Color(0.839, 0.251, 0.184)
const GREEN := Color(0.247, 0.62, 0.184)
const GOLD := Color(0.949, 0.698, 0.114)
const GOLD_DARK := Color(0.71, 0.486, 0.055)
const ORANGE := Color(0.91, 0.475, 0.102)
const NONE := Color(0, 0, 0, 0)

static var _dither_tex: ImageTexture = null


static func setup() -> void:
	# pixel fonts only scale by whole numbers
	var font: FontFile = FONT
	font.fixed_size_scale_mode = TextServer.FIXED_SIZE_SCALE_INTEGER_ONLY
	font.antialiasing = TextServer.FONT_ANTIALIASING_NONE


static func snap(value: float) -> float:
	return roundf(value / U) * U


static func text_width(msg: String, scale: int) -> float:
	if msg.is_empty():
		return 0.0
	return FONT.get_string_size(msg, HORIZONTAL_ALIGNMENT_LEFT, -1, 8 * scale).x - scale


static func text(ci: CanvasItem, pos: Vector2, msg: String, scale: int, color: Color, outline := NONE) -> void:
	var base := Vector2(roundf(pos.x), roundf(pos.y) + GLYPH_H * scale)
	if outline.a > 0.0:
		var o := float(mini(scale, 4))
		for dy in [-1, 0, 1]:
			for dx in [-1, 0, 1]:
				if dx != 0 or dy != 0:
					ci.draw_string(FONT, base + Vector2(dx, dy) * o, msg, HORIZONTAL_ALIGNMENT_LEFT, -1, 8 * scale, outline)
	ci.draw_string(FONT, base, msg, HORIZONTAL_ALIGNMENT_LEFT, -1, 8 * scale, color)


static func text_centered(ci: CanvasItem, center_x: float, top: float, msg: String, scale: int, color: Color, outline := NONE) -> void:
	text(ci, Vector2(snap(center_x - text_width(msg, scale) * 0.5), top), msg, scale, color, outline)


static func text_right(ci: CanvasItem, right_x: float, top: float, msg: String, scale: int, color: Color, outline := NONE) -> void:
	text(ci, Vector2(right_x - text_width(msg, scale), top), msg, scale, color, outline)


static func shadow_text(ci: CanvasItem, pos: Vector2, msg: String, scale: int, color: Color, shadow: Color) -> void:
	text(ci, pos + Vector2(scale, scale), msg, scale, shadow)
	text(ci, pos, msg, scale, color)


static func panel(ci: CanvasItem, r: Rect2, fill := PAPER, outline := INK, bevel := true) -> void:
	ci.draw_rect(Rect2(r.position.x + U, r.position.y, r.size.x - U * 2.0, r.size.y), outline)
	ci.draw_rect(Rect2(r.position.x, r.position.y + U, r.size.x, r.size.y - U * 2.0), outline)
	var inner := r.grow(-U)
	ci.draw_rect(inner, fill)
	if bevel:
		ci.draw_rect(Rect2(inner.position, Vector2(inner.size.x, U)), fill.lightened(0.4))
		ci.draw_rect(Rect2(inner.position.x, inner.end.y - U, inner.size.x, U), fill.darkened(0.16))


static func button(ci: CanvasItem, r: Rect2, label: String, hovered: bool, pressed: bool, scale := 2) -> void:
	panel(ci, r, GOLD_DARK, INK, false)
	var inner := r.grow(-U)
	var drop := U if pressed else 0.0
	var face := Rect2(inner.position.x, inner.position.y + drop, inner.size.x, inner.size.y - U * 2.0)
	var color := GOLD.lightened(0.3) if hovered else GOLD
	ci.draw_rect(face, color)
	ci.draw_rect(Rect2(face.position, Vector2(face.size.x, U)), color.lightened(0.45))
	var ty := snap(face.position.y + (face.size.y - GLYPH_H * scale) * 0.5)
	text_centered(ci, face.get_center().x, ty, label, scale, INK)


static func keycap(ci: CanvasItem, pos: Vector2, label: String) -> float:
	var w := text_width(label, 2) + 12.0
	var r := Rect2(pos, Vector2(w, 24.0))
	panel(ci, r, PAPER_DARK, INK, false)
	ci.draw_rect(Rect2(r.position.x + U, r.position.y + U, w - U * 2.0, 24.0 - U * 4.0), PAPER_LIGHT)
	text(ci, pos + Vector2(6, 4), label, 2, INK)
	return w


static func tag(ci: CanvasItem, pos: Vector2, label: String, fill: Color, ink := INK) -> float:
	var w := text_width(label, 2) + 8.0
	ci.draw_rect(Rect2(pos, Vector2(w, 18.0)), fill)
	text(ci, pos + Vector2(4, 2), label, 2, ink)
	return w


static func bar(ci: CanvasItem, r: Rect2, frac: float, fill: Color) -> void:
	ci.draw_rect(r, INK)
	var inner := r.grow(-U)
	ci.draw_rect(inner, WELL)
	var w := snap(inner.size.x * clampf(frac, 0.0, 1.0))
	if w > 0.0:
		ci.draw_rect(Rect2(inner.position, Vector2(w, inner.size.y)), fill)
		ci.draw_rect(Rect2(inner.position, Vector2(w, U)), fill.lightened(0.4))


static func dither(ci: CanvasItem, r: Rect2) -> void:
	if _dither_tex == null:
		var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
		for y in 4:
			for x in 4:
				var on := (x / 2 + y / 2) % 2 == 0
				img.set_pixel(x, y, Color(INK, 0.92 if on else 0.6))
		_dither_tex = ImageTexture.create_from_image(img)
	ci.draw_texture_rect(_dither_tex, r, true)
