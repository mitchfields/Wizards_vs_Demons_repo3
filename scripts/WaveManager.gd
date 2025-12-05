# res://scripts/WaveManager.gd
extends Node

signal wave_started(wave_number: int, total_enemies: int)
signal enemy_spawned(enemy: Node2D)
signal enemy_died(enemy: Node2D)
signal enemy_hit_queen(enemy: Node2D)
signal wave_ended(wave_number: int)

@export var enemy_scenes       : Array[PackedScene] = []
@export var base_enemy_count  : int                = 12
@export var clusters_per_wave : int                = 3   # still used as fallback
@export var spawn_interval    : float              = 0.2
@export var cluster_interval  : float              = 1.5
@export var cluster_radius    : float              = 400.0

var wave_number     : int  = 0
var _active         : int  = 0
var _spawning       : bool = false
var cluster_origins : Array[Vector2] = []

@onready var _world = get_tree().current_scene


func is_wave_active() -> bool:
	return _spawning or (_active > 0)


func start_wave() -> void:
	if _spawning:
		return

	wave_number += 1
	var total_enemies: int = base_enemy_count + (wave_number - 1) * 2
	_active   = total_enemies
	_spawning = true
	emit_signal("wave_started", wave_number, total_enemies)

	# 1) Ask World for portal spawn origins
	cluster_origins.clear()
	var origins: Array = []

	if _world != null and _world.has_method("get_portal_spawn_origins"):
		origins = _world.get_portal_spawn_origins()

	# Fallback: if no portals, use old circle clusters
	if origins.is_empty():
		for i in range(clusters_per_wave):
			var ang    = randf() * TAU
			var origin = Vector2(cos(ang), sin(ang)) * cluster_radius
			origins.append(origin)

	for o in origins:
		cluster_origins.append(o)

	var cluster_count: int = max(1, cluster_origins.size())
	var paths: Array = []

	# 2) Compute path from each origin to queen (axial 0,0)
	for i in range(cluster_count):
		var start_axial: Vector2 = _world.world_to_axial(cluster_origins[i])
		var p: Array = GridManager.find_path(start_axial, Vector2.ZERO)
		if p.is_empty():
			push_error("Wave blocked from " + str(start_axial))
			_spawning = false
			return
		paths.append(p)

	# 3) Spawn enemies cluster-by-cluster, distributed across portals
	var spawned: int      = 0
	var per_cluster: int  = int(ceil(float(total_enemies) / float(cluster_count)))

	for i in range(cluster_count):
		for j in range(per_cluster):
			if spawned >= total_enemies:
				break
			_spawn_enemy_at(cluster_origins[i], paths[i])
			spawned += 1
			await get_tree().create_timer(spawn_interval).timeout

		if i < cluster_count - 1:
			await get_tree().create_timer(cluster_interval).timeout

	_spawning = false
	_check_wave_end()


func _spawn_enemy_at(origin: Vector2, path: Array) -> void:
	if enemy_scenes.is_empty():
		push_error("WaveManager: no enemy_scenes assigned!")
		return

	var scene: PackedScene = enemy_scenes[randi() % enemy_scenes.size()]
	var enemy := scene.instantiate() as CharacterBody2D
	enemy.position = origin + Vector2(randf_range(-20, 20), randf_range(-20, 20))
	add_child(enemy)
	emit_signal("enemy_spawned", enemy)

	if enemy.has_method("set_path"):
		enemy.set_path(path)

	if enemy.has_signal("died"):
		enemy.connect("died", Callable(self, "_on_enemy_died"))
	if enemy.has_signal("hit_queen"):
		enemy.connect("hit_queen", Callable(self, "_on_enemy_hit_queen"))


func _on_enemy_died(enemy: Node2D) -> void:
	_active -= 1
	emit_signal("enemy_died", enemy)
	_check_wave_end()


func _on_enemy_hit_queen(enemy: Node2D) -> void:
	_active -= 1
	emit_signal("enemy_hit_queen", enemy)
	_check_wave_end()


func _check_wave_end() -> void:
	if not _spawning and _active <= 0:
		emit_signal("wave_ended", wave_number)
