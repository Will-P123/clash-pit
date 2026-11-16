extends Node2D

const TRAIL_LENGTH := 7

var game: Node = null
var shooter = null
var team := 0
var velocity := Vector2.ZERO
var damage := 100.0
var life := 1.0
var bounces := 0
var radius := 5.0
# wider than the drawn shot
var hit_radius := 12.0
var pierce := false
var is_ball := false
var color := Color.WHITE
var team_color := Color.WHITE
var knock := 140.0

var _already_hit: Array = []
var _trail: Array[Vector2] = []
var _sprite: Sprite2D = null


func set_ball_sprite(tex: Texture2D, region: Rect2) -> void:
	_sprite = Sprite2D.new()
	_sprite.texture = tex
	_sprite.region_enabled = true
	_sprite.region_rect = region
	add_child(_sprite)


func _physics_process(delta: float) -> void:
	life -= delta
	if life <= 0.0:
		game.fx_spark(global_position, color, 4)
		queue_free()
		return

	var from := global_position
	var step := velocity * delta
	var to := from + step

	var hit: Dictionary = game.wall_ray(from, to + step.normalized() * radius)
	if not hit.is_empty():
		var normal: Vector2 = hit["normal"]
		var hit_pos: Vector2 = hit["position"]
		if bounces > 0 and normal != Vector2.ZERO:
			bounces -= 1
			velocity = velocity.bounce(normal)
			to = hit_pos + normal * (radius + 1.0)
			game.fx_spark(hit_pos, color, 4)
		else:
			game.fx_spark(hit_pos, color, 6)
			queue_free()
			return

	for e in game.fighters:
		if not e.alive or e.team == team or _already_hit.has(e):
			continue
		var center: Vector2 = e.global_position
		var closest := Geometry2D.get_closest_point_to_segment(center, from, to)
		var diff := center - closest
		diff.y *= 0.8
		if diff.length() <= hit_radius + e.HIT_RADIUS:
			e.take_damage(damage, shooter, velocity.normalized() * knock)
			game.fx_spark(closest, color.lerp(Color.WHITE, 0.4), 7)
			if pierce:
				_already_hit.append(e)
			else:
				queue_free()
				return

	global_position = to
	_trail.push_front(to)
	if _trail.size() > TRAIL_LENGTH:
		_trail.pop_back()
	queue_redraw()


func _draw() -> void:
	if is_ball:
		for i in _trail.size():
			var t := 1.0 - float(i) / TRAIL_LENGTH
			draw_circle(_trail[i] - global_position, radius * t, Color(color, 0.32 * t))
		draw_circle(Vector2.ZERO, radius + 2.0, Color(color, 0.3))
		draw_arc(Vector2.ZERO, radius + 3.0, 0.0, TAU, 20, team_color, 2.0)
	else:
		var dir := velocity.normalized()
		draw_line(-dir * 22.0, Vector2.ZERO, Color(color, 0.35), 7.0)
		draw_line(-dir * 14.0, Vector2.ZERO, color, 4.0)
		draw_circle(Vector2.ZERO, 3.5, Color(1, 1, 1, 0.95))
