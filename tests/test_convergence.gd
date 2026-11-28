extends SceneTree
## Cross-domain witnesses against the actual application. Real graphical input
## is qualified separately; this suite measures lifecycle, persistence and state.
const Main = preload("res://main.gd")
const Catalogue = preload("res://convergence/composition_catalogue.gd")
const Store = preload("res://convergence/composition_store.gd")
const Graph = preload("res://core/synth_graph.gd")
var checks := 0
var failures: Array = []
var app
var compositions: Array = []


func _initialize() -> void:
	_run.call_deferred()


func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
	print("PASS " if condition else "FAIL ", description)


func builds() -> Array:
	var result: Array = []
	for region in app.matter.regions:
		result.append(region.builds)
	return result


func _run() -> void:
	app = Main.new()
	root.add_child(app)
	app.set_process(false)
	var source_revision: String = app.dataset.manifest.revision
	var bus_id: int = app.bus.get_instance_id()
	check(app._ready_done and app.ecology.hosted and app.ecology.bus == app.bus, "Application and ecology share exactly one authoritative modulation bus")
	check(app.presets.size() == 25 and Catalogue.validate(app.presets).ok, "Unified application exposes all25 unique persistent compositions")
	check(app.bus.targets.size() <= 256 and app.bus.targets.has("matter.region2.optical_mix") and app.bus.targets.has("optical.transmission") and app.bus.targets.has("eco.growth"), "One bounded registry contains every required domain")
	for preset in app.presets.slice(19):
		app.apply_preset(Catalogue.index_of(app.presets, preset.stable_id))
		app._process(0.0)
		check(app.bus.get_instance_id() == bus_id and app.ecology.bus == app.bus, "Stable shared bus after composition recall: " + preset.id)
		check(app.matter.active and app.synth.patch.get("preset_id", "") == preset.stable_id, "Integrated matter and graph execute together: " + preset.id)
		var before := builds()
		var optical_before: int = app.optical.get_metrics().proxy_geometry_builds
		var numerical_before: int = app.ecology.world.tick
		app.synth.set_manual("xy_x", 0.35)
		app.synth.set_manual("xy_y", -0.25)
		app.synth.trigger("strike")
		for frame in range(24):
			app._process(1.0 / 60.0)
		check(app.synth.ticks == 48 and app.synth.missing_targets.is_empty(), "Integrated graph advances48 fixed ticks with all destinations: " + preset.id)
		check(before == builds() and optical_before == app.optical.get_metrics().proxy_geometry_builds, "Continuous cross-domain performance reuses geometry: " + preset.id)
		check(app.dataset.manifest.revision == source_revision, "Integrated composition preserves exact scientific source: " + preset.id)
		if preset.has("ecology_config"):
			check(app.ecology.simulation_enabled and app.ecology.world.tick == numerical_before + 12, "Ecology samples every fourth graph tick: " + preset.id)
			check(app.spatial_ecology.records.size() == app.ecology.world.organisms.size() and app.spatial_ecology.visible, "Identity-owned spatial resources represent current living population: " + preset.id)
			check(is_equal_approx(float(app.ecology.world.effective.growth), float(app.instrument_clock.last_boundary_values["eco.growth"])), "Solver applies resolved shared growth only at boundary: " + preset.id)
		else:
			check(not app.ecology.simulation_enabled and app.ecology.world.tick == numerical_before, "Matter-only composition does not accidentally evolve ecology: " + preset.id)
		compositions.append({"id": preset.stable_id, "graph": app.synth.metrics(), "matter": app.matter.metrics(),
			"ecology": app.ecology.convergence_metrics(), "representation": app.spatial_ecology.metrics()})

	app.ecology.paused = true
	var digest: String = app.ecology.world.digest()
	var allocations: int = app.spatial_ecology.allocations
	var registry_count: int = app.bus.targets.size()
	for cycle in range(5):
		app.set_workspace("planar")
		app._process(0.0)
		app.set_workspace("spatial")
		app._process(0.0)
		app.set_workspace("instrument")
		app._process(0.0)
	check(app.ecology.world.digest() == digest and app.ecology.paused, "Repeated workspace changes preserve paused numerical state and lifecycle")
	check(app.spatial_ecology.allocations == allocations and app.bus.targets.size() == registry_count and app.ecology.bus == app.bus, "Workspace transitions reuse organism resources and registry without duplicate ownership")
	app.ecology.stride = 4
	app._process(0.0)
	check(app.ecology.world.digest() == digest and app.spatial_ecology.quality == 2, "Representation quality changes do not alter numerical ecology")
	app.camera.set_pose({"yaw": 0.65, "pitch": 0.37})
	app._process(0.0)
	check(app.ecology.world.digest() == digest, "Camera changes cannot alter numerical ecology")
	app.set_parameter("optical.optical_thickness", 0.79)
	app.set_parameter("matter.edit.condensation", 0.73)
	app.ecology._parameter(1.42, "growth")
	app._process(0.0)
	var path := "user://convergence-mixed.json"
	app.save_scene(path)
	var saved = Store.read(path)
	check(saved is Dictionary and saved.schema == Store.SCHEMA and saved.preset_id == "composition.matter_orchestra", "Full composition save binds stable identity and v2 schema")
	check(saved.ecology.configuration.params.growth == 1.42 and saved.ecology.representation.quality == 2, "Saved composition includes ecology initial configuration and representation separately")
	var original_base: float = app.bus.get_base("matter.region0.condensation")
	var original_patch: Dictionary = app.synth.snapshot(app.bus)
	app.apply_preset(0)
	check(app.load_scene(path), "Mixed-domain composition loads after unrelated baseline recall")
	app._process(0.0)
	check(app.bus.get_instance_id() == bus_id and app.ecology.bus == app.bus, "Scene recall keeps shared modulation identity")
	check(is_equal_approx(app.bus.get_base("optical.optical_thickness"), 0.79) and is_equal_approx(app.bus.get_base("matter.region0.condensation"), original_base), "Unified recall restores optical and generated-matter authored parameters")
	check(app.synth.snapshot(app.bus) == original_patch, "Unified recall restores complete editable patch without transient histories")
	check(app.ecology.world.tick == 0 and app.ecology.paused and app.ecology.stride == 4 and is_equal_approx(app.ecology.world.config.params.growth, 1.42), "Unified recall explicitly restarts ecology while restoring pause, quality and authored parameters")
	for prior_index in [4, 6, 5]:
		app.apply_preset(prior_index)
		app._process(0.0)
		check(app.load_scene(path) and app.dataset.manifest.revision == source_revision and app.presets[app.preset_index].stable_id == "composition.matter_orchestra", "Composition recall reconstructs exact built-in source after baseline scene%d" % prior_index)
		app._process(0.0)

	var malformed: Dictionary = saved.duplicate(true)
	malformed.ecology.configuration.params.growth = -100.0
	malformed.base_parameters["optical.optical_thickness"] = 1.2
	var bad_path := "user://convergence-invalid.json"
	Store.write(bad_path, malformed)
	digest = app.ecology.world.digest()
	var camera_before: Dictionary = app.camera.get_pose()
	var selection_before: Dictionary = app.selection.get_reference()
	check(not app.load_scene(bad_path), "Invalid ecology envelope is rejected before scene mutation")
	check(app.ecology.world.digest() == digest and app.camera.get_pose() == camera_before and app.selection.get_reference() == selection_before and is_equal_approx(app.bus.get_base("optical.optical_thickness"), 0.79), "Invalid mixed-domain recall is atomic across solver, optics, camera and source selection")
	malformed = saved.duplicate(true)
	malformed.synth_patch.routes[0].target = "eco.missing"
	Store.write(bad_path, malformed)
	check(not app.load_scene(bad_path) and app.ecology.world.digest() == digest, "Missing graph destination refuses entire composition before ecology reset")

	# Actual legacy FOUND and OPTICAL layouts used the same zero-based slot7.
	app.apply_preset(Catalogue.index_of(app.presets, "matter.nursery"))
	app._process(0.0)
	app.save_scene(path)
	var old_found: Dictionary = Store.read(path)
	old_found.schema = "xenovection.scene.v1"
	old_found.erase("preset_id")
	old_found.erase("ecology")
	old_found.erase("workspace")
	old_found.preset_index = 7
	Store.write(path, old_found)
	app.apply_preset(Catalogue.index_of(app.presets, "composition.matter_orchestra"))
	check(app.load_scene(path) and app.presets[app.preset_index].stable_id == "matter.nursery" and not app.ecology.simulation_enabled, "Legacy FOUND08 recalls correct composition and clears unrelated ecology")
	app.apply_preset(Catalogue.index_of(app.presets, "optical.dichroic"))
	app._process(0.0)
	app.save_scene(path)
	var old_optical: Dictionary = Store.read(path)
	old_optical.schema = "xenovection.scene.v1"
	for field in ["preset_id", "matter", "ecology", "workspace"]:
		old_optical.erase(field)
	old_optical.preset_index = 7
	for name in old_optical.base_parameters.keys():
		if str(name).begins_with("matter.") or str(name).begins_with("eco."):
			old_optical.base_parameters.erase(name)
	Store.write(path, old_optical)
	app.apply_preset(Catalogue.index_of(app.presets, "composition.matter_orchestra"))
	check(app.load_scene(path) and app.presets[app.preset_index].stable_id == "optical.dichroic" and not app.matter.active and not app.ecology.simulation_enabled, "Legacy OPTICAL08 recalls distinct optical composition and clears generated state")
	app.apply_preset(Catalogue.index_of(app.presets, "composition.living_membrane"))
	app._process(0.0)
	app.set_ecology_enabled(false)
	check(app.spatial_ecology.records.is_empty() and app.spatial_ecology.allocations == app.spatial_ecology.deallocations, "Explicit ecology deactivation releases every organism-owned resource")
	app.apply_preset(4)
	app._process(1.0 / 60.0)
	check(app.scientific and not app.matter.visible and not app.spatial_ecology.visible and app.synth.patch.is_empty() and app.dataset.manifest.revision == source_revision, "Scientific mode isolates exact source from all generated, optical and ecological compositions")
	var report := {"schema": "xenovection.integrated-convergence.v1", "checks": checks, "failures": failures,
		"source_revision": source_revision, "compositions": compositions}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):
			var file := FileAccess.open(arg.trim_prefix("--output="), FileAccess.WRITE)
			if file != null:
				file.store_string(JSON.stringify(report, "\t"))
				file.close()
	app.queue_free()
	await process_frame
	for file_path in [path, path + ".bak", bad_path, bad_path + ".bak"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(file_path))
	print("CONVERGENCE_APPLICATION ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
