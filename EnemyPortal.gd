extends Node2D
class_name EnemyPortal

# axial position of this portal in the hex grid
var axial_coords: Vector2 = Vector2.ZERO

@onready var anim_sprite: AnimatedSprite2D = $AnimatedSprite2D


func set_axial(a: Vector2) -> void:
	axial_coords = a


# Called by World when a new portal appears and the camera is looking at it.
func play_spawn_animation() -> void:
	# Safety checks
	if anim_sprite == null:
		await get_tree().create_timer(0.6).timeout
		return

	if not anim_sprite.sprite_frames or not anim_sprite.sprite_frames.has_animation("spawn"):
		await get_tree().create_timer(0.6).timeout
		return

	# Play the spawn animation and wait until it finishes
	anim_sprite.play("spawn")
	await anim_sprite.animation_finished
