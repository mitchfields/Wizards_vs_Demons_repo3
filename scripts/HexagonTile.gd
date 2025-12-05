# res://scripts/HexagonTile.gd
class_name HexagonTile
extends Node2D

@export var axial_coords: Vector2
@export var ripple_radius: int = 10
var neighbors: Array = []

func _ready() -> void:
	scale = Vector2.ONE
	rotation_degrees = 0

func play_placement_ripple() -> void:
	_create_ball_bounce()

	var layers = _bfs_layers(ripple_radius)
	var max_ring = layers.size() - 1
	for ring_index in range(1, layers.size()):
		await get_tree().create_timer(ring_index * 0.05).timeout

		var intensity: float
		if max_ring > 0:
			intensity = 1.0 - float(ring_index) / float(max_ring)
		else:
			intensity = 1.0

		for tile in layers[ring_index]:
			tile._create_ripple_tween_with_falloff(intensity)

func _create_ball_bounce() -> void:
	var peaks = [1.4, 1.12, 1.05]
	var durations = [0.1, 0.08, 0.06]
	var tw = create_tween()
	for i in range(peaks.size()):
		var target = Vector2.ONE * peaks[i]
		var d = durations[i]
		tw.tween_property(self, "scale", target, d) \
		  .set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tw.tween_property(self, "scale", Vector2.ONE, d) \
		  .set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)

func _create_ripple_tween_with_falloff(intensity: float) -> void:
	var base_trough = 0.85
	var trough_scale = clamp(1.0 - (1.0 - base_trough) * intensity, base_trough, 1.0)
	trough_scale *= (0.9 + randf() * 0.1)
	var dur = lerp(0.1, 0.2, 1.0 - intensity)
	var max_rot = 15.0
	var rot = (randf() * 2.0 - 1.0) * max_rot * intensity

	var tw = create_tween()
	tw.tween_property(self, "scale", Vector2(trough_scale, trough_scale), dur) \
	  .set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "rotation_degrees", rot, dur) \
	  .set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "scale", Vector2.ONE, dur) \
	  .set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "rotation_degrees", 0, dur) \
	  .set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)

func _bfs_layers(max_radius: int) -> Array:
	var visited = { self: true }
	var frontier = [ self ]
	var layers = []
	var depth = 0
	while frontier.size() > 0 and depth <= max_radius:
		layers.append(frontier.duplicate())
		var next_frontier = []
		for t in frontier:
			for n in t.neighbors:
				if not visited.has(n):
					visited[n] = true
					next_frontier.append(n)
		frontier = next_frontier
		depth += 1
	return layers
# -------------------------------------------------------------------
# Wizard / tower placement helpers
# -------------------------------------------------------------------

# Simple type tag. For now, leave "Normal" for regular tiles.
# Set to "Modifier" or "Power" in the Inspector for special tiles later.
@export var tile_type: String = "Normal"

# Which wizard/tower is sitting on this tile (if any)
var wizard: Node2D = null


func has_wizard() -> bool:
	return wizard != null and is_instance_valid(wizard)


func can_place_wizard() -> bool:
	# Only allow wizards on NORMAL tiles that have no wizard yet
	if tile_type != "Normal":
		return false
	return not has_wizard()


func set_wizard(new_wizard: Node2D) -> void:
	wizard = new_wizard
