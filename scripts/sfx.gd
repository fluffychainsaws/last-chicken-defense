extends Node
## Procedural bleep-bloop sound effects. No audio assets needed.

var _streams := {}
var _players: Array[AudioStreamPlayer] = []
var _cluck_cd := 0.0
var _crow_player: AudioStreamPlayer

## Real recordings, loaded at runtime so no .import step is needed.
const CLUCK_PATH := "res://audio/chicken_cluck.mp3"
const CROW_PATH := "res://audio/rooster_crow.mp3"
const SHOTGUN_PATH := "res://audio/shotgun.mp3"
## Minimum gap between chicken vocalizations, so the yard never turns into a wall of clucking.
const CLUCK_MIN_GAP := 3.2

func _process(delta: float) -> void:
	_cluck_cd -= delta

func _load_mp3(path: String) -> AudioStream:
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	var s := AudioStreamMP3.new()
	s.data = f.get_buffer(f.get_length())
	return s

## Occasional chicken vocalization. Rate-limited; extra calls are dropped, not queued.
func cluck(vol_db := -12.0) -> void:
	if _cluck_cd > 0.0 or not _streams.has("real_cluck"):
		return
	_cluck_cd = CLUCK_MIN_GAP + randf() * 3.5
	var p := _free_player()
	if p == null:
		return
	p.stream = _streams["real_cluck"]
	p.volume_db = vol_db + randf_range(-2.5, 2.5)
	p.pitch_scale = randf_range(0.88, 1.15)
	p.play()

## The rooster crowing — dawn and nightfall. Never overlaps itself.
func crow(vol_db := -6.0) -> void:
	if not _streams.has("real_crow"):
		return
	if _crow_player.playing:
		return
	_crow_player.stream = _streams["real_crow"]
	_crow_player.volume_db = vol_db
	_crow_player.pitch_scale = randf_range(0.96, 1.04)
	_crow_player.play()

func _free_player() -> AudioStreamPlayer:
	for p in _players:
		if not p.playing:
			return p
	return null

func _ready() -> void:
	_streams = {
		"cluck": _tone(640.0, 0.09, "square", 0.18, -260.0),
		"cluck2": _tone(520.0, 0.07, "square", 0.15, -180.0),
		"hit": _tone(180.0, 0.09, "saw", 0.3, -70.0),
		"swing": _tone(90.0, 0.1, "sine", 0.25, 240.0),
		"shot": _tone(0.0, 0.25, "noise", 0.5, 0.0),
		"coin": _tone(880.0, 0.08, "square", 0.2, 440.0),
		"egg": _tone(300.0, 0.06, "sine", 0.3, -140.0),
		"horn": _tone(72.0, 1.3, "saw", 0.4, -28.0),
		"hurt": _tone(140.0, 0.22, "saw", 0.4, -85.0),
		"buy": _tone(520.0, 0.12, "square", 0.2, 300.0),
		"denied": _tone(160.0, 0.16, "square", 0.25, -50.0),
		"grab": _tone(420.0, 0.2, "saw", 0.25, -300.0),
	}
	var cluck_stream := _load_mp3(CLUCK_PATH)
	if cluck_stream != null:
		_streams["real_cluck"] = cluck_stream
	var crow_stream := _load_mp3(CROW_PATH)
	if crow_stream != null:
		_streams["real_crow"] = crow_stream
	# real gunshot replaces the synthesized "shot" bleep when present
	var gun_stream := _load_mp3(SHOTGUN_PATH)
	if gun_stream != null:
		_streams["shot"] = gun_stream
	for i in 10:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	_crow_player = AudioStreamPlayer.new()
	add_child(_crow_player)

func play(sfx_name: String, vol_db := 0.0) -> void:
	if not _streams.has(sfx_name):
		return
	var p := _free_player()
	if p == null:
		return
	p.stream = _streams[sfx_name]
	p.volume_db = vol_db
	# players are pooled and cluck() randomizes pitch, so always reset it
	p.pitch_scale = randf_range(0.95, 1.06) if sfx_name == "shot" else 1.0
	p.play()

func _tone(freq: float, dur: float, kind: String, vol: float, slide: float) -> AudioStreamWAV:
	var rate := 22050
	var n := int(dur * rate)
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	var phase := 0.0
	for i in n:
		var t := float(i) / float(rate)
		var f := freq + slide * (t / dur)
		phase += f / float(rate)
		var cycle := fmod(phase, 1.0)
		var s := 0.0
		match kind:
			"square":
				s = 1.0 if cycle < 0.5 else -1.0
			"saw":
				s = cycle * 2.0 - 1.0
			"sine":
				s = sin(TAU * phase)
			"noise":
				s = randf() * 2.0 - 1.0
		var envelope := 1.0 - t / dur
		var v := int(clampf(s * envelope * vol, -1.0, 1.0) * 32767.0)
		bytes.encode_s16(i * 2, v)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.data = bytes
	return wav
