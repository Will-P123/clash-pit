extends Node

const Weapons = preload("res://scripts/weapons.gd")

@onready var f = get_parent()
var target = null

var _think := 0.0
# aim wobble so bots miss now and then
var _noise := 0.0
var _strafe := signf(randf() - 0.5)
var _strafe_timer := 0.0
var _fire_delay := randf_range(0.2, 0.8)
# last place we saw an enemy, or somewhere to wander to
var _goal := Vector2.INF
var _goal_timer := 0.0
var _stuck := 0.0
var _path := PackedVector2Array()
var _path_i := 0
var _path_goal := Vector2.INF
var _repath := 0.0


func _physics_process(delta: float) -> void:
	var game = f.game
	if not f.alive or not game.is_playing():
		f.move_input = Vector2.ZERO
		target = null
		_goal = Vector2.INF
		return

	_think -= delta
	_strafe_timer -= delta
	_fire_delay -= delta
	_goal_timer -= delta
	if _think <= 0.0:
		_think = randf_range(0.12, 0.25)
		_noise = randf_range(-0.13, 0.13)
		_pick_target()
	if _strafe_timer <= 0.0:
		_strafe_timer = randf_range(1.2, 2.4)
		_strafe = -_strafe

	var pos: Vector2 = f.position
	var w: Dictionary = f.w
	var hp: float = f.hp / f.max_hp
	var move := Vector2.ZERO

	if is_instance_valid(target) and target.alive and not target.hidden_from_enemy:
		var tpos: Vector2 = target.position
		var to := tpos - pos
		var dist := to.length()
		var los: bool = game.has_los(pos, tpos)
		_goal = tpos
		_goal_timer = 4.0

		var want := to.angle() + _noise
		var angle := rotate_toward(f.aim_dir.angle(), want, 9.0 * delta)
		f.aim_dir = Vector2.from_angle(angle)

		var sword: bool = f.weapon_type == Weapons.Type.SWORD
		var dir := to / maxf(dist, 1.0)
		var side := dir.orthogonal() * _strafe
		if hp < (0.26 if sword else 0.32) and dist > 120.0:
			move = _move_to(f.spawn_point, delta)
		elif not los or dist > w.ai_range:
			move = _move_to(tpos, delta)
			if los and not sword:
				move = (move + side * 0.45).normalized()
		elif dist < w.ai_min:
			move = (side * 0.6 - dir).normalized()
		else:
			move = (side + dir * 0.15).normalized()

		if los and _fire_delay <= 0.0 and absf(angle_difference(angle, want)) < 0.3:
			if f.super_charge >= 1.0 and dist > w.ai_super.x and dist < w.ai_super.y:
				f.try_super()
				_fire_delay = randf_range(0.3, 0.6)
			elif dist <= w.ai_fire and f.can_attack():
				f.try_attack()
				_fire_delay = randf_range(0.12, 0.5)
	else:
		target = null
		# hang back and heal when hurt, otherwise wander
		if hp >= 0.6:
			if _goal == Vector2.INF or _goal_timer <= 0.0 or pos.distance_to(_goal) < 50.0:
				_goal = game.roam_point(f.team)
				_goal_timer = randf_range(3.0, 6.0)
			move = _move_to(_goal, delta)
			f.aim_dir = Vector2.from_angle(rotate_toward(f.aim_dir.angle(), move.angle(), 6.0 * delta))

	# stuck on a wall, flip strafe
	if move.length() > 0.5 and f.velocity.length() < 40.0:
		_stuck += delta
		if _stuck > 0.35:
			_stuck = 0.0
			_strafe = -_strafe
			_strafe_timer = 1.0
			_repath = 0.0
	else:
		_stuck = 0.0
	f.move_input = move


func _pick_target() -> void:
	var best = null
	var best_score := INF
	for e in f.game.fighters:
		var dist: float = f.position.distance_to(e.position)
		if e.team == f.team or not e.alive or e.hidden_from_enemy or dist > 780.0:
			continue
		# prefer close, weak, and whoever we're already fighting
		var score: float = dist * (0.7 + 0.3 * e.hp / e.max_hp) * (0.75 if e == target else 1.0)
		if score < best_score:
			best_score = score
			best = e
	target = best


func _move_to(goal: Vector2, delta: float) -> Vector2:
	var pos: Vector2 = f.position
	_repath -= delta
	if _repath <= 0.0 or _path_goal.distance_to(goal) > 90.0:
		_repath = randf_range(0.35, 0.5)
		_path_goal = goal
		_path_i = 0
		_path = PackedVector2Array([goal]) if f.game.clear_walk(pos, goal) else f.game.find_path(pos, goal)
	if _path.is_empty():
		return pos.direction_to(goal)
	while _path_i < _path.size() - 1 and pos.distance_to(_path[_path_i]) < 20.0:
		_path_i += 1
	return pos.direction_to(_path[_path_i])
