extends Node2D
class_name FogOfWar

@export var fog_hex_scene: PackedScene      # assign FogHex.tscn in inspector

# Which axial coords are "known" (revealed)
var _known: Dictionary = {}                 # Vector2 -> true
# Fog nodes only on the PERIMETER between known and unknown
var _fog_nodes: Dictionary = {}             # Vector2 -> Node2D

var _world: World = null

const HEX_DIRS := [
	Vector2(1, 0),
	Vector2(1, -1),
	Vector2(0, -1),
	Vector2(-1, 0),
	Vector2(-1, 1),
	Vector2(0, 1)
]


func _ready() -> void:
	_world = get_parent() as World
	if _world == null:
		push_error("FogOfWar.gd: parent is not World. Make FogOfWar a direct child of World.")
		return

	if fog_hex_scene == null:
		push_error("FogOfWar.gd: fog_hex_scene is not assigned. Set it in the inspector.")
		return


func reveal_around(center_axial: Vector2, radius: int) -> void:
	if _world == null or fog_hex_scene == null:
		return
	if radius <= 0:
		return

	# 1) Mark all cells in this radius as "known"
	var q_min: int = int(center_axial.x) - radius
	var q_max: int = int(center_axial.x) + radius
	var r_min: int = int(center_axial.y) - radius
	var r_max: int = int(center_axial.y) + radius

	for q in range(q_min, q_max + 1):
		for r in range(r_min, r_max + 1):
			var a := Vector2(q, r)
			if _world._axial_distance(center_axial, a) <= radius:
				_known[a] = true

	# 2) Rebuild the perimeter ring only
	_rebuild_perimeter()


func _rebuild_perimeter() -> void:
	if _world == null:
		return

	# Find all neighbors of known cells that are still unknown
	var needed: Dictionary = {}  # Vector2 -> true

	for key in _known.keys():
		var a: Vector2 = key
		for dir in HEX_DIRS:
			var nb: Vector2 = a + dir
			if not _known.has(nb):
				needed[nb] = true

	# Remove fog nodes that are no longer on the perimeter
	var to_remove: Array = _fog_nodes.keys()
	for k in to_remove:
		if not needed.has(k):
			var node: Node2D = _fog_nodes[k]
			if node != null and is_instance_valid(node):
				node.queue_free()
			_fog_nodes.erase(k)

	# Add fog nodes for any newly needed perimeter cells
	for k in needed.keys():
		if _fog_nodes.has(k):
			continue

		var fog := fog_hex_scene.instantiate() as Node2D
		add_child(fog)
		fog.global_position = _world.axial_to_world(k)
		fog.z_as_relative = false
		fog.z_index = 10000  # keep fog visually on top
		_fog_nodes[k] = fog
