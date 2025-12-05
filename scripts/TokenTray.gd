extends Node2D

@export var coin_scene: PackedScene
@export var initial_items: int = 5
@export var spawn_height: float = -200.0
@export var spawn_interval: float = 0.08
@export var spawn_rotation_range_degrees: float = 6.0

@export var held_token_scene: PackedScene
@export var base_grab_radius: float = 80.0   # base radius around pile center

var _spawned_count: int = 0
var _spawn_timer: float = 0.0


func _ready() -> void:
	randomize()

	if spawn_interval <= 0.0:
		var i: int = 0
		while i < initial_items:
			_spawn_coin()
			_spawned_count += 1
			i += 1
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
		# tight horizontal stack like you wanted
		var x_offset: float = randf_range(-2, 2)
		node2d.position = Vector2(x_offset, spawn_height)
		node2d.rotation_degrees = randf_range(-spawn_rotation_range_degrees, spawn_rotation_range_degrees)


func _get_all_coins() -> Array[RigidBody2D]:
	var coins: Array[RigidBody2D] = []
	for child in get_children():
		if child is RigidBody2D:
			coins.append(child as RigidBody2D)
	return coins


func _input(event: InputEvent) -> void:
	# Grab stack on left mouse press
	if event is InputEventMouseButton \
	and event.button_index == MOUSE_BUTTON_LEFT \
	and event.pressed:
		if _is_mouse_over_stack():
			_on_stack_grabbed()


func _is_mouse_over_stack() -> bool:
	var mouse_world: Vector2 = get_global_mouse_position()
	return _is_world_pos_over_stack(mouse_world)


## Internal helper: same logic used for pickup AND drop
func _is_world_pos_over_stack(world_pos: Vector2) -> bool:
	var coins: Array[RigidBody2D] = _get_all_coins()
	if coins.is_empty():
		return false

	# Center of pile in LOCAL space (average of coin positions)
	var center: Vector2 = Vector2.ZERO
	var i: int = 0
	while i < coins.size():
		var c: RigidBody2D = coins[i]
		center += c.position
		i += 1
	center /= float(coins.size())

	# Radius based on furthest coin + padding
	var max_dist: float = 0.0
	i = 0
	while i < coins.size():
		var c2: RigidBody2D = coins[i]
		var d: float = center.distance_to(c2.position)
		if d > max_dist:
			max_dist = d
		i += 1

	var local_point: Vector2 = to_local(world_pos)
	var radius: float = max(base_grab_radius, max_dist + 40.0)

	return local_point.distance_to(center) <= radius


func _on_stack_grabbed() -> void:
	var coins: Array[RigidBody2D] = _get_all_coins()
	if coins.is_empty():
		return

	# 1) Randomly remove one coin from the pile
	var idx: int = int(randi() % coins.size())
	var removed_coin: RigidBody2D = coins[idx]
	if is_instance_valid(removed_coin):
		removed_coin.queue_free()

	# Refresh list now that one was removed
	coins = _get_all_coins()

	# 2) Strong impulse to remaining coins so the stack VERY CLEARLY reacts
	var i: int = 0
	while i < coins.size():
		var c: RigidBody2D = coins[i]
		if c != null:
			var impulse: Vector2 = Vector2(randf_range(-200.0, 200.0), -600.0)
			c.apply_impulse(impulse)
			c.linear_velocity += impulse * 0.2
		i += 1

	# 3) Spawn a HeldToken in the player's hand
	if held_token_scene != null:
		var held: Node = held_token_scene.instantiate()
		var root: Node = get_tree().current_scene
		if root != null:
			root.add_child(held)
			if held is Node2D:
				var held2d: Node2D = held as Node2D
				held2d.global_position = get_global_mouse_position()
			# Pass a reference to this tray so the HeldToken can call back
			held.set("stack_tray", self)


## Add a coin back just above the highest one and jostle the pile.
func return_token_from_hand(_world_pos: Vector2) -> void:
	if coin_scene == null:
		return

	var coins: Array[RigidBody2D] = _get_all_coins()
	var center: Vector2 = Vector2.ZERO
	var highest_y: float = 0.0
	var have_any: bool = false

	var i: int = 0
	while i < coins.size():
		var c: RigidBody2D = coins[i]
		center += c.position
		if not have_any or c.position.y < highest_y:
			highest_y = c.position.y
			have_any = true
		i += 1

	if have_any:
		center /= float(coins.size())
	else:
		center = Vector2.ZERO
		highest_y = 0.0

	var inst: Node = coin_scene.instantiate()
	add_child(inst)

	var new_coin_rb: RigidBody2D = null
	if inst is RigidBody2D:
		new_coin_rb = inst as RigidBody2D
		new_coin_rb.position = Vector2(center.x, highest_y - 40.0)
		var impulse_new: Vector2 = Vector2(0.0, -700.0)
		new_coin_rb.apply_impulse(impulse_new)
		new_coin_rb.linear_velocity += impulse_new * 0.3

	# Jostle the rest of the stack a bit
	coins = _get_all_coins()
	i = 0
	while i < coins.size():
		var c2: RigidBody2D = coins[i]
		if c2 != null and c2 != new_coin_rb:
			var impulse: Vector2 = Vector2(randf_range(-150.0, 150.0), -500.0)
			c2.apply_impulse(impulse)
			c2.linear_velocity += impulse * 0.25
		i += 1
