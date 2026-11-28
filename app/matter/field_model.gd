extends RefCounted
## Artistic fields; no original source samples or coefficients enter this module.
const LIMIT := 5.0
const FIXED_STEP := 1.0 / 60.0

static func generator(kind: int, p: Vector3, t: float) -> Vector3:
	var rr := p.length_squared()
	var radial := p / (0.45 + rr)
	match kind:
		0: return Vector3(-p.y, p.x, 0.18 * sin(p.z + t)) / (0.55 + rr * 0.25)
		1: return -radial + Vector3(0.0, 0.15 * sin(p.x + t), 0.0)
		2: return Vector3(sin(p.y * 1.7 + t), sin(p.z * 1.3 - t), sin(p.x * 1.5 + 0.3 * t))
		3: return Vector3(-p.z, 0.65, p.x) / (0.8 + rr * 0.17)
		4:
			var d := 0.5 + rr
			return (3.0 * p * p.y - Vector3.UP * rr) / pow(d, 2.5)
		5:
			# Scaled Lorenz flow; a bounded artistic projection, not a fluid.
			var q := p * 5.0 + Vector3(0.0, 0.0, 24.0)
			return Vector3(10.0 * (q.y - q.x), q.x * (28.0 - q.z) - q.y, q.x * q.y - (8.0 / 3.0) * q.z) * 0.018
		6: return radial
	return Vector3.ZERO

static func sample(p: Vector3, t: float, config: Dictionary) -> Vector3:
	if not p.is_finite() or not is_finite(t):
		return Vector3.ZERO
	var phase := clampf(t, -1000000.0, 1000000.0)
	var origin: Vector3 = config.get("origin", Vector3.ZERO)
	var moving := origin + Vector3(sin(phase * 0.23), cos(phase * 0.31), sin(phase * 0.17)) * 0.36
	var a := p - moving
	var b := p + origin + Vector3(1.1, -0.6, 0.5)
	var blend := clampf(float(config.get("mix", 0.5)), 0.0, 1.0)
	var mask := exp(-b.length_squared() * 0.055)
	var velocity := generator(int(config.get("field", 0)), a, phase) * (1.0 - blend)
	velocity += generator(int(config.get("secondary", 2)), b, phase) * blend * mask
	velocity *= clampf(float(config.get("strength", 1.0)), 0.0, 3.0)
	return velocity.limit_length(4.0) if velocity.is_finite() else Vector3.ZERO

static func step(p: Vector3, t: float, dt: float, config: Dictionary, moving: bool = true) -> Vector3:
	if not p.is_finite() or not is_finite(dt) or not is_finite(t):
		return Vector3.ZERO
	var h := clampf(dt, 0.0, 0.12)
	var mid := p + sample(p, t, config) * h * 0.5
	var result := p + sample(mid, t + h * 0.5 if moving else t, config) * h
	return result.clamp(Vector3.ONE * -LIMIT, Vector3.ONE * LIMIT) if result.is_finite() else Vector3.ZERO

static func seeds(seed_value: int, count: int) -> PackedVector3Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var result := PackedVector3Array()
	for i in range(clampi(count, 0, 192)):
		result.append(Vector3(rng.randf_range(-2.6, 2.6), rng.randf_range(-1.9, 1.9), rng.randf_range(-1.9, 1.9)))
	return result

static func path(start: Vector3, count: int, dt: float, config: Dictionary, moving: bool) -> PackedVector3Array:
	var result := PackedVector3Array()
	var p := start
	for i in range(clampi(count, 2, 129)):
		result.append(p)
		p = step(p, float(i) * dt if moving else 0.0, dt, config, moving)
	return result
