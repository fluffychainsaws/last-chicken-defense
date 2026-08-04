extends CanvasLayer
## All 2D UI: HUD, hotbar, announcements, whispers, Farmers Market, overlays.

var game: Node3D

var _hp_fill: ColorRect
var _hp_label: Label
var _chips := {}
var _clock: Label
var _announce_big: Label
var _announce_sub: Label
var _prompt: Label
var _whisper: Label
var _hotbar_slots: Array = []
var _damage_flash: ColorRect
var _night_shade: ColorRect
var _fade: ColorRect
var _market_panel: PanelContainer
var _market_body: VBoxContainer
var _coop_panel: PanelContainer
var _coop_body: VBoxContainer
var _overlay: Control
var _crosshair: Label

const FONT_BIG := 42
const FONT_MED := 20

## One shared look for every control, instead of each panel inventing its own.
## A CanvasLayer can't hold a theme, so it's pushed onto the direct Control
## children after the tree is built and inherited down from there.
const UI_INK := Color(0.93, 0.91, 0.85)
const UI_PANEL := Color(0.07, 0.065, 0.055, 0.86)
const UI_EDGE := Color(0.62, 0.55, 0.36, 0.55)
const UI_ACCENT := Color(0.86, 0.72, 0.30)

static func _box(bg: Color, edge: Color, radius := 8, border := 1) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = bg
	b.set_corner_radius_all(radius)
	b.set_border_width_all(border)
	b.border_color = edge
	b.content_margin_left = 14
	b.content_margin_right = 14
	b.content_margin_top = 7
	b.content_margin_bottom = 7
	return b

func _build_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = FONT_MED
	# buttons carry most of the interface's character — the market is all buttons
	t.set_stylebox("normal", "Button", _box(Color(0.12, 0.11, 0.09, 0.92), UI_EDGE))
	t.set_stylebox("hover", "Button", _box(Color(0.2, 0.18, 0.13, 0.95), UI_ACCENT))
	t.set_stylebox("pressed", "Button", _box(Color(0.08, 0.075, 0.06, 0.98), UI_ACCENT))
	t.set_stylebox("disabled", "Button", _box(Color(0.1, 0.1, 0.1, 0.55), Color(0.35, 0.33, 0.3, 0.35)))
	t.set_stylebox("focus", "Button", _box(Color(0, 0, 0, 0), UI_ACCENT))
	t.set_color("font_color", "Button", UI_INK)
	t.set_color("font_hover_color", "Button", Color(1.0, 0.95, 0.78))
	t.set_color("font_disabled_color", "Button", Color(0.55, 0.53, 0.5))
	t.set_font_size("font_size", "Button", FONT_MED)
	t.set_stylebox("panel", "PanelContainer", _box(UI_PANEL, UI_EDGE, 10))
	t.set_color("font_color", "Label", UI_INK)
	t.set_stylebox("panel", "ScrollContainer", _box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 0))
	return t

func setup(g: Node3D) -> void:
	game = g
	layer = 10
	_build_fx()
	_build_hud()
	_build_market()
	_build_coop()
	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_overlay)
	# added last so the sleep fade covers the HUD and menus too
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0.0)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.visible = false
	add_child(_fade)
	# applied last so the start screen and overlays inherit it too, not just the
	# controls that happened to exist before them
	var t := _build_theme()
	for c in get_children():
		if c is Control:
			(c as Control).theme = t

func _label(parent: Node, text: String, size: int, color := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 6)
	parent.add_child(l)
	return l

func _chip(parent: Node, key: String, text: String, color := Color.WHITE) -> void:
	var p := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.07, 0.05, 0.72)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	p.add_theme_stylebox_override("panel", style)
	parent.add_child(p)
	_chips[key] = _label(p, text, 17, color)

func _build_fx() -> void:
	_night_shade = ColorRect.new()
	_night_shade.color = Color(0.02, 0.02, 0.1, 0.0)
	_night_shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_night_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_night_shade)
	_damage_flash = ColorRect.new()
	_damage_flash.color = Color(0.8, 0.05, 0.05, 0.0)
	_damage_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_damage_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_damage_flash)

func _build_hud() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	# crosshair
	_crosshair = _label(root, "+", 22, Color(1, 1, 1, 0.8))
	_crosshair.anchor_left = 0.5
	_crosshair.anchor_right = 0.5
	_crosshair.anchor_top = 0.5
	_crosshair.anchor_bottom = 0.5
	_crosshair.offset_left = -7.0
	_crosshair.offset_top = -16.0
	# top-right: clock chip
	var top := HBoxContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	top.position += Vector2(-360, 12)
	top.add_theme_constant_override("separation", 8)
	root.add_child(top)
	_chip(top, "clock", "Day 1   6:00 a.m.", Color(1, 0.9, 0.6))
	# top-left: status chips
	var tl := HBoxContainer.new()
	tl.set_anchors_preset(Control.PRESET_TOP_LEFT)
	tl.position = Vector2(12, 12)
	tl.add_theme_constant_override("separation", 8)
	root.add_child(tl)
	_chip(tl, "coins", "$ 25", Color(1, 0.85, 0.3))
	_chip(tl, "eggs", "EGGS 0", Color(1, 1, 1))
	_chip(tl, "feed", "FEED 5", Color(0.85, 0.75, 0.5))
	_chip(tl, "shells", "SHELLS 0", Color(0.9, 0.5, 0.4))
	_chip(tl, "hens", "HENS 10", Color(0.95, 0.9, 0.8))
	_chip(tl, "coop", "COOP 100%", Color(0.7, 0.9, 0.7))
	# bottom-left: hp
	var hp_box := Control.new()
	hp_box.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	hp_box.position = Vector2(16, -56)
	root.add_child(hp_box)
	var hp_bg := ColorRect.new()
	hp_bg.color = Color(0, 0, 0, 0.55)
	hp_bg.size = Vector2(240, 22)
	hp_box.add_child(hp_bg)
	_hp_fill = ColorRect.new()
	_hp_fill.color = Color(0.75, 0.2, 0.15)
	_hp_fill.position = Vector2(2, 2)
	_hp_fill.size = Vector2(236, 18)
	hp_box.add_child(_hp_fill)
	_hp_label = _label(hp_box, "100 / 100", 15)
	_hp_label.position = Vector2(8, -2)
	# announcements
	var center := VBoxContainer.new()
	center.set_anchors_preset(Control.PRESET_CENTER_TOP)
	center.position += Vector2(-420, 90)
	center.custom_minimum_size = Vector2(840, 0)
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(center)
	_announce_big = _label(center, "", FONT_BIG, Color(1, 0.95, 0.85))
	_announce_big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_announce_sub = _label(center, "", FONT_MED, Color(0.9, 0.55, 0.5))
	_announce_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_announce_big.modulate.a = 0.0
	_announce_sub.modulate.a = 0.0
	# prompt
	_prompt = _label(root, "", 19, Color(1, 1, 0.85))
	_prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt.position += Vector2(-200, -140)
	_prompt.custom_minimum_size = Vector2(400, 0)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# whisper
	_whisper = _label(root, "", 18, Color(0.75, 0.1, 0.12))
	_whisper.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_whisper.position += Vector2(-300, -200)
	_whisper.custom_minimum_size = Vector2(600, 0)
	_whisper.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_whisper.modulate.a = 0.0
	# hotbar
	var bar := HBoxContainer.new()
	bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	bar.position += Vector2(-240, -46)
	bar.add_theme_constant_override("separation", 6)
	root.add_child(bar)
	for i in 4:
		var p := PanelContainer.new()
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.08, 0.07, 0.05, 0.72)
		style.border_color = Color(1, 0.85, 0.3)
		style.content_margin_left = 10
		style.content_margin_right = 10
		style.content_margin_top = 6
		style.content_margin_bottom = 6
		p.add_theme_stylebox_override("panel", style)
		bar.add_child(p)
		var l := _label(p, "", 15)
		l.custom_minimum_size = Vector2(96, 0)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_hotbar_slots.append({"panel": p, "style": style, "label": l})

func refresh() -> void:
	var pl = game.player
	_hp_fill.size.x = 236.0 * clampf(pl.hp / pl.max_hp, 0.0, 1.0)
	_hp_label.text = "%d / %d" % [int(maxf(0, pl.hp)), int(pl.max_hp)]
	_chips["coins"].text = "$ %d" % game.coins
	_chips["eggs"].text = "EGGS %d" % game.eggs
	_chips["feed"].text = "FEED %d" % game.feed
	_chips["shells"].text = "SHELLS %d" % game.shells
	var hens := 0
	var chicks := 0
	for c in game.chickens:
		if c.is_chick:
			chicks += 1
		else:
			hens += 1
	var hen_txt := "HENS %d" % hens
	if chicks > 0:
		hen_txt += " +%d chick" % chicks
	if game.roosters.size() > 0:
		hen_txt += " +%d ROO" % game.roosters.size()
	_chips["hens"].text = hen_txt
	var pct := int(100.0 * game.coop_hp / game.max_coop_hp())
	_chips["coop"].text = ("ARMORY %d%%" if game.is_night else "COOP %d%%") % pct
	_chips["coop"].add_theme_color_override("font_color", Color(0.7, 0.9, 0.7) if pct > 50 else Color(1, 0.4, 0.3))
	_chips["clock"].text = game.clock_text()
	update_hotbar()

func update_hotbar() -> void:
	var names := ["SHOVEL", "SHOTGUN", "FEED", "EGG"]
	var shotgun_txt := "LOCKED"
	if game.upgrades.shotgun:
		var pl = game.player
		shotgun_txt = "RELOADING" if pl.reloading else "%d/%d" % [pl.shotgun_mag, game.shells]
	var counts := ["", shotgun_txt, "x%d" % game.feed, "x%d" % game.eggs]
	for i in 4:
		var s = _hotbar_slots[i]
		s.label.text = "%d  %s %s" % [i + 1, names[i], counts[i]]
		s.style.border_width_top = 2 if game.player.slot == i else 0
		s.style.border_width_bottom = 2 if game.player.slot == i else 0
		s.style.border_width_left = 2 if game.player.slot == i else 0
		s.style.border_width_right = 2 if game.player.slot == i else 0

func set_prompt(text) -> void:
	_prompt.text = text if text != null else ""

func announce(big: String, sub := "", shake := false) -> void:
	_announce_big.text = big
	_announce_sub.text = sub
	var tw := create_tween()
	_announce_big.modulate.a = 0.0
	_announce_sub.modulate.a = 0.0
	tw.tween_property(_announce_big, "modulate:a", 1.0, 0.15)
	tw.parallel().tween_property(_announce_sub, "modulate:a", 1.0, 0.3)
	tw.tween_interval(3.2)
	tw.tween_property(_announce_big, "modulate:a", 0.0, 0.6)
	tw.parallel().tween_property(_announce_sub, "modulate:a", 0.0, 0.6)
	if shake:
		var tw2 := create_tween()
		for i in 12:
			tw2.tween_property(_announce_big, "position:x", randf_range(-6, 6), 0.04)
		tw2.tween_property(_announce_big, "position:x", 0.0, 0.04)

func whisper(text: String) -> void:
	_whisper.text = text.to_lower()
	var tw := create_tween()
	_whisper.modulate.a = 0.0
	tw.tween_property(_whisper, "modulate:a", 0.85, 0.8)
	tw.tween_interval(2.2)
	tw.tween_property(_whisper, "modulate:a", 0.0, 1.2)

## Sleep transition. Awaited by the caller.
func fade_to_black(dur: float) -> void:
	_fade.color.a = 0.0
	_fade.visible = true
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, dur)
	await tw.finished

func fade_from_black(dur: float) -> void:
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 0.0, dur)
	await tw.finished
	_fade.visible = false

func flash_damage() -> void:
	_damage_flash.color.a = 0.35
	var tw := create_tween()
	tw.tween_property(_damage_flash, "color:a", 0.0, 0.45)

func night_fx(on: bool, boss := false) -> void:
	var tw := create_tween()
	var target := 0.0
	if on:
		target = 0.22 if not boss else 0.3
	var col := Color(0.25, 0.02, 0.05) if boss else Color(0.02, 0.02, 0.1)
	_night_shade.color = Color(col.r, col.g, col.b, _night_shade.color.a)
	tw.tween_property(_night_shade, "color:a", target, 2.0)

# ---------- Coop upgrades ----------

const CL = preload("res://scripts/classes.gd")

func _build_coop() -> void:
	_coop_panel = PanelContainer.new()
	_coop_panel.anchor_left = 0.5
	_coop_panel.anchor_right = 0.5
	_coop_panel.anchor_top = 0.5
	_coop_panel.anchor_bottom = 0.5
	_coop_panel.offset_left = -430
	_coop_panel.offset_right = 430
	_coop_panel.offset_top = -310
	_coop_panel.offset_bottom = 310
	_coop_panel.custom_minimum_size = Vector2(860, 620)
	_coop_panel.visible = false
	add_child(_coop_panel)
	_coop_body = VBoxContainer.new()
	_coop_body.add_theme_constant_override("separation", 6)
	_coop_panel.add_child(_coop_body)

func open_coop() -> void:
	_coop_panel.visible = true
	_render_coop()

func close_coop() -> void:
	_coop_panel.visible = false

func coop_refresh() -> void:
	if _coop_panel != null and _coop_panel.visible:
		_render_coop()

## Two views in one panel: the roster, and one bird's sheet. game.coop_sel of -1
## means the roster; anything else indexes game.birds().
func _render_coop() -> void:
	_clear(_coop_body)
	var t := _label(_coop_body, "THE ROOST", 32, Color(1, 0.85, 0.45))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label(_coop_body, "training, tempering and terrible ideas  -  you have $ %d" % game.coins, 15, Color(0.8, 0.8, 0.72))
	var flock: Array = game.birds()
	if game.coop_sel < 0 or game.coop_sel >= flock.size():
		_render_roster(flock)
	else:
		_render_sheet(flock[game.coop_sel])
	var close := Button.new()
	close.text = "CLOSE  [ESC]"
	close.pressed.connect(func(): game.close_coop())
	_coop_body.add_child(close)

func _render_roster(flock: Array) -> void:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(820, 440)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_coop_body.add_child(scroll)
	var list := VBoxContainer.new()
	list.custom_minimum_size.x = 790
	list.add_theme_constant_override("separation", 4)
	scroll.add_child(list)
	for i in flock.size():
		var b = flock[i]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		list.add_child(row)
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.custom_minimum_size.x = 600
		row.add_child(col)
		_label(col, b.title(), 18, Color(1, 0.95, 0.8))
		var lv: int = CL.level(b.tracks)
		_label(col, "level %d  -  %d hp  -  %d points spent" % [lv, int(b.max_hp), CL.points_spent(b.tracks)], 13, Color(0.66, 0.7, 0.66))
		var open := Button.new()
		open.text = "TRAIN"
		open.custom_minimum_size = Vector2(120, 0)
		var idx := i
		open.pressed.connect(func():
			game.coop_sel = idx
			_render_coop())
		row.add_child(open)

func _render_sheet(b) -> void:
	var back := Button.new()
	back.text = "< BACK TO THE ROOST"
	back.pressed.connect(func():
		game.coop_sel = -1
		_render_coop())
	_coop_body.add_child(back)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(820, 400)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_coop_body.add_child(scroll)
	var list := VBoxContainer.new()
	list.custom_minimum_size.x = 790
	list.add_theme_constant_override("separation", 4)
	scroll.add_child(list)

	_label(list, b.title(), 22, Color(1, 0.9, 0.6))
	var st: Dictionary = b.stats
	_label(list, "dmg %.1f  -  reach %.1f  -  every %.2fs  -  %d hp  -  %d%% armor  -  %d%% dodge" % [
		st.get("dmg", 0.0), st.get("range", 0.0), st.get("cd", 0.0), int(st.get("hp", 0.0)),
		int(st.get("armor", 0.0) * 100.0), int(st.get("dodge", 0.0) * 100.0)], 14, Color(0.7, 0.78, 0.7))

	# promotion is only ever offered to a plain hen
	if b.class_id == "hen":
		_label(list, "", 10)
		_label(list, "PROMOTE", 18, Color(0.9, 0.8, 0.5))
		for cid in CL.CLASSES:
			if cid == "hen":
				continue
			var info: Dictionary = CL.CLASSES[cid]
			_offer(list, info["name"], info["desc"], int(info["price"]),
				func(): game.promote(b, cid))
	elif b.spec_id == "":
		_label(list, "", 10)
		var ready: bool = CL.can_spec(b.tracks)
		_label(list, "SPECIALISE" if ready else "SPECIALISE  (needs %d points spent)" % CL.SPEC_AT, 18, Color(0.9, 0.8, 0.5))
		if ready:
			for sid in CL.specs_of(b.class_id):
				var sp: Dictionary = CL.specs_of(b.class_id)[sid]
				_offer(list, sp["name"], sp["desc"], game.SPEC_PRICE,
					func(): game.specialise(b, sid))

	_label(list, "", 10)
	_label(list, "TRAINING", 18, Color(0.9, 0.8, 0.5))
	for tr in CL.TRACK_ORDER:
		var info: Dictionary = CL.TRACKS[tr]
		var owned: int = int(b.tracks.get(tr, 0))
		var maxed: bool = owned >= int(info["max"])
		var label := "%s  %d/%d" % [info["name"], owned, int(info["max"])]
		_offer(list, label, info["desc"], -1 if maxed else CL.track_cost(tr, owned),
			func(): game.buy_track(b, tr))

## One purchasable row. A price of -1 renders as MAXED and is not clickable.
func _offer(list: Node, name_text: String, desc_text: String, price: int, on_buy: Callable) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	list.add_child(row)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.custom_minimum_size.x = 560
	row.add_child(col)
	_label(col, name_text, 17, Color(1, 0.95, 0.8))
	var d := _label(col, desc_text, 13, Color(0.65, 0.7, 0.65))
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.custom_minimum_size.x = 560
	var btn := Button.new()
	if price < 0:
		btn.text = "MAXED"
		btn.disabled = true
	else:
		btn.text = "$ %d" % price
		btn.disabled = game.coins < price
		btn.pressed.connect(on_buy)
	btn.custom_minimum_size = Vector2(120, 0)
	row.add_child(btn)

# ---------- Farmers Market ----------

func _build_market() -> void:
	_market_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.08, 0.06, 0.96)
	style.border_color = Color(0.3, 0.8, 0.4)
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_width_left = 2
	style.border_width_right = 2
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	_market_panel.add_theme_stylebox_override("panel", style)
	_market_panel.anchor_left = 0.5
	_market_panel.anchor_right = 0.5
	_market_panel.anchor_top = 0.5
	_market_panel.anchor_bottom = 0.5
	_market_panel.offset_left = -380
	_market_panel.offset_right = 380
	_market_panel.offset_top = -280
	_market_panel.offset_bottom = 280
	_market_panel.custom_minimum_size = Vector2(760, 560)
	_market_panel.visible = false
	add_child(_market_panel)
	_market_body = VBoxContainer.new()
	_market_body.add_theme_constant_override("separation", 6)
	_market_panel.add_child(_market_body)

func open_market() -> void:
	_market_panel.visible = true
	_render_market()

func close_market() -> void:
	_market_panel.visible = false

func _clear(node: Node) -> void:
	for ch in node.get_children():
		ch.queue_free()

func _render_market() -> void:
	_clear(_market_body)
	if game.is_night:
		_label(_market_body, "NO SIGNAL", 40, Color(0.8, 0.2, 0.2))
		_label(_market_body, "the market sleeps. you should not be indoors.", 18, Color(0.6, 0.6, 0.6))
		_label(_market_body, "", 14)
		var btn0 := Button.new()
		btn0.text = "STEP AWAY FROM THE COMPUTER"
		btn0.pressed.connect(func(): game.close_market())
		_market_body.add_child(btn0)
		return
	var title := _label(_market_body, "FARMERSMARKET.NET", 34, Color(0.5, 1, 0.6))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label(_market_body, "est. 1997  -  now with 40%% fewer curses  -  you have $ %d" % game.coins, 16, Color(0.75, 0.85, 0.75))
	var sell := Button.new()
	sell.text = "SELL ALL EGGS  (%d x $6 = $%d)" % [game.eggs, game.eggs * 6]
	sell.disabled = game.eggs <= 0
	sell.pressed.connect(func(): game.sell_eggs())
	_market_body.add_child(sell)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(720, 380)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_market_body.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.custom_minimum_size.x = 690
	list.add_theme_constant_override("separation", 4)
	scroll.add_child(list)
	for item in game.market_items():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		list.add_child(row)
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.custom_minimum_size.x = 540
		row.add_child(col)
		_label(col, item.name, 18, Color(1, 0.95, 0.8))
		var desc := _label(col, item.desc, 13, Color(0.65, 0.7, 0.65))
		# An unwrapped description sets the row's minimum width, which pushes the
		# price button past the scroll viewport, where it is clipped away — the
		# item is then unbuyable with no visible cause.
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.custom_minimum_size.x = 540
		var btn := Button.new()
		if item.owned:
			btn.text = "OWNED"
			btn.disabled = true
		else:
			btn.text = "$ %d" % item.price
			btn.disabled = game.coins < item.price
			var id: String = item.id
			btn.pressed.connect(func(): game.buy(id))
		btn.custom_minimum_size = Vector2(110, 0)
		row.add_child(btn)
	var close := Button.new()
	close.text = "CLOSE  [ESC]"
	close.pressed.connect(func(): game.close_market())
	_market_body.add_child(close)

func market_refresh() -> void:
	if _market_panel.visible:
		_render_market()

# ---------- Overlays ----------

func clear_overlay() -> void:
	for ch in _overlay.get_children():
		ch.queue_free()

func _overlay_panel() -> VBoxContainer:
	clear_overlay()
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.02, 0.03, 0.88)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(bg)
	var box := VBoxContainer.new()
	box.anchor_left = 0.5
	box.anchor_right = 0.5
	box.anchor_top = 0.5
	box.anchor_bottom = 0.5
	box.offset_left = -350
	box.offset_right = 350
	box.offset_top = -280
	box.offset_bottom = 280
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 10)
	_overlay.add_child(box)
	return box

func show_start(has_save: bool) -> void:
	var box := _overlay_panel()
	var t := _label(box, "LAST CHICKEN DEFENSE", 52, Color(1, 0.85, 0.3))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var s := _label(box, "T H E   A R M A E G G I N", 24, Color(0.8, 0.25, 0.2))
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label(box, "", 10)
	_label(box, "By day: feed the hens, fix the coop, send them foraging.", 17, Color(0.8, 0.85, 0.8))
	_label(box, "By night: something comes out of the trees. It wants chicken.", 17, Color(0.8, 0.5, 0.5))
	_label(box, "", 10)
	_label(box, "WASD move   SHIFT sprint   SPACE jump   MOUSE look/attack", 15, Color(0.6, 0.65, 0.6))
	_label(box, "E interact   1-4 / wheel items   ESC pause", 15, Color(0.6, 0.65, 0.6))
	_label(box, "", 10)
	if has_save:
		var cont := Button.new()
		cont.text = "CONTINUE  (Day %d)" % game.peek_save_day()
		cont.pressed.connect(func(): game.start_continue())
		box.add_child(cont)
	var new_btn := Button.new()
	new_btn.text = "NEW GAME"
	new_btn.pressed.connect(func(): game.start_new())
	box.add_child(new_btn)

func show_pause() -> void:
	var box := _overlay_panel()
	var t := _label(box, "PAUSED", 44, Color(1, 0.95, 0.85))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label(box, "the chickens are waiting.", 16, Color(0.6, 0.65, 0.6))
	var btn := Button.new()
	btn.text = "RESUME"
	btn.pressed.connect(func(): game.unpause())
	box.add_child(btn)

func show_downed() -> void:
	var box := _overlay_panel()
	var t := _label(box, "YOU BLACKED OUT", 44, Color(0.9, 0.2, 0.15))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label(box, "you wake at dawn. your wallet feels lighter. the chickens saw everything.", 16, Color(0.7, 0.6, 0.6))

func show_game_over(days: int) -> void:
	var box := _overlay_panel()
	var t := _label(box, "THE ARMAEGGIN HAS COME", 46, Color(0.9, 0.2, 0.15))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label(box, "every last chicken is gone. the yard is silent.", 18, Color(0.75, 0.65, 0.65))
	_label(box, "you survived %d days." % days, 18, Color(1, 0.85, 0.3))
	var btn := Button.new()
	btn.text = "TRY AGAIN"
	btn.pressed.connect(func(): game.restart())
	box.add_child(btn)
