extends Node2D
class_name EnemyPortal

@export var axial_coords: Vector2 = Vector2.ZERO

func set_axial(a: Vector2) -> void:
	axial_coords = a

# Called by the World when a new portal spawns and the camera is looking at it.
# You can later wire this to an AnimationPlayer with a "spawn" animation.
func play_spawn_animation() -> void:
	var anim := get_node_or_null("AnimationPlayer") as AnimationPlayer
	if anim and anim.has_animation("spawn"):
		anim.play("spawn")
		await anim.animation_finished
	else:
		# Fallback: small pause so the camera linger feels good
		await get_tree().create_timer(0.6).timeout
