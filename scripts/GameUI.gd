# res://scripts/GameUI.gd
extends Control

# Locate the WaveManager in your scene tree
@onready var wave_manager      = get_tree().current_scene.get_node("GameLayer/WaveManager")
# These live under this TopBar Control
@onready var money_label       = get_node("MoneyLabel")
@onready var wave_label        = get_node("WaveLabel")
@onready var wave_progress     = get_node("WaveProgress")
@onready var start_wave_button = get_node("StartWaveButton")
@onready var fast_forward_btn  = get_node("FastForwardButton")

var money : int = 0

func _ready() -> void:
	# Connect the Start Wave button (through World now)
	start_wave_button.connect("pressed", Callable(self, "_on_start_wave_pressed"))

	# Hook up UI to WaveManager signals
	wave_manager.connect("wave_started",    Callable(self, "_on_wave_started"))
	wave_manager.connect("enemy_spawned",   Callable(self, "_on_enemy_spawned"))
	wave_manager.connect("enemy_died",      Callable(self, "_on_enemy_died"))
	wave_manager.connect("enemy_hit_queen", Callable(self, "_on_enemy_hit_queen"))
	wave_manager.connect("wave_ended",      Callable(self, "_on_wave_ended"))


func _on_start_wave_pressed() -> void:
	var world := get_tree().current_scene
	if world != null and world.has_method("handle_start_wave_pressed"):
		world.handle_start_wave_pressed()
	else:
		# Fallback if something is weird
		wave_manager.start_wave()


func _on_wave_started(wave_number: int, total_enemies: int) -> void:
	wave_label.text         = "Wave %d" % wave_number
	wave_progress.min_value = 0
	wave_progress.max_value = total_enemies
	wave_progress.value     = 0
	start_wave_button.disabled = true


func _on_enemy_spawned(_enemy: Node2D) -> void:
	# no UI change needed here for now
	pass


func _on_enemy_died(_enemy: Node2D) -> void:
	wave_progress.value += 1
	money += 1
	money_label.text = "$%d" % money


func _on_enemy_hit_queen(_enemy: Node2D) -> void:
	wave_progress.value += 1
	# no gold for queen hits (for now)


func _on_wave_ended(_wave_number: int) -> void:
	start_wave_button.disabled = false
