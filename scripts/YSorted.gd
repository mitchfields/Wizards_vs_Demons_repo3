# res://scripts/YSorted.gd
extends Node2D

# Extra offset so you can push some things always in front/behind.
@export var z_offset: int = 0

# If true, use global_position.y (respects parent transforms).
# If false, just uses local position.y
@export var use_global_position: bool = true


func _ready() -> void:
	z_as_relative = false
	_update_z()


func _process(_delta: float) -> void:
	_update_z()


func _update_z() -> void:
	var y = global_position.y if use_global_position else position.y
	z_index = int(y) + z_offset
