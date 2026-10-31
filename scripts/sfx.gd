extends Node
## Procedural sound effects (autoload "Sfx"). Every sound is synthesised at
## startup into an AudioStreamWAV, so the game ships with no audio assets.

const RATE := 22050
const POOL_SIZE := 10

var _streams: Dictionary = {}
var _pool: Array[AudioStreamPlayer] = []
var _next := 0
var _engine: AudioStreamPlayer
var _laser: AudioStreamPlayer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_streams = {
		"ui": _tone(0.06, 880.0, 880.0, 0.0, 0.35),
		"pickup": _tone(0.12, 660.0, 1320.0, 0.0, 0.35),
		"mine": _tone(0.1, 180.0, 90.0, 0.6, 0.5),
		"place": _tone(0.08, 300.0, 240.0, 0.3, 0.45),
		"jump": _tone(0.12, 220.0, 440.0, 0.1, 0.25),
		"hit": _tone(0.25, 120.0, 50.0, 0.8, 0.6),
		"explode": _tone(0.6, 90.0, 30.0, 0.9, 0.7),
		"zap": _tone(0.18, 1200.0, 300.0, 0.1, 0.3),
		"alert": _tone(0.3, 520.0, 520.0, 0.0, 0.3, 8.0),
		"land": _tone(0.3, 140.0, 70.0, 0.5, 0.5),
		"scan": _tone(0.5, 400.0, 1600.0, 0.0, 0.3),
		"beacon": _chord(1.4, [261.6, 329.6, 392.0, 523.3]),
		"warp": _tone(1.6, 60.0, 900.0, 0.4, 0.55),
		"sell": _chord(0.4, [523.3, 659.3, 784.0]),
	}
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pool.append(p)
	_engine = AudioStreamPlayer.new()
	_engine.stream = _loop_noise(1.0, 0.18)
	_engine.volume_db = -80.0
	_engine.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(_engine)
	_laser = AudioStreamPlayer.new()
	_laser.stream = _loop_tone(0.5, 330.0, 0.2)
	_laser.volume_db = -14.0
	_laser.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(_laser)


func play(sound: String) -> void:
	if not _streams.has(sound):
		return
	var p := _pool[_next]
	_next = (_next + 1) % POOL_SIZE
	p.stream = _streams[sound]
	p.pitch_scale = randf_range(0.95, 1.05)
	p.play()


func set_engine(power: float) -> void:
	if power <= 0.01:
		if _engine.playing:
			_engine.stop()
		return
	if not _engine.playing:
		_engine.play()
	_engine.volume_db = linear_to_db(clampf(0.15 + power * 0.35, 0.0, 1.0)) - 6.0
	_engine.pitch_scale = 0.7 + power * 0.35


func loop_laser(on: bool) -> void:
	if on and not _laser.playing:
		_laser.play()
	elif not on and _laser.playing:
		_laser.stop()


func _wav(samples: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.data = bytes
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_end = samples.size()
	return wav


## Square-ish sweep from f0 to f1 mixed with `noise_mix` white noise,
## decaying envelope; `tremolo` > 0 pulses the volume.
func _tone(length: float, f0: float, f1: float, noise_mix: float, volume: float, tremolo := 0.0) -> AudioStreamWAV:
	var n := int(length * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / n
		phase += lerpf(f0, f1, t) / RATE
		var wave := 0.6 * sin(phase * TAU) + 0.4 * signf(sin(phase * TAU))
		var s := lerpf(wave, randf_range(-1.0, 1.0), noise_mix)
		var env := minf(1.0, t * 40.0) * pow(1.0 - t, 2.0)
		if tremolo > 0.0:
			env *= 0.5 + 0.5 * signf(sin(t * length * tremolo * TAU))
		out[i] = s * env * volume
	return _wav(out, false)


func _chord(length: float, freqs: Array) -> AudioStreamWAV:
	var n := int(length * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / n
		var s := 0.0
		for k in freqs.size():
			var start := float(k) * 0.08
			if t * length >= start:
				s += sin(TAU * freqs[k] * (float(i) / RATE - start))
		out[i] = s / freqs.size() * minf(1.0, t * 30.0) * pow(1.0 - t, 1.5) * 0.5
	return _wav(out, false)


func _loop_noise(length: float, volume: float) -> AudioStreamWAV:
	var n := int(length * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var low := 0.0
	for i in n:
		low = lerpf(low, randf_range(-1.0, 1.0), 0.08)
		out[i] = low * volume * 3.0
	return _wav(out, true)


func _loop_tone(length: float, freq: float, volume: float) -> AudioStreamWAV:
	var n := int(length * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var wobble := 1.0 + 0.04 * sin(TAU * 12.0 * t)
		out[i] = (0.5 * sin(TAU * freq * t * wobble) + 0.3 * sin(TAU * freq * 2.0 * t)) * volume
	return _wav(out, true)
