class_name LightMask
extends RefCounted
## Soft-edged polygon masks for lights and shafts (data/story/lights/<LOC>.json).
##
## A mask is a small RGBA texture (white, alpha = coverage) of the polygons' bounding box grown by
## the feather: coverage is sampled at texel centres (2×2 sub-samples), then box-blurred three times
## (≈ gaussian) so the edge fades over about `feather` screen px. The GPU stretches the texture with
## bilinear filtering — a 900×800 px area is ~60×55 texels, so building it costs a few ms, once:
## results are cached per data key for the session (rooms are rebuilt on every visit).
##
## Optional `gradient` {from:[x,y], to:[x,y], alpha_from, alpha_to}: alpha is also multiplied along
## that screen-space axis (a window shaft is bright at the glass and fades towards the floor).

static var _cache: Dictionary = {}


## Returns {"texture": ImageTexture, "rect": Rect2 (screen px), "texel": float (px per texel)}.
static func build(polys: Array, feather: float, gradient: Dictionary = {}) -> Dictionary:
	var key := JSON.stringify([polys, feather, gradient])
	if _cache.has(key):
		return _cache[key]
	var pvs: Array[PackedVector2Array] = []
	var bounds := Rect2()
	var first := true
	for poly in polys:
		var pv := PackedVector2Array()
		for p in poly:
			var v := Vector2(float(p[0]), float(p[1]))
			pv.append(v)
			if first:
				bounds = Rect2(v, Vector2.ZERO)
				first = false
			else:
				bounds = bounds.expand(v)
		if pv.size() >= 3:
			pvs.append(pv)
	feather = maxf(feather, 4.0)
	bounds = bounds.grow(feather * 1.2 + 2.0)
	var texel := feather / 4.0
	var w := maxi(int(ceil(bounds.size.x / texel)), 2)
	var h := maxi(int(ceil(bounds.size.y / texel)), 2)
	var a := PackedFloat32Array()
	a.resize(w * h)
	var sub := [Vector2(0.25, 0.25), Vector2(0.75, 0.25), Vector2(0.25, 0.75), Vector2(0.75, 0.75)]
	for y in h:
		for x in w:
			var cov := 0.0
			for s in sub:
				var p: Vector2 = bounds.position + (Vector2(x, y) + s) * texel
				for pv in pvs:
					if Geometry2D.is_point_in_polygon(p, pv):
						cov += 0.25
						break
			a[y * w + x] = cov
	for _pass in 3:
		a = _box_blur(a, w, h)
	var has_grad := not gradient.is_empty()
	var g_from := Vector2.ZERO
	var g_axis := Vector2.RIGHT
	var g_len2 := 1.0
	var af := 1.0
	var at := 1.0
	if has_grad:
		var f: Array = gradient.get("from", [0, 0])
		var t: Array = gradient.get("to", [0, 1])
		g_from = Vector2(float(f[0]), float(f[1]))
		g_axis = Vector2(float(t[0]), float(t[1])) - g_from
		g_len2 = maxf(g_axis.length_squared(), 1.0)
		af = float(gradient.get("alpha_from", 1.0))
		at = float(gradient.get("alpha_to", 0.0))
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var v := a[y * w + x]
			if has_grad:
				var p: Vector2 = bounds.position + (Vector2(x, y) + Vector2(0.5, 0.5)) * texel
				var k := clampf((p - g_from).dot(g_axis) / g_len2, 0.0, 1.0)
				v *= lerpf(af, at, smoothstep(0.0, 1.0, k))
			v = clampf(v, 0.0, 1.0)
			a[y * w + x] = v
			img.set_pixel(x, y, Color(1, 1, 1, v))
	var out := {"texture": ImageTexture.create_from_image(img), "rect": bounds, "texel": texel, "alpha": a, "w": w, "h": h}
	_cache[key] = out
	return out


## Coverage of a built mask at screen point `p` (bilinear between texel centres, 0 outside) — what
## the GPU shows there; actors are toned by the mask value under their feet.
static func sample(m: Dictionary, p: Vector2) -> float:
	var r: Rect2 = m["rect"]
	var texel: float = m["texel"]
	var w: int = m["w"]
	var h: int = m["h"]
	var a: PackedFloat32Array = m["alpha"]
	var q := (p - r.position) / texel - Vector2(0.5, 0.5)
	var x0 := int(floor(q.x))
	var y0 := int(floor(q.y))
	var fx := q.x - x0
	var fy := q.y - y0
	var acc := 0.0
	for j in 2:
		for i in 2:
			var x := x0 + i
			var y := y0 + j
			if x < 0 or y < 0 or x >= w or y >= h:
				continue
			acc += a[y * w + x] * (fx if i == 1 else 1.0 - fx) * (fy if j == 1 else 1.0 - fy)
	return acc


## One separable box blur of radius 1 (edges clamp).
static func _box_blur(src: PackedFloat32Array, w: int, h: int) -> PackedFloat32Array:
	var tmp := PackedFloat32Array()
	tmp.resize(w * h)
	for y in h:
		for x in w:
			var l := src[y * w + maxi(x - 1, 0)]
			var r := src[y * w + mini(x + 1, w - 1)]
			tmp[y * w + x] = (l + src[y * w + x] + r) / 3.0
	var out := PackedFloat32Array()
	out.resize(w * h)
	for y in h:
		for x in w:
			var u := tmp[maxi(y - 1, 0) * w + x]
			var d := tmp[mini(y + 1, h - 1) * w + x]
			out[y * w + x] = (u + tmp[y * w + x] + d) / 3.0
	return out


## Radial falloff texture for point lights: white, alpha 1 at the centre → 0 at the rim.
## `softness` > 1 makes the core smaller (more light near the source, longer tail).
static func radial(size: int = 256, softness: float = 1.6) -> GradientTexture2D:
	var key := "radial:%d:%.3f" % [size, softness]
	if _cache.has(key):
		return _cache[key]
	var grad := Gradient.new()
	var offs := PackedFloat32Array()
	var cols := PackedColorArray()
	for i in 9:
		var t := float(i) / 8.0
		offs.append(t)
		cols.append(Color(1, 1, 1, pow(1.0 - t, softness) * (1.0 - t * t * 0.15)))
	grad.offsets = offs
	grad.colors = cols
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.width = size
	tex.height = size
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	_cache[key] = tex
	return tex
