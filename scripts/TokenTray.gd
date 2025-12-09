# res://scripts/TokenTray.gd
extends Node2D
class_name TokenTray

@export var coin_scene: PackedScene
@export var initial_items: int = 5
@export var spawn_height: float = -200.0
@export var spawn_interval: float = 0.08
@export var spawn_rotation_range_degrees: float = 6.0

@export var held_token_scene: PackedScene
@export var base_grab_radius: float = 80.0   # base radius around pile center

# Coins granted after each completed wave
@export var coins_per_wave: int = 5

var _spawned_count: int = 0
var _spawn_timer: float = 0.0


func _ready() -> void:
	randomize()

	# Initial pile
	if spawn_interval <= 0.0:
		var i: int = 0
		while i < initial_items:
			_spawn_coin()
			_spawned_count += 1
			i += 1
	else:
		set_physics_process(true)

	# Hook wave rewards from WaveManager (lives in World/GameLayer)
	var world := get_tree().current_scene
	if world and world.has_node("GameLayer/WaveManager"):
		var wm: Node = world.get_node("GameLayer/WaveManager")
		if not wm.is_connected("wave_ended", Callable(self, "_on_wave_ended")):
			wm.connect("wave_ended", Callable(self, "_on_wave_ended"))


func _physics_process(delta: float) -> void:
	# No timed spawning → turn off
	if spawn_interval <= 0.0:
		set_physics_process(false)
		return

	# Finished current target stack
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
		var x_offset: float = randf_range(-2.0, 2.0)
		node2d.position = Vector2(x_offset, spawn_height)
		node2d.rotation_degrees = randf_range(-spawn_rotation_range_degrees, spawn_rotation_range_degrees)


func _get_all_coins() -> Array[RigidBody2D]:
	var coins: Array[RigidBody2D] = []
	for child in get_children():
		if child is RigidBody2D:
			coins.append(child as RigidBody2D)
	return coins


func _input(event: InputEvent) -> void:
	# Grab a coin from the stack on left-click
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
		coins.remove_at(idx)
		removed_coin.queue_free()

	# 2) Jostle the remaining coins a bit for juice
	_burst_stack()

	# 3) Spawn a HeldToken in the player's hand
	if held_token_scene == null:
		return

	var held: Node2D = held_token_scene.instantiate() as Node2D
	if held == null:
		return

	get_tree().current_scene.add_child(held)
	if held.has_method("begin_drag_from_tray"):
		held.begin_drag_from_tray()


func _burst_stack() -> void:
	var coins: Array[RigidBody2D] = _get_all_coins()
	var i: int = 0
	while i < coins.size():
		var c: RigidBody2D = coins[i]
		if c:
			var impulse: Vector2 = Vector2(randf_range(-200.0, 200.0), -600.0)
			c.apply_impulse(impulse)
			c.linear_velocity += impulse * 0.2
		i += 1


func _on_wave_ended(_wave_number: int) -> void:
	# Reward coins after each completed wave,
	# spawning them EXACTLY the same way as the initial stack.
	if coins_per_wave <= 0:
		return

	if spawn_interval <= 0.0:
		# Instant-spawn case: do exactly what initial stack does
		var i: int = 0
		while i < coins_per_wave:
			_spawn_coin()
			_spawned_count += 1
			i += 1
	else:
		# Timed-spawn case: bump the target count and let _physics_process
		# use the same spawning logic as the initial pile.
		initial_items += coins_per_wave
		set_physics_process(true)
