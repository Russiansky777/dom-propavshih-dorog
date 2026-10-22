class_name SynthSfx
extends RefCounted
## Sounds of the day-two close-ups made by the engine (no recording ordered yet): the mill bell struck in
## Dunya's workshop, its long ring, a knuckle on glass, a hammer on the iron brace, the lantern shutter.
## PCM is computed once (additive partials with exponential decay, filtered noise) into AudioStreamWAV and
## cached; MechanicView plays them on the SFX bus, so the «Звуки» slider governs them. A real recording can
## replace any of them later without touching the panels (they ask for a sound by name).

const RATE := 22050
static var _cache: Dictionary = {}


static func stream(sound_name: String) -> AudioStreamWAV:
	if _cache.has(sound_name):
		return _cache[sound_name]
	var pcm: PackedFloat32Array
	match sound_name:
		"bell":
			pcm = _bell(2.6, 1, 0.0)
		"bell_long":
			pcm = _bell(3.2, 7, 0.24)
		"knock":
			pcm = _knock()
		"hammer":
			pcm = _hammer()
		"shutter":
			pcm = _shutter()
		_:
			pcm = PackedFloat32Array([0.0])
	var s := _to_wav(pcm)
	_cache[sound_name] = s
	return s


## Bronze bell: hum, prime, minor third, fifth, nominal and two upper partials (ratios of a church bell),
## each with its own decay. `strikes` > 1 rings it again every `every` seconds, softer — the long signal.
static func _bell(seconds: float, strikes: int, every: float) -> PackedFloat32Array:
	var n := int(seconds * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var f0 := 196.0
	var partials := [[0.5, 0.55, 1.4], [1.0, 1.0, 2.2], [1.19, 0.55, 3.0], [1.5, 0.35, 3.6], [2.0, 0.6, 4.2], [2.52, 0.25, 6.0], [3.0, 0.2, 7.5]]
	for k in strikes:
		var start := int(k * every * RATE)
		var amp := 1.0 if k == 0 else 0.55
		for i in range(start, n):
			var t := float(i - start) / RATE
			var v := 0.0
			for p in partials:
				v += float(p[1]) * exp(-float(p[2]) * t) * sin(TAU * f0 * float(p[0]) * t)
			var attack := minf(t / 0.004, 1.0)
			out[i] += v * amp * attack * 0.22
	return out


static func _knock() -> PackedFloat32Array:
	var n := int(0.18 * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		lp = lp * 0.82 + rng.randf_range(-1.0, 1.0) * 0.18
		out[i] = (lp * 1.6 + 0.6 * sin(TAU * 520.0 * t)) * exp(-38.0 * t) * 0.6
	return out


static func _hammer() -> PackedFloat32Array:
	var n := int(0.45 * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i in n:
		var t := float(i) / RATE
		var ring := 0.5 * sin(TAU * 1180.0 * t) * exp(-9.0 * t) + 0.35 * sin(TAU * 2730.0 * t) * exp(-14.0 * t)
		var hit := rng.randf_range(-1.0, 1.0) * exp(-90.0 * t)
		out[i] = (ring + hit) * 0.45
	return out


static func _shutter() -> PackedFloat32Array:
	var n := int(0.12 * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for i in n:
		var t := float(i) / RATE
		out[i] = (rng.randf_range(-1.0, 1.0) * exp(-60.0 * t) + 0.4 * sin(TAU * 900.0 * t) * exp(-50.0 * t)) * 0.35
	return out


static func _to_wav(pcm: PackedFloat32Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(pcm.size() * 2)
	for i in pcm.size():
		bytes.encode_s16(i * 2, int(clampf(pcm[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	return w
