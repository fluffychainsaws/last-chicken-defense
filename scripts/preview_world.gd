extends SceneTree
## Dev utility: boot the real game world and screenshot it, so lighting, fog and
## colour grading can be judged on the actual scene rather than a blank plane.
## Run: xvfb-run -a godot --path . --script scripts/preview_world.gd -- --out=day.png
##      ... -- --night --out=night.png

var _frames := 0
var _out := "world.png"
var _night := false
var _market := false
var _roost := false
var _sheet := false
var _game: Node3D = null
var _switched := false

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.trim_prefix("--out=")
		elif a == "--night":
			_night = true
		elif a == "--market":
			_market = true
		elif a == "--roost":
			_roost = true
		elif a == "--sheet":
			_roost = true
			_sheet = true
	root.size = Vector2i(1600, 900)
	var packed: PackedScene = load("res://scenes/main.tscn")
	_game = packed.instantiate()
	root.add_child(_game)

func _process(_d: float) -> bool:
	_frames += 1
	# let the world build, then skip the title screen so the HUD isn't over it
	if _frames == 20 and _game != null and _game.has_method("start_new"):
		_game.start_new()
	if _night and not _switched and _frames == 60:
		_switched = true
		# jump the clock to nightfall rather than waiting out a whole day
		_game.phase_t = 0.999
	if _market and _frames == 70 and _game.has_method("open_market"):
		_game.open_market()
	if _roost and _frames == 70 and _game.has_method("open_coop"):
		_game.coins = 9999
		# put one bird partway up a class so the sheet has something to show
		if _sheet and _game.chickens.size() > 0:
			var b = _game.chickens[0]
			_game.promote(b, "mage")
			for i in 6:
				_game.buy_track(b, "damage")
		_game.open_coop()
		if _sheet:
			_game.coop_sel = 0
			_game.ui.coop_refresh()
	if _frames < 150:
		return false
	var img := root.get_texture().get_image()
	img.save_png(_out)
	print("wrote ", _out)
	quit()
	return true
