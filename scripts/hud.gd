extends CanvasLayer

const Game = preload("res://scripts/game.gd")
const Weapons = preload("res://scripts/weapons.gd")
const UI = preload("res://scripts/pixel_ui.gd")

@onready var game = get_parent()
var _canvas := Control.new()
# draw calls don't keep textures alive, so hold on to them here
var _icons := Weapons.DATA.map(func(wd): return load(wd.tex))
var _selected := 0
# clickable rects, rebuilt every draw
var _buttons := {}
var _banner := ""
var _banner_color := Color.WHITE
var _banner_left := 0.0


func _ready() -> void:
	UI.setup()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	_canvas.draw.connect(_draw_hud)
	add_child(_canvas)


func _process(delta: float) -> void:
	if not get_tree().paused:
		_banner_left -= delta
	_canvas.queue_redraw()


func banner(text: String, color: Color) -> void:
	_banner = text
	_banner_color = color
	_banner_left = 1.5


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		for id in _buttons:
			if _buttons[id].has_point(_canvas.get_local_mouse_position()):
				_press(id)
				return
	elif event is InputEventKey and event.pressed and not event.echo:
		var key: int = event.physical_keycode
		match game.state:
			Game.State.MENU:
				if key in [KEY_LEFT, KEY_A, KEY_RIGHT, KEY_D]:
					_selected = wrapi(_selected + (1 if key in [KEY_RIGHT, KEY_D] else -1), 0, 3)
				elif key == KEY_ENTER:
					_press("fight")
			Game.State.PLAYING:
				if key == KEY_ESCAPE:
					get_tree().paused = not get_tree().paused
				elif key == KEY_Q and get_tree().paused:
					game.show_menu()
			Game.State.RESULTS:
				if key == KEY_ENTER:
					game.show_menu()


func _press(id) -> void:
	if id is int:
		_selected = id
	elif id == "fight":
		game.start_match(_selected)
	else:
		game.show_menu()


func _draw_hud() -> void:
	_buttons.clear()
	var vs := _canvas.size
	var mid := UI.snap(vs.x * 0.5)
	match game.state:
		Game.State.MENU:
			_draw_menu(vs)
		Game.State.RESULTS:
			UI.dither(_canvas, Rect2(Vector2.ZERO, vs))
			var won: bool = game.scores[0] > game.scores[1]
			var r := Rect2(mid - 200, UI.snap(vs.y * 0.5 - 110.0), 400, 220)
			UI.panel(_canvas, r)
			UI.text_centered(_canvas, mid, r.position.y + 20, "VICTORY" if won else "DEFEAT", 8, UI.BLUE if won else UI.RED, UI.INK)
			UI.text_centered(_canvas, mid, r.position.y + 96, "%d - %d" % game.scores, 4, UI.INK)
			_button(Rect2(mid - 104, r.end.y - 64, 208, 48), "again", "PLAY AGAIN", 2)
		_:
			_draw_match(vs, mid)


func _button(r: Rect2, id: String, label: String, scale: int) -> void:
	_buttons[id] = r
	UI.button(_canvas, r, label, scale)


func _draw_match(vs: Vector2, mid: float) -> void:
	var c := _canvas
	var xf := get_viewport().get_canvas_transform()
	for f in game.fighters:
		if not f.alive or f.team != 0 and f.modulate.a < 0.5:
			continue
		var p: Vector2 = (xf * (f.position + Vector2(0, -40))).round()
		var bar := Rect2(p.x - 30, p.y - 10, 60, 10)
		UI.text_centered(c, p.x, p.y - 30, f.fighter_name, 2, UI.PAPER_LIGHT, UI.INK)
		UI.bar(c, bar, f.hp / f.max_hp, UI.GREEN if f.is_player else game.TEAM_COLORS[f.team])
		if f.is_player:
			for i in 3:
				UI.bar(c, Rect2(bar.position.x + i * 21.0, bar.end.y + 2, 18, 6), f.ammo - i, UI.ORANGE)
			UI.bar(c, Rect2(bar.position.x, bar.end.y + 10, 60, 6), f.super_charge, UI.GOLD)

	# score
	var r := Rect2(mid - 100, 8, 200, 44)
	UI.panel(c, r)
	for team in 2:
		var box := Rect2(r.position.x + 6 + team * 132, 14, 56, 32)
		UI.panel(c, box, game.TEAM_COLORS[team])
		UI.text_centered(c, box.get_center().x, 20, str(game.scores[team]), 3, UI.PAPER_LIGHT)
	UI.text_centered(c, mid, 23, "TO %d" % game.SCORE_TO_WIN, 2, UI.MUTED)

	var y := UI.snap(vs.y * 0.24)
	if _banner_left > 0.0:
		UI.text_centered(c, mid, y, _banner, 8 if _banner.length() <= 10 else 4, _banner_color, UI.INK)
	if not game.player.alive:
		UI.text_centered(c, mid, UI.snap(vs.y - 80.0), "BOUNCES BACK IN %d" % ceili(game.player.respawn_timer), 3, UI.PAPER_LIGHT, UI.INK)
	if get_tree().paused:
		UI.dither(c, Rect2(Vector2.ZERO, vs))
		UI.text_centered(c, mid, y + 80, "PAUSED", 6, UI.PAPER_LIGHT, UI.INK)
		UI.text_centered(c, mid, y + 150, "ESC  RESUME     Q  QUIT", 2, UI.PAPER_LIGHT, UI.INK)


func _draw_menu(vs: Vector2) -> void:
	var c := _canvas
	UI.dither(c, Rect2(Vector2.ZERO, vs))
	var r := Rect2(UI.snap((vs.x - 704.0) * 0.5), maxf(96.0, UI.snap((vs.y - 284.0) * 0.5)), 704, 284)
	UI.text(c, r.position - Vector2(0, 80), "CLASH PIT", 8, UI.PAPER_LIGHT, UI.INK)
	UI.text(c, r.position - Vector2(-440, 36), "FIRST TEAM TO %d WINS" % game.SCORE_TO_WIN, 2, UI.GOLD, UI.INK)
	UI.panel(c, r)

	for i in 3:
		var card := Rect2(r.position.x + 8 + i * 232, r.position.y + 8, 224, 140)
		var region: Rect2 = Weapons.DATA[i].region
		_buttons[i] = card
		if i == _selected:
			c.draw_rect(card, UI.INK)
		c.draw_texture_rect_region(_icons[i], Rect2((card.get_center() - region.size - Vector2(0, 12)).round(), region.size * 2), region)
		UI.text_centered(c, card.get_center().x, card.end.y - 28, Weapons.DATA[i].name, 2, UI.PAPER_LIGHT if i == _selected else UI.INK)

	var wd: Dictionary = Weapons.DATA[_selected]
	UI.text(c, r.position + Vector2(16, 166), wd.blurb, 2, UI.INK)
	UI.text(c, r.position + Vector2(16, 192), "SUPER: " + wd.super, 2, UI.GOLD_DARK)
	_button(Rect2(r.end - Vector2(224, 64), Vector2(208, 48)), "fight", "FIGHT", 3)

	UI.text(c, Vector2(r.position.x, r.end.y + 20), "WASD MOVE   MOUSE AIM   CLICK ATTACK   SPACE SUPER   ESC PAUSE", 2, UI.PAPER_LIGHT, UI.INK)
	UI.text(c, Vector2(r.position.x, r.end.y + 46), "GRASS HIDES YOU.  REST TO HEAL.  HITS CHARGE YOUR SUPER.", 2, UI.PAPER_DARK, UI.INK)
