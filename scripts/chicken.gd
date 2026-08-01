extends Node3D
## One chicken. Wanders and forages by day, garrisons the Armory (or fights) by night.

const MK = preload("res://scripts/meshkit.gd")

var game: Node3D
var hp := 25.0
var max_hp := 25.0
# wander | eat | forage_go | forage_work | forage_return | to_coop | in_coop | guard | panic | carried
var state := "wander"
var forager := false
var is_chick := false
var age := 0.0

var _target := Vector3.ZERO
var _timer := 0.0
var _peck_t := 0.0
var _attack_cd := 0.0
var _tree := Vector3.ZERO
var _eat_pile = null

var _head: Node3D
var _body_mat: StandardMaterial3D
var _helmet: MeshInstance3D = null

func setup(g: Node3D, pos: Vector3, chick: bool) -> void:
	game = g
	position = pos
	is_chick = chick
	if chick:
		hp = 12.0
		max_hp = 12.0
	_build_mesh()
	if chick:
		scale = Vector3.ONE * 0.45

func _build_mesh() -> void:
	var body_col: Color = [Color(0.94, 0.91, 0.84), Color(0.76, 0.55, 0.32), Color(0.9, 0.82, 0.65)][randi() % 3]
	var body := MK.sphere(self, 0.32, body_col, Vector3(0, 0.36, 0))
	body.scale = Vector3(0.9, 0.85, 1.15)
	_body_mat = body.material_override
	# head group sits forward (+Z is our facing direction)
	_head = Node3D.new()
	_head.position = Vector3(0, 0.62, 0.26)
	add_child(_head)
	MK.sphere(_head, 0.16, body_col, Vector3.ZERO)
	MK.cyl(_head, 0.0, 0.05, 0.14, Color(0.95, 0.6, 0.1), Vector3(0, 0.0, 0.19)).rotation.x = deg_to_rad(90)
	MK.box(_head, Vector3(0.05, 0.12, 0.1), Color(0.85, 0.15, 0.1), Vector3(0, 0.18, 0.0))
	MK.sphere(_head, 0.03, Color(0.05, 0.05, 0.05), Vector3(0.1, 0.04, 0.1))
	MK.sphere(_head, 0.03, Color(0.05, 0.05, 0.05), Vector3(-0.1, 0.04, 0.1))
	# tail + legs
	MK.cyl(self, 0.0, 0.1, 0.22, body_col.darkened(0.25), Vector3(0, 0.5, -0.32)).rotation.x = deg_to_rad(-50)
	MK.cyl(self, 0.03, 0.03, 0.2, Color(0.95, 0.6, 0.1), Vector3(0.09, 0.1, 0))
	MK.cyl(self, 0.03, 0.03, 0.2, Color(0.95, 0.6, 0.1), Vector3(-0.09, 0.1, 0))

func apply_helmet() -> void:
	if _helmet != null or _head == null:
		return
	_helmet = MK.cyl(_head, 0.14, 0.18, 0.1, Color(0.35, 0.4, 0.35), Vector3(0, 0.14, 0))

func targetable() -> bool:
	return state != "in_coop" and state != "carried"

func tick(delta: float) -> void:
	_timer -= delta
	_attack_cd -= delta
	_peck_t += delta
	if is_chick and not game.is_night:
		age += delta
		var s: float = lerpf(0.45, 1.0, clampf(age / 340.0, 0.0, 1.0))
		scale = Vector3.ONE * s
		if age >= 340.0:
			is_chick = false
			hp = 25.0
			max_hp = 25.0
			scale = Vector3.ONE
	match state:
		"carried", "in_coop":
			return
		"wander":
			if _timer <= 0.0:
				_target = game.rand_in_yard()
				_timer = randf_range(2.0, 5.0)
				if randf() < 0.25:
					game.sfx.play("cluck" if randf() < 0.5 else "cluck2", -14.0)
			_walk_toward(_target, 1.6, delta)
			_head.rotation.x = maxf(0.0, sin(_peck_t * 3.0)) * 0.9
		"eat":
			if _eat_pile == null or not is_instance_valid(_eat_pile.node):
				_eat_pile = null
				state = "wander"
				return
			var p: Vector3 = _eat_pile.node.position
			if _walk_toward(p, 2.4, delta):
				_timer -= delta
				_head.rotation.x = maxf(0.0, sin(_peck_t * 8.0)) * 1.1
				if _timer <= 0.0:
					hp = minf(max_hp, hp + 30.0)
					game.consume_feed_pile(_eat_pile)
					_eat_pile = null
					state = "wander"
					game.sfx.play("cluck", -8.0)
		"forage_go":
			if _walk_toward(_tree, 2.2, delta):
				state = "forage_work"
				_timer = 4.0
		"forage_work":
			_head.rotation.x = maxf(0.0, sin(_peck_t * 7.0)) * 1.0
			_timer -= delta
			if _timer <= 0.0:
				state = "forage_return"
		"forage_return":
			var home := Vector3(randf_range(-8.0, 8.0), 0, randf_range(12.0, 18.0))
			if _walk_toward(Vector3(0, 0, 16), 2.2, delta):
				game.forage_deposit(self)
				_tree = game.pick_tree()
				state = "forage_go" if forager else "wander"
				_target = home
		"to_coop":
			if _walk_toward(game.coop_door, 3.2, delta):
				if game.coop_broken:
					state = "panic"
				else:
					state = "in_coop"
					visible = false
		"guard":
			var enemy = game.nearest_enemy(position, 3.2)
			if enemy != null:
				_walk_toward(enemy.position, 2.6, delta)
				_head.rotation.x = maxf(0.0, sin(_peck_t * 10.0)) * 1.2
				if _attack_cd <= 0.0 and position.distance_to(enemy.position) < 1.6:
					_attack_cd = 0.8
					enemy.damage(4.0)
					game.sfx.play("cluck2", -6.0)
			else:
				_walk_toward(game.coop_door + Vector3(randf_range(-2, 2), 0, randf_range(-2, 2)), 1.8, delta)
		"panic":
			if _timer <= 0.0:
				_target = game.rand_in_yard()
				_timer = randf_range(0.5, 1.2)
				game.sfx.play("cluck", -6.0)
			_walk_toward(_target, 4.2, delta)

func start_forage() -> void:
	forager = true
	_tree = game.pick_tree()
	state = "forage_go"

func stop_forage() -> void:
	forager = false
	if state.begins_with("forage"):
		state = "wander"

func night_mode() -> void:
	stop_forage()
	if game.upgrades.helmets and not is_chick:
		apply_helmet()
		state = "guard"
	else:
		state = "to_coop"

func day_mode() -> void:
	visible = true
	hp = minf(max_hp, hp + 5.0)
	state = "forage_go" if forager else "wander"
	if forager:
		_tree = game.pick_tree()

func assign_eat(pile) -> void:
	if state in ["wander", "forage_go", "forage_return"]:
		_eat_pile = pile
		_timer = 1.6
		state = "eat"

## Returns true when arrived. Speed in m/s.
func _walk_toward(dest: Vector3, speed: float, delta: float) -> bool:
	var flat := Vector3(dest.x, 0, dest.z)
	var d := flat - Vector3(position.x, 0, position.z)
	if d.length() < 0.35:
		return true
	var dir := d.normalized()
	position += dir * speed * delta
	position.y = absf(sin(_peck_t * 9.0)) * 0.05
	rotation.y = atan2(dir.x, dir.z)
	return false

func damage(n: float) -> void:
	hp -= n
	if _body_mat != null:
		_body_mat.emission_enabled = true
		_body_mat.emission = Color(1, 0.3, 0.3)
		_body_mat.emission_energy_multiplier = 0.7
		var tw := create_tween()
		tw.tween_interval(0.12)
		tw.tween_callback(func(): _body_mat.emission_enabled = false)
	game.sfx.play("cluck", -4.0)
	if hp <= 0.0:
		game.chicken_died(self)
