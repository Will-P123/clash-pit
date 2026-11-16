extends Node

var f = null
var game: Node = null


func _physics_process(_delta: float) -> void:
	if f == null:
		return
	if not f.alive or not game.is_playing():
		f.move_input = Vector2.ZERO
		return
	f.move_input = Input.get_vector("left", "right", "up", "down")
	var to_mouse: Vector2 = f.get_global_mouse_position() - (f.global_position + Vector2(0, 8))
	if to_mouse.length() > 8.0:
		f.aim_dir = to_mouse.normalized()
	if Input.is_action_pressed("fire"):
		f.try_attack()
	if Input.is_action_just_pressed("super"):
		f.try_super()
