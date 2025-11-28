extends Node2D

## HeldToken: a "ghost" token that follows the mouse in world space.
## For now: it just follows the cursor and destroys itself on mouse release.

@export var follow_lerp_speed: float = 20.0

var mouse_velocity: Vector2 = Vector2.ZERO
var _last_mouse_pos: Vector2 = Vector2.ZERO
var _has_last_pos: bool = false


func _ready() -> void:
	var mouse := get_global_mouse_position()
	global_position = mouse
	_last_mouse_pos = mouse
	_has_last_pos = true


func _process(delta: float) -> void:
	var mouse := get_global_mouse_position()

	if _has_last_pos and delta > 0.0:
		mouse_velocity = (mouse - _last_mouse_pos) / delta
	_last_mouse_pos = mouse
	_has_last_pos = true

	global_position = global_position.lerp(mouse, follow_lerp_speed * delta)


func _input(event: InputEvent) -> void:
	# When player releases left click, destroy this held token (for now)
	if event is InputEventMouseButton \
	and event.button_index == MOUSE_BUTTON_LEFT \
	and not event.pressed:
		queue_free()
