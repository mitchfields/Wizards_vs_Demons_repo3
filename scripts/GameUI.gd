# res://scripts/GameUI.gd
extends Control
class_name GameUI

@onready var wave_manager      : Node         = get_tree().current_scene.get_node("GameLayer/WaveManager")

@onready var money_label       : Label        = $MoneyLabel
@onready var wave_label        : Label        = $WaveLabel
@onready var wave_progress     : ProgressBar  = $WaveProgress
@onready var start_wave_button : Button       = $StartWaveButton
@onready var fast_forward_btn  : Button       = $FastForwardButton

var _is_fast_forwarding: bool = false


func _ready() -> void:
	if start_wave_button:
		start_wave_button.pressed.connect(_on_start_wave_pressed)

	if fast_forward_btn:
		fast_forward_btn.pressed.connect(_on_fast_forward_pressed)

	if wave_manager:
		wave_manager.connect("wave_started", Callable(self, "_on_wave_started"))
		wave_manager.connect("enemy_spawned", Callable(self, "_on_enemy_spawned"))
		wave_manager.connect("enemy_died", Callable(self, "_on_enemy_died"))
		wave_manager.connect("enemy_hit_queen", Callable(self, "_on_enemy_hit_queen"))
		wave_manager.connect("wave_ended", Callable(self, "_on_wave_ended"))

	if wave_label:
		wave_label.text = "Wave 0"

	if wave_progress:
		wave_progress.min_value = 0
		wave_progress.max_value = 1
		wave_progress.value = 0

	# Money display can be wired from the TokenTray later
	if money_label:
		money_label.text = ""


func _on_start_wave_pressed() -> void:
	if wave_manager and not wave_manager.is_wave_active():
		wave_manager.start_wave()


func _on_fast_forward_pressed() -> void:
	_is_fast_forwarding = not _is_fast_forwarding
	Engine.time_scale = 2.0 if _is_fast_forwarding else 1.0

	if fast_forward_btn:
		fast_forward_btn.text = ">>" if _is_fast_forwarding else ">"


func _on_wave_started(wave_number: int, enemies_in_wave: int) -> void:
	if wave_label:
		wave_label.text = "Wave %d" % wave_number

	if wave_progress:
		wave_progress.min_value = 0
		wave_progress.max_value = max(enemies_in_wave, 1)
		wave_progress.value = 0

	if start_wave_button:
		start_wave_button.disabled = true


func _on_enemy_spawned(_enemy: Node2D) -> void:
	pass


func _on_enemy_died(_enemy: Node2D) -> void:
	if wave_progress:
		wave_progress.value += 1


func _on_enemy_hit_queen(_enemy: Node2D) -> void:
	pass


func _on_wave_ended(_wave_number: int) -> void:
	if start_wave_button:
		start_wave_button.disabled = false
