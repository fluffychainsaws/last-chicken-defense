extends SceneTree
## Dev utility: render a row of enemies to a PNG so the art can be eyeballed
## without launching the game and waiting for the right wave to roll.
## Run: xvfb-run -a godot --path . --script scripts/preview_enemy.gd -- midget

const ENEMY := preload("res://scripts/enemy.gd")

var _frames := 0
var _out := "preview.png"

func _initialize() -> void:
	var want := "midget"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.trim_prefix("--out=")
		elif not a.begins_with("-"):
			want = a

	var theme := {}
	for t in ENEMY.THEMES:
		if t["id"] == want:
			theme = t
			break
	if theme.is_empty():
		print("no such theme: ", want)
		quit(1)
		return

	root.size = Vector2i(1400, 720)
	var world := Node3D.new()
	root.add_child(world)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.09, 0.10, 0.13)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.45, 0.5, 0.6)
	e.ambient_light_energy = 0.5
	env.environment = e
	world.add_child(env)

	# key light low and to one side so the wet specular actually shows up
	var key := DirectionalLight3D.new()
	key.light_energy = 2.2
	key.rotation = Vector3(deg_to_rad(-32), deg_to_rad(38), 0)
	world.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.light_energy = 0.7
	fill.light_color = Color(0.7, 0.8, 1.0)
	fill.rotation = Vector3(deg_to_rad(-14), deg_to_rad(-125), 0)
	world.add_child(fill)

	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.16, 0.17, 0.15)
	ground.material_override = gm
	world.add_child(ground)

	seed(20260801)
	var n := 5
	for i in n:
		var e3 := Node3D.new()
		e3.set_script(ENEMY)
		world.add_child(e3)
		e3.theme = theme.duplicate()
		e3.body_scale = theme["scale"]
		e3.spd = theme["speed"]
		e3._build_mesh()
		e3.position = Vector3((float(i) - float(n - 1) * 0.5) * 0.95, 0, 0)
		# faces point +Z, same as the camera's side, so 0 yaw looks down the lens
		e3.rotation.y = deg_to_rad((float(i) - 2.0) * 8.0)

	var cam := Camera3D.new()
	cam.position = Vector3(0, 0.78, 4.1)
	cam.rotation.x = deg_to_rad(-7)
	cam.fov = 46
	world.add_child(cam)
	cam.make_current()

func _process(_d: float) -> bool:
	_frames += 1
	# give the noise textures a few frames to finish generating on their thread
	if _frames < 45:
		return false
	var img := root.get_texture().get_image()
	img.save_png(_out)
	print("wrote ", _out)
	quit()
	return true
