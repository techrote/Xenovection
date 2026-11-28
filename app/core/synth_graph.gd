extends RefCounted
## SYNTH-002: bounded fixed-step source graph, feeding the accepted typed bus.
## No renderer ownership, data writes, or geometry allocation.
const SCHEMA := "xenovection.patch.v1"
const TARGET_SCHEMA := "xenovection.target.v1"
const PREFIX := "synth/"
const MAX_NODES := 48
const MAX_ROUTES := 96
const MAX_BYTES := 262144
const STEP := 1.0 / 120.0
const KINDS := ["manual", "sine", "triangle", "saw", "pulse", "noise", "walk", "hold", "envelope", "sequencer", "add", "multiply", "mix", "remap", "quantize", "slew", "delay", "vector2", "vector3", "colour"]
const CLOCKS := ["filament", "sky", "normal", "displacement", "palette", "beat"]
const INPUTS := {"hold": ["a"], "add": ["a", "b"], "multiply": ["a", "b"], "mix": ["a", "b"], "remap": ["a"], "quantize": ["a"], "slew": ["a"], "delay": ["a"], "vector2": ["a", "b"], "vector3": ["a", "b", "c"], "colour": ["a", "b", "c"]}
var patch: Dictionary = {}
var values: Dictionary = {}
var order: Array = []
var nodes: Dictionary = {}
var times: Dictionary = {}
var state: Dictionary = {}
var accumulator := 0.0
var ticks := 0
var dropped_seconds := 0.0
var last_error := ""
var solo_id := ""
var samples := PackedFloat64Array()
var sample_cursor := 0
var fade_from: Dictionary = {}
var fade_elapsed := 0.0
var missing_targets: Array = []
var route_by_id: Dictionary = {}


static func blank(preset: int = 0, preset_id: String = "") -> Dictionary:
	var data := {"schema": SCHEMA, "preset": preset, "bpm": 100.0, "clocks": {}, "xy": ["", ""], "sources": [], "routes": []}
	if not preset_id.is_empty():
		data.preset_id = preset_id
	return data


static func source_defaults(id: String, kind: String = "sine") -> Dictionary:
	return {"id": id, "kind": kind, "clock": "filament", "rate": 0.2, "phase": 0.0, "value": 0.0, "param": 0.25, "seed": 1, "a": "", "b": "", "c": "", "steps": [0.0, 0.5, 1.0, -0.5, 0.25, -1.0, 0.75, 0.0]}


static func target_catalogue(bus, include_unavailable: bool = false) -> Dictionary:
	# A renderer may register further stable, continuously writable typed targets.
	var result: Dictionary = {}
	for id in bus.targets:
		var spec: Dictionary = bus.targets[id]
		if spec.get("policy", "continuous") != "continuous":
			continue
		var available := bool(spec.get("available", true))
		if not available and not include_unavailable:
			continue
		result[id] = {"schema": TARGET_SCHEMA, "id": id, "kind": spec.kind, "minimum": spec.minimum, "maximum": spec.maximum, "base": spec.base, "policy": "continuous", "available": available,
			"category": str(spec.get("category", str(id).get_slice(".", 0))), "field_descriptor": spec.get("field_descriptor", {})}
	return result


static func output_kind(kind: String) -> String:
	return kind if kind in ["vector2", "vector3", "colour"] else "scalar"


static func number(value, low: float, high: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= low and float(value) <= high


static func identifier(value) -> bool:
	if not value is String or value.length() == 0 or value.length() > 64:
		return false
	for ch in value:
		if not ch in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-":
			return false
	return true


func refuse(message: String) -> bool:
	last_error = message
	return false


func configure(data, bus) -> bool:
	last_error = ""
	if not data is Dictionary or data.get("schema") != SCHEMA:
		return refuse("Unknown patch schema")
	if not number(data.get("preset"), 0, 63) or float(data.preset) != floorf(float(data.preset)):
		return refuse("Invalid scene index")
	if not number(data.get("bpm"), 20, 300):
		return refuse("Tempo outside 20..300 BPM")
	if not data.get("sources") is Array or not data.get("routes") is Array or not data.get("clocks", {}) is Dictionary:
		return refuse("Expected source, route and clock collections")
	if data.sources.size() > MAX_NODES or data.routes.size() > MAX_ROUTES:
		return refuse("Patch exceeds graph bounds")
	var clean := blank(int(data.preset))
	if data.has("preset_id"):
		if not data.preset_id is String or data.preset_id.is_empty() or data.preset_id.length() > 96:
			return refuse("Invalid persistent composition identity")
		for ch in data.preset_id:
			if not ch in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.-":
				return refuse("Invalid persistent composition identity")
		clean.preset_id = data.preset_id
	clean.bpm = float(data.bpm)
	for clock in data.get("clocks", {}):
		var cfg = data.clocks[clock]
		if not clock in CLOCKS or clock == "beat" or not cfg is Dictionary:
			return refuse("Unknown clock setting")
		if not number(cfg.get("rate"), -8, 8) or not cfg.get("paused") is bool:
			return refuse("Invalid clock setting")
		clean.clocks[clock] = {"rate": float(cfg.rate), "paused": cfg.paused}
	var by_id: Dictionary = {}
	for raw in data.sources:
		if not raw is Dictionary or not identifier(raw.get("id")) or by_id.has(raw.id):
			return refuse("Missing or duplicate component ID")
		if not raw.get("kind") is String or not raw.kind in KINDS:
			return refuse("Unknown component kind")
		var n := source_defaults(raw.id, raw.kind)
		for key in ["clock", "rate", "phase", "value", "param", "seed", "a", "b", "c", "steps"]:
			if raw.has(key):
				n[key] = raw[key]
		if not n.clock is String or not n.clock in CLOCKS:
			return refuse("Unknown source clock")
		if not number(n.rate, -100, 100) or not number(n.phase, -1000, 1000) or not number(n.value, -16, 16) or not number(n.param, -16, 16) or not number(n.seed, 0, 2147483647):
			return refuse("Invalid numeric component parameter")
		for port in ["a", "b", "c"]:
			if not n[port] is String or (not n[port].is_empty() and not identifier(n[port])):
				return refuse("Invalid component input ID")
		if not n.steps is Array or n.steps.is_empty() or n.steps.size() > 32:
			return refuse("Sequencer requires 1..32 steps")
		for step in n.steps:
			if not number(step, -16, 16):
				return refuse("Invalid sequencer step")
		var normalized_steps: Array = []
		for step in n.steps:
			normalized_steps.append(float(step))
		n.steps = normalized_steps
		for key in ["rate", "phase", "value", "param"]:
			n[key] = float(n[key])
		if float(n.seed) != floorf(float(n.seed)):
			return refuse("Seed must be an integer")
		n.seed = int(n.seed)
		by_id[n.id] = n
		clean.sources.append(n)
	var sorted: Array = []
	var remaining: Array = by_id.keys()
	for n in clean.sources:
		for port in INPUTS.get(n.kind, []):
			if not by_id.has(n[port]) or output_kind(by_id[n[port]].kind) != "scalar":
				return refuse("Missing or incompatible input: " + n.id + "." + port)
	# Delay reads its prior tick, not its input during this tick.
	while not remaining.is_empty():
		var progressed := false
		for id in remaining.duplicate():
			var n: Dictionary = by_id[id]
			var ready := true
			if n.kind != "delay":
				for port in INPUTS.get(n.kind, []):
					if not n[port] in sorted:
						ready = false
			if ready:
				sorted.append(id)
				remaining.erase(id)
				progressed = true
		if not progressed:
			return refuse("Instantaneous cycle; insert a delay")
	var xy = data.get("xy", ["", ""])
	if not xy is Array or xy.size() != 2:
		return refuse("XY assignment must have two axes")
	for id in xy:
		if not id is String or (not id.is_empty() and (not by_id.has(id) or by_id[id].kind != "manual")):
			return refuse("XY axes must reference manual components")
	if not xy[0].is_empty() and xy[0] == xy[1]:
		return refuse("XY axes must use distinct components")
	clean.xy = xy.duplicate()
	var route_ids: Dictionary = {}
	for raw in data.routes:
		if not raw is Dictionary or not identifier(raw.get("id")) or route_ids.has(raw.id):
			return refuse("Missing or duplicate route ID")
		if not raw.get("source") is String or not by_id.has(raw.source) or not raw.get("target") is String or not bus.targets.has(raw.target):
			return refuse("Unknown route source or unavailable destination")
		if bus.targets[raw.target].get("policy", "continuous") != "continuous":
			return refuse("Destination is base-only or discrete")
		var kind := output_kind(by_id[raw.source].kind)
		if kind != "scalar" and kind != bus.targets[raw.target].kind:
			return refuse("Incompatible route signal and target")
		var op = raw.get("operation", "add")
		var amp = raw.get("amplitude", 0.1)
		var offset = raw.get("offset", 0.0)
		var mask = raw.get("mask", 1.0)
		var active = raw.get("enabled", true)
		if not op in ["add", "multiply"] or not number(amp, -1000, 1000) or not number(offset, -1000, 1000) or not number(mask, 0, 1) or not active is bool:
			return refuse("Invalid route operation, depth, offset or mask")
		route_ids[raw.id] = true
		clean.routes.append({"id": raw.id, "source": raw.source, "target": raw.target, "operation": op, "amplitude": float(amp), "offset": float(offset), "mask": float(mask), "enabled": active})
	patch = clean
	nodes = by_id
	order = sorted
	route_by_id.clear()
	for route in clean.routes:
		route_by_id[route.id] = route
	solo_id = ""
	reset()
	return true


func reset() -> void:
	values.clear()
	state.clear()
	times.clear()
	for clock in CLOCKS:
		times[clock] = 0.0
	ticks = 0
	accumulator = 0.0
	dropped_seconds = 0.0
	fade_from.clear()
	fade_elapsed = 0.0
	samples.clear()
	sample_cursor = 0
	missing_targets.clear()
	_evaluate({}, 0.0)


func snapshot(bus) -> Dictionary:
	var data := patch.duplicate(true)
	if data.is_empty():
		return blank()
	data.clocks = {}
	for clock in bus.clocks:
		data.clocks[clock] = {"rate": bus.clocks[clock].rate, "paused": bus.clocks[clock].paused}
	return data


func detach(bus) -> void:
	for i in range(bus.routes.size() - 1, -1, -1):
		if str(bus.routes[i].id).begins_with(PREFIX):
			bus.routes.remove_at(i)
	for id in bus.sources.keys():
		if str(id).begins_with(PREFIX):
			bus.sources.erase(id)


func attach(bus) -> bool:
	detach(bus)
	for id in order:
		if not bus.register_source(PREFIX + id, {"type": "manual", "value": values[id]}):
			detach(bus)
			return refuse(bus.last_error)
	for route in patch.get("routes", []):
		var bound: Dictionary = route.duplicate()
		bound.id = PREFIX + route.id
		bound.source = PREFIX + route.source
		if not bus.add_route(bound):
			detach(bus)
			return refuse(bus.last_error)
	# Active patches own the artistic route mix; stopped patches restore stock LFOs.
	for existing in bus.routes:
		if not str(existing.id).begins_with(PREFIX):
			existing.enabled = false
	return true


func set_manual(id: String, value: float) -> bool:
	if not nodes.has(id) or nodes[id].kind != "manual" or not number(value, -16, 16):
		return false
	nodes[id].value = value
	return true


func trigger(id: String) -> bool:
	if not nodes.has(id) or nodes[id].kind != "envelope":
		return false
	state[id] = {"age": 0.0}
	return true


func transition_from(previous) -> bool:
	# Discrete scene or wiring changes cut; identical routes/types interpolate.
	if previous.patch.is_empty() or patch.preset != previous.patch.preset or patch.routes != previous.patch.routes:
		return false
	if patch.get("preset_id", "") != previous.patch.get("preset_id", ""):
		return false
	for id in nodes:
		if not previous.nodes.has(id) or output_kind(nodes[id].kind) != output_kind(previous.nodes[id].kind):
			return false
	fade_from = previous.values.duplicate()
	fade_elapsed = 0.0
	return true


func _clock_delta(clock: String, clocks: Dictionary, dt: float) -> float:
	var setting: Dictionary = clocks.get("filament" if clock == "beat" else clock, {"rate": 1.0, "paused": false})
	if setting.paused:
		return 0.0
	return dt * float(setting.rate) * (float(patch.get("bpm", 100)) / 60.0 if clock == "beat" else 1.0)


func advance(bus, delta: float, scientific: bool = false) -> void:
	if patch.is_empty():
		return
	var start := Time.get_ticks_usec()
	var elapsed := clampf(delta, 0.0, 0.25) if is_finite(delta) else 0.0
	if not bus.paused and not scientific:
		if delta > elapsed and is_finite(delta):
			dropped_seconds += delta - elapsed
		accumulator += elapsed
		var count := 0
		while accumulator + 1.0e-9 >= STEP and count < 30:
			for clock in CLOCKS:
				times[clock] = clampf(float(times[clock]) + _clock_delta(clock, bus.clocks, STEP), -1.0e6, 1.0e6)
			_evaluate(bus.clocks, STEP)
			accumulator = maxf(0.0, accumulator - STEP)
			ticks += 1
			count += 1
		if count == 0:
			_evaluate(bus.clocks, 0.0)
		fade_elapsed += elapsed
	else:
		_evaluate(bus.clocks, 0.0)
	for id in order:
		var name := PREFIX + str(id)
		if bus.sources.has(name):
			var signal_value = values[id]
			if fade_from.has(id) and fade_elapsed < 0.8:
				var prior = fade_from[id]
				var ratio := clampf(fade_elapsed / 0.8, 0.0, 1.0)
				signal_value = lerpf(float(prior), float(signal_value), ratio) if output_kind(nodes[id].kind) == "scalar" else prior.lerp(signal_value, ratio)
			bus.sources[name].value = signal_value
	if fade_elapsed >= 0.8:
		fade_from.clear()
	# Missing dynamic targets are removed before the accepted bus evaluates.
	for i in range(bus.routes.size() - 1, -1, -1):
		var route: Dictionary = bus.routes[i]
		if not str(route.id).begins_with(PREFIX):
			continue
		if not bus.targets.has(route.target) or bus.targets[route.target].get("policy", "continuous") != "continuous":
			if not route.target in missing_targets:
				missing_targets.append(route.target)
			bus.routes.remove_at(i)
			continue
		var rid: String = route.id.trim_prefix(PREFIX)
		var authored: Dictionary = route_by_id.get(rid, {})
		route.enabled = bool(authored.get("enabled", false)) and not scientific and (solo_id.is_empty() or solo_id == rid)
	var cost := float(Time.get_ticks_usec() - start)
	if samples.size() < 1024:
		samples.append(cost)
	else:
		samples[sample_cursor] = cost
		sample_cursor = (sample_cursor + 1) % 1024


static func _noise(seed: int, index: int) -> float:
	# Integer mixing, independent of global RNG and render frame count.
	var x: int = (seed ^ (index * 374761393)) & 0x7fffffff
	x = ((x ^ (x >> 13)) * 1274126177) & 0x7fffffff
	x = (x ^ (x >> 16)) & 0x7fffffff
	return float(x) / 1073741823.5 - 1.0


func _evaluate(clocks: Dictionary, dt: float) -> void:
	for id in order:
		var n: Dictionary = nodes[id]
		var cycle: float = float(times.get(n.clock, 0.0)) * float(n.rate) + float(n.phase)
		var ph := fposmod(cycle, 1.0)
		var idx := floori(cycle)
		var a := float(values.get(n.a, 0.0)) if not n.a.is_empty() and output_kind(nodes.get(n.a, {}).get("kind", "")) == "scalar" else 0.0
		var b := float(values.get(n.b, 0.0)) if not n.b.is_empty() and output_kind(nodes.get(n.b, {}).get("kind", "")) == "scalar" else 0.0
		var c := float(values.get(n.c, 0.0)) if not n.c.is_empty() and output_kind(nodes.get(n.c, {}).get("kind", "")) == "scalar" else 0.0
		var p := float(n.param)
		var v = 0.0
		var local_dt := absf(_clock_delta(n.clock, clocks, dt))
		match n.kind:
			"manual": v = float(n.value)
			"sine": v = sin(ph * TAU)
			"triangle": v = 1.0 - 4.0 * absf(ph - 0.5)
			"saw": v = 2.0 * ph - 1.0
			"pulse": v = 1.0 if ph < clampf(p, 0.01, 0.99) else -1.0
			"noise": v = _noise(n.seed, idx)
			"walk":
				var memory: Dictionary = state.get(id, {"index": idx, "value": 0.0})
				if local_dt > 0 and memory.index != idx:
					memory.value = clampf(float(memory.value) + _noise(n.seed, idx) * absf(p), -1.0, 1.0)
					memory.index = idx
				state[id] = memory
				v = memory.value
			"hold":
				var memory: Dictionary = state.get(id, {"index": idx, "value": a})
				if local_dt > 0 and memory.index != idx:
					memory = {"index": idx, "value": a}
				state[id] = memory
				v = memory.value
			"envelope":
				var age: float = state.get(id, {}).get("age", -1.0)
				if age >= 0.0:
					var duration := maxf(absf(float(n.rate)), 0.01)
					var progress := age / duration
					var attack := clampf(p, 0.01, 0.99)
					v = clampf(progress / attack if progress < attack else (1.0 - progress) / (1.0 - attack), 0.0, 1.0)
					state[id] = {"age": age + local_dt if progress < 1.0 else -1.0}
			"sequencer": v = float(n.steps[posmod(idx, n.steps.size())])
			"add": v = a + b
			"multiply": v = a * b
			"mix": v = lerpf(a, b, clampf(p, 0.0, 1.0))
			"remap": v = a * p + float(n.value)
			"quantize":
				var quantum := maxf(absf(p), 0.001)
				v = roundf(a / quantum) * quantum
			"slew":
				var previous := float(state.get(id, {}).get("value", a))
				v = lerpf(previous, a, 1.0 - exp(-local_dt / maxf(absf(p), 0.001)))
				state[id] = {"value": v}
			"delay":
				v = state.get(id, {}).get("value", float(n.value)) if dt > 0.0 else values.get(id, float(n.value))
			"vector2": v = Vector2(a, b)
			"vector3": v = Vector3(a, b, c)
			"colour": v = Color(a, b, c, 0.0)
		if v is float or v is int:
			v = clampf(float(v), -16.0, 16.0) if is_finite(float(v)) else 0.0
		values[id] = v
	if dt > 0.0:
		for id in order:
			if nodes[id].kind == "delay":
				state[id] = {"value": float(values[nodes[id].a])}


func metrics() -> Dictionary:
	var sorted := samples.duplicate()
	sorted.sort()
	var n := sorted.size()
	return {"active": not patch.is_empty(), "schema": SCHEMA, "preset": patch.get("preset", -1),
		"source_count": nodes.size(), "route_count": patch.get("routes", []).size(), "fixed_ticks": ticks,
		"dropped_seconds": dropped_seconds, "samples": n, "missing_targets": missing_targets.duplicate(),
		"graph_p50_usec": sorted[floori((n - 1) * 0.5)] if n > 0 else 0.0,
		"graph_p95_usec": sorted[floori((n - 1) * 0.95)] if n > 0 else 0.0}


static func read_patch(path: String):
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > MAX_BYTES:
		return null
	return JSON.parse_string(file.get_as_text())


static func write_patch(path: String, data: Dictionary) -> bool:
	var encoded := JSON.stringify(data, "\t", false, true)
	if encoded.to_utf8_buffer().size() > MAX_BYTES:
		return false
	# Preserve a valid previous save until the new file is fully written.
	var temporary := path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(encoded)
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK:
		return false
	var absolute := ProjectSettings.globalize_path(path)
	var backup := absolute + ".bak"
	if FileAccess.file_exists(absolute):
		if FileAccess.file_exists(backup) and DirAccess.remove_absolute(backup) != OK:
			return false
		if DirAccess.rename_absolute(absolute, backup) != OK:
			return false
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), absolute) != OK:
		if FileAccess.file_exists(backup):
			DirAccess.rename_absolute(backup, absolute)
		return false
	return true
