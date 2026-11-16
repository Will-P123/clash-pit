extends CharacterBody2D

const Weapons = preload("res://scripts/weapons.gd")
const UI = preload("res://scripts/pixel_ui.gd")

signal died(victim, killer)

const MAX_AMMO := 3
const REGEN_DELAY := 3.0
const REGEN_RATE := 0.14
const ACCEL := 1900.0
const DASH_SPEED := 1150.0
const DASH_TIME := 0.26
const SHIELD_TIME := 2.5
const HIT_RADIUS := 22.0

var game: Node = null
var fighter_name := "Fighter"
var team := 0
var is_player := false
var speed_scale := 1.0
var next_weapon := -1
var weapon_type: int = Weapons.Type.GUN
var w: Dictionary = {}
var team_color := Color.WHITE
var spawn_point := Vector2.ZERO

var max_hp := 3000.0
var hp := 3000.0
var ammo := 3.0
var super_charge := 0.0
var alive := true

var move_input := Vector2.ZERO
var aim_dir := Vector2.RIGHT

var respawn_timer := 0.0
var shield_timer := 0.0
var reveal_timer := 0.0
var in_grass := false
var hidden_from_enemy := false

var kills := 0
var deaths := 0
var damage_dealt := 0.0

var _cooldown := 0.0
var _calm_time := 0.0
var _move_vel := Vector2.ZERO
var _knockback := Vector2.ZERO
var _burst_left := 0
var _burst_timer := 0.0
var _burst_interval := 0.08
var _burst_super := false
var _dash_timer := 0.0
var _dash_dir := Vector2.RIGHT
var _dash_hit: Array = []
var _swing := 1.0
var _swing_sign := 1.0
var _recoil := 0.0
var _flash := 0.0
var _walk_phase := 0.0
var _ball_index := 0
var _aim_points := PackedVector2Array()

@onready var body: Sprite2D = $Body
@onready var pivot: Node2D = $WeaponPivot
@onready var weapon_sprite: Sprite2D = $WeaponPivot/Weapon
@onready var muzzle: Marker2D = $WeaponPivot/Muzzle


func setup(cfg: Dictionary, weapon: int, game_ref: Node, spawn: Vector2) -> void:
	game = game_ref
	fighter_name = cfg["name"]
	team = cfg["team"]
	team_color = game.TEAM_COLORS[team]
	_ball_index = randi() % Weapons.BALLS.size()
	body.texture = load(cfg["tex"])
	var region: Rect2 = cfg.get("region", game.DEFAULT_REGION)
	body.region_rect = region
	# line up feet with the soldiers
	body.offset.y = floorf((game.DEFAULT_REGION.size.y - region.size.y) * 0.5)
	_apply_weapon(weapon)
	hp = max_hp

	spawn_point = spawn
	global_position = spawn
	aim_dir = Vector2.RIGHT if team == 0 else Vector2.LEFT
	shield_timer = SHIELD_TIME


func _apply_weapon(weapon: int) -> void:
	weapon_type = weapon
	w = Weapons.DATA[weapon]
	max_hp = float(w["max_hp"])
	weapon_sprite.texture = load(w["tex"])
	weapon_sprite.region_enabled = true
	weapon_sprite.region_rect = w["region"]
	weapon_sprite.centered = w["centered"]
	weapon_sprite.offset = w["offset"]
	weapon_sprite.rotation = w["sprite_rot"]
	weapon_sprite.position = w["sprite_pos"]
	muzzle.position = w["muzzle"]
	_aim_points.clear()
	_swing = 1.0
	_recoil = 0.0


func _physics_process(delta: float) -> void:
	if not alive:
		respawn_timer -= delta
		if respawn_timer <= 0.0 and game.is_playing():
			_respawn()
		return

	_cooldown = maxf(0.0, _cooldown - delta)
	shield_timer = maxf(0.0, shield_timer - delta)
	reveal_timer = maxf(0.0, reveal_timer - delta)
	_calm_time += delta

	if ammo < MAX_AMMO:
		ammo = minf(MAX_AMMO, ammo + delta / float(w["reload"]))
	if _calm_time > REGEN_DELAY and hp < max_hp:
		hp = minf(max_hp, hp + max_hp * REGEN_RATE * delta)

	_update_burst(delta)

	if _dash_timer > 0.0:
		_dash_timer -= delta
		_move_vel = _dash_dir * DASH_SPEED
		_dash_damage()
		if _dash_timer <= 0.0:
			_move_vel = _dash_dir * float(w["speed"]) * speed_scale
	else:
		var wanted: Vector2 = move_input.limit_length(1.0) * float(w["speed"]) * speed_scale
		_move_vel = _move_vel.move_toward(wanted, ACCEL * delta)

	velocity = _move_vel + _knockback
	move_and_slide()
	_knockback = _knockback.move_toward(Vector2.ZERO, 1800.0 * delta)

	if is_player:
		_update_aim_guide()


func _process(delta: float) -> void:
	if not alive:
		return
	if absf(aim_dir.x) > 0.12:
		body.flip_h = aim_dir.x < 0.0
	var flip := -1.0 if aim_dir.x < 0.0 else 1.0
	pivot.scale.y = flip
	var extra := 0.0
	if weapon_type == Weapons.Type.SWORD:
		if _dash_timer > 0.0:
			extra = _dash_timer * 60.0
		elif _swing < 1.0:
			_swing = minf(1.0, _swing + delta / 0.16)
			extra = lerpf(-1.5, 1.5, ease(_swing, 0.4)) * _swing_sign
		else:
			extra = -0.6
	pivot.rotation = aim_dir.angle() + extra * flip
	pivot.show_behind_parent = aim_dir.y < -0.35
	_recoil = move_toward(_recoil, 0.0, delta * 60.0)
	pivot.position = Vector2(0, 8) - aim_dir * _recoil

	if _move_vel.length() > 40.0:
		_walk_phase += delta * 14.0
		body.position.y = -absf(sin(_walk_phase)) * 3.0
	else:
		body.position.y = move_toward(body.position.y, 0.0, delta * 20.0)

	_flash = maxf(0.0, _flash - delta * 10.0)
	(body.material as ShaderMaterial).set_shader_parameter("flash", _flash * 0.45)

	var target_alpha := 1.0
	if in_grass:
		target_alpha = 0.7
	if hidden_from_enemy and team != game.local_team:
		target_alpha = 0.0
	modulate.a = move_toward(modulate.a, target_alpha, delta * 6.0)

	queue_redraw()


func _draw() -> void:
	if not alive:
		return
	draw_set_transform(Vector2(0, 29), 0.0, Vector2(1.0, 0.4))
	draw_circle(Vector2.ZERO, 25.0, Color(0, 0, 0, 0.28))
	var ring := UI.GREEN if is_player else team_color
	draw_arc(Vector2.ZERO, 28.0, 0.0, TAU, 32, ring, 3.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	if is_player and game != null and game.is_playing():
		_draw_aim_guide()

	if shield_timer > 0.0:
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.012)
		draw_circle(Vector2.ZERO, 42.0, Color(1, 1, 1, 0.08 + 0.06 * pulse))
		draw_arc(Vector2.ZERO, 42.0, 0.0, TAU, 40, Color(1, 1, 1, 0.5 + 0.3 * pulse), 2.0)


func can_attack() -> bool:
	return alive and _cooldown <= 0.0 and ammo >= 1.0 and _burst_left <= 0 and _dash_timer <= 0.0


func try_attack() -> bool:
	if not can_attack():
		return false
	ammo -= 1.0
	_cooldown = float(w["cooldown"])
	_calm_time = 0.0
	reveal_timer = 0.8
	match weapon_type:
		Weapons.Type.GUN:
			_start_burst(int(w["shots"]), 0.055, false)
		Weapons.Type.SWORD:
			_slash()
		Weapons.Type.LAUNCHER:
			var count: int = w["shots"]
			var aimed := _assisted(aim_dir, _fire_origin(), float(w["range"]))
			for i in count:
				var offset := 0.0 if count == 1 else lerpf(-1.0, 1.0, float(i) / (count - 1))
				_fire_ball(aimed.rotated(deg_to_rad(3.5) * offset), false)
	return true


func try_super() -> bool:
	if not alive or super_charge < 1.0 or _burst_left > 0 or _dash_timer > 0.0:
		return false
	super_charge = 0.0
	_calm_time = 0.0
	reveal_timer = 1.2
	_cooldown = 0.3
	game.fx_ring(global_position, Color(1.0, 0.85, 0.3), 70.0)
	match weapon_type:
		Weapons.Type.GUN:
			_start_burst(10, 0.055, true)
		Weapons.Type.SWORD:
			_dash_timer = DASH_TIME
			_dash_dir = aim_dir
			_dash_hit.clear()
		Weapons.Type.LAUNCHER:
			for i in 5:
				var angle := deg_to_rad(-24.0 + 12.0 * i)
				_fire_ball(aim_dir.rotated(angle), true)
			if is_player:
				game.add_shake(5.0)
	return true


func _start_burst(count: int, interval: float, is_super: bool) -> void:
	_burst_left = count
	_burst_interval = interval
	_burst_timer = 0.0
	_burst_super = is_super


func _update_burst(delta: float) -> void:
	if _burst_left <= 0:
		return
	_burst_timer -= delta
	while _burst_left > 0 and _burst_timer <= 0.0:
		_burst_timer += _burst_interval
		_burst_left -= 1
		_fire_bullet()
	_cooldown = maxf(_cooldown, 0.12)


func _fire_bullet() -> void:
	var spread := deg_to_rad(5.0 if _burst_super else 1.5)
	var origin := _fire_origin()
	var dir := _assisted(aim_dir, origin, float(w["range"])).rotated(randf_range(-spread, spread))
	var dmg: float = w["super_damage"] if _burst_super else w["damage"]
	var reach: float = float(w["range"]) * (1.2 if _burst_super else 1.0)
	var speed: float = w["proj_speed"]
	game.spawn_bullet(self, origin, dir, dmg, speed, reach / speed, _burst_super)
	game.fx_muzzle(origin, dir)
	_recoil = 7.0
	if is_player:
		game.add_shake(1.5)


func _fire_ball(dir: Vector2, is_super: bool) -> void:
	var origin := _fire_origin()
	var speed: float = w["proj_speed"]
	var dmg: float = w["super_damage"] if is_super else w["damage"]
	var life: float = float(w["range"]) / speed
	var bounces := 3
	if is_super:
		life *= 1.7
		bounces = 7
		speed *= 1.1
	game.spawn_ball(self, origin, dir, dmg, speed, life, bounces, _ball_index)
	_ball_index = (_ball_index + 1) % Weapons.BALLS.size()
	_recoil = 9.0


func _slash() -> void:
	_swing = 0.0
	_swing_sign = -_swing_sign
	_knockback += aim_dir * 240.0
	var reach: float = w["range"]
	var half_arc := deg_to_rad(float(w["arc"]) * 0.5)
	var center := global_position + Vector2(0, 8)
	var landed := false
	for e in game.fighters:
		if not e.alive or e.team == team:
			continue
		var to: Vector2 = e.global_position - global_position
		var dist := to.length()
		if dist > reach + HIT_RADIUS:
			continue
		if dist > 34.0 and absf(aim_dir.angle_to(to)) > half_arc:
			continue
		if not game.has_los(global_position, e.global_position):
			continue
		e.take_damage(float(w["damage"]), self, aim_dir * 320.0)
		landed = true
	game.fx_slash(center, aim_dir, reach + 14.0, float(w["arc"]), team_color)
	if landed and is_player:
		game.add_shake(5.0)


func _dash_damage() -> void:
	for e in game.fighters:
		if not e.alive or e.team == team or _dash_hit.has(e):
			continue
		if e.global_position.distance_to(global_position) < 66.0:
			_dash_hit.append(e)
			e.take_damage(float(w["super_damage"]), self, _dash_dir * 560.0)
			if is_player:
				game.add_shake(7.0)
	if Engine.get_physics_frames() % 2 == 0:
		game.fx_spark(global_position, team_color, 3)


# light aim assist for the player
func _assisted(dir: Vector2, origin: Vector2, reach: float) -> Vector2:
	if not is_player:
		return dir
	var best := dir
	var best_off := deg_to_rad(7.0)
	for e in game.fighters:
		if not e.alive or e.team == team or e.hidden_from_enemy:
			continue
		var to: Vector2 = e.global_position - origin
		if to.length() > reach + HIT_RADIUS:
			continue
		var off := absf(dir.angle_to(to))
		if off < best_off and game.has_los(origin, e.global_position):
			best_off = off
			best = dir.rotated(dir.angle_to(to))
	return best


func _fire_origin() -> Vector2:
	var center: Vector2 = global_position + Vector2(0, 8)
	var tip: Vector2 = center + aim_dir * float(muzzle.position.x)
	var hit: Dictionary = game.wall_ray(center, tip)
	if not hit.is_empty():
		return hit["position"] - aim_dir * 4.0
	return tip


func take_damage(amount: float, attacker, knock := Vector2.ZERO) -> void:
	if not alive or shield_timer > 0.0 or not game.is_playing():
		return
	if _dash_timer > 0.0:
		amount *= 0.5
	amount = minf(amount, hp)
	hp -= amount
	_calm_time = 0.0
	_flash = 1.0
	reveal_timer = maxf(reveal_timer, 0.6)
	_knockback += knock
	var valid_attacker: bool = attacker != null and is_instance_valid(attacker)
	if valid_attacker:
		attacker.damage_dealt += amount
		attacker.super_charge = minf(1.0, attacker.super_charge + amount / float(attacker.w["super_cost"]))
	if is_player:
		game.add_shake(4.0)
	if hp <= 0.0:
		_die(attacker if valid_attacker else null)


func _die(killer) -> void:
	alive = false
	deaths += 1
	if killer != null:
		killer.kills += 1
	respawn_timer = game.RESPAWN_TIME
	_burst_left = 0
	_dash_timer = 0.0
	_knockback = Vector2.ZERO
	_move_vel = Vector2.ZERO
	velocity = Vector2.ZERO
	visible = false
	died.emit(self, killer)


func _respawn() -> void:
	if next_weapon >= 0 and next_weapon != weapon_type:
		_apply_weapon(next_weapon)
	next_weapon = -1
	global_position = spawn_point
	hp = max_hp
	ammo = MAX_AMMO
	alive = true
	visible = true
	modulate.a = 1.0
	shield_timer = SHIELD_TIME
	reveal_timer = 0.0
	_cooldown = 0.0
	_calm_time = 0.0
	aim_dir = Vector2.RIGHT if team == 0 else Vector2.LEFT
	game.fx_ring(global_position, team_color, 60.0)


func _update_aim_guide() -> void:
	_aim_points.clear()
	var origin := Vector2(0, 8)
	var start: Vector2 = global_position + origin
	match weapon_type:
		Weapons.Type.GUN:
			var end: Vector2 = start + aim_dir * float(w["range"])
			var hit: Dictionary = game.wall_ray(start, end)
			if not hit.is_empty():
				end = hit["position"]
			_aim_points.append(origin)
			_aim_points.append(end - global_position)
		Weapons.Type.LAUNCHER:
			var dir := aim_dir
			var pos := start
			var left := 430.0
			_aim_points.append(origin)
			for i in 3:
				var hit: Dictionary = game.wall_ray(pos, pos + dir * left)
				if hit.is_empty():
					_aim_points.append(pos + dir * left - global_position)
					break
				var hit_pos: Vector2 = hit["position"]
				var normal: Vector2 = hit["normal"]
				_aim_points.append(hit_pos - global_position)
				left -= pos.distance_to(hit_pos)
				if left <= 0.0 or normal == Vector2.ZERO:
					break
				dir = dir.bounce(normal)
				pos = hit_pos + normal * 2.0


func _draw_aim_guide() -> void:
	var tint := Color(1, 1, 1, 0.16)
	if not can_attack() and _burst_left <= 0:
		tint.a = 0.07
	match weapon_type:
		Weapons.Type.SWORD:
			var reach: float = float(w["range"]) + 14.0
			var half := deg_to_rad(float(w["arc"]) * 0.5)
			var base := aim_dir.angle()
			var pts := PackedVector2Array([Vector2(0, 8)])
			for i in 17:
				var a := base - half + (half * 2.0) * i / 16.0
				pts.append(Vector2(0, 8) + Vector2.from_angle(a) * reach)
			draw_colored_polygon(pts, tint)
		_:
			if _aim_points.size() >= 2:
				draw_polyline(_aim_points, tint, 28.0 if weapon_type == Weapons.Type.GUN else 32.0)
				draw_polyline(_aim_points, Color(1, 1, 1, tint.a * 1.8), 2.0)
				draw_circle(_aim_points[_aim_points.size() - 1], 6.0, Color(1, 1, 1, tint.a * 2.0))
