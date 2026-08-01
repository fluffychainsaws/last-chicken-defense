extends Node
## Procedural bleep-bloop sound effects. No audio assets needed.

var _streams := {}
var _players: Array[AudioStreamPlayer] = []

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
	for i in 10:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)

func play(sfx_name: String, vol_db := 0.0) -> void:
	if not _streams.has(sfx_name):
		return
	for p in _players:
		if not p.playing:
			p.stream = _streams[sfx_name]
			p.volume_db = vol_db
			p.play()
			return

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
