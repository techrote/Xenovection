extends SceneTree
const Graph = preload("res://core/synth_graph.gd")
const Examples = preload("res://core/synth_examples.gd")
const Bus = preload("res://core/modulation_bus.gd")
const Main = preload("res://main.gd")
var checks := 0
var failures: Array = []

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
		print("FAIL ", description)
	else:
		print("PASS ", description)

func fixture():
	var bus = Bus.new()
	bus.register_target("test.scalar", 0.0, -16.0, 16.0)
	bus.register_target("test.vector", Vector2.ZERO, -16.0, 16.0)
	bus.register_target("test.colour", Color(0.5, 0.5, 0.5, 1.0), 0.0, 1.0)
	return bus

func patch_fixture() -> Dictionary:
	var p := Graph.blank()
	p.sources = [
		Examples.node("input", "manual", {"value": 0.25}),
		Examples.node("random", "noise", {"clock": "sky", "rate": 4.0, "seed": 1234}),
		Examples.node("osc", "saw", {"rate": 2.0}),
		Examples.node("prior", "delay", {"a": "sum"}),
		Examples.node("scaled", "remap", {"a": "prior", "param": 0.5}),
		Examples.node("sum", "add", {"a": "scaled", "b": "input"}),
		Examples.node("vec", "vector2", {"a": "random", "b": "osc"}),
		Examples.node("env", "envelope", {"rate": 1.0, "param": 0.2})
	]
	p.routes = [
		Examples.route("r", "sum", "test.scalar", 1.0),
		Examples.route("v", "vec", "test.vector", 1.0),
		Examples.route("e", "env", "test.scalar", 0.5)
	]
	return p

func _run() -> void:
	var first = fixture()
	var second = fixture()
	var a = Graph.new()
	var b = Graph.new()
	var p := patch_fixture()
	check(a.configure(p, first) and a.attach(first), "Valid typed graph binds existing bus")
	check(b.configure(p, second) and b.attach(second), "Independent replay graph binds")
	if not failures.is_empty():
		quit(1)
		return
	a.advance(first, Graph.STEP)
	b.advance(second, Graph.STEP)
	check(is_equal_approx(float(a.values.sum), 0.25), "Explicit delay reads initial state")
	a.advance(first, Graph.STEP)
	b.advance(second, Graph.STEP)
	check(is_equal_approx(float(a.values.sum), 0.375), "Delayed feedback reads previous tick")
	for i in range(600):
		a.advance(first, Graph.STEP * 2.0)
		b.advance(second, Graph.STEP)
		b.advance(second, Graph.STEP)
	check(a.ticks == b.ticks and a.values == b.values and a.times == b.times, "Fixed-step replay identical at 60 and 120 Hz render cadence")
	check(first.evaluate()["test.vector"] is Vector2, "Typed vector reaches registered bus destination")
	first.set_clock("sky", {"paused": true})
	var frozen: float = a.times.sky
	var advancing: float = a.times.filament
	a.advance(first, 0.125)
	check(a.times.sky == frozen and a.times.filament > advancing, "Independent clock pause")
	first.set_clock("filament", {"rate": -1.0})
	advancing = a.times.filament
	a.advance(first, 0.125)
	check(a.times.filament < advancing, "Analytical clock reverses")
	first.paused = true
	var tick_count: int = a.ticks
	a.advance(first, 0.2)
	check(a.ticks == tick_count, "Global pause preserves tick count")
	first.paused = false
	a.trigger("env")
	for i in range(24):
		a.advance(first, Graph.STEP)
	check(float(a.values.env) > 0.7, "Manual envelope produces a playable attack")
	var invalid := p.duplicate(true)
	invalid.sources[3].kind = "remap"
	check(not a.configure(invalid, first), "Instantaneous cycle rejected")
	invalid = p.duplicate(true)
	invalid.routes[1].target = "test.scalar"
	check(not a.configure(invalid, first), "Vector to scalar route rejected")
	invalid = p.duplicate(true)
	invalid.routes[0].target = "unknown"
	check(not a.configure(invalid, first), "Unavailable destination refused")
	invalid = p.duplicate(true)
	invalid.sources[0].value = INF
	check(not a.configure(invalid, first), "Non-finite value rejected")
	invalid = p.duplicate(true)
	invalid.sources[0].id = invalid.sources[1].id
	check(not a.configure(invalid, first), "Duplicate component IDs rejected")
	first.register_target("test.discrete", 0.0, 0.0, 1.0, {"policy": "base_only"})
	invalid = p.duplicate(true)
	invalid.routes[0].target = "test.discrete"
	check(not a.configure(invalid, first) and not Graph.target_catalogue(first).has("test.discrete"), "Base-only topology targets excluded")
	check(a.patch.sources.size() == p.sources.size(), "Invalid edit retains prior graph")
	first.targets.erase("test.vector")
	a.advance(first, Graph.STEP)
	first.evaluate()
	check("test.vector" in a.missing_targets, "Deleted destination safely omitted before bus evaluation")
	check(Graph.write_patch("user://synth-test-roundtrip.json", b.snapshot(second)), "Patch save succeeds")
	var loaded = Graph.read_patch("user://synth-test-roundtrip.json")
	var roundtrip = Graph.new()
	check(roundtrip.configure(loaded, second) and roundtrip.patch == b.snapshot(second), "JSON roundtrip reproduces authored graph")
	roundtrip.attach(second)
	b.reset()
	for i in range(120):
		roundtrip.advance(second, Graph.STEP)
		b.advance(second, Graph.STEP)
	check(roundtrip.values == b.values, "Reload and reset reproduce deterministic graph trace")
	var dense := Graph.blank()
	for i in range(Graph.MAX_NODES):
		dense.sources.append(Examples.node("n%d" % i, "sine", {"rate": 0.1 + i * 0.02}))
	for i in range(Graph.MAX_ROUTES):
		dense.routes.append(Examples.route("r%d" % i, "n%d" % (i % Graph.MAX_NODES), "test.scalar", 0.01))
	var dense_graph = Graph.new()
	var dense_bus = fixture()
	check(dense_graph.configure(dense, dense_bus) and dense_graph.attach(dense_bus), "48-source/96-route bounded dense specimen")
	var start := Time.get_ticks_usec()
	for i in range(3600):
		dense_graph.advance(dense_bus, 1.0 / 60.0)
		dense_bus.advance(1.0 / 60.0)
	var elapsed := float(Time.get_ticks_usec() - start) / 1000000.0
	check(dense_graph.ticks == 7200 and dense_graph.samples.size() == 1024, "60 simulated seconds; bounded profile ring")
	print("SYNTH_DENSE ", JSON.stringify({"wall_seconds": elapsed, "simulated_seconds": 60, "metrics": dense_graph.metrics()}))
	dense.sources.append(Examples.node("overflow", "manual"))
	check(not dense_graph.configure(dense, dense_bus), "Oversized graph refused")

	var app = Main.new()
	root.add_child(app)
	app.set_process(false)
	var panel = app.synth_panel
	var retained_baseline: Array = []
	for preset in app.presets.slice(0, 7):
		retained_baseline.append(preset.id)
	check(retained_baseline == ["hybrid", "filaments", "optical", "membrane", "scientific", "stress", "flow"] and app.synth.patch.is_empty(), "Original seven preset identities and order retained; synth is opt-in")
	panel._edit(Graph.blank(app.preset_index))
	panel._show_source("")
	panel._items(panel.kind_picker, Graph.KINDS, "manual")
	panel.value.value = 0.5
	panel._apply_source()
	check(app.synth.nodes.size() == 1, "Authoring creates a component through editor controls")
	panel._show_route("")
	panel._targets("filament.phase_speed")
	panel.amplitude.value = 0.8
	var authored_source: String = panel._selected(panel.route_source)
	var authored_target: String = panel._selected(panel.target_picker)
	panel._apply_route()
	print("SYNTH_ROUTE_AUTHORING ", JSON.stringify({"selected_source": authored_source,
		"selected_target": authored_target, "route_count": app.synth.patch.get("routes", []).size(),
		"synth_error": app.synth_error, "panel_status": panel.status.text}))
	check(app.synth.patch.routes.size() == 1, "Editor constructs route without file editing")
	app._process(1.0 / 60.0)
	check(float(app.bus.get_parameters()["filament.phase_speed"]) > float(app.bus.get_base("filament.phase_speed")) + 0.39, "New route drives actual renderer target")
	panel._undo()
	check(app.synth.patch.routes.is_empty(), "Undo restores pre-route state")
	panel._redo()
	check(app.synth.patch.routes.size() == 1, "Redo restores route")
	for entry in Examples.all():
		var ok: bool = app.install_synth_patch(entry.patch, true)
		check(ok, entry.title + " binds actual renderer targets")
		if not ok:
			continue
		# Patch recall may legitimately change preset topology (segments/fibres).
		# Flush that authored transition before measuring ordinary continuous
		# modulation so the assertion still rejects every subsequent rebuild.
		app._process(0.0)
		var source_revision: String = app.dataset.manifest.revision
		var before: Dictionary = app.filaments.get_metrics()
		var before_optical: Dictionary = app.optical.get_metrics()
		app.synth.set_manual("xy_x", 0.75)
		app.synth.set_manual("xy_y", -0.6)
		app.synth.trigger("strike")
		for frame in range(90):
			app._process(1.0 / 60.0)
		var after: Dictionary = app.filaments.get_metrics()
		check(app.synth.ticks == 180 and source_revision == app.dataset.manifest.revision, entry.title + " executes with immutable source")
		check(before.mesh_build_count == after.mesh_build_count and before.instance_upload_count == after.instance_upload_count and before_optical.proxy_geometry_builds == app.optical.get_metrics().proxy_geometry_builds, entry.title + " ordinary modulation does not rebuild geometry")
		print("SYNTH_EXAMPLE ", entry.title, " ", JSON.stringify(app.synth.metrics()))
	app.apply_preset(4)
	check(app.synth.patch.is_empty() and app.scientific, "Scientific preset restores baseline without patch")
	app.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://synth-test-roundtrip.json"))
	print("SYNTH_TEST ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
