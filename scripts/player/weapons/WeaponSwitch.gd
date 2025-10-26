extends Node3D

@export var ak: PackedScene
@export var pistol: PackedScene  # ← Dodaj pistoleta
@export var camera_path: NodePath = "../../PlayerCamera"

var current_weapon: Node3D

func _ready():
	equip_weapon(ak)  # Zacznij z pistoletem
	# lub equip_weapon(ak) dla AK

func _process(_delta):
	# Przełączanie broni klawiszem 1 i 2
	if Input.is_action_just_pressed("weapon_1"):
		switch_weapon(ak)
	elif Input.is_action_just_pressed("weapon_2"):
		switch_weapon(pistol)

func equip_weapon(weapon_scene: PackedScene):
	if not weapon_scene:
		return
	
	var weapon_instance = weapon_scene.instantiate()
	
	# Przypisz odpowiedni skrypt
	if weapon_scene == pistol:
		var pistol_script = preload("res://scripts/player/weapons/WeaponPistol.gd")
		weapon_instance.set_script(pistol_script)
	elif weapon_scene == ak:
		var ak_script = preload("res://scripts/player/weapons/WeaponAK.gd")
		weapon_instance.set_script(ak_script)
	
	# Ustawienie pozycji (dostosuj dla każdej broni)
	
	if weapon_scene == pistol:
		weapon_instance.position = Vector3(0.01, -0.4, -0.6)
		weapon_instance.rotation_degrees = Vector3(0, 93, 0)
		weapon_instance.scale = Vector3(0.1, 0.1, 0.1)
	elif weapon_scene == ak:
		weapon_instance.position = Vector3(0.15, -0.4, -0.7)
		weapon_instance.rotation_degrees = Vector3(0, 93, 0)
		weapon_instance.scale = Vector3(0.1, 0.1, 0.1)
	
	var camera = get_node(camera_path) as Node3D
	if camera:
		camera.add_child(weapon_instance)
		current_weapon = weapon_instance
		print("Zaekwipowano broń: ", weapon_instance.name)

func switch_weapon(weapon_scene: PackedScene):
	# Usuń aktualną broń
	if current_weapon:
		current_weapon.queue_free()
	
	# Ekwipuj nową
	equip_weapon(weapon_scene)
