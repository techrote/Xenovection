extends RefCounted
## Read-only presentation custody. This class never changes World, its RNG or its clocks.
## Packed numeric arrays become bounded frozen Arrays so consumers cannot mutate a shared snapshot.
const World = preload("res://ecology/world.gd")
var epoch: int = 0
var revision: int = 0
var sequence: int = 0
var last_signature: String = ""
var generation_usec: int = 0
var generation_samples: Array[int] = []

func reset_generation() -> void:
	epoch += 1
	last_signature = ""

func capture(world, domain_transform: Transform3D = Transform3D.IDENTITY) -> Dictionary:
	var started = Time.get_ticks_usec()
	var rows: Array = []
	var topology: Array = []
	for o in world.organisms:
		var segments: Array = Array(o.segments)
		var tips: Array = Array(o.tips)
		var trail: Array = Array(o.trail)
		var topology_key = "%d:%d:%d:%d" % [o.id, o.kind, segments.size(), tips.size()]
		topology.append(topology_key)
		rows.append({"id": int(o.id), "organism_id": "eco.organism.%d" % o.id,
			"lineage": int(o.lineage), "lineage_id": "eco.lineage.%d" % o.lineage,
			"parent": int(o.parent), "generation": int(o.generation), "family": int(o.kind),
			"position": o.p, "previous_position": o.prev_p, "velocity": o.v,
			"energy": float(o.energy), "phase": float(o.phase), "excitation": float(o.excited),
			"radius": float(o.radius), "growth": float(o.allele), "age_ticks": int(o.age),
			"segments": segments, "tips": tips, "trail": trail,
			"resource": world.sample(world.resource, o.p), "signal": world.sample(world.signal_field, o.p),
			"topology_revision": topology_key})
	var signature: String = str(topology)
	if signature != last_signature:
		revision += 1
		last_signature = signature
	sequence += 1
	var result = {"schema": "xenovection.ecology.snapshot.v1", "epoch": epoch,
		"sequence": sequence, "tick": int(world.tick), "seed": int(world.config.seed),
		"fixed_step_hz": 30, "field_step_hz": 10, "growth_step_hz": 5,
		"domain_transform": domain_transform, "domain": Rect2(Vector2.ZERO, Vector2.ONE),
		"topology_revision": revision, "organisms": rows,
		"resource_field": Array(world.resource), "signal_field": Array(world.signal_field),
		"field_side": World.N, "sources": world.config.sources.duplicate(true),
		"effective": world.effective.duplicate(true), "metrics": world.metrics()}
	_freeze(result)
	generation_usec = Time.get_ticks_usec() - started
	generation_samples.append(generation_usec)
	if generation_samples.size() > 1024:
		generation_samples.pop_front()
	return result

static func _freeze(value) -> void:
	if value is Dictionary:
		for child in value.values():
			_freeze(child)
		value.make_read_only()
	elif value is Array:
		for child in value:
			_freeze(child)
		value.make_read_only()

func metrics() -> Dictionary:
	var samples: Array[int] = generation_samples.duplicate()
	samples.sort()
	return {"snapshot_generation_us_last": generation_usec,
		"snapshot_generation_us_p50": samples[int((samples.size() - 1) * 0.50)] if not samples.is_empty() else 0,
		"snapshot_generation_us_p95": samples[int((samples.size() - 1) * 0.95)] if not samples.is_empty() else 0,
		"snapshot_samples": samples.size(), "snapshot_epoch": epoch, "snapshot_topology_revision": revision}
