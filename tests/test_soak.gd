extends SceneTree
## Bounded deterministic application soak; simulated frames, not GPU uptime.

const Main = preload("res://main.gd")
const FRAMES := 36000
const STEP := 1.0 / 60.0
var application
var checks := 0
var failures: Array = []
var receipt_path := "user://soak-receipt.json"


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--receipt="):
			receipt_path = argument.trim_prefix("--receipt=")
	_run.call_deferred()


func _run() -> void:
	var started := Time.get_ticks_usec()
	application = Main.new()
	root.add_child(application)
	application.set_process(false)
	application.load_density(128)
	application.selection.select_band(2, 9, 12)
	application.selection.set_materialisation("knot")
	var revision: String = application.dataset.manifest.revision
	var reference: Dictionary = application.selection.get_reference()
	check(application.dataset.nodes.size() == 768 and application.dataset.edges.size() == 81920,
		"Extreme density binds 768 source nodes and 81,920 exact primary edges")
	for pair in [
		["filament.wave_amplitude", 2.0], ["filament.braid_radius", 1.0],
		["filament.resonance", 1.0], ["filament.turbulence", 1.0],
		["filament.phase_speed", -8.0], ["filament.phase_frequency", 16.0],
		["filament.line_width_px", 6.0], ["filament.fibres", 4], ["filament.segments", 64],
		["optical.sky_frequency", Vector2(16.0, -16.0)], ["optical.sky_warp", 3.0],
		["optical.sky_intensity", 8.0], ["optical.normal_strength", 2.0],
		["optical.displacement", 1.0], ["optical.domain_warp", 3.0],
		["optical.roughness", 0.02], ["modulation.depth", 2.0], ["modulation.frequency", 2.0]]:
		application.set_parameter(pair[0], pair[1])
	application.set_parameter("replay.enabled", true)
	application._process(STEP)
	await process_frame
	await process_frame
	for frame in range(240):
		application._process(STEP)
	var strands_before: Dictionary = application.filaments.get_metrics()
	var proxy_before: Dictionary = application.optical.get_metrics()
	var memory_before := int(Performance.get_monitor(Performance.MEMORY_STATIC))
	var objects_before := int(Performance.get_monitor(Performance.OBJECT_COUNT))
	var maximum_memory := memory_before
	var invalid_values := 0
	var invalid_curves := 0
	var pause_preserved := true
	var frozen: Dictionary = {}
	var phase_wall_start := Time.get_ticks_usec()
	for frame in range(FRAMES):
		if frame == 9000:
			application.bus.set_clock("filament", {"rate": -8.0})
			application.bus.set_clock("sky", {"rate": 8.0})
			application.bus.set_clock("normal", {"paused": true})
			application.bus.set_clock("displacement", {"rate": -4.0})
			application.bus.set_clock("palette", {"rate": -2.0})
		elif frame == 18000:
			application.bus.paused = true
			frozen = application.bus.get_clocks()
		elif frame == 21000:
			pause_preserved = application.bus.get_clocks() == frozen
			application.bus.paused = false
			application.bus.set_clock("normal", {"paused": false, "rate": -3.0})
		elif frame == 27000:
			application.bus.set_clock("filament", {"rate": 4.0})
			application.bus.set_clock("sky", {"paused": true})
		application._process(STEP)
		if frame % 257 == 0:
			maximum_memory = maxi(maximum_memory, int(Performance.get_monitor(Performance.MEMORY_STATIC)))
			for value in application.bus.get_parameters().values():
				if not finite(value):
					invalid_values += 1
			for name in application.bus.clocks:
				if not is_finite(float(application.bus.clocks[name].time)):
					invalid_values += 1
			for edge_index in [0, 40960, 81919]:
				var edge: Dictionary = application.dataset.edges[edge_index]
				var point: Vector3 = application.filaments.curve_world_position(edge.id, 0.5)
				if not point.is_finite() or point.distance_to((edge.a + edge.b) * 0.5) > application.filaments.max_primary_offset() + 0.001:
					invalid_curves += 1
	var phase_wall_seconds := float(Time.get_ticks_usec() - phase_wall_start) / 1.0e6
	var memory_after := int(Performance.get_monitor(Performance.MEMORY_STATIC))
	var objects_after := int(Performance.get_monitor(Performance.OBJECT_COUNT))
	var strands_after: Dictionary = application.filaments.get_metrics()
	var proxy_after: Dictionary = application.optical.get_metrics()
	check(invalid_values == 0, "Extreme control values and long reversed clocks stay finite")
	check(invalid_curves == 0, "Sampled primary curves stay within analytical displacement bounds")
	check(pause_preserved, "Global pause remains exact over 3,000 simulated frames")
	check(strands_after.instance_upload_count == strands_before.instance_upload_count,
		"36,000 animation frames cause no source instance uploads")
	check(strands_after.mesh_build_count == strands_before.mesh_build_count,
		"36,000 animation frames cause no filament mesh rebuilds")
	check(proxy_after.proxy_geometry_builds == proxy_before.proxy_geometry_builds,
		"36,000 animation frames cause no optical proxy mesh rebuilds")
	check(application.selection.get_reference() == reference and application.dataset.manifest.revision == revision,
		"Source revision and exact selection survive the entire timeline sequence")
	check(memory_after - memory_before < 16 * 1024 * 1024,
		"Steady animation engine allocations remain within 16 MiB of the warmed baseline")
	check(objects_after - objects_before < 16,
		"Steady animation does not accumulate scene/resource objects")
	var curve_id: String = application.dataset.edges[12345].id
	var curve_edge: Dictionary = application.dataset.edges[12345]
	check(application.filaments.curve_world_position(curve_id, 0.0).distance_to(curve_edge.a) < 0.00001
		and application.filaments.curve_world_position(curve_id, 1.0).distance_to(curve_edge.b) < 0.00001,
		"Extreme kinetics leave source endpoints attached without stubs")
	var cycle_objects_before := int(Performance.get_monitor(Performance.OBJECT_COUNT))
	var cycle_memory_before := int(Performance.get_monitor(Performance.MEMORY_STATIC))
	for cycle in range(96):
		application.selection.set_materialisation(["knot", "ribbon", "membrane", "none"][cycle % 4])
		application._process(STEP)
		if cycle % 12 == 11:
			await process_frame
	await process_frame
	check(application.selection.get_reference() == reference, "96 materialise/unmaterialise changes retain exact source membership")
	check(application.filaments.get_metrics().instance_upload_count == strands_after.instance_upload_count,
		"Optical style changes do not upload the population of 81,920 source edges")
	check(application.selection.get_history_counts().x <= 48, "Repeated authoring keeps graphics undo bounded")
	var cycle_memory_after := int(Performance.get_monitor(Performance.MEMORY_STATIC))
	var cycle_objects_after := int(Performance.get_monitor(Performance.OBJECT_COUNT))
	check(cycle_objects_after - cycle_objects_before < 24 and cycle_memory_after - cycle_memory_before < 24 * 1024 * 1024,
		"Repeated proxy replacement releases resources instead of accumulating meshes")
	application.bus.paused = true
	application.set_parameter("filament.enabled", false)
	application.set_parameter("optical.enabled", false)
	application._process(STEP)
	var disabled_filament: Dictionary = application.filaments.get_metrics()
	var disabled_optical: Dictionary = application.optical.get_metrics()
	for frame in range(600):
		application._process(STEP)
	check(application.filaments.get_metrics().submitted_passes == 0
		and not application.optical.get_metrics().optical_visible and not application.optical.get_metrics().sky_visible,
		"Disabled layers submit no visible populations or environment pass")
	check(application.filaments.get_metrics().uniform_update_count == disabled_filament.uniform_update_count
		and application.optical.get_metrics().proxy_clock_updates == disabled_optical.proxy_clock_updates,
		"Disabled paused passes perform no repeated clock-uniform work")
	application.bus.register_source("sample", {"type": "manual", "value": 0.6})
	var empty_file := "user://soak-empty.json"
	var file := FileAccess.open(empty_file, FileAccess.WRITE)
	file.store_string(JSON.stringify({"schema": "xenovection.source.v1", "manifest": {"source_id": "soak-empty"}, "nodes": [], "edges": []}))
	file.close()
	application._import_source(empty_file)
	application._process(STEP)
	check(application.dataset.nodes.is_empty() and application.selection.get_reference().edge_ids.is_empty(),
		"Empty-source replacement clears dense selections and populations")
	check(application.bus.sources.sample.value == 0.0, "Empty-source replacement clears the prior source replay sample")
	application.load_density(48)
	application._process(STEP)
	check(application.dataset.manifest.revision == "sha256:" + Main.SourceModel.HISTORICAL_SPECIMEN_SHA256,
		"Restoring the archived source recovers its exact original revision")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(empty_file))
	var receipt := {"suite": "deterministic-adversarial-headless-soak", "status": "PASS" if failures.is_empty() else "FAIL",
		"checks": checks, "failures": failures, "simulated_steady_frames": FRAMES,
		"simulated_timeline_seconds": FRAMES * STEP, "steady_loop_wall_seconds": phase_wall_seconds,
		"total_wall_seconds": float(Time.get_ticks_usec() - started) / 1.0e6,
		"density": {"nodes": 768, "primary_edges": 81920, "secondary_fibres": strands_before.secondary_fibres,
			"segments_per_strand": strands_before.segments_per_strand, "instance_buffer_bytes_estimate": strands_before.instance_buffer_bytes_estimate},
		"steady_memory": {"before_engine_static_bytes": memory_before, "after_engine_static_bytes": memory_after,
			"peak_sampled_engine_static_bytes": maximum_memory, "before_objects": objects_before, "after_objects": objects_after},
		"proxy_cycles": {"count": 96, "before_engine_static_bytes": cycle_memory_before,
			"after_engine_static_bytes": cycle_memory_after, "before_objects": cycle_objects_before, "after_objects": cycle_objects_after},
		"source_instance_uploads_during_steady_loop": strands_after.instance_upload_count - strands_before.instance_upload_count,
		"proxy_mesh_rebuilds_during_steady_loop": proxy_after.proxy_geometry_builds - proxy_before.proxy_geometry_builds,
		"evidence_kind": "Headless actual application state/update loop; simulated fixed-step timeline, NOT wall-clock GPU uptime or target GPU performance",
		"memory_scope": "Godot engine tracked static allocations and object counts; not process RSS or total GPU VRAM"}
	file = FileAccess.open(receipt_path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(receipt, "\t"))
	print(JSON.stringify(receipt))
	application.free()
	quit(0 if failures.is_empty() else 1)


func finite(value) -> bool:
	if value is float or value is int:
		return is_finite(float(value))
	if value is Vector2 or value is Vector3:
		return value.is_finite()
	if value is Color:
		return is_finite(value.r) and is_finite(value.g) and is_finite(value.b) and is_finite(value.a)
	return false


func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		push_error("FAIL: " + label)
