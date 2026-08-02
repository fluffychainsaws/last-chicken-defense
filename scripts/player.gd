extends CharacterBody3D
## First-person farmer. Shovel by day, shotgun by night, regrets always.

const MK = preload("res://scripts/meshkit.gd")

var game: Node3D
var cam: Camera3D
var hp := 100.0
var max_hp := 100.0
var slot := 0
var _pitch := 0.0
var _swing_t := 0.0
var _fire_cd := 0.0
var _vm: Array = []
var _vm_root: Node3D

const GRAVITY := 18.0

func setup(g: Node3D) -> void:
	game = g
	position = Vector3(-10, 0.1, 5)
	var cs := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.35
	shape.height = 1.7
	cs.shape = shape
	cs.position = Vector3(0, 0.95, 0)
	add_child(cs)
	cam = Camera3D.new()
	cam.position = Vector3(0, 1.55, 0)
	cam.fov = 78
	cam.near = 0.05
	cam.far = 400
	add_child(cam)
	_build_viewmodels()

func _build_viewmodels() -> void:
	_vm_root = Node3D.new()
	_vm_root.position = Vector3(0.35, -0.34, -0.55)
	cam.add_child(_vm_root)
	# 0: shovel
	var shovel := Node3D.new()
	MK.cyl(shovel, 0.02, 0.02, 0.55, Color(0.5, 0.35, 0.2), Vector3.ZERO).rotation.x = deg_to_rad(-55)
	var blade := MK.box(shovel, Vector3(0.14, 0.03, 0.2), Color(0.55, 0.57, 0.6), Vector3(0, 0.22, -0.31))
	blade.rotation.x = deg_to_rad(-55)
	_vm_root.add_child(shovel)
	# 1: shotgun
	var gun := Node3D.new()
	MK.cyl(gun, 0.025, 0.025, 0.6, Color(0.2, 0.2, 0.22), Vector3(0, 0.02, -0.2)).rotation.x = deg_to_rad(90)
	MK.cyl(gun, 0.025, 0.025, 0.6, Color(0.2, 0.2, 0.22), Vector3(0.055, 0.02, -0.2)).rotation.x = deg_to_rad(90)
	MK.box(gun, Vector3(0.08, 0.09, 0.3), Color(0.45, 0.28, 0.12), Vector3(0.03, -0.04, 0.14))
	_vm_root.add_child(gun)
	# 2: feed bag
	var bag := Node3D.new()
	MK.box(bag, Vector3(0.2, 0.26, 0.12), Color(0.8, 0.68, 0.4), Vector3.ZERO)
	MK.box(bag, Vector3(0.2, 0.06, 0.12), Color(0.5, 0.15, 0.1), Vector3(0, 0.1, 0))
	_vm_root.add_child(bag)
	# 3: egg
	var egg := Node3D.new()
	var e := MK.sphere(egg, 0.09, Color(0.98, 0.95, 0.88), Vector3.ZERO)
	e.scale = Vector3(1, 1.25, 1)
	_vm_root.add_child(egg)
	_vm = [shovel, gun, bag, egg]
	_update_vm()

func _update_vm() -> void:
	for i in _vm.size():
		_vm[i].visible = (i == slot)

func set_slot(i: int) -> void:
	slot = clampi(i, 0, 3)
	_update_vm()
	game.ui.update_hotbar()

func _unhandled_input(event: InputEvent) -> void:
	if game == null or game.paused:
		return
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		rotation.y -= event.relative.x * 0.0022
		_pitch = clampf(_pitch - event.relative.y * 0.0022, -1.5, 1.5)
		cam.rotation.x = _pitch
	elif event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				_use_item()
			MOUSE_BUTTON_WHEEL_UP:
				set_slot((slot + 3) % 4)
			MOUSE_BUTTON_WHEEL_DOWN:
				set_slot((slot + 1) % 4)

func _physics_process(delta: float) -> void:
	if game == null or game.paused:
		return
	_fire_cd -= delta
	if _swing_t > 0.0:
		_swing_t -= delta * 3.5
		_vm_root.rotation.x = -sin(maxf(0.0, _swing_t) * PI) * 1.1
	for i in 4:
		if Input.is_action_just_pressed("slot%d" % (i + 1)):
			set_slot(i)
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var dir := (transform.basis * Vector3(input_dir.x, 0, input_dir.y))
	if dir.length() > 0.01:
		dir = dir.normalized()
	var speed := 6.0
	if game.upgrades.shoes:
		speed *= 1.25
	if Input.is_action_pressed("sprint"):
		speed *= 1.45
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	if is_on_floor():
		if Input.is_action_just_pressed("jump"):
			velocity.y = 6.5
	else:
		velocity.y -= GRAVITY * delta
	move_and_slide()
	# keep inside the world
	position.x = clampf(position.x, -90.0, 90.0)
	position.z = clampf(position.z, -90.0, 90.0)
	_interact_scan()

func _interact_scan() -> void:
	var prompt = null
	var ctx := ""
	if position.distance_to(game.computer_pos) < 2.6:
		ctx = "market"
		prompt = "[E]  FARMERS MARKET" if not game.is_night else "[E]  COMPUTER  (signal...?)"
	elif position.distance_to(game.bed_pos) < 2.6:
		ctx = "bed"
		if game.is_night:
			prompt = "[E]  SLEEP  (not while they're out there)"
		else:
			prompt = "[E]  SLEEP UNTIL NIGHTFALL"
	elif game.is_day() and position.distance_to(game.coop_pos) < 4.5 and game.coop_hp < game.max_coop_hp():
		ctx = "repair"
		prompt = "[HOLD E]  REPAIR COOP  (%d%%)" % int(100.0 * game.coop_hp / game.max_coop_hp())
	elif game.is_day() and position.distance_to(game.coop_pos) < 4.5:
		# an intact coop is the training ground; a damaged one is repaired first
		ctx = "roost"
		prompt = "[E]  THE ROOST  (train the flock)"
	else:
		var c = game.nearest_chicken(position, 2.8)
		if c != null and game.is_day():
			ctx = "chicken"
			prompt = ("[E]  RECALL FORAGER" if c.forager else "[E]  SEND TO FORAGE")
	game.ui.set_prompt(prompt)
	if ctx == "repair" and Input.is_action_pressed("interact"):
		game.repair_coop(get_physics_process_delta_time())
	if Input.is_action_just_pressed("interact"):
		match ctx:
			"market":
				game.open_market()
			"roost":
				game.open_coop()
			"bed":
				if game.is_night:
					game.sfx.play("denied")
				else:
					game.sleep_until_night()
			"chicken":
				var c = game.nearest_chicken(position, 2.8)
				if c != null:
					if c.forager:
						c.stop_forage()
					else:
						c.start_forage()
					game.sfx.play("cluck")

func _use_item() -> void:
	if _fire_cd > 0.0:
		return
	match slot:
		0:
			_fire_cd = 0.45
			_swing_t = 1.0
			game.sfx.play("swing")
			game.melee_attack(cam.global_position, -cam.global_transform.basis.z)
		1:
			if not game.upgrades.shotgun or game.shells <= 0:
				game.sfx.play("denied")
				return
			_fire_cd = 0.9
			_swing_t = 0.6
			game.shells -= 1
			game.sfx.play("shot", -4.0)
			game.shotgun_attack(cam.global_position, -cam.global_transform.basis.z)
			game.ui.refresh()
		2:
			if game.feed <= 0:
				game.sfx.play("denied")
				return
			_fire_cd = 0.5
			game.feed -= 1
			game.throw_projectile("feed", cam.global_position, -cam.global_transform.basis.z)
			game.ui.refresh()
		3:
			if game.eggs <= 0:
				game.sfx.play("denied")
				return
			_fire_cd = 0.4
			game.eggs -= 1
			game.sfx.play("egg")
			game.throw_projectile("egg", cam.global_position, -cam.global_transform.basis.z)
			game.ui.refresh()

func take_damage(n: float) -> void:
	hp -= n
	game.sfx.play("hurt")
	game.ui.flash_damage()
	game.ui.refresh()
	if hp <= 0.0:
		game.player_downed()
