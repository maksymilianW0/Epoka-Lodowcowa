extends CharacterBody3D

# === RUCH ===
@export_group("Movement")
@export var walk_speed = 5.0
@export var sprint_speed = 8.0
@export var crouch_speed = 2.5
@export var mouse_sensitivity = 0.15
@export var jump_velocity = 4.5
@export var acceleration = 10.0
@export var deceleration = 15.0
@export var air_control = 0.3

# === KUCANIE ===
@export_group("Crouch")
@export var crouch_depth = 0.5
@export var crouch_speed_transition = 10.0

# === STAMINA ===
@export_group("Stamina")
@export var max_stamina = 100.0
@export var sprint_stamina_cost = 20.0
@export var jump_stamina_cost = 15.0
@export var stamina_regen_rate = 15.0
@export var stamina_regen_delay = 1.0

# === POCHYLANIE ===
@export_group("Head Bob")
@export var bob_enabled = true
@export var bob_speed = 14.0
@export var bob_amount = 0.08
@export var sprint_bob_multiplier = 1.5

# === FOV ===
@export_group("FOV Effects")
@export var default_fov = 75.0
@export var sprint_fov = 85.0
@export var fov_transition_speed = 8.0

# === KROKI ===
@export_group("Footsteps")
@export var footstep_interval = 0.5
@export var sprint_footstep_multiplier = 0.7

# === DŹWIĘKI ===
@export_group("Audio")
@export var footstep_sounds: Array[AudioStream] = []
@export var jump_sound: AudioStream
@export var land_sound: AudioStream

var yaw = 0.0
var pitch = 0.0
var target_velocity = Vector3.ZERO
var is_crouching = false
var standing_height = 1.0
var current_crouch_factor = 0.0

# Stamina
var current_stamina = max_stamina
var stamina_regen_timer = 0.0
var can_sprint = true

# Head bob
var bob_time = 0.0
var original_camera_y = 0.0

# Footsteps
var footstep_timer = 0.0
var last_on_floor = false

@onready var camera = $PlayerCamera
@onready var collision_shape = $PlayerBody
@onready var audio_player = $PlayerAudio

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	if collision_shape and collision_shape.shape:
		standing_height = collision_shape.shape.height
	
	if camera:
		original_camera_y = camera.position.y
		camera.fov = default_fov
	
	current_stamina = max_stamina

func _input(event):
	if event is InputEventMouseMotion:
		yaw -= event.relative.x * mouse_sensitivity
		pitch -= event.relative.y * mouse_sensitivity
		pitch = clamp(pitch, -90, 90)
		rotation_degrees.y = yaw
		camera.rotation_degrees.x = pitch
	
	if event.is_action_pressed("ui_cancel"):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _physics_process(delta):
	# Kucanie
	handle_crouching(delta)
	
	# Stamina
	handle_stamina(delta)
	
	# Zbieranie wejścia
	var input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	# Określenie prędkości na podstawie stanu
	var current_speed = walk_speed
	var is_sprinting = false
	
	if is_crouching:
		current_speed = crouch_speed
	elif Input.is_action_pressed("sprint") and is_on_floor() and input_dir.y < 0 and can_sprint:
		current_speed = sprint_speed
		is_sprinting = true
		use_stamina(sprint_stamina_cost * delta)
	
	# Kontrola w powietrzu
	var control_factor = air_control if not is_on_floor() else 1.0
	var accel = acceleration if direction.length() > 0 else deceleration
	
	# Płynne przyspieszanie/hamowanie
	target_velocity.x = lerp(target_velocity.x, direction.x * current_speed, accel * delta * control_factor)
	target_velocity.z = lerp(target_velocity.z, direction.z * current_speed, accel * delta * control_factor)
	
	velocity.x = target_velocity.x
	velocity.z = target_velocity.z
	
	# Grawitacja
	if not is_on_floor():
		velocity.y -= ProjectSettings.get_setting("physics/3d/default_gravity") * delta
	
	# Skok
	if Input.is_action_just_pressed("jump") and is_on_floor() and not is_crouching:
		if current_stamina >= jump_stamina_cost:
			velocity.y = jump_velocity
			use_stamina(jump_stamina_cost)
			play_sound(jump_sound)
	
	# Detekcja lądowania
	if is_on_floor() and not last_on_floor:
		play_sound(land_sound)
	last_on_floor = is_on_floor()
	
	move_and_slide()
	
	# Head bob
	if bob_enabled:
		handle_head_bob(delta, direction.length() > 0, is_sprinting)
	
	# FOV
	handle_fov(delta, is_sprinting)
	
	# Footsteps
	handle_footsteps(delta, direction.length() > 0, is_sprinting)

func handle_crouching(delta):
	# Przełączanie kucania
	if Input.is_action_pressed("crouch"):
		is_crouching = true
	else:
		if is_crouching and can_stand_up():
			is_crouching = false
	
	# Płynne przejście kucania
	var target_crouch = 1.0 if is_crouching else 0.0
	current_crouch_factor = lerp(current_crouch_factor, target_crouch, crouch_speed_transition * delta)
	
	# Aktualizacja wysokości kolizji
	if collision_shape and collision_shape.shape:
		var new_height = standing_height * (1.0 - current_crouch_factor * crouch_depth)
		collision_shape.shape.height = new_height
		collision_shape.position.y = new_height / 2.0
		
		# Aktualizuj TYLKO bazową wysokość kamery (bez head bob)
		if camera:
			original_camera_y = new_height - 0.2

func can_stand_up() -> bool:
	if not collision_shape:
		return true
	
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(
		global_position,
		global_position + Vector3.UP * (standing_height * 1.1)
	)
	query.exclude = [self]
	
	var result = space_state.intersect_ray(query)
	return result.is_empty()

# === STAMINA ===
func handle_stamina(delta):
	if stamina_regen_timer > 0:
		stamina_regen_timer -= delta
	else:
		if current_stamina < max_stamina:
			current_stamina = min(current_stamina + stamina_regen_rate * delta, max_stamina)
	
	can_sprint = current_stamina > 10.0

func use_stamina(amount: float):
	current_stamina = max(current_stamina - amount, 0.0)
	stamina_regen_timer = stamina_regen_delay

func get_stamina_percent() -> float:
	return current_stamina / max_stamina

# === HEAD BOB ===
func handle_head_bob(delta, is_moving, is_sprinting):
	if not camera:
		return
	
	if is_moving and is_on_floor():
		var speed_multiplier = sprint_bob_multiplier if is_sprinting else 1.0
		bob_time += delta * bob_speed * speed_multiplier
		
		var bob_offset = sin(bob_time) * bob_amount * speed_multiplier
		camera.position.y = original_camera_y + bob_offset
	else:
		bob_time = 0.0
		camera.position.y = lerp(camera.position.y, original_camera_y, delta * 10.0)

# === FOV ===
func handle_fov(delta, is_sprinting):
	if not camera:
		return
	
	var target_fov = sprint_fov if is_sprinting else default_fov
	camera.fov = lerp(camera.fov, target_fov, fov_transition_speed * delta)

# === FOOTSTEPS ===
func handle_footsteps(delta, is_moving, is_sprinting):
	if not is_moving or not is_on_floor():
		footstep_timer = 0.0
		return
	
	var interval = footstep_interval
	if is_sprinting:
		interval *= sprint_footstep_multiplier
	
	footstep_timer += delta
	if footstep_timer >= interval:
		footstep_timer = 0.0
		play_random_footstep()

func play_random_footstep():
	if footstep_sounds.is_empty() or not audio_player:
		return
	
	var random_sound = footstep_sounds[randi() % footstep_sounds.size()]
	audio_player.stream = random_sound
	audio_player.pitch_scale = randf_range(0.9, 1.1)
	audio_player.play()

func play_sound(sound: AudioStream):
	if sound and audio_player:
		audio_player.stream = sound
		audio_player.play()
