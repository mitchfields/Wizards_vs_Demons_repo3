extends Node2D
class_name World

#——— CONFIGURATION ——————————————————————————————————————————————
enum HexOrientation { POINTY, FLAT }

@export var hex_orientation : HexOrientation = HexOrientation.POINTY
@export var hex_size        : float          = 50.0   # >0!
@export var queen_scene     : PackedScene
@export var initial_spawn_distance : int      = 5
@export var player_health   : int            = 20

@export_range(0.1, 1.0, 0.01)
var tilt_factor: float = 0.6  # 1.0 = flat; 0.6 ≈ nice tilt

# Camera zoom limits
@export var min_zoom: float = 0.6   # how close you can get (smaller = closer)
@export var max_zoom: float = 1.7   # how far you can zoom out

# Portals
@export var portal_scene        : PackedScene
@export var portal_min_distance : int = 3
@export var portal_max_distance : int = 6

# Starting walls / tiles
@export var starting_wall_tile_scene : PackedScene
@export var starting_wall_count      : int = 8
@export var starting_wall_radius     : int = 3

# Vision / fog of war
@export var queen_vision_radius  : int = 3   # how far fog is cleared around queen at start
@export var tile_vision_radius   : int = 2   # vision granted by placed tiles
@export var wizard_vision_radius : int = 1   # vision granted by wizards

# Drag–and–drop state (tile shop)
var _dragging_preview : Node2D      = null
var _dragging_scene   : PackedScene = null
var _panning          : bool        = false

# Path‐blocking checks
var _last_spawn_axial   : Vector2 = Vector2.ZERO
var initial_spawn_world : Vector2

# Track the queen’s hex so we treat it as “occupied”
var queen_axial_coords : Vector2 = Vector2.ZERO

@onready var camera       : Camera2D = $Camera2D
@onready var wave_manager : Node     = $GameLayer/WaveManager
@onready var fog_of_war   : FogOfWar = $FogOfWar

# Track all enemy portals in axial space (relative to the Queen at 0,0)
var portals_axial: Array[Vector2] = []


func _ready() -> void:
	# clamp hex_size
	hex_size = max(hex_size, 0.1)
	randomize()

	# set initial zoom into a safe range
	_set_zoom(camera.zoom.x)

	# 1) spawn Queen, record her axial, and center camera
	var q := _spawn_queen()
	if q:
		queen_axial_coords = world_to_axial(q.position)
		camera.make_current()
		camera.global_position = q.position

		# initial vision around the queen
		if fog_of_war:
			fog_of_war.reveal_around(queen_axial_coords, queen_vision_radius)

	# 2) record a world‐space “spawn origin” for path‐checks
	initial_spawn_world = axial_to_world(Vector2(initial_spawn_distance, 0))

	# 2a) spawn some starter walls/tiles around the queen
	_spawn_initial_walls()

	# 2b) spawn the very first portal (no camera pan)
	_spawn_initial_portal()

	# 3) listen for enemies hitting the queen
	wave_manager.connect("enemy_spawned", Callable(self, "_on_enemy_spawned"))

	# 4) listen for wave end so we can spawn portals BETWEEN waves
	wave_manager.connect("wave_ended", Callable(self, "_on_wave_ended"))


func _process(_delta: float) -> void:
	_update_y_sort()


# Clamp and apply camera zoom
func _set_zoom(target: float) -> void:
	var z: float = clamp(target, min_zoom, max_zoom)
	camera.zoom = Vector2(z, z)


func _on_enemy_spawned(enemy: Node2D) -> void:
	if enemy.has_signal("hit_queen"):
		enemy.connect("hit_queen", Callable(self, "_on_enemy_hit_queen"))


func _on_enemy_hit_queen(_enemy: Node2D) -> void:
	player_health -= 1
	print("Player health:", player_health)
	if player_health <= 0:
		get_tree().change_scene_to_file("res://scenes/GameOver.tscn")


func _input(event: InputEvent) -> void:
	# — Zoom & pan —
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				# zoom IN (smaller zoom value)
				_set_zoom(camera.zoom.x * 1.1)
				return
			MOUSE_BUTTON_WHEEL_DOWN:
				# zoom OUT (bigger zoom value)
				_set_zoom(camera.zoom.x * 0.9)
				return
			MOUSE_BUTTON_MIDDLE:
				_panning = true
				return
	elif event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_MIDDLE:
		_panning = false
		return

	# — Dragging preview from shop (hex tiles) —
	if _dragging_preview:
		if event is InputEventMouseMotion:
			_dragging_preview.global_position = get_global_mouse_position()
		elif event is InputEventMouseButton \
		and event.button_index == MOUSE_BUTTON_LEFT \
		and not event.pressed:
			var drop_y: float = get_global_mouse_position().y
			var screen_h: float = get_viewport().get_visible_rect().size.y
			if drop_y < screen_h * 0.9:
				_spawn_hex(_dragging_scene)
			_end_drag()
		return

	# — Continue panning? —
	if _panning and event is InputEventMouseMotion:
		# divide by zoom so pan speed feels consistent at all zoom levels
		camera.global_position -= event.relative / camera.zoom
		return


func start_drag(scene_to_spawn: PackedScene) -> void:
	if _dragging_preview:
		_dragging_preview.queue_free()
	_dragging_scene   = scene_to_spawn
	_dragging_preview = scene_to_spawn.instantiate() as Node2D
	add_child(_dragging_preview)
	_dragging_preview.modulate = Color(1, 1, 1, 0.6)
	_dragging_preview.scale    = Vector2(0.8, 0.8)
	_dragging_preview.z_index  = 999


func _end_drag() -> void:
	if _dragging_preview:
		_dragging_preview.queue_free()
	_dragging_preview = null
	_dragging_scene   = null


func _spawn_queen() -> Node2D:
	if not queen_scene:
		push_error("World.gd: queen_scene not assigned!")
		return null
	var q := queen_scene.instantiate() as Node2D
	q.position = axial_to_world(Vector2.ZERO)
	add_child(q)
	return q


func _spawn_hex(scene: PackedScene) -> bool:
	if scene == null:
		return false

	# 1) figure out which hex we clicked
	var world_pos: Vector2 = get_global_mouse_position()
	var desired  : Vector2 = world_to_axial(world_pos)
	var axial    : Vector2 = desired

	# 2) if that hex is occupied by any tile or the queen, find the closest free hex
	if GridManager.tiles.has(axial) or axial == queen_axial_coords:
		axial = _find_nearest_empty(desired)

	# 3) pick the furthest spawn‐origin for our path check
	var origins: Array = wave_manager.cluster_origins.duplicate()
	if origins.size() == 0:
		origins.append(initial_spawn_world)

	var furthest: Vector2 = origins[0]
	var best_d  : int = GridManager.distance_map.get(world_to_axial(furthest), -1)
	for world_o in origins:
		var d: int = GridManager.distance_map.get(world_to_axial(world_o), -1)
		if d > best_d:
			best_d = d
			furthest = world_o
	_last_spawn_axial = world_to_axial(furthest)

	# 4) instantiate the tile at that (possibly adjusted) axial
	var h := scene.instantiate() as HexagonTile
	h.axial_coords = axial
	h.position     = axial_to_world(axial)
	add_child(h)

	# 5) rebuild the path map & test for blocking
	GridManager.register_tile(h)
	GridManager._rebuild_distance_map()
	if not GridManager.distance_map.has(_last_spawn_axial):
		# undo placement if it blocks all paths
		for dir in GridManager.DIRECTIONS:
			var nb: Vector2 = axial + dir
			if GridManager.tiles.has(nb):
				var nbr = GridManager.tiles[nb]
				if is_instance_valid(nbr) and nbr.neighbors.has(h):
					nbr.neighbors.erase(h)
		GridManager.deregister_tile(h)
		h.queue_free()
		return false

	# 6) wire up neighbors + play ripple
	for dir in GridManager.DIRECTIONS:
		var nax: Vector2 = axial + dir
		if GridManager.tiles.has(nax):
			var neigh = GridManager.tiles[nax]
			if is_instance_valid(neigh):
				h.neighbors.append(neigh)
				neigh.neighbors.append(h)
	if h.has_method("play_placement_ripple"):
		h.play_placement_ripple()

	# reveal vision around this newly placed tile
	if fog_of_war:
		fog_of_war.reveal_around(axial, tile_vision_radius)

	return true


func _spawn_hex_at_axial(axial: Vector2, scene: PackedScene) -> bool:
	if scene == null:
		return false

	# Skip if something already occupies this hex or it's the queen
	if GridManager.tiles.has(axial) or axial == queen_axial_coords:
		return false

	# 3) pick the furthest spawn‐origin for our path check
	var origins: Array = wave_manager.cluster_origins.duplicate()
	if origins.size() == 0:
		origins.append(initial_spawn_world)

	var furthest: Vector2 = origins[0]
	var best_d  : int = GridManager.distance_map.get(world_to_axial(furthest), -1)
	for world_o in origins:
		var d: int = GridManager.distance_map.get(world_to_axial(world_o), -1)
		if d > best_d:
			best_d = d
			furthest = world_o
	_last_spawn_axial = world_to_axial(furthest)

	# 4) instantiate the tile at that axial
	var h := scene.instantiate() as HexagonTile
	h.axial_coords = axial
	h.position     = axial_to_world(axial)
	add_child(h)

	# 5) rebuild the path map & test for blocking
	GridManager.register_tile(h)
	GridManager._rebuild_distance_map()
	if not GridManager.distance_map.has(_last_spawn_axial):
		# undo placement if it blocks all paths
		for dir in GridManager.DIRECTIONS:
			var nb: Vector2 = axial + dir
			if GridManager.tiles.has(nb):
				var nbr = GridManager.tiles[nb]
				if is_instance_valid(nbr) and nbr.neighbors.has(h):
					nbr.neighbors.erase(h)
		GridManager.deregister_tile(h)
		h.queue_free()
		return false

	# 6) wire up neighbors + play ripple
	for dir in GridManager.DIRECTIONS:
		var nax: Vector2 = axial + dir
		if GridManager.tiles.has(nax):
			var neigh2 = GridManager.tiles[nax]
			if is_instance_valid(neigh2):
				h.neighbors.append(neigh2)
				neigh2.neighbors.append(h)
	if h.has_method("play_placement_ripple"):
		h.play_placement_ripple()

	# reveal vision around this auto-placed tile
	if fog_of_war:
		fog_of_war.reveal_around(axial, tile_vision_radius)

	return true


func _spawn_initial_walls() -> void:
	if starting_wall_tile_scene == null:
		return
	if starting_wall_count <= 0 or starting_wall_radius <= 0:
		return

	var center: Vector2 = queen_axial_coords
	var placed: int = 0
	var attempts: int = 0
	var max_attempts: int = starting_wall_count * 20

	while placed < starting_wall_count and attempts < max_attempts:
		attempts += 1

		var q := randi_range(-starting_wall_radius, starting_wall_radius)
		var r := randi_range(-starting_wall_radius, starting_wall_radius)
		var candidate: Vector2 = center + Vector2(q, r)

		# keep within a hex "disc"
		if _axial_distance(center, candidate) > starting_wall_radius:
			continue

		# never place on the Queen's own hex
		if candidate == queen_axial_coords:
			continue

		# don't double place
		if GridManager.tiles.has(candidate):
			continue

		if _spawn_hex_at_axial(candidate, starting_wall_tile_scene):
			placed += 1


#———————————————————————————————————————————————————————————————
# Find the nearest axial-hex not occupied by a tile or queen
func _find_nearest_empty(start: Vector2) -> Vector2:
	var visited: Array[Vector2] = []
	var queue  : Array[Vector2] = []
	visited.append(start)
	queue.append(start)

	while queue.size() > 0:
		var current: Vector2 = queue.pop_front()
		for dir in GridManager.DIRECTIONS:
			var neighbor: Vector2 = current + dir
			if visited.has(neighbor):
				continue
			visited.append(neighbor)
			# skip both placed tiles and the queen
			if not GridManager.tiles.has(neighbor) and neighbor != queen_axial_coords:
				return neighbor
			queue.append(neighbor)

	# fallback: return original if nowhere else
	return start


#———————————————————————————————————————————————————————————————
# Called by HeldWizard when the player lets go of the mouse.
# world_pos = mouse position in world space
# placed_scene = which wizard/turret scene to spawn
func try_place_wizard_from_hand(world_pos: Vector2, placed_scene: PackedScene) -> bool:
	if placed_scene == null:
		return false

	# 1) Convert mouse position to axial hex coords
	var axial: Vector2 = world_to_axial(world_pos)

	# 2) There must already be a tile here (coin‐placed or pre-placed)
	if not GridManager.tiles.has(axial):
		return false

	var tile = GridManager.tiles[axial]
	if tile == null:
		return false

	# 3) Only allow on "Normal" empty tiles
	if tile.has_method("can_place_wizard") and not tile.can_place_wizard():
		return false

	# 4) Spawn the wizard/turret
	var turret := placed_scene.instantiate() as Node2D
	if turret == null:
		return false

	add_child(turret)
	turret.global_position = axial_to_world(axial)

	# 5) Mark that tile as occupied
	if tile.has_method("set_wizard"):
		tile.set_wizard(turret)

	# 6) Wizards give (usually smaller) vision radius
	if fog_of_war:
		fog_of_war.reveal_around(axial, wizard_vision_radius)

	return true


#———————————————————————————————————————————————————————————————
# PORTAL SPAWNING + CAMERA BEHAVIOR
#———————————————————————————————————————————————————————————————

func get_portal_spawn_origins() -> Array:
	# World positions used by WaveManager as enemy spawn points
	var result: Array = []
	for a in portals_axial:
		result.append(axial_to_world(a))
	return result


func _spawn_initial_portal() -> void:
	if portal_scene == null:
		return

	var axial: Vector2 = _pick_portal_axial()
	_spawn_portal(axial)


func _spawn_portal(axial: Vector2) -> Node2D:
	if portal_scene == null:
		return null

	# Don’t double‐spawn portals on the same hex
	if portals_axial.has(axial):
		return null

	var portal := portal_scene.instantiate() as Node2D
	add_child(portal)
	portal.global_position = axial_to_world(axial)

	if portal.has_method("set_axial"):
		portal.set_axial(axial)

	portals_axial.append(axial)
	return portal


func _pick_portal_axial() -> Vector2:
	# Use GridManager.distance_map to find reachable hexes in a distance band
	var candidates: Array[Vector2] = []

	for k in GridManager.distance_map.keys():
		var dist: int = GridManager.distance_map[k]
		if dist < portal_min_distance or dist > portal_max_distance:
			continue
		if k == queen_axial_coords:
			continue
		if portals_axial.has(k):
			continue
		candidates.append(k)

	if candidates.is_empty():
		# Fallback: farthest reachable hex that isn’t the Queen and not an existing portal
		var best_axial: Vector2 = Vector2.ZERO
		var best_d: int = -1
		for k2 in GridManager.distance_map.keys():
			var d: int = GridManager.distance_map[k2]
			if k2 == queen_axial_coords:
				continue
			if portals_axial.has(k2):
				continue
			if d > best_d:
				best_d = d
				best_axial = k2
		return best_axial

	return candidates[randi() % candidates.size()]


func _do_portal_intro_sequence(axial: Vector2) -> void:
	# Spawn the portal, pan camera to it, let it animate, then pan back to the Queen
	var portal := _spawn_portal(axial)
	if portal == null:
		return

	var portal_pos: Vector2 = axial_to_world(axial)
	var queen_pos : Vector2 = axial_to_world(queen_axial_coords)

	# 1) Pan camera to the new portal
	var tween1 := get_tree().create_tween()
	tween1.tween_property(camera, "global_position", portal_pos, 0.8) \
		.set_trans(Tween.TRANS_SINE) \
		.set_ease(Tween.EASE_IN_OUT)
	await tween1.finished

	# 2) Let the portal do its spawn animation (or simple pause)
	if portal.has_method("play_spawn_animation"):
		await portal.play_spawn_animation()
	else:
		await get_tree().create_timer(0.6).timeout

	# 3) Pan back to the Queen / stronghold
	var tween2 := get_tree().create_tween()
	tween2.tween_property(camera, "global_position", queen_pos, 0.8) \
		.set_trans(Tween.TRANS_SINE) \
		.set_ease(Tween.EASE_IN_OUT)
	await tween2.finished


func _on_wave_ended(wave_number: int) -> void:
	# waves 2,6,10,... get new portals
	if wave_number % 4 != 2:
		return

	var axial: Vector2 = _pick_portal_axial()
	await _do_portal_intro_sequence(axial)


func handle_start_wave_pressed() -> void:
	# Called by GameUI when the player hits "Start Wave".
	# Now this ONLY starts the wave; portal spawning happens on wave_ended.
	if wave_manager.is_wave_active():
		return

	wave_manager.start_wave()


#——— GLOBAL Y-SORT (no groups) ———————————————

func _update_y_sort() -> void:
	var nodes: Array = []
	_collect_y_sort_nodes(self, nodes)

	for n in nodes:
		var n2d := n as Node2D
		n2d.z_as_relative = false
		n2d.z_index = int(n2d.global_position.y)


func _collect_y_sort_nodes(root: Node, out: Array) -> void:
	for c in root.get_children():
		# Don’t touch UI or special nodes
		if c is CanvasLayer:
			continue
		if c is Camera2D:
			continue
		if c is FogOfWar:
			continue

		if c is Node2D:
			out.append(c)

		_collect_y_sort_nodes(c, out)


#——— HEX MATH UTILS ——————————————————————————————————————————————

func axial_to_cube(a: Vector2) -> Vector3:
	return Vector3(a.x, -a.x - a.y, a.y)


func cube_to_axial(c: Vector3) -> Vector2:
	return Vector2(c.x, c.z)


func cube_round(c: Vector3) -> Vector3:
	var rx: float = round(c.x)
	var ry: float = round(c.y)
	var rz: float = round(c.z)

	var dx: float = abs(rx - c.x)
	var dy: float = abs(ry - c.y)
	var dz: float = abs(rz - c.z)

	if dx > dy and dx > dz:
		rx = -ry - rz
	elif dy > dz:
		ry = -rx - rz
	else:
		rz = -rx - ry

	return Vector3(rx, ry, rz)


func world_to_axial(w: Vector2) -> Vector2:
	# Screen → board: undo tilt on Y
	var t: float = tilt_factor
	var board: Vector2 = Vector2(w.x, w.y / t)

	var q: float
	var r: float
	if hex_orientation == HexOrientation.POINTY:
		q = (2.0 / 3.0 * board.x) / hex_size
		r = ((-1.0 / 3.0 * board.x) + (sqrt(3) / 3.0 * board.y)) / hex_size
	else:
		q = ((sqrt(3) / 3.0 * board.x) - (1.0 / 3.0 * board.y)) / hex_size
		r = (2.0 / 3.0 * board.y) / hex_size

	var cube: Vector3 = cube_round(Vector3(q, -q - r, r))
	return cube_to_axial(cube)


func axial_to_world(a: Vector2) -> Vector2:
	# Axial → board (classic flat hex layout)
	var base: Vector2
	if hex_orientation == HexOrientation.POINTY:
		base = Vector2(
			hex_size * 1.5 * a.x,
			hex_size * sqrt(3) * (a.y + a.x * 0.5)
		)
	else:
		base = Vector2(
			hex_size * sqrt(3) * (a.x + 0.5 * a.y),
			hex_size * 1.5 * a.y
		)

	# Board → screen: apply tilt on Y
	var t: float = tilt_factor
	return Vector2(base.x, base.y * t)


func _axial_distance(a: Vector2, b: Vector2) -> int:
	var dq: int = int(a.x - b.x)
	var dr: int = int(a.y - b.y)
	var ds: int = -dq - dr
	return max(abs(dq), max(abs(dr), abs(ds)))
