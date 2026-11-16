extends Node

const Weapons = preload("res://scripts/weapons.gd")

var f = null
var game: Node = null
var target = null

var _think := 0.0
var _path := PackedVector2Array()
var _path_i := 0
var _repath := 0.0
var _path_goal := Vector2.INF
var _strafe := 1.0
var _strafe_timer := 0.0
var _fire_delay := 0.0
var _aim_noise := 0.0
var _noise_timer := 0.0
var _roam_point := Vector2.INF
var _roam_timer := 0.0
var _last_seen := Vector2.INF
var _stuck := 0.0


func _ready() -> void:
	_strafe = 1.0 if randf() < 0.5 else -1.0
	_fire_delay = randf_range(0.2, 0.8)


func _physics_process(delta: float) -> void:
	if f == null:
		return
	if not f.alive or not game.is_playing():
		f.move_input = Vector2.ZERO
		target = null
		_last_seen = Vector2.INF
		return

	_think -= delta
	if _think <= 0.0:
		_think = randf_range(0.12, 0.25)
		_pick_target()

	_noise_timer -= delta
	if _noise_timer <= 0.0:
		_noise_timer = randf_range(0.3, 0.7)
		_aim_noise = randf_range(-0.13, 0.13)

	_strafe_timer -= delta
	if _strafe_timer <= 0.0:
		_strafe_timer = randf_range(1.2, 2.4)
		_strafe = -_strafe

	var pos: Vector2 = f.global_position
	var w: Dictionary = f.w
	var hp_frac: float = f.hp / f.max_hp
	var move := Vector2.ZERO

	if target != null and is_instance_valid(target) and target.alive and not target.hidden_from_enemy:
		var tpos: Vector2 = target.global_position
		var to: Vector2 = tpos - pos
		var dist := to.length()
		var los: bool = game.has_los(pos, tpos)
		_last_seen = tpos

		var lead := 0.0
		var proj_speed: float = w["proj_speed"]
		if proj_speed > 0.0:
			lead = dist / proj_speed
		var tvel: Vector2 = target.velocity
		# lead moving targets a little
		var aim_point: Vector2 = tpos + tvel * lead * 0.75
		var wanted_angle := (aim_point - pos).angle() + _aim_noise
		var aim_dir: Vector2 = f.aim_dir
		var new_angle := rotate_toward(aim_dir.angle(), wanted_angle, 9.0 * delta)
		f.aim_dir = Vector2.from_angle(new_angle)

		var is_sword: bool = f.weapon_type == Weapons.Type.SWORD
		var hurt := hp_frac < (0.26 if is_sword else 0.32)
		var dir := to / maxf(dist, 1.0)
		var side := dir.orthogonal() * _strafe
		if hurt and dist > 120.0:
			move = _move_to(f.spawn_point, delta)
		elif not los or dist > float(w["ai_range"]):
			move = _move_to(tpos, delta)
			if los and not is_sword:
				move = (move + side * 0.45).normalized()
		elif dist < float(w["ai_min"]):
			move = (-dir + side * 0.6).normalized()
		else:
			move = (side + dir * 0.15).normalized()

		_fire_delay -= delta
		var aimed := absf(angle_difference(new_angle, wanted_angle)) < 0.3
		if los and aimed and _fire_delay <= 0.0:
			if f.super_charge >= 1.0 and _super_makes_sense(dist):
				f.try_super()
				_fire_delay = randf_range(0.3, 0.6)
			elif dist <= float(w["ai_fire"]) and f.try_attack():
				_fire_delay = randf_range(0.12, 0.5)
	else:
		target = null
		if hp_frac < 0.6:
			move = Vector2.ZERO
		else:
			var goal := _last_seen
			if goal == Vector2.INF:
				_roam_timer -= delta
				if _roam_point == Vector2.INF or _roam_timer <= 0.0 or pos.distance_to(_roam_point) < 50.0:
					_roam_point = game.random_roam_point(f.team)
					_roam_timer = randf_range(3.0, 6.0)
				goal = _roam_point
			elif pos.distance_to(goal) < 60.0:
				_last_seen = Vector2.INF
			if goal != Vector2.INF:
				move = _move_to(goal, delta)
		if move.length() > 0.1:
			var aim_dir: Vector2 = f.aim_dir
			f.aim_dir = Vector2.from_angle(rotate_toward(aim_dir.angle(), move.angle(), 6.0 * delta))

	var vel: Vector2 = f.velocity
	# stuck on a wall, flip strafe
	if move.length() > 0.5 and vel.length() < 40.0:
		_stuck += delta
		if _stuck > 0.35:
			_stuck = 0.0
			_strafe = -_strafe
			_strafe_timer = 1.0
			_repath = 0.0
	else:
		_stuck = 0.0

	f.move_input = move.limit_length(1.0)


func _pick_target() -> void:
	var pos: Vector2 = f.global_position
	var best = null
	var best_score := INF
	for e in game.fighters:
		if e.team == f.team or not e.alive or e.hidden_from_enemy:
			continue
		var epos: Vector2 = e.global_position
		var score := pos.distance_to(epos)
		if score > 780.0:
			continue
		var e_hp: float = e.hp / e.max_hp
		score *= 0.7 + 0.3 * e_hp
		if e == target:
			score *= 0.75
		if score < best_score:
			best_score = score
			best = e
	target = best


func _super_makes_sense(dist: float) -> bool:
	match f.weapon_type:
		Weapons.Type.SWORD:
			return dist > 90.0 and dist < 300.0
		Weapons.Type.GUN:
			return dist < 470.0
		_:
			return dist < 430.0


func _move_to(goal: Vector2, delta: float) -> Vector2:
	var pos: Vector2 = f.global_position
	_repath -= delta
	if _repath <= 0.0 or _path_goal == Vector2.INF or _path_goal.distance_to(goal) > 90.0:
		_repath = randf_range(0.35, 0.5)
		_path_goal = goal
		if game.clear_walk(pos, goal):
			_path = PackedVector2Array([goal])
			_path_i = 0
		else:
			_path = game.find_path(pos, goal)
			_path_i = mini(1, _path.size() - 1)
	if _path.is_empty():
		return pos.direction_to(goal)
	while _path_i < _path.size() - 1 and pos.distance_to(_path[_path_i]) < 20.0:
		_path_i += 1
	return pos.direction_to(_path[_path_i])
