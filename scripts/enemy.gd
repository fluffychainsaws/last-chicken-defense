extends Node3D
## A Thing That Wants Your Chickens. Theme decides what it is tonight.

const MK = preload("res://scripts/meshkit.gd")

const THEMES := [
	{"id": "zombie", "name": "THE SHUFFLING DEAD", "sub": "they smell the eggs", "body": Color(0.35, 0.49, 0.29), "eye": Color(1, 0.15, 0.15), "scale": 1.0, "speed": 2.2, "hp": 50.0, "dmg": 8.0, "bounty": 4, "base": 5.0, "per": 1.6},
	{"id": "goblin", "name": "THE GOBLIN GRAB-GANG", "sub": "quick little hands", "body": Color(0.29, 0.6, 0.25), "eye": Color(1, 0.9, 0.2), "scale": 0.75, "speed": 3.6, "hp": 30.0, "dmg": 5.0, "bounty": 3, "base": 6.0, "per": 2.0},
	{"id": "midget", "name": "FURIOUS MIDGET PEOPLE WITH STICKS", "sub": "so many sticks", "body": Color(0.54, 0.35, 0.17), "eye": Color(1, 1, 1), "scale": 0.6, "speed": 4.2, "hp": 22.0, "dmg": 4.0, "bounty": 3, "base": 8.0, "per": 2.4, "stick": true},
	{"id": "grey", "name": "THE GREY ONES", "sub": "they come for the yolk", "body": Color(0.6, 0.64, 0.68), "eye": Color(0.4, 0.88, 1), "scale": 0.9, "speed": 2.8, "hp": 45.0, "dmg": 7.0, "bounty": 5, "base": 4.0, "per": 1.4},
	{"id": "bones", "name": "THE RATTLING BONES", "sub": "calcium seeks calcium", "body": Color(0.85, 0.83, 0.75), "eye": Color(0.5, 1, 0.5), "scale": 1.0, "speed": 3.0, "hp": 35.0, "dmg": 6.0, "bounty": 4, "base": 6.0, "per": 1.8},
	{"id": "frost", "name": "THE FROST WALKERS", "sub": "winter wants chicken soup", "body": Color(0.62, 0.84, 0.91), "eye": Color(0.7, 0.95, 1), "scale": 1.15, "speed": 1.6, "hp": 120.0, "dmg": 12.0, "bounty": 8, "base": 3.0, "per": 1.0},
	{"id": "wolf", "name": "THE BIG BAD WOLF", "sub": "he huffed. he puffed.", "body": Color(0.3, 0.28, 0.3), "eye": Color(1, 0.3, 0.1), "scale": 2.2, "speed": 4.5, "hp": 400.0, "dmg": 20.0, "bounty": 60, "base": 1.0, "per": 0.0, "boss": true, "min_night": 4, "ears": true, "escort": 3},
	{"id": "bigfoot", "name": "BIGFOOT", "sub": "he is real and he is hungry", "body": Color(0.42, 0.3, 0.2), "eye": Color(1, 1, 0.6), "scale": 2.6, "speed": 3.0, "hp": 600.0, "dmg": 25.0, "bounty": 80, "base": 1.0, "per": 0.0, "boss": true, "min_night": 6},
	{"id": "dragon", "name": "A LITERAL DRAGON???", "sub": "of course it wants chicken", "body": Color(0.55, 0.15, 0.6), "eye": Color(1, 0.5, 0.1), "scale": 2.0, "speed": 5.0, "hp": 500.0, "dmg": 30.0, "bounty": 100, "base": 1.0, "per": 0.0, "boss": true, "min_night": 8, "flying": true, "wings": true},
]

static func pick_theme(night: int) -> Dictionary:
	var bosses := THEMES.filter(func(t): return t.get("boss", false) and night >= t.get("min_night", 99))
	var normals := THEMES.filter(func(t): return not t.get("boss", false))
	if night % 4 == 0 and bosses.size() > 0:
		return bosses[randi() % bosses.size()]
	return normals[randi() % normals.size()]

var game: Node3D
var theme := {}
var hp := 50.0
var max_hp := 50.0
var spd := 2.0
var body_scale := 1.0
var flying := false
# approach | chew | attack_coop | carry | burn
var state := "approach"
var carried = null
var entered := false
var _chew_t := 0.0
var _atk_cd := 0.0
var _retarget_t := 0.0
var _burn_t := 0.0
var _anim_t := 0.0
var _target_chicken = null
var _wings: Array = []
var _mats: Array = []

func setup(g: Node3D, night: int, thm: Dictionary, escort := false) -> void:
	game = g
	theme = thm.duplicate()
	if escort:
		theme["scale"] = thm["scale"] * 0.5
		theme["hp"] = 30.0
		theme["dmg"] = 5.0
		theme["bounty"] = 4
		theme["boss"] = false
		theme["flying"] = false
	body_scale = theme["scale"]
	var hp_mul := 1.0 + 0.13 * float(night - 1)
	hp = theme["hp"] * hp_mul
	max_hp = hp
	spd = theme["speed"] * randf_range(0.9, 1.1)
	flying = theme.get("flying", false)
	var ang := randf() * TAU
	position = Vector3(cos(ang), 0, sin(ang)) * 62.0
	if flying:
		position.y = 9.0
	_build_mesh()

func _build_mesh() -> void:
	var s: float = body_scale
	var body_c: Color = theme["body"]
	var eye_c: Color = theme["eye"]
	var body := MK.capsule(self, 0.42 * s, 1.5 * s, body_c, Vector3(0, 0.85 * s, 0))
	_mats.append(body.material_override)
	var head := MK.sphere(self, 0.3 * s, body_c.lightened(0.08), Vector3(0, 1.75 * s, 0.06 * s))
	_mats.append(head.material_override)
	MK.sphere(self, 0.06 * s, eye_c, Vector3(0.12 * s, 1.8 * s, 0.26 * s), true, 3.0)
	MK.sphere(self, 0.06 * s, eye_c, Vector3(-0.12 * s, 1.8 * s, 0.26 * s), true, 3.0)
	# arms
	MK.capsule(self, 0.1 * s, 0.8 * s, body_c.darkened(0.15), Vector3(0.5 * s, 1.1 * s, 0.1 * s)).rotation.x = deg_to_rad(-40)
	MK.capsule(self, 0.1 * s, 0.8 * s, body_c.darkened(0.15), Vector3(-0.5 * s, 1.1 * s, 0.1 * s)).rotation.x = deg_to_rad(-40)
	if theme.get("stick", false):
		MK.cyl(self, 0.03, 0.04, 1.2, Color(0.45, 0.3, 0.15), Vector3(0.55 * s, 1.3 * s, 0.4 * s)).rotation.x = deg_to_rad(-60)
	if theme.get("ears", false):
		MK.cyl(self, 0.0, 0.12 * s, 0.4 * s, body_c, Vector3(0.16 * s, 2.1 * s, 0))
		MK.cyl(self, 0.0, 0.12 * s, 0.4 * s, body_c, Vector3(-0.16 * s, 2.1 * s, 0))
	if theme.get("wings", false):
		for side in [-1.0, 1.0]:
			var w := MK.box(self, Vector3(1.8 * s, 0.06 * s, 0.7 * s), body_c.darkened(0.2), Vector3(side * 1.1 * s, 1.5 * s, -0.2 * s))
			_wings.append(w)

func tick(delta: float) -> void:
	_anim_t += delta
	_atk_cd -= delta
	for i in _wings.size():
		_wings[i].rotation.z = sin(_anim_t * 9.0) * 0.5 * (1 if i == 0 else -1)
	match state:
		"burn":
			_burn_t -= delta
			scale = Vector3.ONE * maxf(0.01, _burn_t / 1.2)
			position.y -= delta * 0.5
			if _burn_t <= 0.0:
				game.remove_enemy(self, false)
			return
		"chew":
			_chew_t -= delta
			position += Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * 0.02
			if _chew_t <= 0.0:
				entered = true
				state = "approach"
			return
		"carry":
			var out := Vector3(position.x, 0, position.z).normalized()
			_move(out, spd * 1.15, delta)
			if carried != null and is_instance_valid(carried):
				carried.position = position + Vector3(0, 2.2 * body_scale, 0)
			if Vector3(position.x, 0, position.z).length() > 70.0:
				game.chicken_taken(carried)
				carried = null
				game.remove_enemy(self, false)
			return
	# --- approach / attack ---
	_retarget_t -= delta
	if _retarget_t <= 0.0:
		_retarget_t = 0.5
		_target_chicken = game.nearest_targetable_chicken(position)
	var dest: Vector3
	var attacking_coop := false
	if _target_chicken != null and is_instance_valid(_target_chicken) and _target_chicken.targetable():
		dest = _target_chicken.position
	else:
		_target_chicken = null
		dest = game.coop_door
		attacking_coop = true
	var flat_d := Vector3(dest.x - position.x, 0, dest.z - position.z)
	var dist := flat_d.length()
	# player swipe
	var pp: Vector3 = game.player.global_position
	if _atk_cd <= 0.0 and Vector3(pp.x - position.x, 0, pp.z - position.z).length() < 1.8 * body_scale:
		_atk_cd = 1.2
		game.damage_player(theme["dmg"])
	if attacking_coop:
		if dist < 2.6:
			if _atk_cd <= 0.0:
				_atk_cd = 1.0
				game.damage_coop(theme["dmg"] * 0.6)
				position += Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * 0.05
			return
	else:
		if dist < 1.2 * maxf(1.0, body_scale) and (not flying or position.y < 1.5):
			carried = _target_chicken
			carried.state = "carried"
			carried.visible = true
			state = "carry"
			game.sfx.play("grab")
			game.ui.whisper("IT HAS ONE OF YOUR CHICKENS")
			return
	var dir := flat_d.normalized()
	# fence pause: crossing into the yard costs time based on fence tier
	if not entered and not flying:
		var next := position + dir * spd * delta
		if game.in_yard(next.x, next.z):
			if game.in_gate(next.x, next.z) or game.upgrades.fence <= 0:
				entered = true
			else:
				state = "chew"
				_chew_t = 1.8 * float(game.upgrades.fence)
				return
	_move(dir, spd, delta)
	if flying:
		var want_y := 9.0
		if dist < 6.0:
			want_y = 1.0
		position.y = lerpf(position.y, want_y, delta * 2.0)
	else:
		position.y = absf(sin(_anim_t * 8.0)) * 0.06 * body_scale

func _move(dir: Vector3, speed: float, delta: float) -> void:
	position += dir * speed * delta
	if dir.length() > 0.01:
		rotation.y = atan2(dir.x, dir.z)

func ignite() -> void:
	if state == "burn":
		return
	state = "burn"
	_burn_t = 1.2
	for m in _mats:
		m.emission_enabled = true
		m.emission = Color(1.0, 0.45, 0.1)
		m.emission_energy_multiplier = 2.0
	if carried != null and is_instance_valid(carried):
		carried.state = "to_coop"
		carried = null

func damage(n: float) -> void:
	if state == "burn":
		return
	hp -= n
	for m in _mats:
		m.emission_enabled = true
		m.emission = Color(1, 1, 1)
		m.emission_energy_multiplier = 1.2
	var tw := create_tween()
	tw.tween_interval(0.08)
	tw.tween_callback(func():
		for m in _mats:
			m.emission_enabled = false)
	game.sfx.play("hit", -6.0)
	if hp <= 0.0:
		if carried != null and is_instance_valid(carried):
			carried.state = "to_coop"
			carried.position.y = 0.0
			carried = null
		game.remove_enemy(self, true)
