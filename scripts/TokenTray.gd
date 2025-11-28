extends Node2D

@export var coin_scene: PackedScene
@export var initial_items: int = 5
@export var spawn_height: float = -200.0
@export var spawn_interval: float = 0.08  # seconds between spawns (set to 0 for instant)
@export var spawn_rotation_range_degrees: float = 6.0  # small random 2D rotation at spawn

# Scene to use for the ghost coin in the player's hand
@export var held_token_scene: PackedScene

# Base grab radius; we expand this based on actual coin spread
@export var base_grab_radius: float = 80.0

var _spawned_count: int = 0
var _spawn_timer: float = 0.0


func _ready() -> void:
	randomize()

	if spawn_interval <= 0.0:
		for i in range(initial_items):
			_spawn_coin()
			_spawned_count += 1
	else:
		set_physics_process(true)


func _physics_process(delta: float) -> void:
	if spawn_interval <= 0.0:
		set_physics_process(false)
		return

	if _spawned_count >= initial_items:
		set_physics_process(false)
		return

	_spawn_timer += delta

	while _spawn_timer >= spawn_interval and _spawned_count < initial_items:
		_spawn_timer -= spawn_interval
		_spawn_coin()
		_spawned_count += 1


func _spawn_coin() -> void:
	if coin_scene == null:
		return

	var inst: Node = coin_scene.instantiate()
	add_child(inst)

	if inst is Node2D:
		var node2d: Node2D = inst as Node2D
		var x_offset: float = randf_range(-1, 1)
		node2d.position = Vector2(x_offset, spawn_height)
		node2d.rotation_degrees = randf_range(-spawn_rotation_range_degrees, spawn_rotation_range_degrees)


func _get_all_coins() -> Array[RigidBody2D]:
	var coins: Array[RigidBody2D] = []
	for child in get_children():
		if child is RigidBody2D:
			coins.append(child as RigidBody2D)
	return coins


func _input(event: InputEvent) -> void:
	# React on left mouse press
	if event is InputEventMouseButton \
	and event.button_index == MOUSE_BUTTON_LEFT \
	and event.pressed:
		if _is_mouse_over_stack():
			_on_stack_grabbed()


func _is_mouse_over_stack() -> bool:
	var coins: Array[RigidBody2D] = _get_all_coins()
	if coins.is_empty():
		return false

	# Compute center of all coins in LOCAL space of this tray
	var center: Vector2 = Vector2.ZERO
	for c in coins:
		center += c.position
	center /= float(coins.size())

	# Compute a radius that covers the pile
	var max_dist: float = 0.0
	for c in coins:
		var d: float = center.distance_to(c.position)
		if d > max_dist:
			max_dist = d

	var mouse_world: Vector2 = get_global_mouse_position()
	var local_mouse: Vector2 = to_local(mouse_world)

	# Expand radius a bit so it's forgiving
	var radius: float = max(base_grab_radius, max_dist + 40.0)

	return local_mouse.distance_to(center) <= radius


func _on_stack_grabbed() -> void:
	var coins: Array[RigidBody2D] = _get_all_coins()
	if coins.is_empty():
		return

	# 1) Randomly remove one coin
	var idx: int = int(randi() % coins.size())
	var removed_coin: RigidBody2D = coins[idx]
	if is_instance_valid(removed_coin):
		removed_coin.queue_free()

	# Refresh list to avoid freed node
	coins = _get_all_coins()

	# 2) Strong impulse to remaining coins so the stack VERY CLEARLY reacts
	for c in coins:
		if c == null:
			continue
		var impulse: Vector2 = Vector2(randf_range(-50.0, 50.0), -600.0)
		c.apply_impulse(impulse)
		# Also nudge linear_velocity so it's guaranteed visible
		c.linear_velocity += impulse * 0.4

	# 3) Spawn a HeldToken in the player's hand
	if held_token_scene != null:
		var held: Node = held_token_scene.instantiate()
		var root: Node = get_tree().current_scene
		if root != null:
			root.add_child(held)
			if held is Node2D:
				var held2d: Node2D = held as Node2D
				held2d.global_position = get_global_mouse_position()
