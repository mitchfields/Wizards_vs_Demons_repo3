extends Node2D

## Bottom-middle wizard tray.
## Wizards fall down here as RigidBody2D (WizardItem.tscn).
## Clicking a wizard:
##   - removes that wizard from tray
##   - spawns a HeldWizard that sticks to the mouse.

@export var wizard_scene: PackedScene      # e.g. res://scenes/WizardItem.tscn
@export var held_wizard_scene: PackedScene # e.g. res://scenes/HeldWizard.tscn
@export var initial_items: int = 3
@export var spawn_height: float = -50.0
@export var spawn_x_spread: float = 150.0

var _spawned_count: int = 0


func _ready() -> void:
	randomize()
	for i in range(initial_items):
		_spawn_wizard()


func _spawn_wizard() -> void:
	if wizard_scene == null:
		return

	var inst := wizard_scene.instantiate()
	add_child(inst)

	if inst is RigidBody2D:
		var rb: RigidBody2D = inst
		var x_offset: float = randf_range(-spawn_x_spread * 0.5, spawn_x_spread * 0.5)
		rb.position = Vector2(x_offset, spawn_height)

		# WizardItem.gd emits clicked(self) when you click it
		if rb.has_signal("clicked"):
			rb.connect("clicked", Callable(self, "_on_wizard_clicked"))


func _on_wizard_clicked(item: RigidBody2D) -> void:
	if not is_instance_valid(item):
		return

	# Remove that specific wizard from the tray
	item.queue_free()

	# Spawn the HeldWizard ghost
	if held_wizard_scene == null:
		return

	var held := held_wizard_scene.instantiate()
	var root := get_tree().current_scene
	if root != null:
		root.add_child(held)
		if held is Node2D:
			var held2d: Node2D = held
			held2d.global_position = get_global_mouse_position()

	# Let the held wizard know which tray it belongs to
	if held != null:
		held.set("wizard_tray", self)


func return_wizard_from_hand(_world_pos: Vector2) -> void:
	# Wizard “bounced” (bad tile) → just spawn another in the tray
	_spawn_wizard()
