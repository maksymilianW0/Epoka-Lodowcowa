extends Node3D

@onready var player_data: Node = get_node("/root/World/Player/Scripts/PlayerData")

# AnimationPlayer (dziecko broni)
@export var animation_player_path: NodePath = "AnimationPlayer"
var animation_player: AnimationPlayer

# Parametry broni
@export var fire_rate: float = 0.3  # czas między strzałami w sekundach (wolniejszy niż AK)
@export var damage: int = 25  # większe obrażenia per strzał
@export var magazine_size: int = 12  # mniejszy magazynek
@export var max_ammo: int = 60
@export var reload_time: float = 1.5  # szybsze przeładowanie

# Pistolet to zawsze Semi-Auto
var fire_mode: int = 0  # Semi-Auto only

# Stany broni
var current_ammo: int = 0
var reserve_ammo: int = 0
var can_fire: bool = true
var is_reloading: bool = false
var last_fire_time: float = 0.0

func _ready():
	animation_player = get_node_or_null(animation_player_path) as AnimationPlayer
	if animation_player == null:
		push_error("Nie znaleziono AnimationPlayer na podanej ścieżce: " + str(animation_player_path))
	else:
		# Odtwórz animację idle na start
		animation_player.play("Armature|Idle")
	
	# Załaduj amunicję z PlayerData
	if player_data:
		current_ammo = player_data.current_ammo_pistol
		reserve_ammo = player_data.reserve_ammo_pistol
		print("Pistolet załadowany - Amunicja: ", current_ammo, "/", reserve_ammo)
	else:
		push_error("Nie znaleziono PlayerData!")
		# Fallback - ustaw domyślne wartości
		current_ammo = magazine_size
		reserve_ammo = max_ammo - magazine_size

func _process(_delta):
	# Strzelanie - tylko Semi-Auto (pojedyncze kliknięcia)
	if Input.is_action_just_pressed("fire") and can_fire_check():
		fire()
	
	# Przeładowanie
	if Input.is_action_just_pressed("reload") and not is_reloading and current_ammo < magazine_size and reserve_ammo > 0:
		reload()

# Zapisz stan amunicji do PlayerData
func save_ammo_state():
	if player_data:
		player_data.current_ammo_pistol = current_ammo
		player_data.reserve_ammo_pistol = reserve_ammo

# Sprawdza czy możemy strzelać
func can_fire_check() -> bool:
	# Jeśli brak amunicji, automatycznie przeładuj (jeśli możliwe)
	if current_ammo == 0 and not is_reloading and reserve_ammo > 0:
		reload()
		return false
	
	return can_fire and not is_reloading and current_ammo > 0

func fire():
	if not can_fire or current_ammo <= 0 or is_reloading:
		return
	
	can_fire = false
	current_ammo -= 1
	save_ammo_state()  # Zapisz po strzale
	last_fire_time = Time.get_ticks_msec() / 1000.0
	
	# Odtwórz animację strzału
	if animation_player:
		animation_player.play("Armature|Shoot")
	
	shoot_bullet()
	
	print("Pistolet - Amunicja: ", current_ammo, "/", reserve_ammo)
	
	# Timer do cooldownu
	await get_tree().create_timer(fire_rate).timeout
	can_fire = true
	
	# Wróć do idle
	if animation_player and not is_reloading:
		animation_player.play("Armature|Idle")

func reload():
	# Zabezpieczenie przed wielokrotnym wywołaniem
	if is_reloading or reserve_ammo <= 0 or current_ammo >= magazine_size:
		return
	
	is_reloading = true
	can_fire = false
	
	print("Przeładowuję pistolet...")
	
	# Odtwórz animację przeładowania
	if animation_player:
		animation_player.play("Armature|Reload")
	
	# Czekaj na zakończenie przeładowania
	if animation_player:
		await animation_player.animation_finished
	else:
		await get_tree().create_timer(reload_time).timeout
	
	# Oblicz ile amunicji przeładować
	var ammo_needed = magazine_size - current_ammo
	var ammo_to_reload = min(ammo_needed, reserve_ammo)
	
	current_ammo += ammo_to_reload
	reserve_ammo -= ammo_to_reload
	save_ammo_state()  # Zapisz po przeładowaniu
	
	is_reloading = false
	can_fire = true
	
	print("Pistolet przeładowany! Amunicja: ", current_ammo, "/", reserve_ammo)
	
	# Wróć do idle
	if animation_player:
		animation_player.play("Armature|Idle")

func shoot_bullet():
	# Strzał z pozycji broni (self)
	var from = global_transform.origin
	var to = from + global_transform.basis.z * -1000
	var space_state = get_world_3d().direct_space_state
	
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 0b1111
	
	var result = space_state.intersect_ray(query)
	
	if result:
		print("Pistolet trafił: ", result.collider, " w punkcie ", result.position)
		# Zadaj obrażenia
		if result.collider.has_method("take_damage"):
			result.collider.take_damage(damage)

# Opcjonalna animacja schowania broni
func play_holster_animation():
	# Zapisz stan przed schowaniem
	save_ammo_state()
	
	if animation_player and animation_player.has_animation("Armature|Holster"):
		animation_player.play("Armature|Holster")
		await animation_player.animation_finished
	else:
		# Jeśli nie ma animacji, po prostu czekaj chwilę
		await get_tree().create_timer(0.2).timeout
