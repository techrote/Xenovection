extends SceneTree
## Reproduce actual-renderer optical A/B captures and timings without the main UI.
## godot --path app --script res://rendering/optical/capture_studies.gd -- --output=/absolute/path --frames=180
## A software Vulkan device remains software evidence, never target-GPU evidence.

const Optical := preload("res://rendering/optical/optical_layer.gd")
const Source := preload("res://core/source_model.gd")
const Recorder := preload("res://diagnostics/frame_recorder.gd")
const Filaments := preload("res://rendering/filaments/filament_renderer.gd")
const STUDIES := [
	{"id": "disabled", "parameters": {"enabled": false}, "clocks": []},
	{"id": "environment_only", "parameters": {"enabled": true}, "clocks": ["sky"]},
	{"id": "normal_only", "parameters": {"normal_strength": 0.55}, "clocks": ["normal"]},
	{"id": "domain_only", "parameters": {"domain_warp": 1.0, "sky_speed": 0.0}, "clocks": ["sky"]},
	{"id": "displacement_only", "parameters": {"displacement": 0.5}, "clocks": ["displacement"]},
	{"id": "combined", "parameters": {"normal_strength": 0.55, "displacement": 0.4, "domain_warp": 0.6}, "clocks": ["sky", "normal", "displacement", "palette"]},
]
var output := "user://optical-studies"
var frames := 180

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Optical capture requires an actual display/rendering device; headless is not graphical qualification.")
		quit(2)
		return
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			output = argument.trim_prefix("--output=")
		elif argument.begins_with("--frames="):
			frames = clampi(int(argument.trim_prefix("--frames=")), 30, 1800)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	root.size = Vector2i(1120, 800)
	root.content_scale_size = Vector2i.ZERO
	root.msaa_3d = Viewport.MSAA_4X
	var stage := Node3D.new()
	root.add_child(stage)
	var source := Source.new()
	var loaded: Dictionary = source.load_json("res://data/synthetic_foundry.json")
	if not loaded.ok:
		push_error(str(loaded))
		quit(1)
		return
	var data: Dictionary = source.get_dataset()
	var nodes: Array = []
	var edges: Array = []
	var center := Vector3.ZERO
	for node in data.nodes:
		if int(node.layer) in [2, 3] and int(node.channel) < 12:
			nodes.append(node.id)
			center += node.position
	center /= nodes.size()
	for edge in data.edges:
		if edge.source in nodes and edge.target in nodes:
			edges.append(edge.id)
	var camera := Camera3D.new()
	camera.fov = 44.0
	stage.add_child(camera)
	camera.position = center + Vector3(2.3, 1.45, 4.0)
	camera.look_at(center)
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color(0.003, 0.007, 0.014)
	world.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world.environment.tonemap_exposure = 0.8
	stage.add_child(world)
	var optical := Optical.new()
	stage.add_child(optical)
	optical.set_dataset(data)
	optical.set_visual_state({"node_ids": nodes, "edge_ids": edges, "materialisation": "knot"})
	var recorder := Recorder.new()
	recorder.setup(root)
	var receipts: Array = []
	for study: Dictionary in STUDIES:
		var parameters: Dictionary = Optical.DEFAULTS.duplicate(true)
		parameters.merge({"normal_strength": 0.0, "displacement": 0.0, "domain_warp": 0.0}, true)
		parameters.merge(study.parameters, true)
		optical.set_parameters(parameters)
		optical.update_clocks({"sky": 0.0, "normal": 0.0, "displacement": 0.0, "palette": 0.0})
		for i in range(24):
			await process_frame
		if study.id == "environment_only":
			await _capture("environment_t0")
		recorder.reset()
		for i in range(frames):
			var started := Time.get_ticks_usec()
			var clocks := {"sky": 0.0, "normal": 0.0, "displacement": 0.0, "palette": 0.0}
			for key: String in study.clocks:
				clocks[key] = float(i) * 3.0 / float(frames - 1)
			optical.update_clocks(clocks)
			var update_usec := Time.get_ticks_usec() - started
			await process_frame
			recorder.sample(update_usec)
		var receipt: Dictionary = recorder.snapshot({
			"study": study.id, "parameters_changed_from_environment_baseline": study.parameters,
			"advancing_clocks": study.clocks, "clock_interval_seconds": [0.0, 3.0],
			"viewport_pixels": [1120, 800], "msaa": "4x",
			"source_revision": data.manifest.revision, "node_ids": nodes, "edge_ids": edges,
			"optical": optical.get_metrics(), "claim_scope": "Only the recorded device/platform; not implied target-hardware performance"})
		receipts.append(receipt)
		_save_json("performance_" + str(study.id) + ".json", receipt)
		await _capture(str(study.id))
		print("OPTICAL_STUDY ", study.id, " ", JSON.stringify(receipt.wall_frame))
	optical.set_parameters(Optical.DEFAULTS)
	camera.position = center + Vector3(5.0, 3.0, 8.5)
	camera.look_at(center)
	for kind in ["ribbon", "membrane"]:
		optical.set_visual_state({"materialisation": kind})
		for i in range(8):
			await process_frame
		await _capture(kind)
		if kind == "membrane":
			optical.set_parameters({"surface_opacity": 0.55})
			for i in range(8):
				await process_frame
			await _capture("membrane_translucent")
			optical.set_parameters({"surface_opacity": 1.0})
	_save_json("performance_all.json", receipts)
	# Regression: the fullscreen environment must never overwrite alpha hairlines.
	# Nodes/proxies are disabled so a changed image can only come from source edges.
	optical.set_visual_state({"materialisation": "none"})
	optical.update_clocks({"sky": 0.0, "normal": 0.0, "displacement": 0.0, "palette": 0.0})
	var selected_edges: Array = []
	for edge in data.edges:
		if edge.id in edges:
			selected_edges.append(edge)
	var filaments := Filaments.new()
	stage.add_child(filaments)
	filaments.set_dataset({"manifest": data.manifest, "nodes": data.nodes, "edges": selected_edges})
	filaments.set_parameters({"enabled": false, "nodes_visible": false, "fibres": 0,
		"scientific": true, "line_width_px": 1.5, "opacity": 0.8, "intensity": 1.0})
	for i in range(6):
		await process_frame
	var background_only := await _capture("regression_background_only")
	filaments.set_parameters({"enabled": true})
	for i in range(6):
		await process_frame
	var with_filaments := await _capture("regression_background_with_filaments")
	var changed := _changed_pixels(background_only, with_filaments)
	var regression := {"check": "background_preserves_source_hairlines", "changed_pixels": changed,
		"minimum_changed_pixels": 50, "passed": changed > 50, "source_edges": selected_edges.size(),
		"nodes_visible": false, "optical_proxy_visible": false}
	_save_json("background_composition_check.json", regression)
	print("OPTICAL_COMPOSITION ", JSON.stringify(regression))
	quit(0 if changed > 50 else 1)

func _capture(name: String) -> Image:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var result := image.save_png(output.path_join(name + ".png"))
	if result != OK:
		push_error("Could not save optical capture: " + name)
	return image

func _changed_pixels(a: Image, b: Image) -> int:
	if a.get_size() != b.get_size():
		return 0
	a.convert(Image.FORMAT_RGB8)
	b.convert(Image.FORMAT_RGB8)
	var before := a.get_data()
	var after := b.get_data()
	var changed := 0
	for i in range(0, before.size(), 3):
		if absi(int(before[i]) - int(after[i])) + absi(int(before[i + 1]) - int(after[i + 1])) + absi(int(before[i + 2]) - int(after[i + 2])) > 12:
			changed += 1
	return changed

func _save_json(name: String, value: Variant) -> void:
	var file := FileAccess.open(output.path_join(name), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(value, "\t"))
