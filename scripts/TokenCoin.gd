extends RigidBody2D

const ROT_STEPS: int = 12
const TILT_STEPS: int = 6

@export_range(0, ROT_STEPS - 1) var rotation_step: int = 0
@export_range(0, TILT_STEPS - 1) var tilt_level: int = 1  # visible tilt band (0..5)

# Spin speed from velocity
@export var spin_velocity_scale: float = 0.04

# Hover / jiggle settings
@export var hover_radius: float = 40.0          # basically overlap
@export var tilt_rest: int = 1                  # where coins settle
@export var tilt_hover: int = 4                 # how “toward camera” they lean on hover
@export var tilt_motion_neutral: int = 3        # center tilt used during falling

# Strong initial vertical speed so it feels fast without crazy gravity
@export var initial_drop_speed: float = 800.0   # tweak for 3–5x feel

# SFX
@export var spawn_sounds: Array[AudioStream] = []   # now used for HIT
@export var hit_sound: AudioStream                  # now used for HOVER
@export var hover_sounds: Array[AudioStream] = []   # now used for SPAWN

@onready var _sprite: Sprite2D = $Sprite2D
@onready var _sfx: AudioStreamPlayer2D = $SFX

var rotation_phase: float = 0.0
var spin_direction: float = 1.0                 # +1 or -1

var tilt_float: float = 1.0                     # smooth tilt value, 0..(TILT_STEPS-1)
var tilt_direction: int = 1                     # +1 or -1, which extreme we lean toward when moving
var last_vel_y: float = 0.0
var _was_hovered: bool = false                  # track hover state frame-to-frame


func _ready() -> void:
	randomize()

	# Random spin direction (+1 or -1)
	spin_direction = -1.0 if randf() < 0.5 else 1.0

	# Random initial tilt direction (toward 0 or 5 when moving)
	tilt_direction = -1 if randf() < 0.5 else 1

	# Start at rest tilt
	tilt_float = float(tilt_rest)
	tilt_level = tilt_rest

	# Random starting spin phase so loops aren't in sync
	rotation_phase = randf() * float(ROT_STEPS)
	rotation_step = int(rotation_phase) % ROT_STEPS

	# Make sure tokens draw above the floor/backdrop
	z_index = 1

	# Strong initial downward velocity so it feels fast without insane gravity
	linear_velocity = Vector2(0.0, initial_drop_speed)

	# SPAWN: use hover_sounds (no inspector changes needed)
	_play_random_sfx(hover_sounds, -4.0, 0.05)

	_apply_frame()


func _physics_process(delta: float) -> void:
	_update_spin_from_velocity(delta)
	_update_physics_tilt(delta)
	_update_hover_tilt_and_spin(delta)
	_apply_frame()

	# Remember last frame's vertical velocity for bounce detection
	last_vel_y = linear_velocity.y


func _update_spin_from_velocity(delta: float) -> void:
	var speed: float = linear_velocity.length()

	# If basically not moving, don’t spin
	if speed < 10.0:
		return

	# More speed = faster rotation around the fake upvector, with random direction
	rotation_phase += speed * spin_velocity_scale * spin_direction * delta
	rotation_step = int(rotation_phase) % ROT_STEPS


func _update_physics_tilt(delta: float) -> void:
	var speed: float = linear_velocity.length()
	var rest_threshold: float = 15.0
	var high_speed: float = 200.0

	# --- Bounce inversion + big tilt kick ---
	if signf(linear_velocity.y) != signf(last_vel_y) and abs(linear_velocity.y) > 30.0:
		tilt_direction *= -1
		# Big immediate shove toward the new extreme
		var bounce_target: float = float(TILT_STEPS - 1) if tilt_direction > 0 else 0.0
		tilt_float = lerp(tilt_float, bounce_target, 0.6)  # large jump, not scaled by delta

		# HIT: use spawn_sounds
		_play_random_sfx(spawn_sounds, 0.0, 0.08)

	if speed < rest_threshold:
		# Ease back toward resting tilt when nearly still (FASTER now)
		tilt_float = lerp(tilt_float, float(tilt_rest), 10.0 * delta)
	else:
		# When moving, “air drag” pushes tilt toward extremes (0 or 5) from a neutral band.
		var t: float = clamp((speed - rest_threshold) / (high_speed - rest_threshold), 0.0, 1.0)

		var extreme: float = 0.0
		if tilt_direction > 0:
			extreme = float(TILT_STEPS - 1)  # 5
		else:
			extreme = 0.0                     # 0

		var neutral: float = float(tilt_motion_neutral)   # e.g. 3
		var target: float = lerp(neutral, extreme, t)

		# FASTER tilt when moving (especially at high speed)
		var tilt_lerp_speed: float = lerp(8.0, 25.0, t)
		tilt_float = lerp(tilt_float, target, tilt_lerp_speed * delta)

	# Clamp and sync to integer band
	tilt_float = clamp(tilt_float, 0.0, float(TILT_STEPS - 1))
	tilt_level = int(round(tilt_float))


func _update_hover_tilt_and_spin(delta: float) -> void:
	var viewport: Viewport = get_viewport()
	if viewport == null:
		return

	var mouse_pos: Vector2 = viewport.get_mouse_position()
	var local_mouse: Vector2 = to_local(mouse_pos)
	var dist: float = local_mouse.length()

	var hovered: bool = dist <= hover_radius

	if hovered:
		# HOVER ENTER: use hit_sound
		if not _was_hovered:
			_play_single_sfx(hit_sound, -6.0, 0.12)

		# Pull quickly toward hover tilt band
		var target: float = float(tilt_hover)
		tilt_float = lerp(tilt_float, target, 15.0 * delta)
		tilt_float = clamp(tilt_float, 0.0, float(TILT_STEPS - 1))
		tilt_level = int(round(tilt_float))
	else:
		# Not touching tilt here; rest / motion tilt handled in _update_physics_tilt

		# If we JUST left hover this frame, give a tiny random spin nudge
		if _was_hovered:
			# offset in range [-2, 2]
			var raw: int = int(randi() % 5)  # 0..4
			var offset: int = raw - 2        # -2..2
			if offset != 0:
				rotation_phase += float(offset)
				rotation_step = (rotation_step + offset) % ROT_STEPS

	_was_hovered = hovered


func _apply_frame() -> void:
	if _sprite == null:
		return

	var rot: int = clamp(rotation_step, 0, ROT_STEPS - 1)
	var tilt: int = clamp(tilt_level, 0, TILT_STEPS - 1)

	var frame_index: int = tilt * ROT_STEPS + rot
	_sprite.frame = frame_index


func _play_random_sfx(sounds: Array[AudioStream], base_volume_db: float = 0.0, pitch_jitter: float = 0.1) -> void:
	if _sfx == null:
		return
	if sounds.is_empty():
		return

	var idx: int = int(randi() % sounds.size())
	var stream: AudioStream = sounds[idx]
	if stream == null:
		return

	_sfx.stop()
	_sfx.stream = stream
	_sfx.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	_sfx.volume_db = base_volume_db
	_sfx.play()


func _play_single_sfx(stream: AudioStream, base_volume_db: float = 0.0, pitch_jitter: float = 0.1) -> void:
	if _sfx == null:
		return
	if stream == null:
		return

	_sfx.stop()
	_sfx.stream = stream
	_sfx.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	_sfx.volume_db = base_volume_db
	_sfx.play()


func signf(x: float) -> int:
	if x > 0.0:
		return 1
	elif x < 0.0:
		return -1
	else:
		return 0
