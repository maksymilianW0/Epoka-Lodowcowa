extends Node3D

@onready var player_data: Node = get_node("/root/World/Player/Scripts/PlayerData")

# AnimationPlayer (dziecko broni)
@export var animation_player_path: NodePath = "AnimationPlayer"
var animation_player: AnimationPlayer

# Parametry broni
@export var fire_rate: float = 0.1  # czas między strzałami w sekundach
@export var damage: int = 10
@export var magazine_size: int = 30
@export var max_ammo: int = 120
@export var reload_time: float = 2.0

# Tryb strzelania
@export_enum("Semi-Auto", "Burst", "Full-Auto") var fire_mode: int = 2  # 0=Semi, 1=Burst, 2=Full-Auto
@export var burst_count: int = 3  # ile strzałów w serii
@export var burst_delay: float = 0.1  # opóźnienie między strzałami w serii

# Stany broni
var current_ammo: int = 0
var reserve_ammo: int = 0
var can_fire: bool = true
var is_reloading: bool = false
var is_firing_burst: bool = false
var last_fire_time: float = 0.0  # czas ostatniego strzału

func _ready():
	animation_player = get_node(animation_player_path) as AnimationPlayer
	if animation_player == null:
		push_error("Nie znaleziono AnimationPlayer na podanej ścieżce: " + str(animation_player_path))
	else:
		# Odtwórz animację idle na start
		animation_player.play("Armature|Idle")
	
	# Załaduj amunicję z PlayerData
	if player_data:
		current_ammo = player_data.current_ammo_ak
		reserve_ammo = player_data.reserve_ammo_ak
		print("AK załadowany - Amunicja: ", current_ammo, "/", reserve_ammo)
	else:
		push_error("Nie znaleziono PlayerData!")
		# Fallback - ustaw domyślne wartości
		current_ammo = magazine_size
		reserve_ammo = max_ammo - magazine_size

func _process(_delta):
	# Zmiana trybu strzelania (opcjonalnie - klawisz B)
	if Input.is_action_just_pressed("change_fire_mode"):
		cycle_fire_mode()
	
	# Strzelanie według trybu
	match fire_mode:
		0:  # Semi-Auto (pojedyncze strzały)
			if Input.is_action_just_pressed("fire") and can_fire_check():
				fire_single()
		1:  # Burst (seria)
			if Input.is_action_just_pressed("fire") and can_fire_check() and not is_firing_burst:
				fire_burst()
		2:  # Full-Auto (automatyczna)
			if Input.is_action_pressed("fire") and can_fire_check():
				# Sprawdź czy minął wymagany czas od ostatniego strzału
				var current_time = Time.get_ticks_msec() / 1000.0
				if current_time - last_fire_time >= fire_rate:
					fire_single()
	
	# Przeładowanie - tylko jeśli nie przeładowujemy już
	if Input.is_action_just_pressed("reload") and not is_reloading and current_ammo < magazine_size and reserve_ammo > 0:
		reload()

# Zapisz stan amunicji do PlayerData
func save_ammo_state():
	if player_data:
		player_data.current_ammo_ak = current_ammo
		player_data.reserve_ammo_ak = reserve_ammo

# Sprawdza czy możemy strzelać
func can_fire_check() -> bool:
	# Jeśli brak amunicji, automatycznie przeładuj (jeśli możliwe)
	if current_ammo == 0 and not is_reloading and reserve_ammo > 0:
		reload()
		return false
	
	return can_fire and not is_reloading and current_ammo > 0

func cycle_fire_mode():
	fire_mode = (fire_mode + 1) % 3
	var mode_names = ["Semi-Auto", "Burst", "Full-Auto"]
	print("Tryb strzelania: ", mode_names[fire_mode])

func fire_single():
	if not can_fire or current_ammo <= 0 or is_reloading:
		return
	
	can_fire = false
	current_ammo -= 1
	save_ammo_state()  # Zapisz po strzale
	last_fire_time = Time.get_ticks_msec() / 1000.0  # Zapisz czas strzału
	
	# Odtwórz animację strzału
	if animation_player:
		animation_player.play("Armature|Shoot")
	
	shoot_bullet()
	
	print("Amunicja: ", current_ammo, "/", reserve_ammo)
	
	# Timer do cooldownu
	await get_tree().create_timer(fire_rate).timeout
	can_fire = true
	
	# Wróć do idle jeśli nie strzelamy dalej i nie przeładowujemy
	if animation_player and not Input.is_action_pressed("fire") and not is_reloading:
		animation_player.play("Armature|Idle")

func fire_burst():
	if not can_fire or current_ammo <= 0 or is_reloading or is_firing_burst:
		return
	
	is_firing_burst = true
	can_fire = false
	
	# Wystrzel serię
	for i in range(burst_count):
		if current_ammo <= 0 or is_reloading:
			break
		
		current_ammo -= 1
		save_ammo_state()  # Zapisz po każdym strzale
		last_fire_time = Time.get_ticks_msec() / 1000.0
		
		# Odtwórz animację strzału
		if animation_player:
			animation_player.play("Armature|Shoot")
		
		shoot_bullet()
		
		print("Strzał ", i + 1, "/", burst_count, " - Amunicja: ", current_ammo, "/", reserve_ammo)
		
		# Czekaj między strzałami w serii
		if i < burst_count - 1:  # nie czekaj po ostatnim strzale
			await get_tree().create_timer(burst_delay).timeout
	
	# Cooldown po serii
	await get_tree().create_timer(fire_rate).timeout
	
	is_firing_burst = false
	can_fire = true
	
	# Wróć do idle jeśli nie przeładowujemy
	if animation_player and not is_reloading:
		animation_player.play("Armature|Idle")

func reload():
	# Zabezpieczenie przed wielokrotnym wywołaniem
	if is_reloading or reserve_ammo <= 0 or current_ammo >= magazine_size:
		return
	
	is_reloading = true
	can_fire = false
	is_firing_burst = false  # Przerwij serię jeśli trwa
	
	print("Przeładowuję...")
	
	# Odtwórz animację przeładowania
	if animation_player:
		animation_player.play("Armature|Reload")
	
	# Czekaj na zakończenie przeładowania - używamy animacji zamiast timera
	if animation_player:
		# Czekaj aż animacja się skończy
		await animation_player.animation_finished
	else:
		# Fallback na timer jeśli nie ma AnimationPlayera
		await get_tree().create_timer(reload_time).timeout
	
	# Oblicz ile amunicji przeładować
	var ammo_needed = magazine_size - current_ammo
	var ammo_to_reload = min(ammo_needed, reserve_ammo)
	
	current_ammo += ammo_to_reload
	reserve_ammo -= ammo_to_reload
	save_ammo_state()  # Zapisz po przeładowaniu
	
	is_reloading = false
	can_fire = true
	
	print("Przeładowano! Amunicja: ", current_ammo, "/", reserve_ammo)
	
	# Wróć do idle
	if animation_player:
		animation_player.play("Armature|Idle")

func shoot_bullet():
	# Strzał z pozycji broni (self)
	var from = global_transform.origin
	var to = from + global_transform.basis.z * -1000  # strzał do przodu
	var space_state = get_world_3d().direct_space_state
	
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 0b1111
	
	var result = space_state.intersect_ray(query)
	
	if result:
		print("Trafiono: ", result.collider, " w punkcie ", result.position)
		# Tutaj możesz dodać zadawanie obrażeń
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
