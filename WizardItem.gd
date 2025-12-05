extends RigidBody2D

signal clicked(item: RigidBody2D)

func _ready() -> void:
	input_pickable = true  # allow mouse clicks on this body


func _input_event(viewport: Viewport, event: InputEvent, shape_idx: int) -> void:
	if event is InputEventMouseButton \
	and event.button_index == MOUSE_BUTTON_LEFT \
	and event.pressed:
		clicked.emit(self)
