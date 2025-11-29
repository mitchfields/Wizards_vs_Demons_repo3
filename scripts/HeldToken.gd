extends Node2D

## Ghost token that follows the mouse in world space.
## On drop:
## - If over stack (same logic as pickup): tell tray to return a coin
## - Else: spend the token by calling World._spawn_hex(HexagonTile.tscn)

@export var follow_lerp_speed: float = 20.0

const TOKEN_HEX_SCENE: PackedScene = preload("res://scenes/HexagonTile.tscn")

var mouse_velocity: Vector2 = Vector2.ZERO
var _last_mouse_pos: Vector2 = Vector2.ZERO
var _has_last_pos: bool = false

# Set by TokenTray when spawned
var stack_tray: Node = null


func _ready() -> void:
	var mouse: Vector2 = get_global_mouse_position()
	global_position = mouse
	_last_mouse_pos = mouse
	_has_last_pos = true


func _process(delta: float) -> void:
	var mouse: Vector2 = get_global_mouse_position()

	if _has_last_pos and delta > 0.0:
		mouse_velocity = (mouse - _last_mouse_pos) / delta
	_last_mouse_pos = mouse
	_has_last_pos = true

	global_position = global_position.lerp(mouse, follow_lerp_speed * delta)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton \
	and event.button_index == MOUSE_BUTTON_LEFT \
	and not event.pressed:
		_handle_drop()


func _handle_drop() -> void:
	var world_pos: Vector2 = get_global_mouse_position()
	var returned_to_stack: bool = false

	# 1) Try to return to the stack using the SAME logic as pickup
	if stack_tray != null and stack_tray.has_method("_is_mouse_over_stack"):
		var over_variant: Variant = stack_tray.call("_is_mouse_over_stack")
		var over: bool = bool(over_variant)
		if over and stack_tray.has_method("return_token_from_hand"):
			stack_tray.call("return_token_from_hand", world_pos)
			returned_to_stack = true

	# 2) If not returned to the stack, spend token on the board
	if not returned_to_stack and TOKEN_HEX_SCENE != null:
		var world: Node = get_tree().current_scene
		# World.gd has _spawn_hex(scene: PackedScene) -> bool
		if world != null and world.has_method("_spawn_hex"):
			world.call("_spawn_hex", TOKEN_HEX_SCENE)

	# 3) Destroy ghost either way
	queue_free()
