extends Node2D

@export var world: World
@export var camera: Camera2D

@export var base_color: Color      = Color(1, 1, 1, 0.25)
@export var base_width: float      = 1.0

@export var hover_color: Color     = Color(1, 0.9, 0.4, 0.95)
@export var hover_width: float     = 2.5

@export var path_color: Color      = Color(0.4, 0.9, 1.0, 0.9)  # base color, alpha modulated
@export var path_tail_len: float   = 10.0   # how long the fade-out tail lasts (in "steps")
@export var path_wave_speed: float = 4.0    # how fast the pulse travels from portal → queen

@export var marching_speed: float  = 8.0    # marching ants speed

@export var rotation_offset_degrees: float = 30.0  # rotate hex outline to match your art

# NEW: don't draw the whole BFS universe, just a radius around queen
@export var max_draw_distance: int = 30

var _phase_march: float = 0.0
var _phase_path:  float = 0.0


func _ready() -> void:
	z_index = -100
	z_as_relative = false


func _process(delta: float) -> void:
	_phase_march += delta * marching_speed
	if _phase_march > 10000.0:
		_phase_march = 0.0

	_phase_path += path_wave_speed * delta
	if _phase_path > 10000.0:
		_phase_path = 0.0

	queue_redraw()


func _draw() -> void:
	if world == null or camera == null:
		return

	# Mouse + holding state
	var mouse_world: Vector2 = world.get_global_mouse_position()
	var hovered_axial: Vector2 = world.world_to_axial(mouse_world)

	var holding_tile: bool    = world._dragging_preview != null
	var holding_wizard: bool  = get_tree().get_nodes_in_group("held_wizard").size() > 0
	var holding_coin: bool    = get_tree().get_nodes_in_group("held_coin").size() > 0
	var holding: bool         = holding_tile or holding_wizard or holding_coin

	# Visible region (in tilted world coords)
	var viewport_size: Vector2 = get_viewport_rect().size
	var half: Vector2          = viewport_size * 0.5
	var cam_center: Vector2    = camera.global_position
	var visible_rect := Rect2(
		cam_center - half * camera.zoom * 1.2,
		viewport_size * camera.zoom * 1.2
	)

	# Precompute path indices (0 at portal → increasing toward queen)
	var path_indices: Dictionary = {}
	var max_step: int = -1

	if world.portals_axial.size() > 0:
		for portal_axial in world.portals_axial:
			var path: Array = GridManager.find_path(portal_axial, Vector2.ZERO)
			var n: int = path.size()
			for i in range(n):
				var a: Vector2 = path[i]
				var step_idx: int = i
				if not path_indices.has(a) or step_idx < path_indices[a]:
					path_indices[a] = step_idx
				if step_idx > max_step:
					max_step = step_idx

	var march_phase_i: int = int(floor(_phase_march))
	var head: float = 0.0
	if max_step >= 0 and path_tail_len > 0.0:
		head = fmod(_phase_path, float(max_step) + path_tail_len)

	# Draw the board from distance_map, but only up to max_draw_distance
	for axial in GridManager.distance_map.keys():
		var dist: int = int(GridManager.distance_map[axial])
		if dist > max_draw_distance:
			continue

		var center: Vector2 = world.axial_to_world(axial)
		if not visible_rect.has_point(center):
			continue

		var pts: PackedVector2Array = _hex_points(center, world.hex_size, world.hex_orientation)

		# Base outline
		draw_polyline(pts, base_color, base_width, true)

		# Path fill pulse (portal → queen)
		if path_indices.has(axial) and max_step >= 0:
			var step_idx: int = path_indices[axial]
			var intensity: float = _path_intensity(step_idx, head)
			if intensity > 0.01:
				var poly := pts.duplicate()
				if poly.size() > 0:
					poly.remove_at(poly.size() - 1)
				var c: Color = path_color
				c.a *= clamp(intensity, 0.0, 1.0)
				draw_colored_polygon(poly, c)

		# Hover marching ants
		if holding and axial == hovered_axial:
			_draw_marching_outline(pts, hover_color, hover_width, march_phase_i)


func _hex_points(center: Vector2, radius: float, orientation: int) -> PackedVector2Array:
	var pts: PackedVector2Array = PackedVector2Array()
	var rot := deg_to_rad(rotation_offset_degrees)
	var t: float = world.tilt_factor  # use the world's tilt so centers & shapes match

	for i in range(6):
		var base_angle: float = i * PI / 3.0
		var angle: float
		if orientation == World.HexOrientation.POINTY:
			angle = base_angle + rot
		else:
			angle = base_angle

		# local offset in "board space"
		var local_x: float = cos(angle) * radius
		var local_y: float = sin(angle) * radius

		# apply the same tilt as the centers (Y * tilt_factor)
		var offset := Vector2(local_x, local_y * t)

		pts.append(center + offset)

	# close the loop
	pts.append(pts[0])
	return pts


func _draw_marching_outline(pts: PackedVector2Array, color: Color, width: float, phase_i: int) -> void:
	var seg_index: int = 0
	for i in range(6):
		var p0: Vector2 = pts[i]
		var p1: Vector2 = pts[i + 1]
		var mid: Vector2 = (p0 + p1) * 0.5

		var segs: Array = [
			[p0, mid],
			[mid, p1]
		]

		for s in segs:
			var idx: int = seg_index
			seg_index += 1
			var on: bool = (((idx + phase_i) % 4) < 2)
			if on:
				draw_line(s[0], s[1], color, width)


func _path_intensity(step_idx: int, head: float) -> float:
	if path_tail_len <= 0.0:
		return 0.0

	var d: float = head - float(step_idx)
	if d < 0.0:
		return 0.0
	if d > path_tail_len:
		return 0.0

	var t: float = 1.0 - (d / path_tail_len)
	if t <= 0.0:
		return 0.0

	return t * t
