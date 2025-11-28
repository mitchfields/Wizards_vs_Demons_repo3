extends Node2D

@export var coin_scene: PackedScene
@export var initial_items: int = 5
@export var spawn_height: float = -200.0
@export var spawn_interval: float = 0.1  # seconds between spawns (set to 0 for instant)

var _spawned_count: int = 0
var _spawn_timer: float = 0.0

func _ready() -> void:
	randomize()

	if spawn_interval <= 0.0:
		# Spawn everything instantly
		for i in range(initial_items):
			_spawn_coin()
			_spawned_count += 1
	else:
		# Staggered spawning in _physics_process
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

	var inst = coin_scene.instantiate()
	add_child(inst)

	if inst is Node2D:
		var x_offset := randf_range(-6, 6)
		inst.position = Vector2(x_offset, spawn_height)
