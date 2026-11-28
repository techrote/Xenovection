extends SceneTree
## Focused convergence contracts independent of the application scene: identity,
## authored-state migration, a single bounded graph, and fixed ecology sampling.
const Catalogue = preload("res://convergence/composition_catalogue.gd")
const Store = preload("res://convergence/composition_store.gd")
const Integrated = preload("res://convergence/integrated_compositions.gd")
const Clock = preload("res://convergence/instrument_clock.gd")
const Bus = preload("res://core/modulation_bus.gd")
const Graph = preload("res://core/synth_graph.gd")
const Examples = preload("res://core/synth_examples.gd")
const Presets = preload("res://presets.gd")
const MatterPresets = preload("res://matter/presets.gd")
const Matter = preload("res://matter/laboratory.gd")
const Optical = preload("res://rendering/optical/optical_layer.gd")
const World = preload("res://ecology/world.gd")
const EcologyPatch = preload("res://convergence/ecology_patch.gd")
var checks := 0
var failures: Array = []
var boundary_errors := 0
var forced_steps := 0


func check(condition: bool, description: String) -> void:
	checks += 1
	print("PASS " if condition else "FAIL ", description)
	if not condition:
		failures.append(description)


func _initialize() -> void:
	_run.call_deferred()


func catalogue() -> Array:
	var original := Presets.all()
	var result: Array = original.slice(0, 7) + MatterPresets.all() + original.slice(7)
	result = Catalogue.decorate(result)
	result.append_array(Integrated.all(result))
	return Catalogue.decorate(result)


func fixture() -> Dictionary:
	var bus = Bus.new()
	var world = World.new()
	world.reset(World.initial_config(0, 15017))
	world.register_targets(bus)
	var graph = Graph.new()
	var patch := Graph.blank(0, "source.hybrid")
	patch.sources = [Examples.node("wave", "sine", {"rate": 1.37}),
		Examples.node("noise", "noise", {"clock": "sky", "rate": 2.9, "seed": 3971})]
	patch.routes = [Examples.route("growth", "wave", "eco.growth", 0.4),
		Examples.route("resource", "noise", "eco.resource", 0.2)]
	graph.configure(patch, bus)
	graph.attach(bus)
	return {"bus": bus, "graph": graph, "world": world, "clock": Clock.new()}


func boundary(values: Dictionary, force: bool, item: Dictionary) -> void:
	if int(item.clock.ticks) % 4 != 0:
		boundary_errors += 1
	if force:
		forced_steps += 1
	item.world.apply_effective(values)
	item.world.step()
	# Mutating the passed map must not change the authoritative bus/sample map.
	values["eco.growth"] = -1000.0


func _run() -> void:
	var presets := catalogue()
	check(presets.size() == 25, "Seven baseline, six matter, six optical and six integrated compositions retained")
	check(Catalogue.validate(presets).ok, "All composition stable and legacy identities are unique")
	for i in range(7):
		check(str(presets[i].id) == Catalogue.BASE_IDS[i], "Accepted baseline picker order preserved: " + str(presets[i].id))
	var reordered := presets.duplicate(true)
	reordered.reverse()
	var saved := {"schema": Store.SCHEMA, "preset_id": "matter.nursery", "preset_index": 7}
	var resolved := Catalogue.resolve_scene(saved, reordered)
	check(resolved.ok and Catalogue.stable_id(reordered[resolved.index]) == "matter.nursery", "Persistent composition identity survives ordering changes")
	var old_found := {"schema": "xenovection.scene.v1", "preset_index": 7, "matter": {"active": false}}
	var old_optical := {"schema": "xenovection.scene.v1", "preset_index": 7, "base_parameters": {"optical.optical_mix": 1.0}}
	check(Catalogue.resolve_scene(old_found, presets).id == "matter.nursery", "Legacy FOUND 08 migrates using branch-specific matter custody")
	check(Catalogue.resolve_scene(old_optical, presets).id == "optical.dichroic", "Legacy OPTICAL 08 migrates independently without collision")
	check(not Catalogue.resolve_scene({"schema": "xenovection.scene.v1", "preset_index": 7}, presets).ok, "Ambiguous legacy numbered preset is refused")
	var bad_presets := presets.duplicate(true)
	bad_presets.append(presets[0].duplicate(true))
	check(not Catalogue.validate(bad_presets).ok, "Duplicate persistent composition identity is refused")
	var old_patch := Graph.blank(3)
	var migrated_patch := Catalogue.migrate_patch(old_patch, presets)
	check(migrated_patch.ok and migrated_patch.patch.preset_id == "source.membrane", "Qualified legacy synth patches migrate by accepted seven-scene ordering")
	check(not Catalogue.migrate_patch(Graph.blank(10), presets).ok, "Unidentified higher-number patch cannot silently select another lineage")

	var legacy := {"schema": "xenovection.scene.v1", "preset_index": 0,
		"base_parameters": {"test.value": 0.25}, "filament_flags": {}, "optical_flags": {}}
	var defaults := {"test.value": 0.0, "optical.optical_mix": 0.0, "eco.growth": 1.0}
	var normalized := Store.normalize(legacy, presets, defaults, {"enabled": true}, {"enabled": true})
	check(normalized.ok, "Legacy scene upgrades to complete composition defaults")
	check(normalized.scene.base_parameters["optical.optical_mix"] == 0.0 and normalized.scene.base_parameters["test.value"] == 0.25, "Missing destinations reset defaults without losing authored bases")
	check(not normalized.scene.matter.active and not normalized.scene.ecology.enabled and normalized.scene.synth_patch.is_empty(), "Missing newer domains reset to explicit inactive state")
	check(normalized.scene.filament_flags.enabled and normalized.scene.optical_flags.enabled, "Missing renderer flags use declared defaults")
	var v2 := Store.encode_scene(normalized.scene, presets)
	check(v2.schema == Store.SCHEMA and v2.preset_id == "source.hybrid", "V2 scene stores canonical source composition identity")
	check(Store.write("user://composition-contract.json", v2), "Atomic composition save succeeds")
	var loaded = Store.read("user://composition-contract.json")
	check(Store.normalize(loaded, presets, defaults, {"enabled": true}, {"enabled": true}).ok, "V2 composition survives JSON roundtrip")
	var changed := v2.duplicate(true)
	changed.base_parameters["test.value"] = 0.75
	check(Store.write("user://composition-contract.json", changed) and Store.read("user://composition-contract.json.bak").base_parameters["test.value"] == 0.25, "Atomic save retains independently readable prior composition")
	var invalid := v2.duplicate(true)
	invalid.preset_index = 0.5
	check(not Store.normalize(invalid, presets, defaults, {}, {}).ok, "Invalid numeric scene identity cannot be hidden by stable-ID migration")
	invalid = v2.duplicate(true)
	invalid.ecology.configuration.params.growth = 300.0
	check(not Store.normalize(invalid, presets, defaults, {}, {}).ok, "Invalid ecology configuration refused before application mutation")
	invalid = v2.duplicate(true)
	invalid.ecology.representation.quality = 4
	check(not Store.normalize(invalid, presets, defaults, {}, {}).ok, "Representation quality stays bounded independently of numerical configuration")
	invalid = v2.duplicate(true)
	invalid.synth_patch = Graph.blank(1, "source.filaments")
	check(not Store.normalize(invalid, presets, defaults, {}, {}).ok, "Patch from another composition is refused")
	var lfo := EcologyPatch.with_lfo({}, 0, "source.hybrid", true)
	check(lfo.ok and lfo.patch.sources.size() == 1 and lfo.patch.routes.size() == 2, "Legacy ecology LFO becomes one common source and two explicit routes")
	var twice := EcologyPatch.with_lfo(lfo.patch, 0, "source.hybrid", true)
	check(twice.ok and twice.patch == lfo.patch, "Ecology LFO migration is idempotent")
	var stopped := EcologyPatch.with_lfo(lfo.patch, 0, "source.hybrid", false)
	check(stopped.ok and stopped.patch.sources.is_empty() and stopped.patch.routes.is_empty(), "Ecology LFO removal releases unused common graph entries")
	invalid = v2.duplicate(true)
	invalid.ecology.configuration.lfo = true
	var lfo_scene := Store.normalize(invalid, presets, defaults, {}, {})
	check(lfo_scene.ok and lfo_scene.scene.synth_patch.sources[0].id == EcologyPatch.SOURCE, "Saved authored ecology LFO migrates without a private bus")
	var collision: Dictionary = lfo.patch.duplicate(true)
	collision.sources[0].kind = "manual"
	check(not EcologyPatch.with_lfo(collision, 0, "source.hybrid", true).ok, "Ecology migration refuses component identity collision")

	var bus = Bus.new()
	for slot in range(Matter.COUNT):
		for key in Matter.SPECS:
			var spec: Array = Matter.SPECS[key]
			var policy := "base_only" if key in ["mode", "seed", "count", "field", "secondary", "integration", "pathline"] else "continuous"
			bus.register_target(Matter.target(slot, key), spec[0], spec[1], spec[2], {"policy": policy})
	for key in Optical.LIMITS:
		bus.register_target("optical." + key, float(Optical.DEFAULTS[key]), Optical.LIMITS[key].x, Optical.LIMITS[key].y)
	var numerical = World.new()
	numerical.reset(World.initial_config(0, 7301))
	numerical.register_targets(bus)
	check(bus.targets.size() <= Bus.MAX_TARGETS, "Shared matter/optical/ecology registry fits fixed target budget")
	for p in presets.slice(19):
		var graph = Graph.new()
		check(graph.configure(p.synth_patch, bus) and graph.attach(bus), "Editable integrated patch binds: " + p.id)
		check(graph.patch.preset_id == p.stable_id and graph.nodes.size() <= 48 and graph.patch.routes.size() <= 96, "Integrated graph bounds and stable scene ID: " + p.id)
		graph.advance(bus, Graph.STEP)
		bus.evaluate(Graph.STEP)
		check(graph.missing_targets.is_empty(), "Integrated graph has no missing destinations: " + p.id)
		graph.detach(bus)
		if p.has("ecology_config"):
			check(numerical.validate(p.ecology_config), "Integrated seeded ecology configuration valid: " + p.id)
	check(not Graph.target_catalogue(bus).has("matter.region0.count") and Graph.target_catalogue(bus).has("matter.region0.strength"), "Catalogue separates expensive topology from continuous live field control")
	bus.set_namespace_available("eco.", false)
	check(not Graph.target_catalogue(bus).has("eco.growth") and Graph.target_catalogue(bus, true).has("eco.growth"), "Catalogue excludes inactive ecology with explicit diagnostic access")
	bus.register_source("availability", {"type": "manual", "value": 4.0})
	bus.add_route({"id": "availability", "source": "availability", "target": "eco.growth", "amplitude": 1.0})
	bus.evaluate()
	check("eco.growth" in bus.diagnostics.unavailable and bus.get_parameters()["eco.growth"] == bus.get_base("eco.growth"), "Inactive destination retains its base and reports blocked application")
	bus.set_namespace_available("eco.", true)
	bus.evaluate()
	check("eco.growth" in bus.diagnostics.clamped and bus.get_parameters()["eco.growth"] == 2.0, "Bounded saturation reports clamping without changing authored base")
	var bus_identity := bus.get_instance_id()
	bus.reset_registry()
	check(bus.get_instance_id() == bus_identity and bus.targets.is_empty() and bus.sources.is_empty() and bus.routes.is_empty(), "Registry reset preserves sole bus identity and removes prior routes")

	var a := fixture()
	var b := fixture()
	for i in range(240):
		a.clock.advance(a.bus, a.graph, 1.0 / 60.0, false, boundary.bind(a))
	for i in range(960):
		b.clock.advance(b.bus, b.graph, 1.0 / 240.0, false, boundary.bind(b))
	check(a.clock.ticks == 480 and b.clock.ticks == 480 and a.world.tick == 120 and b.world.tick == 120, "120Hz graph and30Hz world share exact boundaries across60/240Hz rendering")
	check(a.graph.values == b.graph.values and a.graph.times == b.graph.times, "Common graph trace is invariant to rendering segmentation")
	check(a.world.digest() == b.world.digest(), "Modulated ecology numerical digest is invariant to rendering segmentation")
	check(boundary_errors == 0 and a.clock.last_boundary_values["eco.growth"] >= 0.0, "Ecology receives isolated samples only after completed graph boundaries")
	var ticks_before: int = a.graph.ticks
	var world_before: int = a.world.tick
	a.clock.advance(a.bus, a.graph, 0.0, false, boundary.bind(a))
	check(a.graph.ticks == ticks_before and a.world.tick == world_before, "Zero-delta authoring flush cannot advance numerical history")
	a.bus.paused = true
	a.clock.advance(a.bus, a.graph, World.DT, false, boundary.bind(a))
	check(a.graph.ticks == ticks_before and a.world.tick == world_before + 1, "Ecology lifecycle remains independent of paused visual graph")
	world_before = a.world.tick
	a.clock.step_ecology(a.bus, a.graph, boundary.bind(a))
	check(forced_steps == 1 and a.world.tick == world_before + 1, "Manual ecology step reaches exactly one fixed boundary")
	world_before = a.world.tick
	a.clock.advance(a.bus, a.graph, World.DT, true, boundary.bind(a))
	check(a.world.tick == world_before, "Scientific mode isolates numerical ecology execution")
	var report := {"schema": "xenovection.convergence-contracts.v1", "checks": checks, "failures": failures,
		"registry_budget": Bus.MAX_TARGETS, "compositions": Catalogue.validate(presets),
		"clock": b.clock.metrics(), "ecology_digest": b.world.digest(), "graph": b.graph.metrics()}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):
			var file := FileAccess.open(arg.trim_prefix("--output="), FileAccess.WRITE)
			if file != null:
				file.store_string(JSON.stringify(report, "\t"))
				file.close()
	print("COMPOSITION_CONTRACTS ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
