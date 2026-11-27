extends SceneTree
## Actual integrated application capture; fixed simulation steps, never a speed benchmark.
## Run with tools/run_graphical.py, then encode the numbered PNGs at the stated FPS.

const Main = preload("res://main.gd")
const FPS := 24
const FRAME_COUNT := 216
const PREVIEW_FRAMES := [0, 84, 150, 200]
var application
var output_directory := "user://authoring-tour"
var provenance_path := ""
var preview := false
var stage_label: Label
var detail_label: Label


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--tour-output="):
			output_directory = argument.trim_prefix("--tour-output=")
		elif argument.begins_with("--tour-provenance="):
			provenance_path = argument.trim_prefix("--tour-provenance=")
		elif argument == "--tour-preview":
			preview = true
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("The authoring tour requires an actual graphical renderer")
		quit(2)
		return
	var provenance: Dictionary = {}
	if not provenance_path.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(provenance_path))
		if parsed is Dictionary:
			provenance = parsed
	var failures: Array = _verify_provenance(provenance) if not preview else []
	if not failures.is_empty():
		push_error("Capture source verification failed: %s" % failures)
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_directory))
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(1280, 720)
	application = Main.new()
	root.add_child(application)
	application.set_process(false)
	application.apply_preset(1)
	application.handle_action("clean")
	application.selection.select_band(2, 9, 14)
	application.selection.set_isolated(true)
	application.set_parameter("filament.nodes_visible", false)
	application.set_parameter("filament.line_width_px", 0.50)
	application.set_parameter("filament.opacity", 0.34)
	application.set_parameter("filament.wave_amplitude", 0.12)
	application.set_parameter("filament.braid_radius", 0.055)
	application.set_parameter("filament.phase_speed", 1.45)
	application.set_parameter("filament.palette_amount", 0.04)
	application.set_parameter("optical.sky_visible", true)
	application.set_parameter("optical.background_strength", 0.003)
	application.set_parameter("optical.sky_frequency", Vector2(1.5, 1.2))
	application.set_parameter("optical.sky_speed", 0.8)
	application.set_parameter("optical.sky_intensity", 2.7)
	application.set_parameter("optical.sky_contrast", 2.0)
	application.set_parameter("optical.roughness", 0.14)
	application.set_parameter("optical.normal_strength", 0.24)
	application.set_parameter("optical.displacement", 0.075)
	application.bus.enabled = false
	application.bus.paused = false
	application.bus.reset()
	application.bus.set_clock("sky", {"rate": 1.3})
	application.camera.focus_points(application.selection.get_selected_points())
	var pivot: Vector3 = application.camera.pivot
	application.camera.set_pose({"pivot": pivot, "distance": 5.9, "yaw": 0.48, "pitch": 0.27})
	application._frame_canvas()
	var reference: Dictionary = application.selection.get_reference()
	_make_captions(reference)
	var started := Time.get_ticks_usec()
	var stages: Array = []
	var captures: Array = []
	for frame in range(FRAME_COUNT):
		var time := float(frame) / float(FPS)
		if frame == 0:
			stage_label.text = "01  /  FINE CURRENTS"
			detail_label.text = "Travelling phase, opposing fibres and bounded geometric waves"
		elif frame == 60:
			application.handle_action("knot")
			application.set_parameter("filament.opacity", 0.055)
			stage_label.text = "02  /  SELECTED MATTER"
			detail_label.text = "An artistic knot proxy retains the same source IDs under moving environment light"
		elif frame == 144:
			application.handle_action("scientific")
			stage_label.text = "03  /  SCIENTIFIC"
			detail_label.text = "Artistic passes disabled; exact source topology and identity remain"
		elif frame == 180:
			application.handle_action("scientific")
			application.handle_action("unmaterialise")
			application.set_parameter("filament.opacity", 0.34)
			stage_label.text = "04  /  FILAMENTS AGAIN"
			detail_label.text = "The same selection returns to fine moving structure"
		application.camera.set_pose({"pivot": pivot, "distance": 5.9,
			"yaw": 0.48 + 0.14 * sin(time * 0.45), "pitch": 0.27 + 0.035 * sin(time * 0.33)})
		application._process(0.0 if frame == 0 else 1.0 / float(FPS))
		if frame in [0, 60, 144, 180, FRAME_COUNT - 1]:
			var same: bool = application.selection.get_reference() == reference
			if not same:
				failures.append("Source selection changed at frame %d" % frame)
			stages.append({"frame": frame, "simulation_seconds": time, "caption": stage_label.text,
				"selection_unchanged": same, "scientific": application.scientific,
				"visual_state": application.selection.get_visual_state(),
				"filaments": application.filaments.get_metrics(), "optical": application.optical.get_metrics(),
				"clocks": application.bus.get_clocks(), "camera": Main._encode(application.camera.get_pose())})
		if preview and not frame in PREVIEW_FRAMES:
			continue
		await process_frame
		await RenderingServer.frame_post_draw
		var image: Image = root.get_texture().get_image()
		var frame_path := output_directory.path_join("frame-%04d.png" % frame)
		if image.get_size() != Vector2i(1280, 720):
			failures.append("Unexpected actual render target: %s" % image.get_size())
		if image.save_png(frame_path) != OK:
			failures.append("Could not write frame %d" % frame)
		captures.append({"frame": frame, "file": frame_path.get_file(), "sha256": FileAccess.get_sha256(frame_path)})
		if frame % 48 == 0:
			print("AUTHORING_TOUR_FRAME ", frame, "/", FRAME_COUNT)
	if not preview:
		failures.append_array(_verify_provenance(provenance))
	var receipt := {"schema": "xenovection.authoring-capture.v1", "status": "PASS" if failures.is_empty() else "FAIL",
		"capture_kind": "Actual Godot main application rendered on software Vulkan at fixed simulation steps; NOT real-time playback throughput",
		"godot": Engine.get_version_info().string, "renderer": RenderingServer.get_current_rendering_method(),
		"engine_binary_sha256": FileAccess.get_sha256(OS.get_executable_path()),
		"device": RenderingServer.get_video_adapter_name(), "display": DisplayServer.get_name(),
		"playback_fps": FPS, "frame_count": captures.size(), "timeline_frame_count": FRAME_COUNT,
		"timeline_duration_seconds": float(FRAME_COUNT) / float(FPS), "resolution": [1280, 720],
		"actual_capture_wall_seconds": float(Time.get_ticks_usec() - started) / 1000000.0,
		"preview": preview, "implementation": provenance, "build_at_start": application._build,
		"source_manifest": application.dataset.manifest, "selection": reference,
		"selection_preserved_at_all_transitions": failures.is_empty(), "stages": stages,
		"captured_frames": captures, "failures": failures}
	var file := FileAccess.open(output_directory.path_join("receipt.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(receipt, "\t"))
	print("AUTHORING_TOUR_DONE ", JSON.stringify({"status": receipt.status, "frames": captures.size(), "wall_seconds": receipt.actual_capture_wall_seconds, "failures": failures}))
	application.free()
	quit(0 if failures.is_empty() else 1)


func _verify_provenance(provenance: Dictionary) -> Array:
	# Full captures require a clean committed source inventory, independently hashed
	# by the caller from git ls-files. Check the real files both before and after
	# rendering so a concurrently edited workspace cannot silently inherit its SHA.
	var failures: Array = []
	if provenance.get("schema", "") != "xenovection.capture-provenance.v1" \
		or provenance.get("repository", "") != "https://github.com/techrote/Xenovection" \
		or provenance.get("tracked_source_clean", false) != true:
		return ["A verified clean Xenovection source manifest is required for full capture"]
	for key in ["source_sha", "tree_sha"]:
		var value = provenance.get(key, "")
		if not value is String or value.length() != 40 or not value.is_valid_hex_number(false):
			failures.append("Invalid implementation revision: " + key)
	var files = provenance.get("files", {})
	if not files is Dictionary or files.is_empty() or files.size() > 256:
		return ["A bounded source-file SHA-256 inventory is required"]
	for required in ["app/main.gd", "app/core/source_model.gd", "app/data/synthetic_foundry.json",
		"app/rendering/filaments/filament.gdshader", "app/rendering/optical/optical_layer.gd",
		"tools/capture_authoring_tour.gd"]:
		if not files.has(required):
			failures.append("Missing required source fingerprint: " + required)
	for path in files:
		if not path is String or path.contains("..") \
			or not (path.begins_with("app/") or path == "tools/capture_authoring_tour.gd"):
			failures.append("Unsupported source inventory path")
			continue
		var local_path: String = "res://" + path.trim_prefix("app/") if path.begins_with("app/") else "res://../" + path
		if not FileAccess.file_exists(local_path) or FileAccess.get_sha256(local_path) != str(files[path]):
			failures.append("Source bytes changed: " + path)
	if provenance.get("engine_binary_sha256", "") != FileAccess.get_sha256(OS.get_executable_path()):
		failures.append("Capture engine executable differs from the declared runtime")
	return failures


func _make_captions(reference: Dictionary) -> void:
	var layer := CanvasLayer.new()
	root.add_child(layer)
	var title := _label("X E N O V E C T I O N", Vector2(34, 23), 22, Color(0.35, 0.93, 0.90))
	layer.add_child(title)
	stage_label = _label("", Vector2(34, 61), 17, Color(0.86, 0.94, 0.96))
	layer.add_child(stage_label)
	detail_label = _label("", Vector2(34, 88), 14, Color(0.50, 0.65, 0.70))
	layer.add_child(detail_label)
	layer.add_child(_label("%d source nodes  /  %d exact edges  /  IDs retained" % [reference.node_ids.size(), reference.edge_ids.size()],
		Vector2(34, 638), 15, Color(0.45, 0.87, 0.84)))
	layer.add_child(_label("FIXED-STEP SOFTWARE VULKAN CAPTURE  ·  24 fps playback  ·  not real-time throughput",
		Vector2(34, 671), 13, Color(0.48, 0.58, 0.63)))


func _label(text_value: String, point: Vector2, size_value: int, colour: Color) -> Label:
	var label := Label.new()
	label.text = text_value
	label.position = point
	label.add_theme_font_size_override("font_size", size_value)
	label.add_theme_color_override("font_color", colour)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
