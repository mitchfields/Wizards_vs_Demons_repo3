extends Node2D
class_name FallingInventory
"""
A simple platform that can spawn items from a list and let them fall down.
We will use this for:
- WizardPlatform (bottom middle)
- ToolsPlatform (bottom left)
- TokenPlatform (right side)

Right now: just falling + snapping into simple horizontal slots.
"""

@export var item_pool: Array[PackedScene] = []  # scenes that can be spawned
@export var max_slots: int = 4                  # how many items fit on this platform
@export var initial_items: int = 0              # how many to spawn on _ready

@export var slot_spacing: float = 120.0         # distance between slots
@export var spawn_height: float = -200.0        # Y above the platform to spawn
@export var floor_y: float = 0.0                # Y where items "land"
@export var gravity: float = 2000.0             # fall speed

# Internal data
var _slots = []      # each: { x, occupied, item }
var _falling = []    # each: { node, vel: Vector2 }

func _ready() -> void:
	randomize()
	_init_slots()

	# For now, this does nothing unless you set initial_items > 0 in the Inspector.
	for i in range(initial_items):
		spawn_random_item()


func _physics_process(delta: float) -> void:
	_update_falling(delta)


# -------------------------------------------------------------------
# PUBLIC: we will use these later from other scripts
# -------------------------------------------------------------------

func spawn_random_item() -> Node2D:
	if item_pool.is_empty():
		# No scenes assigned yet – this is OK for now.
		return null

	var scene: PackedScene = item_pool[randi() % item_pool.size()]
	if scene == null:
		return null

	var inst := scene.instantiate() as Node2D
	add_child(inst)
	inst.position = Vector2(0, spawn_height)

	_falling.append({
		"node": inst,
		"vel": Vector2.ZERO,
	})
	return inst


func give_items(count: int) -> void:
	for i in range(count):
		spawn_random_item()


func get_items() -> Array:
	var result: Array = []
	for s in _slots:
		if s["occupied"] and s["item"]:
			result.append(s["item"])
	return result


# -------------------------------------------------------------------
# INTERNAL
# -------------------------------------------------------------------

func _init_slots() -> void:
	_slots.clear()
	var half := float(max_slots - 1) * 0.5
	for i in range(max_slots):
		var x := (i - half) * slot_spacing
		_slots.append({
			"x": x,
			"occupied": false,
			"item": null,
		})


func _update_falling(delta: float) -> void:
	if _falling.is_empty():
		return

	var still_falling: Array = []

	for entry in _falling:
		var node: Node2D = entry["node"]
		var vel: Vector2   = entry["vel"]

		if node == null or not node.is_inside_tree():
			continue

		vel.y += gravity * delta
		node.position += vel * delta

		if node.position.y >= floor_y:
			node.position.y = floor_y
			entry["vel"] = Vector2.ZERO
			_place_in_slot(node)
		else:
			entry["vel"] = vel
			still_falling.append(entry)

	_falling = still_falling


func _place_in_slot(node: Node2D) -> void:
	var slot_index := _find_free_slot()
	if slot_index == -1:
		# No free slots; just leave it where it landed.
		return

	var slot = _slots[slot_index]
	slot["occupied"] = true
	slot["item"] = node
	_slots[slot_index] = slot

	var target_pos := Vector2(slot["x"], floor_y)

	var tw := create_tween()
	tw.tween_property(node, "position", target_pos, 0.25) \
		.set_trans(Tween.TRANS_BACK) \
		.set_ease(Tween.EASE_OUT)


func _find_free_slot() -> int:
	for i in range(_slots.size()):
		if not _slots[i]["occupied"]:
			return i
	return -1
