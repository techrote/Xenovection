extends SceneTree
const World = preload("res://ecology/world.gd")
const Bus = preload("res://core/modulation_bus.gd")
var passed: int = 0
var failed: int = 0
var experiments: Array = []

func check(ok: bool, description: String) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
		print("FAIL: ", description)

func run_steps(w, count: int) -> void:
	for j in range(count):
		w.step()

func finite_and_bounded(w) -> bool:
	if w.organisms.size() > World.MAX_POP or w.history.size() > 240:
		return false
	var seen = {}
	for o in w.organisms:
		if seen.has(o.id) or o.id <= 0 or o.lineage <= 0 or o.parent >= o.id or not o.p.is_finite() or not o.v.is_finite():
			return false
		seen[o.id] = true
		if o.p.x < 0.0 or o.p.y < 0.0 or o.p.x > 1.0 or o.p.y > 1.0 or not is_finite(o.energy) or o.energy < 0 or o.energy > 1 or not is_finite(o.phase) or o.segments.size() % 2 != 0 or o.segments.size() > World.MAX_SEGMENTS * 2 or o.trail.size() > World.MAX_TRAIL or o.tips.size() > 12:
			return false
		for v in o.segments:
			if not v.is_finite():
				return false
	for f in [w.resource, w.signal_field]:
		for value in f:
			if not is_finite(value) or value < 0.0 or value > 1.000001:
				return false
	return true

func _initialize() -> void:
	for preset in range(6):
		var c = World.initial_config(preset, 9876)
		var a = World.new()
		var b = World.new()
		var control = World.new()
		check(a.reset(c) and b.reset(c), "preset resets %d" % preset)
		var off = c.duplicate(true)
		off.interactions = false
		check(control.reset(off), "control resets %d" % preset)
		run_steps(a, 180)
		run_steps(b, 180)
		run_steps(control, 180)
		check(a.digest() == b.digest(), "fixed-step deterministic %d" % preset)
		check(a.digest() != control.digest(), "interacting state differs %d" % preset)
		check(finite_and_bounded(a) and finite_and_bounded(control), "finite bounds %d" % preset)
		check(a.metrics().signal_mean > 0 and control.metrics().signal_mean == 0.0, "shared deposition contrast %d" % preset)
		check(a.consumed > 0.0 and control.consumed == 0.0, "resource competition contrast %d" % preset)
		check(a.queries <= World.MAX_POP * World.MAX_NEIGHBORS and control.queries == 0, "query limit %d" % preset)
		experiments.append({"preset": World.NAMES[preset], "seed": 9876, "ticks": 180, "interacting": a.metrics(), "noninteracting": control.metrics(), "digest": a.digest(), "control_digest": control.digest()})
		if preset == 0:
			check(a.metrics().segments > 0, "genuine branching topology")
		if preset == 1:
			check(a.organisms[0].trail.size() > 1, "vortex trail persistence")
		if preset == 2:
			check(a.organisms[0].radius != 0.008, "membrane growth")
	var w = World.new()
	var initial = World.initial_config(0, 51)
	check(w.reset(initial), "initial state")
	var before = w.digest()
	var bad = initial.duplicate(true)
	bad.params.growth = "bad"
	check(not w.reset(bad) and w.digest() == before, "malformed config transactional")
	bad = initial.duplicate(true)
	bad.sources = [[0.0, 0.0, 1e99]]
	check(not w.reset(bad), "invalid sources")
	check(w.plant(2, Vector2(0.42, 0.42)), "plant")
	check(w.source_at(Vector2(0.42, 0.42), 1.0), "author source")
	var saved = JSON.parse_string(JSON.stringify(w.config))
	var restored = World.new()
	check(restored.reset(saved), "JSON configuration round trip")
	check(restored.organisms.size() == w.organisms.size(), "authored population retained")
	check(w.reset(saved) and w.digest() == restored.digest(), "recalled initial conditions reproduce")
	w.perturb(Vector2(0.5, 0.5), 1.0)
	var value = w.sample(w.signal_field, Vector2(0.5, 0.5))
	check(value > 0.4, "local excitation")
	w.config.interactions = false
	run_steps(w, 9)
	check(w.sample(w.signal_field, Vector2(0.5, 0.5)) < value, "signal diffuses and decays")
	var bus = Bus.new()
	w.register_targets(bus)
	check(bus.targets.has("eco.growth") and bus.targets.has("eco.excitation"), "typed target registration")
	bus.set_base("eco.growth", 1.7)
	w.apply_effective(bus.evaluate())
	check(is_equal_approx(w.effective.growth, 1.7), "effective modulation applied")
	var evolution = World.new()
	evolution.reset(World.initial_config(5, 131))
	evolution.apply_parameter("mutation", 0.0)
	var parent: Dictionary = evolution.organisms[0].duplicate(true)
	check(evolution._spawn(int(parent.kind), Vector2(0.4, 0.4), parent), "child spawned")
	var child: Dictionary = evolution.organisms[-1]
	check(child.parent == parent.id and child.lineage == parent.lineage and child.generation == parent.generation + 1 and child.trait == parent.trait, "exact no-mutation inheritance")
	for i in range(World.MAX_POP * 2):
		evolution._spawn(0, Vector2(0.1, 0.1))
	check(evolution.organisms.size() == World.MAX_POP, "hard population cap")
	run_steps(evolution, 60)
	check(finite_and_bounded(evolution), "dense bounds")
	evolution.organisms.clear()
	evolution.step()
	check(evolution.organisms.is_empty(), "extinction stable")
	check(evolution.reset(World.initial_config(5, 131)) and evolution.organisms.size() == 36, "extinction reset")
	print("ECOLOGY_EXPERIMENTS ", JSON.stringify(experiments))
	print("ECOLOGY_CONTRACTS ", passed, " PASS / ", failed, " FAIL")
	quit(0 if failed == 0 else 1)
