extends Node2D

## Ghost wizard that follows the mouse.
## On drop:
##  - Try to place on a valid hex tile (World.try_place_wizard_from_hand)
##  - If that fails, tell the tray to give it back.

@export var follow_lerp_speed: float = 30.0
@export var placed_scene: PackedScene  # e.g. res://scenes/SniperTurret.tscn

# Set by WizardTray when spawned
var wizard_tray: Node = null


func _ready() -> void:
	set_process(true)
	set_process_input(true)
	global_position = get_global_mouse_position()


func _process(delta: float) -> void:
	# SUPER simple: just stick to the mouse.
	# (If you want easing later, swap this for a lerp.)
	global_position = get_global_mouse_position()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton \
	and event.button_index == MOUSE_BUTTON_LEFT \
	and not event.pressed:
		_handle_drop()


func _handle_drop() -> void:
	var world_pos: Vector2 = get_global_mouse_position()
	var placed: bool = false

	# 1) Ask World to place this wizard on a tile
	var world: Node = get_tree().current_scene
	if world != null and world.has_method("try_place_wizard_from_hand"):
		placed = world.try_place_wizard_from_hand(world_pos, placed_scene)

	# 2) If placement failed, give it back to the tray
	if not placed and wizard_tray != null and wizard_tray.has_method("return_wizard_from_hand"):
		wizard_tray.return_wizard_from_hand(world_pos)

	# 3) Ghost always disappears after the drop
	queue_free()
