extends RefCounted
## Which talk clip a new line takes (Player's gestures — rt3d.gesture.pool; a villager's — rt3d.talk_pool). Kept apart from
## Player and NpcLive3D: no autoloads named here, the villagers' tests (godot -s) load it too.

static func pick(pool: Array, last: String, rng: RandomNumberGenerator, have: Dictionary, bag = null) -> String:
	var opts: Array = []
	for r in pool:
		if have.has(String(r)) and not opts.has(String(r)):
			opts.append(String(r))
	if opts.is_empty():
		return last if have.has(last) else "talk"
	if opts.size() == 1:
		return String(opts[0])
	if not (bag is Array):
		var others: Array = opts.filter(func(r): return r != last)
		return String(others[rng.randi_range(0, others.size() - 1)])
	# a bag (11.11): every gesture once, in a shuffled order, before any comes again; never the same twice running —
	# with three, the random pick with only «not the last» kept to two of them for a while
	var b: Array = bag
	b.assign(b.filter(func(r): return opts.has(r)))
	if b.is_empty():
		b.assign(opts)
		for i in range(b.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var t = b[i]
			b[i] = b[j]
			b[j] = t
		if String(b[0]) == last:
			var t0 = b[0]
			b[0] = b[1]
			b[1] = t0
	return String(b.pop_front())
