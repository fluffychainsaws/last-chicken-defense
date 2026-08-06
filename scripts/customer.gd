extends Node3D
## Someone who pulls up at the roadside stand. Most of them are exactly what
## they look like: they wander in off the road, pick something off the
## counter, drop money in the honesty box and leave. A few do not pay. And a
## few are not people at all.
##
## The stand runs unattended, so none of this needs the player present — the
## money lands in the till either way. Standing there only lets you catch the
## ones worth catching.

const MK = preload("res://scripts/meshkit.gd")

var game: Node3D
# arrive | browse | leave | offer | grab
var state := "arrive"
## A disguise, worn badly. These come for the birds rather than the produce.
var disguised := false
var _target := Vector3.ZERO
var _timer := 0.0
var _stride := 0.0
var _legs: Array = []
var _arms: Array = []
var _body_mat: StandardMaterial3D = null
var _took := 0
var _paid := 0
var _thief := false
var _exit_x := 0.0
## Nothing about the model is randomised after this point, so a customer that
## reads as suspicious keeps reading that way for its whole visit.
var _skin := Color(0.86, 0.68, 0.52)

const WALK_SPEED := 2.6
const BROWSE_TIME := 4.5
## How long a buyer will stand at the counter waiting on an answer before
## helping itself.
const OFFER_TIME := 14.0

func setup(g: Node3D, is_disguised: bool) -> void:
	game = g
	disguised = is_disguised
	# in from one end of the road, out the other way it came
	# far enough down the lane to walk in from off the property, close enough
	# that the trip is a few seconds rather than most of a minute
	var from_left := randf() < 0.5
	_exit_x = 34.0 if from_left else -34.0
	position = Vector3(-_exit_x, 0, game.ROAD_Z + randf_range(-1.2, 1.2))
	# Several people are served at once and nothing pushes them apart, so pick
	# a spot along the frontage rather than all converging on the middle. The
	# depth jitter keeps two who picked the same x from standing in each other.
	var half: float = maxf(game.stand_width() * 0.5 - 0.45, 0.4)
	_target = game.stand_pos + Vector3(randf_range(-half, half), 0, randf_range(1.9, 2.9))
	_build_mesh()

func _build_mesh() -> void:
	var shirts := [
		Color(0.24, 0.45, 0.78), Color(0.82, 0.34, 0.28), Color(0.28, 0.58, 0.36),
		Color(0.88, 0.72, 0.24), Color(0.55, 0.35, 0.62), Color(0.9, 0.9, 0.88),
	]
	var pants := [Color(0.28, 0.34, 0.48), Color(0.3, 0.3, 0.33), Color(0.45, 0.38, 0.3)]
	var skins := [
		Color(0.90, 0.74, 0.58), Color(0.78, 0.58, 0.42),
		Color(0.55, 0.38, 0.26), Color(0.36, 0.24, 0.17),
	]
	var shirt: Color = shirts[randi() % shirts.size()]
	var trouser: Color = pants[randi() % pants.size()]
	_skin = skins[randi() % skins.size()]
	if disguised:
		# the tell: whatever is wearing this could not get the skin right
		_skin = _skin.lerp(Color(0.42, 0.62, 0.3), 0.55)

	# legs, hip-pivoted so they can stride
	for side in [-1.0, 1.0]:
		var hip := Node3D.new()
		hip.position = Vector3(side * 0.12, 0.86, 0)
		add_child(hip)
		_legs.append(hip)
		MK.box(hip, Vector3(0.19, 0.86, 0.21), trouser, Vector3(0, -0.43, 0))
		MK.box(hip, Vector3(0.21, 0.12, 0.3), Color(0.2, 0.18, 0.17), Vector3(0, -0.86, 0.04))
	# torso
	var torso := MK.box(self, Vector3(0.56, 0.72, 0.3), shirt, Vector3(0, 1.22, 0))
	_body_mat = torso.material_override
	# arms
	for side in [-1.0, 1.0]:
		var sh := Node3D.new()
		sh.position = Vector3(side * 0.34, 1.52, 0)
		add_child(sh)
		_arms.append(sh)
		MK.box(sh, Vector3(0.15, 0.6, 0.16), shirt, Vector3(0, -0.3, 0))
		MK.box(sh, Vector3(0.14, 0.18, 0.15), _skin, Vector3(0, -0.66, 0))
	# neck and head
	MK.box(self, Vector3(0.14, 0.1, 0.14), _skin, Vector3(0, 1.62, 0))
	var head := MK.box(self, Vector3(0.42, 0.46, 0.38), _skin, Vector3(0, 1.9, 0))
	head.scale = Vector3(1.0, 1.0, 1.0)
	# the big flat eyes the reference art lives on
	for side in [-1.0, 1.0]:
		MK.sphere(self, 0.085, Color(0.98, 0.98, 0.96), Vector3(side * 0.11, 1.95, 0.18))
		var pupil_c := Color(0.06, 0.05, 0.05)
		var glow := false
		if disguised:
			pupil_c = Color(0.95, 0.75, 0.15)
			glow = true
		MK.sphere(self, 0.036, pupil_c, Vector3(side * 0.11, 1.95, 0.245), glow, 1.6)
	# hair, or a cap
	if randf() < 0.35:
		MK.box(self, Vector3(0.46, 0.12, 0.42), Color(0.3, 0.32, 0.36), Vector3(0, 2.14, 0))
		MK.box(self, Vector3(0.44, 0.05, 0.22), Color(0.3, 0.32, 0.36), Vector3(0, 2.09, 0.28))
	else:
		var hair := [Color(0.16, 0.12, 0.1), Color(0.45, 0.28, 0.12), Color(0.85, 0.72, 0.4), Color(0.6, 0.6, 0.62)]
		MK.box(self, Vector3(0.44, 0.14, 0.4), hair[randi() % hair.size()], Vector3(0, 2.12, 0))

func tick(delta: float) -> void:
	_timer -= delta
	match state:
		"arrive":
			if _walk_toward(_target, WALK_SPEED, delta):
				if disguised:
					state = "offer"
					_timer = OFFER_TIME
					game.ui.whisper("someone is asking after your birds")
				else:
					state = "browse"
					_timer = BROWSE_TIME
		"browse":
			_face(game.stand_pos)
			_settle(delta)
			if _timer <= 0.0:
				_do_business()
				state = "leave"
		"offer":
			# stands at the counter waiting on an answer, and takes one anyway
			# if it does not get one
			_face(game.stand_pos)
			_settle(delta)
			if _timer <= 0.0:
				state = "grab"
		"grab":
			var bird = game.nearest_stealable_chicken(position)
			if bird == null:
				state = "leave"
				return
			if _walk_toward(bird.position, WALK_SPEED * 1.15, delta):
				game.chicken_stolen_by_buyer(bird)
				state = "leave"
		"leave":
			var out := Vector3(_exit_x, 0, game.ROAD_Z)
			if _walk_toward(out, WALK_SPEED, delta):
				game.customer_gone(self)

## What an honest visitor does at the counter, and what the other sort does.
func _do_business() -> void:
	var want := 1 + randi() % 3
	_took = game.take_from_stand(want)
	if _took <= 0:
		return
	# most pay. a few decide the honour system is optional.
	_thief = randf() < game.stand_theft_chance()
	if _thief:
		game.ui.whisper("something walked off the stand")
		return
	_paid = _took * game.STAND_EGG_PRICE
	game.add_coins(_paid)
	game.sfx.play("coin", -8.0)

## Nightfall. The stand is a daytime thing — nobody shops after dark, and the
## ones who only came to look at the birds do not get to use the cover of it.
## Whatever is still on the lane turns round and walks off, mid-grab or not.
func send_home() -> void:
	state = "leave"

## Sold a bird by the player, at the price it was asking.
func accept_sale(bird) -> void:
	state = "leave"
	game.chicken_sold_to_buyer(bird, offer_price(bird))

## Generous on paper. It is not paying for a chicken, it is paying to get
## close enough to take one, and it never has to make that back.
func offer_price(bird) -> int:
	return int(bird.value() * 1.35)

func _face(at: Vector3) -> void:
	var d := Vector3(at.x - position.x, 0, at.z - position.z)
	if d.length() > 0.05:
		rotation.y = atan2(d.x, d.z)

func _walk_toward(dest: Vector3, speed: float, delta: float) -> bool:
	var d := Vector3(dest.x - position.x, 0, dest.z - position.z)
	if d.length() < 0.5:
		_settle(delta)
		return true
	var dir := d.normalized()
	position += dir * speed * delta
	rotation.y = atan2(dir.x, dir.z)
	_stride += delta * speed * 3.0
	var swing := sin(_stride)
	for i in _legs.size():
		_legs[i].rotation.x = swing * 0.5 * (1.0 if i == 0 else -1.0)
	for i in _arms.size():
		_arms[i].rotation.x = -swing * 0.34 * (1.0 if i == 0 else -1.0)
	position.y = absf(sin(_stride)) * 0.03
	return false

func _settle(delta: float) -> void:
	position.y = lerpf(position.y, 0.0, delta * 8.0)
	for l in _legs:
		l.rotation.x = lerpf(l.rotation.x, 0.0, delta * 8.0)
	for a in _arms:
		a.rotation.x = lerpf(a.rotation.x, 0.0, delta * 8.0)

## Shot, or hit with the shovel. Disguises do not survive it.
func damage(_n: float) -> void:
	if disguised:
		game.ui.whisper("it was never a customer")
		game.spawn_poof(position + Vector3(0, 1.2, 0), Color(0.3, 0.7, 0.25), 12)
	else:
		game.ui.whisper("that was a paying customer")
		game.spawn_poof(position + Vector3(0, 1.2, 0), Color(0.8, 0.2, 0.2), 8)
	game.customer_gone(self)
