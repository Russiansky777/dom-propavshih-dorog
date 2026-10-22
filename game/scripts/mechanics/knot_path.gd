class_name KnotPath
extends RefCounted
## «Протянуть узел» (Director 23.10, F6): the player takes the rope's end with the mouse and draws it along
## the knot, stroke by stroke — under the ring and up through it, round and over, into the loop and tight.
## Each stroke is a polyline (data, per close-up). The end follows the pointer only along the path: while
## the pointer stays within `tolerance` of the stroke the end moves on (never further than `max_lead` ahead
## of where it is — a stroke cannot be skipped by a shortcut across the ring); leaving the path, or letting
## go in the middle of a stroke, makes the end slip back to where that stroke began. No penalty, no count
## that matters — a finished stroke stays finished. Pure logic on screen coordinates; the panel draws it.
##
## Data (`knot` block of a close-up):
##   strokes     [[[x, y], …], …] — each stroke a polyline; stroke k+1 begins where stroke k ends
##   tolerance   how far from the path the pointer may wander (px, 64)
##   grab_r      how near the end the press must be to take it (px, 80)
##   max_lead    the furthest the end may jump ahead along the path in one move (px, 150)
##   labels      text keys, one per stroke (what Pelageya says to do)

var strokes: Array[PackedVector2Array] = []
var lengths: Array[float] = []
var tolerance: float = 64.0
var grab_r: float = 80.0
var max_lead: float = 150.0

var stroke: int = 0           # the stroke being drawn (== strokes.size() — the knot is tied)
var progress: float = 0.0     # arc length along the current stroke
var grabbed: bool = false
var slips: int = 0
var last: String = ""         # last result: "move", "slip", "stroke", "done", "free"


func _init(cfg: Dictionary = {}, offset: Vector2 = Vector2.ZERO, k: float = 1.0) -> void:
	tolerance = float(cfg.get("tolerance", tolerance))
	grab_r = float(cfg.get("grab_r", grab_r))
	max_lead = float(cfg.get("max_lead", max_lead))
	for s in cfg.get("strokes", []):
		var pts := PackedVector2Array()
		for q in s:
			pts.append(offset + Vector2(float(q[0]), float(q[1])) * k)
		if pts.size() >= 2:
			strokes.append(pts)
			lengths.append(_length(pts))


static func _length(pts: PackedVector2Array) -> float:
	var l := 0.0
	for i in range(1, pts.size()):
		l += pts[i - 1].distance_to(pts[i])
	return l


func done() -> bool:
	return stroke >= strokes.size()


## The point `s` px along stroke `k`.
func point_at(k: int, s: float) -> Vector2:
	var pts := strokes[k]
	var left := s
	for i in range(1, pts.size()):
		var seg := pts[i - 1].distance_to(pts[i])
		if left <= seg:
			return pts[i - 1].lerp(pts[i], left / maxf(seg, 0.001))
		left -= seg
	return pts[pts.size() - 1]


## Where the rope's end is now.
func end_point() -> Vector2:
	if strokes.is_empty():
		return Vector2.ZERO
	if done():
		var lp := strokes[strokes.size() - 1]
		return lp[lp.size() - 1]
	return point_at(stroke, progress)


## Nearest point of stroke `k` to `p` within the arc window [a, b]: {s, d}.
func _project(k: int, p: Vector2, a: float, b: float) -> Dictionary:
	var pts := strokes[k]
	var best_s := a
	var best_d := INF
	var acc := 0.0
	for i in range(1, pts.size()):
		var p0 := pts[i - 1]
		var p1 := pts[i]
		var seg := p0.distance_to(p1)
		if acc + seg >= a and acc <= b and seg > 0.0:
			var t := clampf((p - p0).dot(p1 - p0) / (seg * seg), 0.0, 1.0)
			var s := clampf(acc + t * seg, a, b)
			var q := point_at(k, s)
			var d := q.distance_to(p)
			if d < best_d:
				best_d = d
				best_s = s
		acc += seg
	return {"s": best_s, "d": best_d}


## Mouse down at `p`: takes the end if it is near.
func grab(p: Vector2) -> bool:
	if done():
		return false
	grabbed = p.distance_to(end_point()) <= grab_r
	return grabbed


## Mouse moved to `p` while held. "move" | "slip" (left the path) | "stroke" (a stroke finished) | "done".
func drag(p: Vector2) -> String:
	if not grabbed or done():
		last = "free"
		return last
	var pr := _project(stroke, p, maxf(progress - 40.0, 0.0), minf(progress + max_lead, lengths[stroke]))
	if float(pr["d"]) > tolerance:
		_slip()
		return last
	progress = maxf(progress, float(pr["s"]))
	if progress >= lengths[stroke] - 6.0:
		stroke += 1
		progress = 0.0
		last = "done" if done() else "stroke"
		if done():
			grabbed = false
		return last
	last = "move"
	return last


## Mouse up: in the middle of a stroke the end slips back to the stroke's start.
func release() -> String:
	if not grabbed:
		return "free"
	grabbed = false
	if progress > 0.0 and not done():
		_slip()
		return last
	last = "free"
	return last


func _slip() -> void:
	grabbed = false
	progress = 0.0
	slips += 1
	last = "slip"


## The rope from the start of the first stroke to the end, as drawn: every finished stroke and the part of
## the current one.
func rope_points() -> PackedVector2Array:
	var out := PackedVector2Array()
	for k in mini(stroke + 1, strokes.size()):
		var pts := strokes[k]
		if k < stroke:
			for i in pts.size():
				if out.is_empty() or out[out.size() - 1].distance_to(pts[i]) > 0.5:
					out.append(pts[i])
			continue
		var acc := 0.0
		if out.is_empty() or out[out.size() - 1].distance_to(pts[0]) > 0.5:
			out.append(pts[0])
		for i in range(1, pts.size()):
			var seg := pts[i - 1].distance_to(pts[i])
			if acc + seg <= progress:
				out.append(pts[i])
				acc += seg
			else:
				if progress > acc:
					out.append(pts[i - 1].lerp(pts[i], (progress - acc) / maxf(seg, 0.001)))
				break
	return out


## The not yet drawn part of the current stroke (the guide shown to the player).
func guide_points() -> PackedVector2Array:
	var out := PackedVector2Array()
	if done():
		return out
	var pts := strokes[stroke]
	out.append(point_at(stroke, progress))
	var acc := 0.0
	for i in range(1, pts.size()):
		acc += pts[i - 1].distance_to(pts[i])
		if acc > progress:
			out.append(pts[i])
	return out
