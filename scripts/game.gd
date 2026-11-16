extends Node2D

const FighterScene = preload("res://scenes/fighter.tscn")
const Bot = preload("res://scripts/bot_controller.gd")
const UI = preload("res://scripts/pixel_ui.gd")

enum State { MENU, PLAYING, RESULTS }

const SCORE_TO_WIN := 10
const ARENA := Vector2(1824, 1056)
const CELL := 24
const TEAM_COLORS := [UI.BLUE, UI.RED]
const DEFAULT_REGION := Rect2(24, 19, 45, 62)
# the player is always the first fighter
const ROSTER := [
	{"name": "Onyx", "tex": "res://black.png", "team": 0},
	{"name": "Cobalt", "tex": "res://blue.png", "team": 0},
	{"name": "Gloop", "tex": "res://characters/slime.png", "team": 0, "region": Rect2(20, 20, 45, 64)},
	{"name": "Rosa", "tex": "res://pink.png", "team": 1},
	{"name": "Violet", "tex": "res://purple.png", "team": 1},
	{"name": "Amber", "tex": "res://yellow.png", "team": 1},
]
const KEYS := {
	"up": [KEY_W, KEY_UP], "down": [KEY_S, KEY_DOWN], "left": [KEY_A, KEY_LEFT], "right": [KEY_D, KEY_RIGHT],
	"fire": [], "super": [KEY_SPACE],
}
const MOUSE := {"fire": MOUSE_BUTTON_LEFT, "super": MOUSE_BUTTON_RIGHT}

var state := State.MENU
var fighters := []
var player = null
var scores := [0, 0]
var walls := []
var grass := []
var astar := AStarGrid2D.new()

@onready var effects: Node2D = $Effects
@onready var camera: Camera2D = $Camera2D
@onready var hud = $HUD


func _ready() -> void:
	for action in KEYS:
		InputMap.add_action(action)
		for key in KEYS[action]:
			var e := InputEventKey.new()
			e.physical_keycode = key
			InputMap.action_add_event(action, e)
	for action in MOUSE:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE[action]
		InputMap.action_add_event(action, e)

	walls = _rects_in($Arena/Walls)
	grass = _rects_in($Arena/Grass)
	_build_grid()

	# draw the grass again above the fighters so it can hide them
	var canvas: Sprite2D = $Arena/Canvas
	for r in grass:
		var patch := Sprite2D.new()
		patch.texture = canvas.texture
		patch.centered = false
		patch.region_enabled = true
		patch.region_rect = Rect2(r.position / canvas.scale, r.size / canvas.scale)
		patch.position = r.position
		patch.scale = canvas.scale
		patch.modulate.a = 0.55
		patch.z_index = 2
		$Arena.add_child(patch)
	show_menu()


func _rects_in(parent: Node) -> Array:
	return parent.get_children().map(func(c): return Rect2(c.position - c.shape.size * 0.5, c.shape.size))


func _build_grid() -> void:
	astar.region = Rect2i(Vector2i.ZERO, Vector2i(ARENA / CELL))
	astar.cell_size = Vector2.ONE * CELL
	astar.offset = astar.cell_size * 0.5
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.update()
	for x in astar.region.size.x:
		for y in astar.region.size.y:
			var p := (Vector2(x, y) + Vector2.ONE * 0.5) * CELL
			for r in walls:
				if r.has_point(p):
					astar.set_point_solid(Vector2i(x, y))
				elif r.grow_individual(23, 31, 23, 31).has_point(p):
					# hugging walls is allowed but expensive, so paths keep clear
					astar.set_point_weight_scale(Vector2i(x, y), 20.0)


func is_playing() -> bool:
	return state == State.PLAYING


func show_menu() -> void:
	_clear()
	state = State.MENU
	get_tree().paused = false


func start_match(weapon: int) -> void:
	_clear()
	# both teams mirror the same weapon lanes, player's pick in the middle
	var lanes := [0, 1, 2]
	lanes.erase(weapon)
	lanes.shuffle()
	lanes.push_front(weapon)
	for i in ROSTER.size():
		var team: int = ROSTER[i].team
		var f = FighterScene.instantiate()
		$Fighters.add_child(f)
		f.is_player = i == 0
		f.setup(ROSTER[i], lanes[i % 3], self, Vector2([144, 1680][team], [528, 264, 792][i % 3]))
		if i > 0:
			f.speed_scale = 0.75
			f.add_child(Bot.new())
		fighters.append(f)
	player = fighters[0]
	scores = [0, 0]
	state = State.PLAYING
	hud.banner("CLASH!", UI.GOLD)


func _clear() -> void:
	for n in $Fighters.get_children() + effects.get_children():
		n.queue_free()
	fighters.clear()
	player = null


func _physics_process(_delta: float) -> void:
	if not is_playing():
		return
	for f in fighters:
		var feet: Vector2 = f.position + Vector2(0, 12)
		f.in_grass = f.alive and grass.any(func(r): return r.has_point(feet))
	for f in fighters:
		f.hidden_from_enemy = f.in_grass and f.reveal_timer <= 0.0 and not fighters.any(
			func(e): return e.alive and e.team != f.team and e.position.distance_to(f.position) < 130.0)


func on_died(victim, killer) -> void:
	var team: int = 1 - victim.team
	scores[team] += 1
	fx_spark(victim.position, victim.team_color, 26)
	fx_spark(victim.position, Color.WHITE, 12)
	if victim == player:
		hud.banner("KNOCKED OUT" + ("" if killer == null else " BY " + killer.fighter_name), UI.RED)
	elif killer == player:
		hud.banner("KNOCKOUT!", UI.GOLD)
	if scores[team] >= SCORE_TO_WIN:
		state = State.RESULTS


func _process(_delta: float) -> void:
	if player:
		camera.zoom = Vector2.ONE * 1.3
		if player.alive:
			camera.position = player.position + player.aim_dir * 45.0
	else:
		# fit the whole arena behind the menu
		var fit := get_viewport_rect().size / ARENA
		camera.zoom = Vector2.ONE * maxf(fit.x, fit.y)
		camera.position = ARENA * 0.5


func wall_ray(from: Vector2, to: Vector2) -> Dictionary:
	if from.is_equal_approx(to):
		return {}
	return get_world_2d().direct_space_state.intersect_ray(PhysicsRayQueryParameters2D.create(from, to, 1))


func has_los(from: Vector2, to: Vector2) -> bool:
	return wall_ray(from, to).is_empty()


func clear_walk(from: Vector2, to: Vector2) -> bool:
	var side := (to - from).normalized().orthogonal() * 22.0
	return has_los(from, to) and has_los(from + side, to + side) and has_los(from - side, to - side)


func find_path(from: Vector2, to: Vector2) -> PackedVector2Array:
	return astar.get_point_path(_cell(from), _cell(to))


func _cell(p: Vector2) -> Vector2i:
	return Vector2i((p / CELL).floor()).clamp(Vector2i.ZERO, astar.region.size - Vector2i.ONE)


func roam_point(team: int) -> Vector2:
	for attempt in 20:
		var x := randf_range(0.3, 0.85)
		var p := ARENA * Vector2(x if team == 0 else 1.0 - x, randf_range(0.12, 0.88))
		if not astar.is_point_solid(_cell(p)):
			return p
	return ARENA * 0.5


func fx_spark(pos: Vector2, color: Color, amount: int) -> void:
	var p := CPUParticles2D.new()
	p.position = pos
	p.amount = amount
	p.color = color
	p.one_shot = true
	p.explosiveness = 1.0
	p.lifetime = 0.3
	p.spread = 180.0
	p.gravity = Vector2.ZERO
	p.initial_velocity_min = 50.0
	p.initial_velocity_max = 170.0
	p.scale_amount_max = 4.0
	p.finished.connect(p.queue_free)
	effects.add_child(p)


func fx_slash(pos: Vector2, dir: Vector2, radius: float, arc_degrees: float, color: Color) -> void:
	# a crescent: outer arc out, thinner inner arc back
	var half := deg_to_rad(arc_degrees * 0.5)
	var pts := PackedVector2Array()
	for i in 13:
		pts.append(Vector2.from_angle(lerpf(-half, half, i / 12.0)) * radius)
	for i in 13:
		var t := i / 12.0
		pts.append(Vector2.from_angle(lerpf(half, -half, t)) * radius * (0.62 + 0.6 * absf(t - 0.5)))
	var poly := Polygon2D.new()
	poly.polygon = pts
	poly.color = Color(color.lerp(Color.WHITE, 0.6), 0.7)
	poly.position = pos
	poly.rotation = dir.angle()
	effects.add_child(poly)
	poly.create_tween().tween_property(poly, "modulate:a", 0.0, 0.2).finished.connect(poly.queue_free)
