extends CanvasLayer

const Weapons = preload("res://scripts/weapons.gd")
const UI = preload("res://scripts/pixel_ui.gd")

const WEAPON_ORDER := [Weapons.Type.GUN, Weapons.Type.SWORD, Weapons.Type.LAUNCHER]
const STAT_NAMES := ["HEALTH", "DAMAGE", "RANGE", "SPEED"]
const CONTROLS := [["WASD", "MOVE"], ["MOUSE", "AIM"], ["CLICK", "ATTACK"], ["SPACE", "SUPER"], ["ESC", "PAUSE"]]

var game: Node = null

var _canvas: Control
var _screen := "menu"
var _paused := false
var _selected := 0
# clickable rects, rebuilt every draw
var _hot := {}
var _hover := ""
var _pressed := ""
var _clock := 0.0

var _feed: Array = []
var _banner_text := ""
var _banner_age := 0.0
var _banner_life := 0.0
var _banner_color := Color.WHITE
var _textures := {}


func _ready() -> void:
	UI.setup()
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_canvas.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	_canvas.draw.connect(_on_draw)
	add_child(_canvas)


func _process(delta: float) -> void:
	_clock += delta
	if not get_tree().paused:
		for item in _feed:
			item["age"] += delta
		_feed = _feed.filter(func(item): return item["age"] < 5.0)
		_banner_age += delta
	Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND if _hover != "" else Input.CURSOR_ARROW)
	_canvas.queue_redraw()


func show_menu() -> void:
	_set_paused(false)
	_screen = "menu"
	_reset_overlays()


func show_match() -> void:
	_screen = "match"
	_reset_overlays()


func show_end() -> void:
	_screen = "end"
	_hover = ""


func banner(text: String, life: float, color: Color) -> void:
	_banner_text = text
	_banner_life = life
	_banner_age = 0.0
	_banner_color = color


func add_feed(killer, victim) -> void:
	var entry := {"age": 0.0, "victim": str(victim.fighter_name), "victim_color": _team_color(victim), "killer": "", "killer_color": UI.INK}
	if killer != null:
		entry["killer"] = str(killer.fighter_name)
		entry["killer_color"] = _team_color(killer)
	_feed.push_front(entry)
	if _feed.size() > 4:
		_feed.pop_back()


func _reset_overlays() -> void:
	_feed.clear()
	_banner_life = 0.0
	_hover = ""
	_pressed = ""


func _team_color(f) -> Color:
	if f.is_player:
		return UI.GREEN
	return UI.BLUE if f.team == game.local_team else UI.RED


func _set_paused(paused: bool) -> void:
	if paused and not game.is_playing():
		return
	_paused = paused
	get_tree().paused = paused


func _input(event: InputEvent) -> void:
	if game == null:
		return
	if event is InputEventMouseMotion:
		_hover = _hit(_canvas.get_local_mouse_position())
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var at := _hit(_canvas.get_local_mouse_position())
		if event.pressed:
			_pressed = at
		else:
			if at != "" and at == _pressed:
				_activate(at)
			_pressed = ""
	elif event is InputEventKey and event.pressed and not event.echo:
		_on_key(event.physical_keycode)


func _hit(point: Vector2) -> String:
	for id in _hot:
		var r: Rect2 = _hot[id]
		if r.has_point(point):
			return id
	return ""


func _activate(id: String) -> void:
	if id.begins_with("next"):
		_choose_next(int(id.trim_prefix("next")))
	elif id.begins_with("weapon"):
		_select(int(id.trim_prefix("weapon")))
	elif id == "fight":
		game.start_match(WEAPON_ORDER[_selected])
	elif id == "again" or id == "quit":
		game.show_menu()


func _select(index: int) -> void:
	var count := WEAPON_ORDER.size()
	_selected = (index % count + count) % count


func _on_key(key: int) -> void:
	match _screen:
		"menu":
			if key >= KEY_1 and key <= KEY_3:
				_select(key - KEY_1)
			elif key == KEY_UP or key == KEY_W:
				_select(_selected - 1)
			elif key == KEY_DOWN or key == KEY_S:
				_select(_selected + 1)
			elif key == KEY_ENTER or key == KEY_KP_ENTER:
				game.start_match(WEAPON_ORDER[_selected])
		"end":
			if key == KEY_ENTER or key == KEY_KP_ENTER:
				game.show_menu()
		"match":
			if key == KEY_ESCAPE or key == KEY_P:
				_set_paused(not _paused)
			elif key >= KEY_1 and key <= KEY_3:
				_choose_next(key - KEY_1)


func _on_draw() -> void:
	if game == null:
		return
	_hot.clear()
	var vs := _canvas.size
	match _screen:
		"menu":
			_draw_menu(vs)
		"match":
			_draw_overheads()
			_draw_scoreboard(vs)
			_draw_player(vs)
			_draw_feed(vs)
			_draw_banner(vs)
			if _paused:
				_draw_pause(vs)
		"end":
			_draw_end(vs)


func _tex(path: String) -> Texture2D:
	if not _textures.has(path):
		_textures[path] = load(path)
	return _textures[path]


func _weapon_sprite(wd: Dictionary, center: Vector2, zoom: int) -> void:
	var region: Rect2 = wd["region"]
	var size := region.size * zoom
	var pos := (center - size * 0.5).round()
	_canvas.draw_texture_rect_region(_tex(wd["tex"]), Rect2(pos, size), region)


func _pips(pos: Vector2, value: int, total: int) -> void:
	for k in total:
		var r := Rect2(pos.x + k * 16.0, pos.y + 1, 12, 12)
		_canvas.draw_rect(r, UI.INK)
		if k >= value:
			_canvas.draw_rect(r.grow(-UI.U), UI.PAPER_DARK)


func _draw_menu(vs: Vector2) -> void:
	var c := _canvas
	UI.dither(c, Rect2(Vector2.ZERO, vs))
	var w := 880.0
	var x0 := UI.snap((vs.x - w) * 0.5)
	var y0 := maxf(16.0, UI.snap((vs.y - 524.0) * 0.5))

	UI.shadow_text(c, Vector2(x0, y0), "CLASH PIT", 8, UI.PAPER_LIGHT, UI.INK)
	UI.text_right(c, x0 + w, y0 + 12, "3 V 3 KNOCKOUT", 2, UI.PAPER_LIGHT, UI.INK)
	UI.text_right(c, x0 + w, y0 + 34, "FIRST TEAM TO %d WINS" % game.SCORE_TO_WIN, 2, UI.GOLD, UI.INK)

	var top := y0 + 84.0
	var list := Rect2(x0, top, 328, 364)
	UI.panel(c, list)
	UI.text(c, list.position + Vector2(16, 14), "PICK A WEAPON", 2, UI.MUTED)
	for i in WEAPON_ORDER.size():
		var item: Dictionary = Weapons.DATA[WEAPON_ORDER[i]]
		var row := Rect2(list.position.x + 8, list.position.y + 40 + i * 104.0, list.size.x - 16, 100)
		var id := "weapon%d" % i
		_hot[id] = row
		var chosen := i == _selected
		if chosen:
			c.draw_rect(row, UI.INK)
		elif _hover == id:
			c.draw_rect(row, UI.PAPER_DARK)
		_weapon_sprite(item, Vector2(row.position.x + 70, row.get_center().y), 2)
		UI.text(c, Vector2(row.position.x + 140, row.position.y + 26), item["name"], 2, UI.PAPER_LIGHT if chosen else UI.INK)
		UI.keycap(c, Vector2(row.position.x + 140, row.position.y + 50), str(i + 1))
		if chosen:
			UI.text(c, Vector2(row.end.x - 22, row.position.y + 55), ">", 2, UI.GOLD)

	var det := Rect2(x0 + 344, top, w - 344, 364)
	UI.panel(c, det)
	var wd: Dictionary = Weapons.DATA[WEAPON_ORDER[_selected]]
	var well := Rect2(det.position + Vector2(16, 16), Vector2(216, 152))
	UI.panel(c, well, UI.PAPER_DARK, UI.INK, false)
	_weapon_sprite(wd, well.get_center(), 3)

	var tx := well.end.x + 20.0
	UI.text(c, Vector2(tx, det.position.y + 16), wd["name"], 3, UI.INK)
	var blurb: Array = wd["blurb"]
	for i in blurb.size():
		UI.text(c, Vector2(tx, det.position.y + 46 + i * 20.0), blurb[i], 2, UI.INK)
	var stats: Array = wd["stats"]
	for i in STAT_NAMES.size():
		var sy := det.position.y + 94.0 + i * 20.0
		UI.text(c, Vector2(tx, sy), STAT_NAMES[i], 2, UI.MUTED)
		_pips(Vector2(tx + 92, sy), int(stats[i]), 5)

	var line_y := well.end.y + 14.0
	c.draw_rect(Rect2(det.position.x + 16, line_y, det.size.x - 32, UI.U), UI.PAPER_DARK)
	var sx := det.position.x + 16.0
	var tag_w := UI.tag(c, Vector2(sx, line_y + 14), "SUPER", UI.GOLD)
	UI.text(c, Vector2(sx + tag_w + 10, line_y + 16), wd["super_name"], 2, UI.INK)
	UI.text(c, Vector2(sx, line_y + 40), wd["super_desc"], 2, UI.MUTED)

	var foot_y := det.end.y - 16.0
	UI.text(c, Vector2(sx, foot_y - game.DEFAULT_REGION.size.y - 22), "YOUR TEAM", 2, UI.MUTED)
	var slot := 0
	for cfg in game.ROSTER:
		if cfg["team"] != 0:
			continue
		var region: Rect2 = cfg.get("region", game.DEFAULT_REGION)
		var pos := Vector2(sx + slot * 54.0, foot_y - region.size.y)
		c.draw_texture_rect_region(_tex(cfg["tex"]), Rect2(pos, region.size), region)
		slot += 1

	var btn := Rect2(det.end.x - 16 - 208, det.end.y - 16 - 48, 208, 48)
	_hot["fight"] = btn
	UI.button(c, btn, "FIGHT", _hover == "fight", _pressed == "fight", 3)
	var key_w := UI.text_width("ENTER", 2) + 12.0
	UI.keycap(c, Vector2(btn.position.x - 12 - key_w, btn.position.y + 10), "ENTER")

	var ly := top + 364.0 + 20.0
	var lx := x0
	for pair in CONTROLS:
		lx += UI.keycap(c, Vector2(lx, ly), pair[0]) + 8.0
		UI.text(c, Vector2(lx, ly + 4), pair[1], 2, UI.PAPER_LIGHT, UI.INK)
		lx += UI.text_width(pair[1], 2) + 28.0
	UI.text(c, Vector2(x0, ly + 38), "GRASS HIDES YOU.  REST TO HEAL.  HITS CHARGE YOUR SUPER.", 2, UI.PAPER_DARK, UI.INK)


func _draw_overheads() -> void:
	var c := _canvas
	var xf: Transform2D = game.get_viewport().get_canvas_transform()
	for f in game.fighters:
		if not is_instance_valid(f) or not f.alive:
			continue
		if f.team != game.local_team and f.modulate.a < 0.5:
			continue
		var p: Vector2 = (xf * (f.global_position + Vector2(0, -40))).round()
		var bar := Rect2(p.x - 30, p.y - 10, 60, 10)
		UI.text_centered(c, p.x, bar.position.y - 20, f.fighter_name, 2, UI.PAPER_LIGHT, UI.INK)
		UI.bar(c, bar, f.hp / f.max_hp, _team_color(f))
		if f.is_player:
			for i in 3:
				var seg := Rect2(bar.position.x + i * 21.0, bar.end.y + 2, 18, 6)
				c.draw_rect(seg, UI.INK)
				var fill: float = clampf(f.ammo - i, 0.0, 1.0)
				var fw := UI.snap(14.0 * fill)
				if fw > 0.0:
					c.draw_rect(Rect2(seg.position + Vector2(2, 2), Vector2(fw, 2)), UI.ORANGE)
		if f.super_charge >= 1.0:
			var sq := Rect2(bar.position.x - 14, bar.position.y, 10, 10)
			c.draw_rect(sq, UI.INK)
			c.draw_rect(sq.grow(-UI.U), UI.GOLD)


func _draw_scoreboard(vs: Vector2) -> void:
	var c := _canvas
	var need: int = game.SCORE_TO_WIN
	var pip := 10.0
	var gap := 2.0
	var pips_w := need * (pip + gap) - gap
	var box_w := 48.0
	var mid_w := 108.0
	var w := 6.0 + box_w + 8.0 + pips_w + mid_w + pips_w + 8.0 + box_w + 6.0
	var r := Rect2(UI.snap((vs.x - w) * 0.5), 8, w, 44)
	UI.panel(c, r)

	for team in 2:
		var color := UI.BLUE if team == game.local_team else UI.RED
		var score: int = game.scores[team]
		var box := Rect2(r.position.x + 6, r.position.y + 6, box_w, 32)
		if team == 1:
			box.position.x = r.end.x - 6 - box_w
		UI.panel(c, box, color)
		UI.text_centered(c, box.get_center().x, box.position.y + 6, str(score), 3, UI.PAPER_LIGHT)
		for i in need:
			var px := box.end.x + 8 + i * (pip + gap)
			if team == 1:
				px = box.position.x - 8 - pip - i * (pip + gap)
			var pr := Rect2(px, r.position.y + 16, pip, 12)
			c.draw_rect(pr, UI.INK)
			c.draw_rect(pr.grow(-UI.U), color if i < score else UI.PAPER_DARK)

	var cx := r.get_center().x
	if game.overtime:
		UI.text_centered(c, cx, r.position.y + 12, "OT", 3, UI.RED)
	else:
		var secs := int(ceil(game.time_left))
		var low := secs <= 15
		UI.text_centered(c, cx, r.position.y + 12, "%d:%02d" % [secs / 60, secs % 60], 3, UI.RED if low else UI.INK)


func _draw_player(vs: Vector2) -> void:
	var p = game.player
	if p == null or not is_instance_valid(p):
		return
	var c := _canvas
	var r := Rect2(UI.snap(vs.x * 0.5 - 204.0), UI.snap(vs.y - 70.0), 408, 60)
	UI.panel(c, r)
	var x := r.position.x + 8
	var y := r.position.y + 8

	if p.alive:
		var frac: float = p.hp / p.max_hp
		UI.bar(c, Rect2(x, y, 300, 20), frac, UI.GREEN if frac > 0.3 else UI.RED)
		UI.text_centered(c, x + 150, y + 3, str(int(ceil(p.hp))), 2, UI.PAPER_LIGHT, UI.INK)
		for i in 3:
			var fill: float = clampf(p.ammo - i, 0.0, 1.0)
			UI.bar(c, Rect2(x + i * 102.0, y + 24, 96, 20), fill, UI.ORANGE if fill >= 1.0 else UI.ORANGE.darkened(0.4))
	else:
		var wait := int(ceil(maxf(p.respawn_timer, 0.0)))
		UI.text_centered(c, x + 150, y + 12, "BOUNCES BACK IN %d" % wait, 3, UI.INK)
		_draw_weapon_swap(p, Rect2(r.position.x, r.position.y - 104, r.size.x, 96))

	var gauge := Rect2(r.end.x - 8 - 84, y, 84, 44)
	var charge: float = clampf(p.super_charge, 0.0, 1.0)
	c.draw_rect(gauge, UI.INK)
	var inner := gauge.grow(-UI.U)
	c.draw_rect(inner, UI.WELL)
	var h := UI.snap(inner.size.y * charge)
	if h > 0.0:
		c.draw_rect(Rect2(inner.position.x, inner.end.y - h, inner.size.x, h), UI.GOLD)
	var label_y := gauge.position.y + 15
	if charge >= 1.0:
		var label := "SPACE" if int(_clock * 2.5) % 2 == 0 else "SUPER"
		UI.text_centered(c, gauge.get_center().x, label_y, label, 2, UI.INK)
	else:
		UI.text_centered(c, gauge.get_center().x, label_y, "SUPER", 2, UI.PAPER_LIGHT, UI.INK)


func _draw_weapon_swap(p, r: Rect2) -> void:
	var c := _canvas
	UI.panel(c, r)
	var chosen: int = p.next_weapon if p.next_weapon >= 0 else p.weapon_type
	UI.text(c, r.position + Vector2(10, 8), "NEXT WEAPON", 2, UI.MUTED)
	UI.text_right(c, r.end.x - 10, r.position.y + 8, Weapons.DATA[chosen]["name"], 2, UI.INK)
	var slot_w := (r.size.x - 16.0 - 8.0 * 2.0) / 3.0
	for i in WEAPON_ORDER.size():
		var slot := Rect2(r.position.x + 8 + i * (slot_w + 8.0), r.position.y + 30, slot_w, 58)
		var id := "next%d" % i
		_hot[id] = slot
		var on: bool = WEAPON_ORDER[i] == chosen
		if on:
			c.draw_rect(slot, UI.INK)
		elif _hover == id:
			c.draw_rect(slot, UI.PAPER_DARK)
		_weapon_sprite(Weapons.DATA[WEAPON_ORDER[i]], slot.get_center() + Vector2(10, 0), 1)
		UI.keycap(c, slot.position + Vector2(4, 4), str(i + 1))


func _choose_next(index: int) -> void:
	var p = game.player
	if p == null or not is_instance_valid(p) or p.alive or _paused:
		return
	p.next_weapon = WEAPON_ORDER[index]


func _draw_feed(vs: Vector2) -> void:
	var c := _canvas
	var y := 8.0
	for item in _feed:
		var killer: String = item["killer"]
		var victim: String = item["victim"]
		var kw := UI.text_width(killer, 2)
		var mw := UI.text_width("KO", 2)
		var vw := UI.text_width(victim, 2)
		var total := 8.0 + kw + 10.0 + mw + 10.0 + vw + 8.0
		var r := Rect2(UI.snap(vs.x - 8.0 - total), y, UI.snap(total), 24)
		UI.panel(c, r, UI.PAPER, UI.INK, false)
		var tx := r.position.x + 8
		UI.text(c, Vector2(tx, y + 5), killer, 2, item["killer_color"])
		UI.text(c, Vector2(tx + kw + 10, y + 5), "KO", 2, UI.MUTED)
		UI.text(c, Vector2(tx + kw + 10 + mw + 10, y + 5), victim, 2, item["victim_color"])
		y += 28.0


func _draw_banner(vs: Vector2) -> void:
	if _banner_life <= 0.0 or _banner_age >= _banner_life:
		return
	if _banner_life - _banner_age < 0.3 and int(_clock * 20.0) % 2 == 0:
		return
	var n := _banner_text.length()
	var zoom := 4
	if n <= 2:
		zoom = 12
	elif n <= 10:
		zoom = 8
	UI.text_centered(_canvas, vs.x * 0.5, UI.snap(vs.y * 0.24), _banner_text, zoom, _banner_color, UI.INK)


func _draw_pause(vs: Vector2) -> void:
	var c := _canvas
	UI.dither(c, Rect2(Vector2.ZERO, vs))
	var r := Rect2(UI.snap(vs.x * 0.5 - 180.0), UI.snap(vs.y * 0.5 - 100.0), 360, 200)
	UI.panel(c, r)
	var cx := r.get_center().x
	UI.text_centered(c, cx, r.position.y + 24, "PAUSED", 6, UI.INK)
	var key_w := UI.text_width("ESC", 2) + 12.0
	var row_w := key_w + 8.0 + UI.text_width("RESUME", 2)
	var kx := UI.snap(cx - row_w * 0.5)
	UI.keycap(c, Vector2(kx, r.position.y + 88), "ESC")
	UI.text(c, Vector2(kx + key_w + 8, r.position.y + 92), "RESUME", 2, UI.INK)
	var btn := Rect2(UI.snap(cx - 104.0), r.end.y - 16 - 48, 208, 48)
	_hot["quit"] = btn
	UI.button(c, btn, "QUIT TO MENU", _hover == "quit", _pressed == "quit")


func _draw_end(vs: Vector2) -> void:
	var c := _canvas
	UI.dither(c, Rect2(Vector2.ZERO, vs))
	var won: bool = game.winner == game.local_team
	var rows: int = game.fighters.size()
	var pw := 632.0
	var ph := 88.0 + 60.0 + 30.0 + rows * 26.0 + 84.0
	var r := Rect2(UI.snap((vs.x - pw) * 0.5), UI.snap((vs.y - ph) * 0.5), pw, ph)
	UI.panel(c, r)
	var cx := r.get_center().x

	var band := Rect2(r.position.x + UI.U, r.position.y + UI.U, pw - UI.U * 2.0, 84)
	c.draw_rect(band, UI.BLUE if won else UI.RED)
	c.draw_rect(Rect2(band.position.x, band.end.y, band.size.x, UI.U), UI.INK)
	var title := "VICTORY" if won else "DEFEAT"
	var title_x := UI.snap(cx - UI.text_width(title, 8) * 0.5)
	UI.shadow_text(c, Vector2(title_x, band.position.y + 14), title, 8, UI.PAPER_LIGHT, UI.INK)

	var ours: int = game.scores[game.local_team]
	var theirs: int = game.scores[1 - game.local_team]
	var sy := band.end.y + 18.0
	UI.text_centered(c, cx, sy, "%d - %d" % [ours, theirs], 4, UI.INK)

	var name_x := r.position.x + 24
	var weapon_x := r.position.x + 252
	var ko_x := r.position.x + 456
	var falls_x := r.position.x + 530
	var dmg_x := r.end.x - 24
	var ty := sy + 28.0 + 22.0
	UI.text(c, Vector2(name_x, ty), "FIGHTER", 2, UI.MUTED)
	UI.text(c, Vector2(weapon_x, ty), "WEAPON", 2, UI.MUTED)
	UI.text_right(c, ko_x, ty, "KOS", 2, UI.MUTED)
	UI.text_right(c, falls_x, ty, "FALLS", 2, UI.MUTED)
	UI.text_right(c, dmg_x, ty, "DAMAGE", 2, UI.MUTED)
	c.draw_rect(Rect2(r.position.x + 16, ty + 20, pw - 32, UI.U), UI.PAPER_DARK)
	ty += 30.0

	var best := 0.0
	for f in game.fighters:
		best = maxf(best, f.damage_dealt)
	for f in game.fighters:
		if f.is_player:
			c.draw_rect(Rect2(r.position.x + 12, ty - 6, pw - 24, 26), UI.PAPER_DARK)
		var marker := Rect2(name_x, ty + 2, 10, 10)
		c.draw_rect(marker, UI.INK)
		c.draw_rect(marker.grow(-UI.U), _team_color(f))
		var fname: String = f.fighter_name
		UI.text(c, Vector2(name_x + 18, ty), fname, 2, UI.INK)
		var after := name_x + 18 + UI.text_width(fname, 2) + 10
		if f.is_player:
			after += UI.tag(c, Vector2(after, ty - 2), "YOU", UI.GREEN, UI.PAPER_LIGHT) + 6
		if best > 0.0 and f.damage_dealt >= best:
			UI.tag(c, Vector2(after, ty - 2), "MVP", UI.GOLD)
		UI.text(c, Vector2(weapon_x, ty), f.w["name"], 2, UI.INK)
		UI.text_right(c, ko_x, ty, str(f.kills), 2, UI.INK)
		UI.text_right(c, falls_x, ty, str(f.deaths), 2, UI.INK)
		UI.text_right(c, dmg_x, ty, str(int(f.damage_dealt)), 2, UI.INK)
		ty += 26.0

	var btn := Rect2(UI.snap(cx - 104.0), r.end.y - 16 - 48, 208, 48)
	_hot["again"] = btn
	UI.button(c, btn, "PLAY AGAIN", _hover == "again", _pressed == "again")
	UI.keycap(c, Vector2(btn.end.x + 12, btn.position.y + 10), "ENTER")
