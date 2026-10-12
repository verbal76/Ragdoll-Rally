class_name Sfx
extends Node
## Procedurally generated sound effects (no third-party audio files).

const RATE := 22050
var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _next: int = 0

func _ready() -> void:
	_streams["launch"] = _make(0.35, 700.0, 110.0, 0.05, 6.0)
	_streams["thud"] = _make(0.20, 110.0, 45.0, 0.35, 14.0)
	_streams["crash"] = _make(0.55, 300.0, 80.0, 0.9, 5.0)
	_streams["pop"] = _make(0.10, 650.0, 1100.0, 0.0, 12.0)
	_streams["boing"] = _make(0.30, 250.0, 520.0, 0.0, 6.0)
	# material-specific impacts (all synthesized, no third-party audio)
	_streams["wood"] = _make(0.18, 420.0, 190.0, 0.6, 12.0)
	_streams["glass"] = _make(0.40, 2600.0, 3400.0, 0.55, 7.0)
	_streams["stone"] = _make(0.26, 170.0, 85.0, 0.8, 9.0)
	_streams["metal"] = _make(0.50, 950.0, 640.0, 0.12, 6.0)
	_streams["boom"] = _make(1.00, 130.0, 32.0, 0.75, 3.2)
	_streams["fire"] = _make(0.55, 220.0, 170.0, 1.0, 2.5)
	_streams["limb"] = _make(0.24, 520.0, 110.0, 0.5, 10.0)
	for i in 8:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)

func play(name: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if not _streams.has(name) or _players.is_empty():
		return
	var p: AudioStreamPlayer = _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = _streams[name]
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.play()

func _make(dur: float, f0: float, f1: float, noise: float, decay: float) -> AudioStreamWAV:
	var n: int = int(RATE * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	var phase: float = 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var lp: float = 0.0
	for i in n:
		var t: float = float(i) / float(n)
		var f: float = lerpf(f0, f1, t)
		phase += TAU * f / float(RATE)
		lp = lerpf(lp, rng.randf_range(-1.0, 1.0), 0.35)
		var s: float = (sin(phase) * (1.0 - noise) + lp * noise) * exp(-t * decay)
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 30000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	return w
