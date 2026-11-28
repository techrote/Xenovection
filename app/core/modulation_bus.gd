extends RefCounted
## Typed, bounded visual modulation. Evaluated values never overwrite preset bases.

const CLOCK_NAMES := ["filament", "sky", "normal", "displacement", "palette"]
const MAX_ROUTES := 128
const MAX_TARGETS := 256
const MAX_SOURCES := 64

var targets: Dictionary = {}
var sources: Dictionary = {}
var routes: Array = []
var clocks: Dictionary = {}
var paused := false
var enabled := true
var last_error := ""
var _effective: Dictionary = {}
var _smoothed: Dictionary = {}
var _last_delta := 0.0


func _init() -> void:
	for name in CLOCK_NAMES:
		clocks[name] = {"time": 0.0, "rate": 1.0, "paused": false}


func register_target(name: String, base, minimum = -1000.0, maximum = 1000.0, metadata: Dictionary = {}) -> bool:
	if name.is_empty() or (targets.size() >= MAX_TARGETS and not targets.has(name)):
		return _error("Target limit exceeded or empty target name")
	var kind := _kind(base)
	if kind.is_empty() or not _finite(base) or not _finite(minimum) or not _finite(maximum):
		return _error("Target values and bounds must be finite scalar/vector/colour values")
	if not _compatible_bound(base, minimum) or not _compatible_bound(base, maximum):
		return _error("Target bounds have an incompatible type")
	if not _valid_bounds(minimum, maximum):
		return _error("Target minimum exceeds maximum")
	var policy = metadata.get("policy", "continuous")
	if not policy in ["continuous", "base_only", "discrete"]:
		return _error("Unknown target update policy")
	targets[name] = {"base": _bounded(base, minimum, maximum), "minimum": minimum, "maximum": maximum, "kind": kind}
	if metadata.has("policy"):
		targets[name]["policy"] = policy
	if metadata.get("field_descriptor") is Dictionary:
		targets[name]["field_descriptor"] = metadata.field_descriptor.duplicate(true)
	_effective[name] = targets[name].base
	return true


func set_base(name: String, value) -> bool:
	if not targets.has(name) or not _finite(value) or _kind(value) != targets[name].kind:
		return _error("Unknown target, non-finite value or incompatible base type")
	var spec: Dictionary = targets[name]
	spec.base = _bounded(value, spec.minimum, spec.maximum)
	return true


func get_base(name: String):
	return targets.get(name, {}).get("base", 0.0)


func register_source(name: String, config: Dictionary) -> bool:
	if name.is_empty() or (sources.size() >= MAX_SOURCES and not sources.has(name)):
		return _error("Source limit exceeded or empty source name")
	if not _valid_source(config):
		return false
	sources[name] = config.duplicate(true)
	return true


func add_route(config: Dictionary) -> bool:
	if routes.size() >= MAX_ROUTES:
		return _error("Modulation route limit exceeded")
	var target := str(config.get("target", ""))
	if not targets.has(target):
		return _error("Modulation route references an unknown target")
	if targets[target].get("policy", "continuous") != "continuous":
		return _error("Destination is not a continuously modulated target")
	var operation := str(config.get("operation", "add"))
	if not operation in ["add", "multiply"]:
		return _error("Modulation operation must be add or multiply")
	var source_name := str(config.get("source", "lfo"))
	var source: Dictionary = sources.get(source_name, config)
	if not _valid_source(source):
		return false
	var amplitude = config.get("amplitude", 1.0)
	if not _finite(amplitude) or not _compatible_bound(targets[target].base, amplitude):
		return _error("Route amplitude must match the target type or be scalar")
	var sample = _source_value(source)
	if not (_kind(sample) == "scalar" or _kind(sample) == targets[target].kind):
		return _error("Source and target types are incompatible")
	for key in ["mask", "smoothing"]:
		if not _finite(config.get(key, 0.0)) or _kind(config.get(key, 0.0)) != "scalar":
			return _error("Route mask and smoothing must be finite scalars")
	if not _finite(config.get("offset", 0.0)) or not _compatible_bound(targets[target].base, config.get("offset", 0.0)):
		return _error("Route offset must match the target type or be scalar")
	var route := config.duplicate(true)
	route["id"] = str(config.get("id", "route-%d" % routes.size()))
	for existing in routes:
		if existing.id == route.id:
			return _error("Duplicate modulation route ID")
	route["target"] = target
	route["source"] = source_name
	route["operation"] = operation
	route["amplitude"] = amplitude
	route["mask"] = clampf(float(config.get("mask", 1.0)), 0.0, 1.0)
	route["smoothing"] = clampf(float(config.get("smoothing", 0.0)), 0.0, 30.0)
	route["enabled"] = bool(config.get("enabled", true))
	routes.append(route)
	return true


func clear_routes() -> void:
	routes.clear()
	_smoothed.clear()


func set_route_enabled(id: String, active: bool) -> bool:
	for route in routes:
		if route.id == id:
			route.enabled = active
			return true
	return false


func set_clock(name: String, config: Dictionary) -> bool:
	if not clocks.has(name):
		return _error("Unknown visual clock")
	if config.has("rate"):
		if not _finite(config.rate) or not _kind(config.rate) == "scalar":
			return _error("Clock rate must be finite")
		clocks[name].rate = clampf(float(config.rate), -8.0, 8.0)
	if config.has("paused"):
		clocks[name].paused = bool(config.paused)
	return true


func get_clocks() -> Dictionary:
	var result: Dictionary = {}
	for name in clocks:
		result[name] = clocks[name].time
	return result


func advance(delta: float) -> Dictionary:
	if not is_finite(delta) or delta < 0.0:
		return evaluate(0.0)
	# A suspended window must not explode the phase on resume.
	_last_delta = minf(delta, 0.25)
	if not paused:
		for name in clocks:
			if not clocks[name].paused:
				clocks[name].time = clampf(float(clocks[name].time) + _last_delta * float(clocks[name].rate), -1.0e9, 1.0e9)
	return evaluate(0.0 if paused else _last_delta)


func evaluate(delta: float = 0.0) -> Dictionary:
	_effective.clear()
	for name in targets:
		_effective[name] = targets[name].base
	if not enabled:
		return _effective.duplicate()
	var sampled: Dictionary = {}
	for name in sources:
		sampled[name] = _source_value(sources[name])
	# Insertion order is the declared, serialized route order.
	for route in routes:
		if not route.enabled or route.mask <= 0.0 or not targets.has(route.target) or targets[route.target].get("policy", "continuous") != "continuous":
			continue
		var raw = sampled.get(route.source, null)
		if raw == null:
			raw = _source_value(route)
		var target: String = route.target
		var base = targets[target].base
		var modulation = _coerce(raw, base) * _coerce(route.amplitude, base)
		var offset = _coerce(route.get("offset", 0.0), base)
		modulation += offset
		modulation *= float(route.mask)
		if not _finite(modulation):
			modulation = _coerce(0.0, base)
		modulation = _bounded(modulation, -1.0e6, 1.0e6)
		if route.smoothing > 0.0:
			if not _smoothed.has(route.id):
				_smoothed[route.id] = modulation
			elif delta > 0.0:
				_smoothed[route.id] = _smoothed[route.id].lerp(modulation, 1.0 - exp(-delta / route.smoothing)) if base is Vector2 or base is Vector3 or base is Color else lerpf(float(_smoothed[route.id]), float(modulation), 1.0 - exp(-delta / route.smoothing))
			modulation = _smoothed[route.id]
		if route.operation == "multiply":
			_effective[target] *= _coerce(1.0, base) + modulation
		else:
			_effective[target] += modulation
		var spec: Dictionary = targets[target]
		_effective[target] = _bounded(_effective[target], spec.minimum, spec.maximum)
	return _effective.duplicate()


func get_parameters() -> Dictionary:
	return _effective.duplicate()


func reset() -> void:
	for name in clocks:
		clocks[name].time = 0.0
	_smoothed.clear()
	evaluate()


func seek(seconds: float) -> void:
	if not is_finite(seconds):
		return
	for name in clocks:
		clocks[name].time = clampf(seconds, -86400.0, 86400.0) * float(clocks[name].rate)
	_smoothed.clear()
	evaluate()


func snapshot() -> Dictionary:
	# Contains bases and routes, not transient evaluated replacements.
	return {"schema": "xenovection.modulation.v1", "targets": targets.duplicate(true),
		"sources": sources.duplicate(true), "routes": routes.duplicate(true),
		"clocks": clocks.duplicate(true), "paused": paused, "enabled": enabled}


func _valid_source(config: Dictionary) -> bool:
	var source_type := str(config.get("type", "lfo"))
	if not source_type in ["lfo", "manual"]:
		return _error("Source type must be lfo or manual")
	if source_type == "manual":
		return _finite(config.get("value", 0.0)) or _error("Manual source must be finite")
	if not clocks.has(str(config.get("clock", "filament"))):
		return _error("Oscillator references an unknown clock")
	if not str(config.get("waveform", "sine")) in ["sine", "triangle", "smooth_triangle", "cosine"]:
		return _error("Unsupported oscillator waveform")
	for name in ["frequency", "phase"]:
		var number = config.get(name, 0.0)
		if not _finite(number) or _kind(number) != "scalar":
			return _error("Oscillator frequency and phase must be finite scalars")
	return true


func _source_value(config: Dictionary):
	if config.get("type", "lfo") == "manual":
		return config.get("value", 0.0)
	var clock: Dictionary = clocks.get(str(config.get("clock", "filament")), clocks.filament)
	var hz := clampf(float(config.get("frequency", 0.1)), -100.0, 100.0)
	var cycle := float(clock.time) * hz + clampf(float(config.get("phase", 0.0)), -1.0e6, 1.0e6)
	var phase := fposmod(cycle, 1.0)
	match str(config.get("waveform", "sine")):
		"cosine":
			return cos(phase * TAU)
		"triangle":
			return 1.0 - 4.0 * absf(phase - 0.5)
		"smooth_triangle":
			var triangle := 1.0 - 4.0 * absf(phase - 0.5)
			return triangle * (1.5 - 0.5 * triangle * triangle)
	return sin(phase * TAU)


func _error(message: String) -> bool:
	last_error = message
	return false


static func _kind(value) -> String:
	if value is int or value is float:
		return "scalar"
	if value is Vector2:
		return "vector2"
	if value is Vector3:
		return "vector3"
	if value is Color:
		return "colour"
	return ""


static func _finite(value) -> bool:
	if value is int or value is float:
		return is_finite(float(value))
	if value is Vector2 or value is Vector3:
		return value.is_finite()
	if value is Color:
		return is_finite(value.r) and is_finite(value.g) and is_finite(value.b) and is_finite(value.a)
	return false


static func _compatible_bound(base, value) -> bool:
	return _kind(value) == "scalar" or _kind(base) == _kind(value)


static func _coerce(value, base):
	if _kind(value) != "scalar" or _kind(base) == "scalar":
		return value
	if base is Vector2:
		return Vector2.ONE * float(value)
	if base is Vector3:
		return Vector3.ONE * float(value)
	return Color(float(value), float(value), float(value), float(value))


static func _bounded(value, minimum, maximum):
	var lo = _coerce(minimum, value)
	var hi = _coerce(maximum, value)
	if value is Vector2 or value is Vector3:
		return value.clamp(lo, hi)
	if value is Color:
		return Color(clampf(value.r, lo.r, hi.r), clampf(value.g, lo.g, hi.g), clampf(value.b, lo.b, hi.b), clampf(value.a, lo.a, hi.a))
	return clampf(float(value), float(lo), float(hi))


static func _valid_bounds(minimum, maximum) -> bool:
	if _kind(minimum) == "scalar" and _kind(maximum) == "scalar":
		return float(minimum) <= float(maximum)
	var base = maximum if _kind(minimum) == "scalar" else minimum
	var lo = _coerce(minimum, base)
	var hi = _coerce(maximum, base)
	if base is Vector2:
		return lo.x <= hi.x and lo.y <= hi.y
	if base is Vector3:
		return lo.x <= hi.x and lo.y <= hi.y and lo.z <= hi.z
	if base is Color:
		return lo.r <= hi.r and lo.g <= hi.g and lo.b <= hi.b and lo.a <= hi.a
	return false
