extends Node2D

const Weapons = preload("res://scripts/weapons.gd")
const FighterScene = preload("res://scenes/fighter.tscn")
const Projectile = preload("res://scripts/projectile.gd")
const BotController = preload("res://scripts/bot_controller.gd")
const PlayerController = preload("res://scripts/player_controller.gd")
const UI = preload("res://scripts/pixel_ui.gd")

enum State { MENU, COUNTDOWN, PLAYING, ENDED }

const SCORE_TO_WIN := 10
const MATCH_TIME := 150.0
const RESPAWN_TIME := 4.0
const COUNTDOWN_TIME := 3.0
const GAME_ZOOM := 1.3
const GRASS_REVEAL_DISTANCE := 130.0
const CELL := 24
const BOT_SPEED_SCALE := 0.75
const TEAM_COLORS := [UI.BLUE, UI.RED]

const DEFAULT_REGION := Rect2(24, 19, 45, 62)
const ROSTER := [
	{"name": "Onyx", "tex": "res://black.png", "team": 0},
	{"name": "Cobalt", "tex": "res://blue.png", "team": 0},
	{"name": "Gloop", "tex": "res://characters/slime.png", "team": 0, "region": Rect2(20, 20, 45, 64)},
	{"name": "Rosa", "tex": "res://pink.png", "team": 1},
	{"name": "Violet", "tex": "res://purple.png", "team": 1},
	{"name": "Amber", "tex": "res://yellow.png", "team": 1},
]

var state: int = State.MENU
var fighters: Array = []
var player = null
var local_team := 0
var scores := [0, 0]
var time_left := MATCH_TIME
var overtime := false
var winner := -1
var countdown := 0.0

var arena_rect := Rect2(0, 0, 1824, 1056)
var walls: Array[Rect2] = []
var grass: Array[Rect2] = []
var astar := AStarGrid2D.new()

var _shake := 0.0
var _death_cam := Vector2.ZERO
var _last_count := 0

@onready var arena: Node2D = $Arena
@onready var canvas_sprite: Sprite2D = $Arena/Canvas
@onready var fighters_root: Node2D = $Fighters
@onready var projectiles_root: Node2D = $Projectiles
@onready var effects_root: Node2D = $Effects
@onready var grass_overlay: Node2D = $GrassOverlay
@onready var camera: Camera2D = $Camera2D
@onready var hud = $HUD


func _ready() -> void:
	randomize()
	_register_inputs()
	_read_arena()
	_build_path_grid()
	_build_grass_overlay()
	hud.game = self

	camera.limit_left = int(arena_rect.position.x)
	camera.limit_top = int(arena_rect.position.y)
	camera.limit_right = int(arena_rect.end.x)
	camera.limit_bottom = int(arena_rect.end.y)
	camera.global_position = arena_rect.get_center()
	camera.zoom = Vector2.ONE * _menu_zoom()
	show_menu()


func is_playing() -> bool:
	return state == State.PLAYING


func _register_inputs() -> void:
	for pair in [["up", KEY_UP], ["down", KEY_DOWN], ["left", KEY_LEFT], ["right", KEY_RIGHT], ["super", KEY_SPACE]]:
		var key := InputEventKey.new()
		key.physical_keycode = pair[1]
		_bind(pair[0], key)
	for pair in [["fire", MOUSE_BUTTON_LEFT], ["super", MOUSE_BUTTON_RIGHT]]:
		var click := InputEventMouseButton.new()
		click.button_index = pair[1]
		_bind(pair[0], click)


func _bind(action: String, event: InputEvent) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	InputMap.action_add_event(action, event)


func _read_arena() -> void:
	arena_rect = Rect2(canvas_sprite.global_position, canvas_sprite.texture.get_size() * canvas_sprite.scale)
	walls = _rects_in($Arena/Walls)
	grass = _rects_in($Arena/Grass)


func _rects_in(parent: Node) -> Array[Rect2]:
	var rects: Array[Rect2] = []
	for c in parent.get_children():
		if c is CollisionShape2D and c.shape is RectangleShape2D:
			var size: Vector2 = c.shape.size
			rects.append(Rect2(c.global_position - size * 0.5, size))
	return rects


func _build_path_grid() -> void:
	astar.region = Rect2i(0, 0, int(arena_rect.size.x / CELL), int(arena_rect.size.y / CELL))
	astar.cell_size = Vector2(CELL, CELL)
	astar.offset = arena_rect.position + Vector2(CELL, CELL) * 0.5
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.update()
	for y in astar.region.size.y:
		for x in astar.region.size.x:
			var center := arena_rect.position + Vector2(x + 0.5, y + 0.5) * CELL
			for r in walls:
				# grow walls so paths keep clear
				if r.grow_individual(23, 31, 23, 31).has_point(center):
					astar.set_point_solid(Vector2i(x, y), true)
					break


func _build_grass_overlay() -> void:
	var tex := canvas_sprite.texture
	var s := canvas_sprite.scale
	for r in grass:
		var patch := Sprite2D.new()
		patch.texture = tex
		patch.centered = false
		patch.region_enabled = true
		patch.region_rect = Rect2((r.position - arena_rect.position) / s, r.size / s)
		patch.position = r.position
		patch.scale = s
		patch.modulate = Color(1, 1, 1, 0.55)
		grass_overlay.add_child(patch)


func show_menu() -> void:
	_clear_match()
	state = State.MENU
	Engine.time_scale = 1.0
	hud.show_menu()


func start_match(player_weapon: int) -> void:
	_clear_match()
	var ally_weapons: Array = []
	for t in [Weapons.Type.GUN, Weapons.Type.SWORD, Weapons.Type.LAUNCHER]:
		if t != player_weapon:
			ally_weapons.append(t)
	ally_weapons.shuffle()

	var spawns_a := [$Arena/Spawns/A2, $Arena/Spawns/A1, $Arena/Spawns/A3]
	var spawns_b := [$Arena/Spawns/B2, $Arena/Spawns/B1, $Arena/Spawns/B3]
	# both teams mirror the same weapon lanes
	var lane_weapons: Array = [player_weapon, ally_weapons[0], ally_weapons[1]]
	var count := [0, 0]
	for i in ROSTER.size():
		var cfg: Dictionary = ROSTER[i]
		var team: int = cfg["team"]
		var slot: int = count[team]
		count[team] += 1
		var spawns: Array = spawns_a if team == 0 else spawns_b

		var f = FighterScene.instantiate()
		fighters_root.add_child(f)
		f.setup(cfg, lane_weapons[slot], self, spawns[slot].global_position)
		f.died.connect(_on_fighter_died)
		fighters.append(f)

		var ctrl: Node
		if i == 0:
			f.is_player = true
			player = f
			ctrl = PlayerController.new()
		else:
			ctrl = BotController.new()
			f.speed_scale = BOT_SPEED_SCALE
		ctrl.f = f
		ctrl.game = self
		f.add_child(ctrl)

	scores = [0, 0]
	time_left = MATCH_TIME
	overtime = false
	winner = -1
	countdown = COUNTDOWN_TIME
	_last_count = 0
	state = State.COUNTDOWN
	camera.global_position = player.global_position
	hud.show_match()


func _clear_match() -> void:
	for f in fighters:
		if is_instance_valid(f):
			f.queue_free()
	fighters.clear()
	player = null
	for c in projectiles_root.get_children():
		c.queue_free()
	for c in effects_root.get_children():
		c.queue_free()


func _physics_process(delta: float) -> void:
	match state:
		State.COUNTDOWN:
			countdown -= delta
			var n := int(ceil(countdown))
			if n != _last_count and n > 0:
				_last_count = n
				hud.banner(str(n), 0.9, UI.PAPER_LIGHT)
			if countdown <= 0.0:
				state = State.PLAYING
				hud.banner("CLASH!", 1.0, UI.GOLD)
		State.PLAYING:
			_update_grass()
			if not overtime:
				time_left -= delta
				if time_left <= 0.0:
					time_left = 0.0
					if scores[0] != scores[1]:
						_end_match(0 if scores[0] > scores[1] else 1)
					else:
						overtime = true
						hud.banner("OVERTIME - NEXT KNOCKOUT WINS", 2.5, UI.RED)


func _update_grass() -> void:
	for f in fighters:
		f.in_grass = f.alive and _in_grass(f.global_position + Vector2(0, 12))
	for f in fighters:
		var hidden := false
		if f.alive and f.in_grass and f.reveal_timer <= 0.0:
			hidden = true
			for e in fighters:
				if e.team != f.team and e.alive and e.global_position.distance_to(f.global_position) < GRASS_REVEAL_DISTANCE:
					hidden = false
					break
		f.hidden_from_enemy = hidden


func _in_grass(p: Vector2) -> bool:
	for r in grass:
		if r.has_point(p):
			return true
	return false


func _on_fighter_died(victim, killer) -> void:
	if state != State.PLAYING:
		return
	var scoring_team: int = 1 - victim.team
	scores[scoring_team] += 1
	hud.add_feed(killer, victim)
	fx_ko(victim.global_position, victim.team_color)
	if victim == player:
		add_shake(14.0)
		_death_cam = victim.global_position
		var by := "" if killer == null else " BY " + str(killer.fighter_name)
		hud.banner("KNOCKED OUT" + by, 2.0, UI.RED)
	elif killer == player:
		add_shake(6.0)
		hud.banner("KNOCKOUT!", 1.0, UI.GOLD)
	if overtime or scores[scoring_team] >= SCORE_TO_WIN:
		_end_match(scoring_team)


func _end_match(winning_team: int) -> void:
	if state == State.ENDED:
		return
	state = State.ENDED
	winner = winning_team
	Engine.time_scale = 0.35
	await get_tree().create_timer(1.3, true, false, true).timeout
	Engine.time_scale = 1.0
	if state != State.ENDED:
		return
	hud.show_end()


func _process(delta: float) -> void:
	var target := arena_rect.get_center()
	var zoom := _menu_zoom()
	if state != State.MENU and player != null:
		zoom = GAME_ZOOM
		if player.alive:
			target = player.global_position + player.aim_dir * 45.0
		else:
			target = _death_cam
	var k := 1.0 - exp(-7.0 * delta)
	camera.global_position = camera.global_position.lerp(target, k)
	camera.zoom = camera.zoom.lerp(Vector2.ONE * zoom, 1.0 - exp(-4.0 * delta))
	_shake = maxf(0.0, _shake - delta * 40.0)
	camera.offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * _shake


func _menu_zoom() -> float:
	var vs := get_viewport_rect().size
	return maxf(vs.x / arena_rect.size.x, vs.y / arena_rect.size.y)


func add_shake(amount: float) -> void:
	_shake = minf(18.0, maxf(_shake, amount))


func wall_ray(from: Vector2, to: Vector2) -> Dictionary:
	if from.is_equal_approx(to):
		return {}
	var query := PhysicsRayQueryParameters2D.create(from, to, 1)
	return get_world_2d().direct_space_state.intersect_ray(query)


func has_los(from: Vector2, to: Vector2) -> bool:
	return wall_ray(from, to).is_empty()


func clear_walk(from: Vector2, to: Vector2) -> bool:
	var side := (to - from).normalized().orthogonal() * 22.0
	return has_los(from, to) and has_los(from + side, to + side) and has_los(from - side, to - side)


func find_path(from: Vector2, to: Vector2) -> PackedVector2Array:
	return astar.get_point_path(_open_cell(from), _open_cell(to))


func _cell_of(p: Vector2) -> Vector2i:
	return Vector2i(((p - arena_rect.position) / CELL).floor())


func _open_cell(p: Vector2) -> Vector2i:
	var region := astar.region
	var c := _cell_of(p)
	c.x = clampi(c.x, 0, region.size.x - 1)
	c.y = clampi(c.y, 0, region.size.y - 1)
	if not astar.is_point_solid(c):
		return c
	for ring in range(1, 6):
		for dy in range(-ring, ring + 1):
			for dx in range(-ring, ring + 1):
				var n := c + Vector2i(dx, dy)
				if region.has_point(n) and not astar.is_point_solid(n):
					return n
	return c


func random_roam_point(team: int) -> Vector2:
	for attempt in 20:
		var fx := randf_range(0.3, 0.85) if team == 0 else randf_range(0.15, 0.7)
		var p := arena_rect.position + Vector2(fx, randf_range(0.12, 0.88)) * arena_rect.size
		var c := _cell_of(p)
		if astar.region.has_point(c) and not astar.is_point_solid(c):
			return p
	return arena_rect.get_center()


func _new_projectile(shooter, pos: Vector2, dir: Vector2, damage: float, speed: float, life: float) -> Projectile:
	var p := Projectile.new()
	p.game = self
	p.shooter = shooter
	p.team = shooter.team
	p.team_color = shooter.team_color
	p.velocity = dir * speed
	p.damage = damage
	p.life = life
	p.position = pos
	return p


func spawn_bullet(shooter, pos: Vector2, dir: Vector2, damage: float, speed: float, life: float, pierce: bool) -> void:
	var p := _new_projectile(shooter, pos, dir, damage, speed, life)
	p.pierce = pierce
	p.radius = 5.0
	p.hit_radius = 14.0
	p.color = Color(0.75, 0.95, 1.0) if shooter.team == local_team else Color(1.0, 0.6, 0.35)
	if pierce:
		p.color = Color(1.0, 0.9, 0.4)
	projectiles_root.add_child(p)


func spawn_ball(shooter, pos: Vector2, dir: Vector2, damage: float, speed: float, life: float, bounces: int, ball_index: int) -> void:
	var ball: Dictionary = Weapons.BALLS[ball_index % Weapons.BALLS.size()]
	var p := _new_projectile(shooter, pos, dir, damage, speed, life)
	p.bounces = bounces
	p.is_ball = true
	p.radius = 7.0
	p.hit_radius = 16.0
	p.knock = 220.0
	p.color = ball["color"]
	p.set_ball_sprite(load(ball["tex"]), ball["region"])
	projectiles_root.add_child(p)


func fx_spark(pos: Vector2, color: Color, amount: int) -> void:
	var p := CPUParticles2D.new()
	p.position = pos
	p.amount = amount
	p.one_shot = true
	p.explosiveness = 1.0
	p.lifetime = 0.3
	p.spread = 180.0
	p.gravity = Vector2.ZERO
	p.initial_velocity_min = 50.0
	p.initial_velocity_max = 170.0
	p.damping_min = 150.0
	p.damping_max = 300.0
	p.scale_amount_min = 2.0
	p.scale_amount_max = 4.0
	p.color = color
	effects_root.add_child(p)
	p.emitting = true
	get_tree().create_timer(0.8).timeout.connect(p.queue_free)


func fx_ko(pos: Vector2, color: Color) -> void:
	fx_spark(pos, color, 26)
	fx_spark(pos, Color.WHITE, 12)
	fx_ring(pos, color, 90.0)


func fx_ring(pos: Vector2, color: Color, radius: float) -> void:
	var ring := Line2D.new()
	for i in 33:
		ring.add_point(Vector2.from_angle(TAU * i / 32.0) * radius)
	ring.width = 5.0
	ring.default_color = color
	ring.position = pos
	ring.scale = Vector2.ONE * 0.25
	effects_root.add_child(ring)
	var tw := ring.create_tween().set_parallel(true)
	tw.tween_property(ring, "scale", Vector2.ONE, 0.35).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(ring, "modulate:a", 0.0, 0.35)
	tw.chain().tween_callback(ring.queue_free)


func fx_slash(pos: Vector2, dir: Vector2, radius: float, arc_degrees: float, color: Color) -> void:
	var half := deg_to_rad(arc_degrees * 0.5)
	var pts := PackedVector2Array()
	for i in 13:
		pts.append(Vector2.from_angle(-half + half * 2.0 * i / 12.0) * radius)
	for i in 13:
		var t := i / 12.0
		var inner := radius * (0.62 + 0.3 * absf(t - 0.5) * 2.0)
		pts.append(Vector2.from_angle(half - half * 2.0 * t) * inner)
	var poly := Polygon2D.new()
	poly.polygon = pts
	poly.color = Color(color.lerp(Color.WHITE, 0.6), 0.7)
	poly.position = pos
	poly.rotation = dir.angle()
	poly.scale = Vector2.ONE * 0.8
	effects_root.add_child(poly)
	var tw := poly.create_tween().set_parallel(true)
	tw.tween_property(poly, "scale", Vector2.ONE * 1.05, 0.2).set_ease(Tween.EASE_OUT)
	tw.tween_property(poly, "modulate:a", 0.0, 0.2)
	tw.chain().tween_callback(poly.queue_free)


func fx_muzzle(pos: Vector2, dir: Vector2) -> void:
	var poly := Polygon2D.new()
	poly.polygon = PackedVector2Array([Vector2(-2, 0), Vector2(4, -6), Vector2(20, 0), Vector2(4, 6)])
	poly.color = Color(1.0, 0.92, 0.55, 0.9)
	poly.position = pos
	poly.rotation = dir.angle()
	effects_root.add_child(poly)
	var tw := poly.create_tween()
	tw.tween_property(poly, "modulate:a", 0.0, 0.07)
	tw.tween_callback(poly.queue_free)
