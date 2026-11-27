extends SceneTree
## Real graphical event routing through Input.parse_input_event, not direct actions.

const Main = preload("res://main.gd")
var application
var checks := 0
var failures: Array = []
var output_prefix := "user://gui-input"


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output-prefix="):
			output_prefix = argument.trim_prefix("--output-prefix=")
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("GUI input probe requires a real graphical display")
		quit(2)
		return
	application = Main.new()
	root.add_child(application)
	root.grab_focus()
	var scene_existed := FileAccess.file_exists("user://scene.json")
	var previous_scene := FileAccess.get_file_as_bytes("user://scene.json") if scene_existed else PackedByteArray()
	await frames(6)
	var original_revision: String = application.dataset.manifest.revision
	# Choose a canvas-only rectangle around projected middle layers, away from HUD.
	var start := Vector2(250, 200)
	var end := Vector2(920, 560)
	var camera_before: Transform3D = application.camera.global_transform
	await motion(start, start)
	await button(start, MOUSE_BUTTON_LEFT, true)
	await motion(start, end, MOUSE_BUTTON_MASK_LEFT)
	await button(end, MOUSE_BUTTON_LEFT, false)
	var reference: Dictionary = application.selection.get_reference()
	check(not reference.node_ids.is_empty() and not reference.edge_ids.is_empty(), "Real canvas drag selects an exact through-depth source region")
	check(not application._dragging and not application.camera.is_navigating(), "Selection release relinquishes gesture ownership")
	check(application.camera.global_transform.is_equal_approx(camera_before), "Box selection does not rotate or pan the camera")
	await click_control("Knot")
	check(application.selection.get_visual_state().materialisation == "knot", "Knot UI button materialises the selected region")
	check(application.selection.get_reference() == reference, "UI materialisation preserves exact source selection")
	check(not application._dragging and not application.camera.is_navigating(), "Knot UI button does not start canvas/camera drag")
	await click_control("Filaments")
	check(application.selection.get_visual_state().materialisation == "none", "Filaments UI button removes the optical proxy")
	check(application.selection.get_reference() == reference, "Returning to filaments preserves source identity")
	await key(KEY_G)
	check(application.scientific and not application.optical.get_metrics().optical_visible
		and application.filaments.get_metrics().secondary_fibres == 0, "Actual G key disables artistic passes")
	await key(KEY_SPACE)
	var frozen: Dictionary = application.bus.get_clocks()
	await frames(3)
	check(application.bus.paused and application.bus.get_clocks() == frozen, "Actual Space key pauses all clocks")
	await key(KEY_SPACE)
	await key(KEY_G)
	var canvas := Vector2(700, 320)
	await motion(canvas, canvas)
	await button(canvas, MOUSE_BUTTON_RIGHT, true)
	check(application.camera.is_navigating() and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "RMB on the canvas captures fly navigation")
	await button(canvas, MOUSE_BUTTON_RIGHT, false)
	check(not application.camera.is_navigating() and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED, "RMB release restores the pointer")
	var knot: Button = find_button(application.ui, "Knot")
	var control_point := knot.get_global_rect().get_center()
	await motion(canvas, control_point)
	await button(control_point, MOUSE_BUTTON_RIGHT, true)
	check(not application.camera.is_navigating(), "RMB over an actual UI control cannot capture the scene camera")
	await button(control_point, MOUSE_BUTTON_RIGHT, false)
	root.size = Vector2i(1100, 700)
	await frames(4)
	await key(KEY_R)
	await frames(3)
	check(application.dataset.manifest.revision == original_revision and not application.camera.is_navigating(), "Resize followed by reset preserves source and releases navigation")
	check(application.ui.rail.get_global_rect().end.x <= root.get_visible_rect().size.x + 1.0,
		"Instrument controls remain within the resized viewport")
	# Start a real selection gesture, then emulate the OS focus-out notification.
	await motion(Vector2(400, 300), Vector2(400, 300))
	await button(Vector2(400, 300), MOUSE_BUTTON_LEFT, true)
	check(application._dragging, "Canvas owns an active left-drag gesture")
	application.propagate_notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	await frames(1)
	check(not application._dragging, "Focus loss cancels a selection gesture without waiting for mouse-up")
	await button(Vector2(400, 300), MOUSE_BUTTON_LEFT, false)
	await key(KEY_ESCAPE)
	await frames(2)
	# Optical-only source group picking uses the actual canvas event path.
	await key(KEY_3)
	application.set_parameter("optical.displacement", 0.0)
	if not application.bus.paused:
		await key(KEY_SPACE)
	await frames(2)
	var optical_reference: Dictionary = application.selection.get_reference()
	var optical_state: Dictionary = application.selection.get_visual_state()
	var optical_history: Vector2i = application.selection.get_history_counts()
	var proxy_point := proxy_canvas_point()
	check(proxy_point.x >= 0.0, "Optical proxy has an actual visible mesh hit inside the interactive canvas")
	if proxy_point.x >= 0.0:
		await motion(proxy_point, proxy_point)
		await button(proxy_point, MOUSE_BUTTON_LEFT, true)
		await button(proxy_point, MOUSE_BUTTON_LEFT, false)
	check(application.selection.get_reference() == optical_reference
		and application.selection.get_visual_state() == optical_state
		and application.selection.get_history_counts() == optical_history and not application._dragging,
		"Real optical-only proxy click retains full exact group, origin, materialisation and history")
	await key(KEY_U)
	check(application.selection.get_reference() == optical_reference
		and application.filaments.get_metrics().primary_edges > 0
		and not application.optical.get_metrics().optical_visible,
		"Actual U key returns an optical-only preset to visible fine filaments with unchanged source IDs")
	# Same-source preset changes allow recall to prove that labels are restored.
	await key(KEY_1)
	await key(KEY_F5)
	await key(KEY_2)
	await key(KEY_F6)
	check(application.preset_index == 0 and application.ui.preset_picker.selected == 0
		and application.ui.subtitle_label.text == str(application.presets[0].description).to_upper(),
		"Actual F5/F6 restores the saved preset label after another preset on the same source")
	# The new non-layered specimen uses a generic nearest spatial region.
	await key(KEY_7)
	await key(KEY_M)
	var flow_reference: Dictionary = application.selection.get_reference()
	var flow_state: Dictionary = application.selection.get_visual_state()
	check(application.dataset.nodes.size() == 4608 and application.dataset.edges.size() == 6144
		and flow_reference.node_ids.size() == 96 and not flow_reference.edge_ids.is_empty()
		and flow_state.selection_origin == "nearest-spatial-region-induced-edges"
		and flow_state.materialisation == "knot",
		"Key7 then M selects and materialises a generic nearest spatial region with exact induced edges")
	await key(KEY_U)
	check(application.selection.get_reference() == flow_reference
		and application.selection.get_visual_state().materialisation == "none"
		and application.filaments.get_metrics().primary_edges == 6144,
		"Spatial materialisation returns to all fine source curves without ID changes")
	await key(KEY_F5)
	var flow_saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("user://scene.json"))
	check(flow_saved.source_revision == application.dataset.manifest.revision
		and flow_saved.source_projection_revision == application.dataset.manifest.projection_revision
		and int(flow_saved.preset_index) == 6, "F5 stores exact spatial source, projection and preset identity")
	await key(KEY_3)
	var incompatible_reference: Dictionary = application.selection.get_reference()
	await key(KEY_F6)
	check(application.selection.get_reference() == incompatible_reference and application.preset_index == 2,
		"F6 refuses a saved flow scene on the historical source without mutating selection or preset")
	await key(KEY_7)
	await key(KEY_F6)
	check(application.selection.get_reference() == flow_reference and application.preset_index == 6
		and application.ui.preset_picker.selected == 6
		and application.ui.subtitle_label.text == str(application.presets[6].description).to_upper(),
		"F6 restores exact flow IDs and preset label after its correct source is reloaded")
	var original_flow: Dictionary = application.dataset
	var reprojected: Dictionary = original_flow.duplicate(true)
	reprojected.manifest.erase("content_sha256")
	reprojected.nodes[0].position += Vector3(0.0, 0.1, 0.0)
	application.source.set_validated(reprojected)
	application._bind_source()
	await frames(1)
	var changed_projection: String = application.dataset.manifest.projection_revision
	var projected_reference: Dictionary = application.selection.get_reference()
	await key(KEY_F6)
	check(application.dataset.manifest.revision == original_flow.manifest.revision
		and changed_projection != original_flow.manifest.projection_revision
		and application.dataset.manifest.projection_revision == changed_projection
		and application.selection.get_reference() == projected_reference,
		"F6 refuses a different artistic projection even when scientific source identity is unchanged")
	application.source.set_validated(original_flow)
	application._bind_source()
	await key(KEY_F6)
	check(application.selection.get_reference() == flow_reference,
		"Exact source projection restoration makes the saved flow scene usable again")
	await frames(2)
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	var capture_error := image.save_png(output_prefix + ".png")
	var receipt := {"suite": "graphical-input-routing", "status": "PASS" if failures.is_empty() else "FAIL",
		"checks": checks, "passed": checks - failures.size(), "failures": failures,
		"display": DisplayServer.get_name(), "renderer": RenderingServer.get_current_rendering_method(),
		"device": RenderingServer.get_video_adapter_name(), "capture_result": capture_error,
		"viewport": [root.get_visible_rect().size.x, root.get_visible_rect().size.y],
		"source_revision": application.dataset.manifest.revision,
		"evidence_kind": "Real graphical event routing on software Vulkan; not owner TITAN RTX performance"}
	var file := FileAccess.open(output_prefix + ".json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(receipt, "\t"))
	if scene_existed:
		var scene_file := FileAccess.open("user://scene.json", FileAccess.WRITE)
		scene_file.store_buffer(previous_scene)
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://scene.json"))
	print(JSON.stringify(receipt))
	application.free()
	quit(0 if failures.is_empty() else 1)


func frames(count: int) -> void:
	for frame in range(count):
		await process_frame


func proxy_canvas_point() -> Vector2:
	var surface: MeshInstance3D = application.optical.get_node("SelectedArtisticProxy")
	if surface.mesh == null:
		return Vector2(-1.0, -1.0)
	var arrays: Array = surface.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var safe_canvas := Rect2(70.0, 100.0,
		application.ui.rail.get_global_rect().position.x - 110.0, root.get_visible_rect().size.y - 230.0)
	var stride := maxi(1, indices.size() / (3 * 64)) * 3
	for index in range(0, indices.size() - 2, stride):
		var world: Vector3 = surface.global_transform * ((vertices[indices[index]]
			+ vertices[indices[index + 1]] + vertices[indices[index + 2]]) / 3.0)
		if application.camera.is_position_behind(world):
			continue
		var point: Vector2 = application.camera.unproject_position(world)
		if not safe_canvas.has_point(point):
			continue
		var hit: Dictionary = application.optical.ray_pick_proxy(application.camera.project_ray_origin(point),
			application.camera.project_ray_normal(point), application.camera.far)
		if not hit.is_empty():
			return point
	return Vector2(-1.0, -1.0)


func button(point: Vector2, index: MouseButton, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = root.get_screen_transform() * point
	event.global_position = event.position
	event.button_index = index
	event.pressed = pressed
	event.button_mask = (MOUSE_BUTTON_MASK_LEFT if index == MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_RIGHT) if pressed else 0
	Input.parse_input_event(event)
	await frames(1)


func motion(from: Vector2, to: Vector2, mask: int = 0) -> void:
	var event := InputEventMouseMotion.new()
	event.position = root.get_screen_transform() * to
	event.global_position = event.position
	event.relative = to - from
	event.screen_relative = to - from
	event.button_mask = mask
	Input.parse_input_event(event)
	await frames(1)


func key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	await frames(1)
	event = InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = false
	Input.parse_input_event(event)
	await frames(1)


func click_control(text_value: String) -> void:
	var control: Button = find_button(application.ui, text_value)
	if control == null:
		check(false, "Control exists: " + text_value)
		return
	var point := control.get_global_rect().get_center()
	await motion(point, point)
	await button(point, MOUSE_BUTTON_LEFT, true)
	await button(point, MOUSE_BUTTON_LEFT, false)
	await frames(1)


func find_button(node: Node, text_value: String) -> Button:
	if node is Button and node.text == text_value:
		return node
	for child in node.get_children():
		var found := find_button(child, text_value)
		if found != null:
			return found
	return null


func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		push_error("FAIL: " + label)
