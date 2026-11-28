extends SceneTree
## Build a new four-domain composition through the actual authoring widgets.
var app
var checks := 0
var failures: Array[String] = []
var prefix := "user://gui-convergence"
var input_events := 0
var previous_save := PackedByteArray()
var had_save := false
var interaction_trace: Array[Dictionary] = []
var captured_menu_failure := false
var last_click_hold_usec := 0

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output-prefix="):
			prefix = argument.trim_prefix("--output-prefix=")
	_run.call_deferred()

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		quit(2)
		return
	had_save = FileAccess.file_exists("user://scene.json")
	if had_save: previous_save = FileAccess.get_file_as_bytes("user://scene.json")
	app = load("res://main.tscn").instantiate()
	root.add_child(app)
	root.grab_focus()
	await frames(6)
	await choose(app.ui.preset_picker, app.Catalogue.index_of(app.presets, "living"))
	check(app.presets[app.preset_index].id == "living" and app.matter.active, "Pointer recalls an inherited editable matter scene")
	var source_identity: String = app.dataset.manifest.revision
	await key(KEY_F2)
	await slider(app.ui._controls["matter.edit.condensation"].input, 0.5)
	await slider(app.ui._controls["matter.edit.optical_mix"].input, 1.0)
	await key(KEY_F3)
	var master: BaseButton = app.ui._controls["optical.enabled"].input
	check(await expose(master), "Real scrolling exposes the optical environment master")
	if not master.button_pressed: await click(master.get_global_rect().get_center())
	await slider(app.ui._controls["optical.optical_mix"].input, 1.0)
	await key(KEY_F4)
	await click_button("Show spatial ecology")
	check(app.ecology.simulation_enabled and app.spatial_ecology.visible, "Pointer enables living spatial matter without replacing the procedural composition")
	await click_button("Pause ecology")
	check(app.ecology.paused, "Ecology transport has independent real authoring control")
	await key(KEY_F7)
	await click_button("Blank")
	await click_button("New component")
	var panel = app.synth_panel
	await choose(panel.kind_picker, app.SynthGraph.KINDS.find("manual"))
	await type_number(panel.value, "0.65")
	await click_button("Apply component")
	check(app.synth.nodes.size() == 1 and app.synth.nodes.source1.kind == "manual", "Actual widgets create one manual source in the shared graph")
	check(is_equal_approx(float(app.synth.nodes.source1.value), 0.65), "Actual numeric entry authors the manual performance value")
	for destination in ["matter.region0.condensation", "optical.optical_thickness", "eco.growth"]:
		await click_button("New route")
		await type_line(panel.target_search, destination)
		await choose(panel.target_picker, 0)
		await type_number(panel.amplitude, "0.15")
		await click_button("Apply route")
		var found := false
		for route in app.synth.patch.get("routes", []):
			found = found or route.target == destination
		check(found, "Real route authoring binds " + destination)
	await click_button("Undo")
	check(app.synth.patch.routes.size() == 2, "Graph Undo removes only the latest authored route")
	await click_button("Redo")
	check(app.synth.patch.routes.size() == 3, "Graph Redo restores the cross-domain route")
	await frames(5)
	check(app.bus == app.ecology.bus and app.synth.missing_targets.is_empty(), "One authoritative registry resolves all authored domains")
	var enabled_routes := 0
	var only_shared_routes := true
	for route in app.bus.routes:
		if route.enabled:
			enabled_routes += 1
			only_shared_routes = only_shared_routes and str(route.id).begins_with(app.SynthGraph.PREFIX)
	check(enabled_routes == 3 and only_shared_routes, "Shared patch replaces active stock routing without stacking hidden routes")
	var geometry: int = app.matter.regions[0].builds
	var proxy_builds: int = app.optical.get_metrics().proxy_geometry_builds
	var effective: Dictionary = app.bus.get_parameters()
	for destination in ["matter.region0.condensation", "optical.optical_thickness", "eco.growth"]:
		check(float(effective[destination]) > float(app.bus.get_base(destination)), "Authored manual modulation resolves into " + destination)
	await frames(15)
	check(app.matter.regions[0].builds == geometry and app.optical.get_metrics().proxy_geometry_builds == proxy_builds, "Ordinary cross-domain modulation reuses existing geometry")
	await key(KEY_F4)
	var tick: int = app.ecology.world.tick
	await click_button("Step ecology")
	check(app.ecology.world.tick == tick + 1, "Actual ecology step samples the graph at exactly one fixed boundary")
	check(is_equal_approx(float(app.ecology.world.effective.growth), float(app.bus.get_parameters()["eco.growth"])), "The solver receives the resolved shared growth value at its boundary")
	await key(KEY_F5)
	check(FileAccess.file_exists("user://scene.json"), "Real F5 writes the unified authored composition")
	var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://scene.json"))
	check(saved is Dictionary and saved.schema == "xenovection.scene.v2" and saved.ecology.enabled and saved.synth_patch.routes.size() == 3,
		"The saved composition includes matter, optics, synthesis and ecology")
	await choose(app.ui.preset_picker, app.Catalogue.index_of(app.presets, "scientific"))
	check(app.scientific and not app.ecology.simulation_enabled, "Actual scientific recall isolates the original source")
	await key(KEY_F6)
	await frames(5)
	check(app.presets[app.preset_index].id == "living" and app.ecology.simulation_enabled and app.ecology.paused and app.synth.patch.routes.size() == 3,
		"Actual F6 reconstructs the authored four-domain composition after another scene")
	check(app.dataset.manifest.revision == source_identity and app.ecology.world.tick == 0, "Recall preserves exact source and explicitly restarts numerical history")
	check(app.matter.regions[0].shader.get_shader_parameter("xeno_optical_mix") > 0.99, "Recalled generated matter retains shared optical assignment")
	await key(KEY_F7)
	await capture(prefix + "-authoring.png")
	await key(KEY_H)
	await frames(3)
	var composition: Image = await capture(prefix + "-composition.png")
	check(visible_samples(composition) > 80, "The graphically authored integrated composition renders visible matter")
	var receipt := {"suite": "graphical-integrated-authoring", "status": "PASS" if failures.is_empty() else "FAIL",
		"checks": checks, "passed": checks - failures.size(), "failures": failures, "input_events": input_events,
		"interaction_trace": interaction_trace,
		"composition_id": app.presets[app.preset_index].stable_id, "graph": app.synth.metrics(),
		"ecology": app.ecology.convergence_metrics(), "matter": app.matter.metrics(),
		"source_revision": source_identity, "renderer": RenderingServer.get_current_rendering_method(),
		"device": RenderingServer.get_video_adapter_name(), "build": app._build}
	var file := FileAccess.open(prefix + ".json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(receipt, "\t"))
		file.close()
	if had_save:
		var restore := FileAccess.open("user://scene.json", FileAccess.WRITE)
		restore.store_buffer(previous_save)
		restore.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://scene.json"))
	print("CONVERGENCE_GUI ", JSON.stringify(receipt))
	app.free()
	await frames(2)
	quit(0 if failures.is_empty() else 1)

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures.append(description)
		print("FAIL: ", description)

func find_button(node: Node, text_value: String) -> Button:
	if node is Button and node.text == text_value and node.is_visible_in_tree():
		return node
	for child in node.get_children():
		var result := find_button(child, text_value)
		if result != null: return result
	return null

func click_button(label: String) -> void:
	var control := find_button(app, label)
	check(control != null, "Exposed authoring control: " + label)
	if control == null: return
	check(await expose(control), "Real scrolling exposes " + label)
	var before := control.get_global_rect()
	await click(control.get_global_rect().get_center())
	await frames(2)
	interaction_trace.append({"event": "button", "label": label, "rect_before": str(before),
		"rect_after": str(control.get_global_rect()), "form": form_state()})

func form_state() -> Dictionary:
	var panel = app.synth_panel
	return {"source_id": panel.source_id, "source_count": app.synth.nodes.size(),
		"kind_index": panel.kind_picker.selected, "value": panel.value.value,
		"value_text": panel.value.get_line_edit().text, "sequencer_steps": panel.steps.text,
		"status": panel.status.text, "search": panel.target_search.text,
		"route_count": app.synth.patch.get("routes", []).size()}

func expose(control: Control) -> bool:
	var parent: Node = control.get_parent()
	while parent != null and not parent is ScrollContainer:
		parent = parent.get_parent()
	if not parent is ScrollContainer: return control.is_visible_in_tree()
	var scroll: ScrollContainer = parent
	for attempt in range(100):
		var area := scroll.get_global_rect().grow(-8.0)
		var point := control.get_global_rect().get_center()
		if area.has_point(point): return true
		var position := Vector2(scroll.get_global_rect().end.x - 4.0, area.get_center().y)
		var direction := MOUSE_BUTTON_WHEEL_DOWN if point.y > area.end.y else MOUSE_BUTTON_WHEEL_UP
		await motion(position)
		await mouse(position, direction, true, 4.0 if absf(point.y - area.get_center().y) > 350 else 1.0)
		await mouse(position, direction, false)
	return false

func choose(control: OptionButton, index: int) -> void:
	check(index >= 0 and index < control.item_count, "Requested option exists")
	if index < 0 or index >= control.item_count: return
	check(await expose(control), "Real scrolling exposes option picker")
	var trace := {"event": "option", "path": str(control.get_path()),
		"requested": index, "requested_text": control.get_item_text(index),
		"selected_before": control.selected, "visible_in_tree": control.is_visible_in_tree(),
		"popup_before_pointer": control.get_popup().visible,
		"disabled": control.disabled, "rect_before": str(control.get_global_rect()),
		"screen_transform": str(root.get_screen_transform()), "form_before": form_state()}
	interaction_trace.append(trace)
	await click(control.get_global_rect().get_center())
	var popup := control.get_popup()
	trace.rect_after = str(control.get_global_rect())
	trace.popup_visible = popup.visible
	trace.popup_window_id = popup.get_window_id()
	trace.popup_position = str(popup.position)
	trace.popup_size = str(popup.size)
	trace.click_hold_usec = last_click_hold_usec
	trace.selected_after_pointer = control.selected
	trace.focused_items = [popup.get_focused_item()]
	check(popup.visible, "Actual pointer opens option menu")
	if not popup.visible:
		print("CONVERGENCE_FIRST_MENU_FAILURE ", JSON.stringify(trace))
		if not captured_menu_failure and DisplayServer.get_name() != "headless":
			captured_menu_failure = true
			await capture(prefix + "-first-menu-failure.png")
		return
	for attempt in range(control.item_count + 3):
		if popup.get_focused_item() == index: break
		await key(KEY_DOWN if popup.get_focused_item() < index else KEY_UP)
		trace.focused_items.append(popup.get_focused_item())
	await key(KEY_ENTER)
	await frames(3)
	trace.selected_after_keyboard = control.selected
	trace.form_after = form_state()
	check(control.selected == index, "Actual keyboard commits the selected option")

func slider(control: HSlider, fraction: float) -> void:
	check(await expose(control), "Real scrolling exposes material control")
	var rect := control.get_global_rect()
	await click(Vector2(lerpf(rect.position.x + 1, rect.end.x - 1, fraction), rect.get_center().y))
	await frames(3)

func type_number(control: SpinBox, value: String) -> void:
	await type_line(control.get_line_edit(), value)
	await key(KEY_ENTER)
	await frames(2)

func type_line(control: LineEdit, value: String) -> void:
	check(await expose(control), "Real scrolling exposes text input")
	await click(control.get_global_rect().get_center())
	await key(KEY_A, true)
	for character in value:
		for pressed in [true, false]:
			var event := InputEventKey.new()
			event.pressed = pressed
			event.unicode = character.unicode_at(0)
			event.keycode = character.to_upper().unicode_at(0)
			Input.parse_input_event(event)
			input_events += 1
		await frames(1)
	await frames(2)

func key(code: Key, control := false, window_id := 0) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.window_id = window_id
		event.keycode = code
		event.physical_keycode = code
		event.ctrl_pressed = control
		event.pressed = pressed
		Input.parse_input_event(event)
		input_events += 1
		await frames(1)

func motion(point: Vector2) -> void:
	var mapped := root.get_screen_transform() * point
	var event := InputEventMouseMotion.new()
	event.position = mapped
	event.global_position = mapped
	Input.parse_input_event(event)
	input_events += 1
	await frames(1)

func mouse(point: Vector2, code: MouseButton, pressed: bool, factor := 1.0) -> void:
	mouse_event(point, code, pressed, factor)
	await frames(1)

func mouse_event(point: Vector2, code: MouseButton, pressed: bool, factor := 1.0) -> void:
	var mapped := root.get_screen_transform() * point
	var event := InputEventMouseButton.new()
	event.position = mapped
	event.global_position = mapped
	event.button_index = code
	event.pressed = pressed
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed and code == MOUSE_BUTTON_LEFT else 0
	event.factor = factor
	Input.parse_input_event(event)
	input_events += 1

func click(point: Vector2) -> void:
	# A click is one motion followed by a prompt press/release pair. Waiting for
	# a software-rendered frame while held turns it into a long press: an upward
	# popup can overlap the button and legitimately select the item on release.
	await motion(point)
	var pressed_at := Time.get_ticks_usec()
	mouse_event(point, MOUSE_BUTTON_LEFT, true)
	mouse_event(point, MOUSE_BUTTON_LEFT, false)
	last_click_hold_usec = Time.get_ticks_usec() - pressed_at
	await frames(2)

func frames(count: int) -> void:
	for frame in range(count): await process_frame

func capture(path: String) -> Image:
	await RenderingServer.frame_post_draw
	var result: Image = root.get_texture().get_image()
	check(not result.is_empty() and result.save_png(path) == OK, "Rendered integrated witness saved: " + path.get_file())
	return result

func visible_samples(result: Image) -> int:
	var count := 0
	for y in range(0, result.get_height(), 8):
		for x in range(0, result.get_width(), 8):
			var colour := result.get_pixel(x, y)
			count += int(maxf(colour.r, maxf(colour.g, colour.b)) > 0.06)
	return count
