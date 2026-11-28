extends RefCounted
## Deterministic planar artificial ecology. No scientific/source data enters this state.
const N = 32
const MAX_POP = 192
const MAX_SEGMENTS = 80
const MAX_TRAIL = 28
const MAX_NEIGHBORS = 32
const DT = 1.0 / 30.0
const NAMES = ["Mycelial Atlas", "Vortex Colony", "Membrane Reef", "Symbiotic Garden", "Excitable Sea", "Evolutionary Terrarium"]
const FAMILIES = ["Filament", "Vortex", "Membrane", "Excitable"]
const BOUNDS = {"growth": Vector2(0.0, 2.0), "interaction": Vector2(0.0, 2.0), "diffusion": Vector2(0.0, 0.24), "resource": Vector2(0.0, 2.0), "alignment": Vector2(0.0, 2.0), "excitation": Vector2(0.0, 2.0), "mutation": Vector2(0.0, 0.3), "material": Vector2(0.0, 2.0)}
const DEFAULTS = {"growth": 1.0, "interaction": 1.0, "diffusion": 0.16, "resource": 1.0, "alignment": 0.7, "excitation": 1.0, "mutation": 0.06, "material": 1.0}
var rng = RandomNumberGenerator.new()
var organisms: Array[Dictionary] = []
var resource = PackedFloat32Array()
var signal_field = PackedFloat32Array()
var next_resource = PackedFloat32Array()
var next_signal = PackedFloat32Array()
var buckets: Dictionary = {}
var config: Dictionary = {}
var effective: Dictionary = {}
var tick: int = 0
var next_id: int = 1
var births: int = 0
var deaths: int = 0
var queries: int = 0
var events: int = 0
var step_us: int = 0
var field_us: int = 0
var growth_us: int = 0
var history: Array[Dictionary] = []
var last_error: String = ""
var last_consumed: float = 0.0
var consumed: float = 0.0

static func initial_config(preset: int, seed_value: int) -> Dictionary:
	var params: Dictionary = DEFAULTS.duplicate()
	match preset:
		0: params.growth = 1.35
		1: params.alignment = 1.25
		2: params.diffusion = 0.09
		3: params.resource = 0.6
		4: params.excitation = 1.55
		5: params.resource = 0.75
	return {"schema": "xenovection.ecology.v1", "preset": clampi(preset, 0, 5), "seed": clampi(seed_value, 0, 2147483647), "interactions": true, "reproduce": preset == 5, "lfo": false, "params": params, "plants": [], "sources": [[0.24, 0.28, 1.0], [0.75, 0.64, 0.8], [0.52, 0.48, -0.35]]}

static func numeric(value) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func valid_integer(value, low: int, high: int) -> bool:
	return numeric(value) and float(value) == floor(float(value)) and float(value) >= low and float(value) <= high

func reset(candidate: Dictionary) -> bool:
	if not validate(candidate):
		return false
	config = candidate.duplicate(true)
	effective = config.params.duplicate()
	rng.seed = int(config.seed)
	organisms.clear()
	history.clear()
	tick = 0
	next_id = 1
	births = 0
	deaths = 0
	events = 0
	queries = 0
	consumed = 0.0
	last_consumed = 0.0
	resource.resize(N * N)
	resource.fill(0.46)
	signal_field.resize(N * N)
	signal_field.fill(0.0)
	next_resource.resize(N * N)
	next_signal.resize(N * N)
	var count: int = [12, 84, 26, 42, 144, 36][int(config.preset)]
	for i in range(count):
		var p = Vector2(rng.randf_range(0.14, 0.86), rng.randf_range(0.14, 0.86))
		var family: int = 0
		match int(config.preset):
			0: family = 0
			1: family = 1
			2: family = 2
			3: family = 0 if i % 3 == 0 else 1
			4:
				family = 3
				p = Vector2(0.12 + float(i % 12) * 0.069, 0.12 + floorf(float(i) / 12.0) * 0.069)
			5: family = i % 3
		_spawn(family, p)
	for item in config.plants:
		_spawn(int(item[2]), Vector2(float(item[0]), float(item[1])))
	births = 0
	return true

func validate(c: Dictionary) -> bool:
	last_error = "Invalid ecology configuration"
	if c.get("schema") != "xenovection.ecology.v1" or not valid_integer(c.get("preset"), 0, 5) or not valid_integer(c.get("seed"), 0, 2147483647):
		return false
	if not c.get("interactions") is bool or not c.get("reproduce") is bool or not c.get("lfo", false) is bool or not c.get("params") is Dictionary:
		return false
	for key in BOUNDS:
		var value = c.params.get(key)
		if not numeric(value) or float(value) < BOUNDS[key].x or float(value) > BOUNDS[key].y:
			return false
	for name in ["plants", "sources"]:
		var entries = c.get(name)
		if not entries is Array or entries.size() > (32 if name == "plants" else 16):
			return false
		for row in entries:
			if not row is Array or row.size() != 3:
				return false
			for j in range(2):
				if not numeric(row[j]) or float(row[j]) < 0.0 or float(row[j]) > 1.0:
					return false
			if name == "plants":
				if not valid_integer(row[2], 0, 3):
					return false
			elif not numeric(row[2]) or absf(float(row[2])) > 1.0:
				return false
	last_error = ""
	return true

func apply_parameter(key: String, value) -> bool:
	if not BOUNDS.has(key) or not numeric(value):
		return false
	config.params[key] = clampf(float(value), BOUNDS[key].x, BOUNDS[key].y)
	effective[key] = config.params[key]
	return true

func register_targets(bus) -> void:
	for key in BOUNDS:
		bus.register_target("eco." + key, float(config.params[key]), BOUNDS[key].x, BOUNDS[key].y)

func apply_effective(values: Dictionary) -> void:
	for key in BOUNDS:
		var value = values.get("eco." + key, config.params[key])
		effective[key] = clampf(float(value), BOUNDS[key].x, BOUNDS[key].y) if numeric(value) else config.params[key]

func _spawn(family: int, p: Vector2, parent: Dictionary = {}) -> bool:
	if organisms.size() >= MAX_POP or not p.is_finite() or family < 0 or family > 3:
		return false
	var id = next_id
	next_id += 1
	var trait: float = rng.randf_range(0.65, 1.35) if parent.is_empty() else clampf(float(parent.trait) + rng.randf_range(-1.0, 1.0) * float(effective.mutation), 0.35, 1.65)
	var phase: float = rng.randf_range(0.0, TAU)
	if family == 3:
		phase = rng.randf_range(0.0, 0.35) + p.x * 0.4
	p = p.clamp(Vector2.ONE * 0.02, Vector2.ONE * 0.98)
	organisms.append({"id": id, "parent": int(parent.get("id", 0)), "lineage": int(parent.get("lineage", id)), "generation": int(parent.get("generation", -1)) + 1, "kind": family, "p": p, "prev_p": p, "v": Vector2.from_angle(rng.randf_range(0.0, TAU)) * 0.035, "age": 0, "energy": 0.58, "trait": trait, "phase": phase, "excited": 0.0, "refractory": 0.0, "radius": 0.008, "segments": PackedVector2Array(), "tips": PackedVector2Array([p]), "trail": PackedVector2Array([p])})
	births += 1
	return true

func plant(family: int, p: Vector2) -> bool:
	if config.plants.size() >= 32 or organisms.size() >= MAX_POP or not p.is_finite() or family < 0 or family > 3:
		return false
	p = p.clamp(Vector2.ZERO, Vector2.ONE)
	if not _spawn(family, p):
		return false
	config.plants.append([p.x, p.y, family])
	return true

func source_at(p: Vector2, amount: float) -> bool:
	if config.sources.size() >= 16 or not p.is_finite() or not is_finite(amount):
		return false
	p = p.clamp(Vector2.ZERO, Vector2.ONE)
	config.sources.append([p.x, p.y, clampf(amount, -1.0, 1.0)])
	return true

func cell(p: Vector2) -> Vector2i:
	return Vector2i(clampi(int(p.x * N), 0, N - 1), clampi(int(p.y * N), 0, N - 1))

func _index(p: Vector2i) -> int:
	return p.y * N + p.x

func sample(field: PackedFloat32Array, p: Vector2) -> float:
	return field[_index(cell(p))]

func gradient(field: PackedFloat32Array, p: Vector2) -> Vector2:
	var h = 1.0 / N
	return Vector2(sample(field, p + Vector2(h, 0)) - sample(field, p - Vector2(h, 0)), sample(field, p + Vector2(0, h)) - sample(field, p - Vector2(0, h)))

func perturb(p: Vector2, amount: float) -> void:
	if not p.is_finite() or not is_finite(amount):
		return
	for i in range(N * N):
		var q = Vector2(float(i % N) + 0.5, floorf(float(i) / N) + 0.5) / N
		var w = exp(-q.distance_squared_to(p) * 420.0)
		signal_field[i] = clampf(signal_field[i] + clampf(amount, -1.0, 1.0) * w, 0.0, 1.0)

func _evolve_fields() -> void:
	var start = Time.get_ticks_usec()
	var diff: float = float(effective.diffusion)
	for y in range(N):
		for x in range(N):
			var i = y * N + x
			var l = y * N + maxi(0, x - 1)
			var r = y * N + mini(N - 1, x + 1)
			var u = maxi(0, y - 1) * N + x
			var d = mini(N - 1, y + 1) * N + x
			var a: float = resource[i]
			var s: float = signal_field[i]
			next_resource[i] = clampf(a + diff * (resource[l] + resource[r] + resource[u] + resource[d] - 4.0 * a) + 0.003 * (0.4 - a), 0.0, 1.0)
			next_signal[i] = clampf(s + diff * (signal_field[l] + signal_field[r] + signal_field[u] + signal_field[d] - 4.0 * s) - 0.018 * s, 0.0, 1.0)
	for src in config.sources:
		var center = Vector2(float(src[0]), float(src[1]))
		for y in range(N):
			for x in range(N):
				var p = Vector2(x + 0.5, y + 0.5) / N
				if p.distance_squared_to(center) < 0.012:
					var i = y * N + x
					var amount = float(src[2]) * 0.045 * float(effective.resource)
					next_resource[i] = clampf(next_resource[i] + amount * exp(-p.distance_squared_to(center) * 160.0), 0.0, 1.0)
	var old_r = resource
	var old_s = signal_field
	resource = next_resource
	signal_field = next_signal
	next_resource = old_r
	next_signal = old_s
	field_us = Time.get_ticks_usec() - start

func _build_buckets() -> void:
	buckets.clear()
	for i in range(organisms.size()):
		var b = cell(organisms[i].p)
		if not buckets.has(b):
			buckets[b] = []
		buckets[b].append(i)

func _neighbors(o: Dictionary) -> Dictionary:
	var b = cell(o.p)
	var force = Vector2.ZERO
	var alignment = Vector2.ZERO
	var phase: float = 0.0
	var excite: float = 0.0
	var count: int = 0
	var checked: int = 0
	for dy in range(-3, 4):
		for dx in range(-3, 4):
			if checked >= MAX_NEIGHBORS:
				break
			var entries: Array = buckets.get(b + Vector2i(dx, dy), [])
			for j in entries:
				if checked >= MAX_NEIGHBORS:
					break
				checked += 1
				var other: Dictionary = organisms[j]
				if other.id == o.id:
					continue
				var displacement: Vector2 = other.p - o.p
				var distance: float = displacement.length()
				if distance > 0.085 or distance < 0.00001:
					continue
				var direction: Vector2 = displacement / distance
				var w = 1.0 - distance / 0.085
				force += direction * (-1.7 * w if distance < 0.022 else 0.28 * w)
				alignment += other.v
				phase += sin(float(other.phase) - float(o.phase))
				excite += float(other.excited) * w
				count += 1
	queries += checked
	events += count
	var denom = float(maxi(count, 1))
	return {"force": force / denom, "alignment": alignment / denom, "phase": phase / denom, "excite": excite, "count": count}

func _grow(o: Dictionary) -> void:
	if o.kind == 0:
		var tips: PackedVector2Array = o.tips
		var segments: PackedVector2Array = o.segments
		if o.energy > 0.13 and effective.growth > 0.0 and segments.size() < MAX_SEGMENTS * 2:
			var choice = rng.randi_range(0, tips.size() - 1)
			var tip: Vector2 = tips[choice]
			var direction = Vector2.from_angle(rng.randf_range(0.0, TAU)) * 0.32 + gradient(resource, tip) * 3.4
			if config.interactions:
				direction += gradient(signal_field, tip) * 1.2 * float(effective.interaction)
			var next: Vector2 = (tip + direction.normalized() * 0.015 * float(o.trait) * float(effective.growth)).clamp(Vector2.ONE * 0.01, Vector2.ONE * 0.99)
			if next.distance_squared_to(tip) > 0.0000001:
				segments.append(tip)
				segments.append(next)
				if tips.size() < 12 and rng.randf() < 0.28:
					tips.append(next)
				else:
					tips[choice] = next
				o.energy = maxf(0.0, float(o.energy) - 0.022)
		elif o.energy < 0.09 and segments.size() > 2:
			segments.resize(segments.size() - 2)
			tips = PackedVector2Array([segments[segments.size() - 1]])
		o.tips = tips
		o.segments = segments
	elif o.kind == 2:
		o.radius = clampf(float(o.radius) + (float(o.energy) - 0.19) * 0.003 * float(effective.growth) * float(o.trait), 0.005, 0.11)

func step() -> void:
	var start = Time.get_ticks_usec()
	tick += 1
	if tick % 3 == 0:
		_evolve_fields()
	queries = 0
	events = 0
	last_consumed = 0.0
	var interacting: bool = config.interactions and float(effective.interaction) > 0.0
	_build_buckets()
	var observations: Array[Dictionary] = []
	for o in organisms:
		observations.append(_neighbors(o) if interacting else {"force": Vector2.ZERO, "alignment": Vector2.ZERO, "phase": 0.0, "excite": 0.0, "count": 0})
	var offspring: Array[Dictionary] = []
	var survivors: Array[Dictionary] = []
	growth_us = 0
	for i in range(organisms.size()):
		var o: Dictionary = organisms[i]
		var sensed: Dictionary = observations[i]
		var idx = _index(cell(o.p))
		var available: float = resource[idx]
		var uptake = minf(available, 0.010 * float(effective.resource) * float(o.trait))
		if interacting:
			resource[idx] = maxf(0.0, available - uptake)
			last_consumed += uptake
		o.energy = clampf(float(o.energy) + uptake - 0.0048, 0.0, 1.0)
		o.age += 1
		o.prev_p = o.p
		var strength: float = float(effective.interaction) if interacting else 0.0
		if o.kind == 1:
			var q: Vector2 = o.p - Vector2(0.5, 0.5)
			var flow = Vector2(-q.y, q.x) * 0.18 + gradient(resource, o.p) * 0.4
			flow += gradient(signal_field, o.p).orthogonal() * strength * 0.8
			flow += sensed.force * strength * 0.13 + (sensed.alignment - o.v) * float(effective.alignment) * strength
			var velocity: Vector2 = (o.v + flow * DT).limit_length(0.15) * 0.997
			var next: Vector2 = o.p + velocity * DT
			if next.x < 0.015 or next.x > 0.985:
				velocity.x = -velocity.x
			if next.y < 0.015 or next.y > 0.985:
				velocity.y = -velocity.y
			o.v = velocity
			o.p = next.clamp(Vector2.ONE * 0.015, Vector2.ONE * 0.985)
			if tick % 3 == 0:
				var trail: PackedVector2Array = o.trail
				trail.append(o.p)
				if trail.size() > MAX_TRAIL:
					trail.remove_at(0)
				o.trail = trail
		elif o.kind == 2 and interacting:
			o.p = (o.p + sensed.force * strength * 0.0015).clamp(Vector2.ONE * 0.02, Vector2.ONE * 0.98)
		if o.kind == 3:
			o.refractory = maxf(0.0, float(o.refractory) - DT)
			o.excited = maxf(0.0, float(o.excited) - DT * 2.4)
			var stimulus = (float(sensed.excite) * 1.15 + float(signal_field[idx]) * 0.8) * float(effective.excitation) * strength
			if o.refractory <= 0.0 and (stimulus > 0.24 or (tick % 120 == 1 and o.id % 41 == 1)):
				o.excited = 1.0
				o.refractory = 1.35
			o.phase = fposmod(float(o.phase) + DT * (0.5 + float(sensed.phase) * strength), TAU)
		else:
			o.phase = fposmod(float(o.phase) + DT * (0.8 * float(o.trait) + float(sensed.phase) * strength), TAU)
		if interacting:
			var deposit: float = 0.012 * strength * float(o.energy)
			if o.kind == 3:
				deposit *= float(o.excited) * 4.0
			signal_field[idx] = minf(1.0, float(signal_field[idx]) + deposit)
			if int(config.preset) == 3 and o.kind == 1 and sensed.count > 0:
				# Resource production is an open-system source, not conservation.
				resource[idx] = minf(1.0, float(resource[idx]) + 0.014 * strength)
		if tick % 6 == 0:
			var growth_start = Time.get_ticks_usec()
			_grow(o)
			growth_us += Time.get_ticks_usec() - growth_start
		if config.reproduce and o.age >= 120 and o.energy > 0.70 and tick % 60 == 0 and rng.randf() < 0.28:
			if organisms.size() + offspring.size() < MAX_POP:
				o.energy *= 0.54
				offspring.append(o.duplicate(true))
		if config.reproduce and (o.age > 2400 or (o.energy < 0.015 and o.age > 300)):
			deaths += 1
		else:
			survivors.append(o)
	organisms = survivors
	for parent in offspring:
		var p: Vector2 = parent.p + Vector2.from_angle(rng.randf_range(0.0, TAU)) * 0.035
		_spawn(int(parent.kind), p, parent)
	consumed += last_consumed
	step_us = Time.get_ticks_usec() - start
	if tick % 30 == 0:
		history.append(metrics())
		if history.size() > 240:
			history.pop_front()

func metrics() -> Dictionary:
	var segments: int = 0
	var energy: float = 0.0
	var total_resource: float = 0.0
	var total_signal: float = 0.0
	var phase_sum = Vector2.ZERO
	var excited: int = 0
	var families: Dictionary = {}
	var lineages: Dictionary = {}
	for o in organisms:
		segments += int(o.segments.size() / 2)
		energy += float(o.energy)
		phase_sum += Vector2.from_angle(float(o.phase))
		lineages[o.lineage] = true
		families[o.kind] = int(families.get(o.kind, 0)) + 1
		if o.excited > 0.2: excited += 1
	for i in range(resource.size()):
		total_resource += resource[i]
		total_signal += signal_field[i]
	return {"tick": tick, "population": organisms.size(), "lineages": lineages.size(), "family_counts": families, "excited_count": excited, "births": births, "deaths": deaths, "segments": segments, "energy_mean": energy / maxi(1, organisms.size()), "resource_mean": total_resource / maxi(1, resource.size()), "signal_mean": total_signal / maxi(1, signal_field.size()), "synchrony": phase_sum.length() / maxi(1, organisms.size()), "consumed": consumed, "queries": queries, "events": events, "step_us": step_us, "field_us": field_us, "growth_us": growth_us}

func digest() -> String:
	# Timing counters excluded. Same-engine deterministic replay, not cross-platform bit equality.
	var state: Array = [tick, next_id, rng.state, births, deaths, resource, signal_field]
	for o in organisms:
		state.append(o)
	return var_to_bytes(state).hex_encode().sha256_text()


func spatial_digest() -> String:
	var state: Array = []
	for o in organisms:
		state.append([o.id, o.p, o.radius, o.segments, o.trail, o.excited])
	return var_to_bytes(state).hex_encode().sha256_text()
