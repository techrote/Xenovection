extends SceneTree
## Real GUI controls and viewport pointer events exercise the planar inverse projection.
var checks: int = 0
var failures: Array[String] = []
var prefix: String = "user://gui-spatial-ecology"
var app
var life
var scroll: ScrollContainer
var material_comparison: Dictionary = {}
var option_trace: Array[Dictionary] = []

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output-prefix="):
			prefix = arg.trim_prefix("--output-prefix=")
	_run.call_deferred()

func frames(count: int) -> void:
	for i in range(count):
		await process_frame

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		print("FAIL: ", label)

func click(point: Vector2) -> void:
	var mapped: Vector2 = root.get_screen_transform() * point
	var move = InputEventMouseMotion.new()
	move.position = mapped
	move.global_position = mapped
	Input.parse_input_event(move)
	await frames(1)
	for pressed in [true, false]:
		var event = InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		event.position = mapped
		event.global_position = mapped
		event.pressed = pressed
		Input.parse_input_event(event)
		await frames(2)

func key(code: Key, window_id: int = 0) -> void:
	for pressed in [true, false]:
		var event = InputEventKey.new()
		event.window_id = window_id
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)
		await frames(2)

func find_button(node: Node, label: String) -> Button:
	if node is Button and node.text == label:
		return node
	for child in node.get_children():
		var result = find_button(child, label)
		if result != null:
			return result
	return null

func reveal(control: Control) -> void:
	var container: Node = control.get_parent()
	while container != null and not container is ScrollContainer:
		container = container.get_parent()
	if not container is ScrollContainer:
		return
	for attempt in range(90):
		var area: Rect2 = container.get_global_rect().grow(-8.0)
		var point: Vector2 = control.get_global_rect().get_center()
		if area.has_point(point):
			return
		var mapped: Vector2 = root.get_screen_transform() * Vector2(container.get_global_rect().end.x - 4.0, area.get_center().y)
		var motion = InputEventMouseMotion.new()
		motion.position = mapped
		motion.global_position = mapped
		Input.parse_input_event(motion)
		await frames(1)
		for pressed in [true, false]:
			var event = InputEventMouseButton.new()
			event.position = mapped
			event.global_position = mapped
			event.button_index = MOUSE_BUTTON_WHEEL_DOWN if point.y > area.end.y else MOUSE_BUTTON_WHEEL_UP
			event.factor = 4.0 if absf(point.y - area.get_center().y) > 350.0 else 1.0
			event.pressed = pressed
			Input.parse_input_event(event)
			await frames(1)
		await frames(1)
	check(false, "Actual scroll exposes required control")

func slide(control: HSlider, fraction: float) -> void:
	await reveal(control)
	var rect = control.get_global_rect()
	await click(Vector2(lerpf(rect.position.x + 1.0, rect.end.x - 1.0, fraction), rect.get_center().y))
	await frames(3)

func capture(path: String) -> Image:
	await RenderingServer.frame_post_draw
	var result: Image = root.get_texture().get_image()
	check(not result.is_empty() and result.save_png(path) == OK, "Material comparison capture written")
	return result

func image_difference(first: Image, second: Image) -> Dictionary:
	if first.is_empty() or second.is_empty() or first.get_size() != second.get_size():
		return {}
	var total: float = 0.0
	var changed: int = 0
	var samples: int = 0
	for y in range(0, first.get_height(), 2):
		for x in range(0, first.get_width(), 2):
			var a = first.get_pixel(x, y)
			var b = second.get_pixel(x, y)
			var difference = (absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)) / 3.0
			total += difference
			changed += int(difference > 0.005)
			samples += 1
	return {"mean_rgb_difference": total / maxi(samples, 1), "changed_samples": changed, "samples": samples}

func press(label: String) -> bool:
	var button = find_button(life, label)
	if button == null:
		check(false, "Required control exists: " + label)
		return false
	await reveal(button)
	await click(button.get_global_rect().get_center())
	return true

func choose(picker: OptionButton, index: int) -> void:
	await reveal(picker)
	await click(picker.get_global_rect().get_center())
	await frames(2)
	var popup: PopupMenu = picker.get_popup()
	var trace: Dictionary = {"target": str(picker.get_meta("target", "")),
		"requested": index, "selected_before": picker.selected,
		"popup_visible": popup.visible, "popup_window_id": popup.get_window_id(),
		"event_window_id": 0, "focused_items": [popup.get_focused_item()]}
	check(popup.visible, "Actual option pointer opens " + picker.get_item_text(index) + " menu")
	if not popup.visible:
		option_trace.append(trace)
		return
	# Match the real-event path already qualified by gui_material_probe. Popup
	# initial focus and HOME semantics vary with native/embedded menus; observe
	# the focused item and let Godot route ordinary key events to the open menu.
	for attempt in range(picker.item_count + 3):
		var focused: int = popup.get_focused_item()
		if focused == index:
			break
		await key(KEY_DOWN if focused < index else KEY_UP)
		trace.focused_items.append(popup.get_focused_item())
	check(popup.get_focused_item() == index, "Actual option navigation locates " + picker.get_item_text(index))
	await key(KEY_ENTER)
	await frames(3)
	trace.selected_after = picker.selected
	trace.popup_visible_after = popup.visible
	option_trace.append(trace)
	check(picker.selected == index, "Actual option input selects " + picker.get_item_text(index))

func orbit() -> void:
	var point: Vector2 = app.spatial_ecology.domain_to_screen(app.camera, Vector2(0.5, 0.5))
	var from: Vector2 = root.get_screen_transform() * point
	var to: Vector2 = root.get_screen_transform() * (point + Vector2(42, 24))
	var down = InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_MIDDLE
	down.button_mask = MOUSE_BUTTON_MASK_MIDDLE
	down.position = from
	down.global_position = from
	down.pressed = true
	Input.parse_input_event(down)
	await frames(2)
	var movement = InputEventMouseMotion.new()
	movement.position = to
	movement.global_position = to
	movement.relative = to - from
	movement.button_mask = MOUSE_BUTTON_MASK_MIDDLE
	Input.parse_input_event(movement)
	await frames(2)
	var up = InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_MIDDLE
	up.position = to
	up.global_position = to
	up.pressed = false
	Input.parse_input_event(up)
	await frames(3)

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		quit(2)
		return
	change_scene_to_file("res://main.tscn")
	await frames(12)
	root.grab_focus()
	app = current_scene
	life = app.life_panel
	scroll = app.ui.tabs.get_node("Life")
	await key(KEY_F4)
	await frames(4)
	check(life.is_visible_in_tree(), "Life authoring controls visible")
	await press("Show spatial ecology")
	await frames(6)
	check(app.workspace_mode == "spatial" and app.spatial_ecology.visible and not app.ecology.visible, "Actual spatial-view button activates shared spatial ecology")
	check(app.ecology.bus == app.bus and app.spatial_ecology.records.size() == app.ecology.world.organisms.size(), "One shared registry and one representation record per living identity")
	await press("Pause ecology")
	check(app.ecology.paused, "Actual pause control freezes ecology independently")
	var frozen_tick: int = app.ecology.world.tick
	await frames(5)
	check(app.ecology.world.tick == frozen_tick, "Paused spatial ecology has stable ticks")
	await choose(life.tool_picker, 1)
	await choose(life.family_picker, 2)
	var p = Vector2(0.48, 0.45)
	var population: int = app.ecology.world.organisms.size()
	var allocations: int = app.spatial_ecology.allocations
	var pose: Dictionary = app.camera.get_pose()
	await click(app.spatial_ecology.domain_to_screen(app.camera, p))
	await frames(3)
	check(app.ecology.world.organisms.size() == population + 1, "Actual 3D viewport click plants selected family")
	if app.ecology.world.organisms.size() != population + 1:
		await finish()
		return
	var organism: Dictionary = app.ecology.world.organisms[-1]
	check(organism.kind == 2 and organism.p.distance_to(p) < 0.00001, "Plant uses reproducible inverse numerical coordinates")
	check(app.spatial_ecology.allocations == allocations + 1, "Plant allocates one persistent representation record")
	check(app.camera.get_pose() == pose, "Planting pointer does not navigate camera")
	await choose(life.tool_picker, 0)
	await click(app.spatial_ecology.domain_to_screen(app.camera, p))
	check(app.ecology.selected == organism.id, "Actual spatial inspection selects stable organism identity")
	await press("Isolate / reveal selected family")
	check(app.ecology.isolated == 2 and app.spatial_ecology.isolated == 2, "Actual isolate control changes presentation family only")
	await press("Isolate / reveal selected family")
	await choose(life.tool_picker, 2)
	var source_count: int = app.ecology.world.config.sources.size()
	await click(app.spatial_ecology.domain_to_screen(app.camera, Vector2(0.32, 0.42)))
	check(app.ecology.world.config.sources.size() == source_count + 1, "Actual spatial resource placement updates authored initial sources")
	await choose(life.tool_picker, 4)
	var stimulus = Vector2(0.62, 0.56)
	await click(app.spatial_ecology.domain_to_screen(app.camera, stimulus))
	var signal_before: float = app.ecology.world.sample(app.ecology.world.signal_field, stimulus)
	check(signal_before > 0.5, "Actual spatial signal placement excites numerical field")
	await choose(life.tool_picker, 5)
	await click(app.spatial_ecology.domain_to_screen(app.camera, stimulus))
	check(app.ecology.world.sample(app.ecology.world.signal_field, stimulus) < signal_before, "Actual spatial inhibition is a local numerical disturbance")
	var digest: String = app.ecology.world.digest()
	var built: int = app.spatial_ecology.topology_builds
	await choose(life.quality_picker, 2)
	check(app.ecology.stride == 4 and app.ecology.world.digest() == digest and app.spatial_ecology.topology_builds == built, "Actual detail control preserves numerical digest and shared topology")
	pose = app.camera.get_pose()
	await orbit()
	check(app.camera.get_pose() != pose and app.ecology.world.digest() == digest, "Actual camera orbit preserves paused numerical state")
	await choose(life.tool_picker, 0)
	await click(app.spatial_ecology.domain_to_screen(app.camera, p))
	check(app.ecology.selected == organism.id, "Oblique actual pointer selection maps to same identity")
	var world = app.ecology.world
	await press("Open Ecosystem")
	await frames(4)
	check(app.ecology.visible and current_scene == app and app.ecology.world == world and app.ecology.world.digest() == digest, "Actual planar transition retains world, digest and main scene")
	await key(KEY_ESCAPE)
	await frames(4)
	check(not app.ecology.visible and app.ecology.world == world and app.ecology.world.digest() == digest, "Actual return retains spatial ecology history")
	await key(KEY_F4)
	await reveal(life.enabled_control)
	await click(life.enabled_control.get_global_rect().get_center())
	check(not app.ecology.simulation_enabled and app.spatial_ecology.records.is_empty(), "Actual deactivation releases organism representation resources")
	await click(life.enabled_control.get_global_rect().get_center())
	await frames(3)
	check(app.ecology.simulation_enabled and app.spatial_ecology.records.size() == world.organisms.size() and world.digest() == digest, "Actual reactivation reuses unchanged numerical world")
	await press("Step ecology")
	check(world.tick == frozen_tick + 1 and app.ecology.paused, "Actual spatial Step advances exactly one fixed boundary")
	# Freeze every visual clock as well as the solver, then compare the same
	# fully optical geometry under two real eco.material slider settings.
	if not app.bus.paused:
		await key(KEY_SPACE)
	await key(KEY_F3)
	await slide(app.ui._controls["optical.optical_mix"].input, 1.0)
	check(is_equal_approx(float(app.bus.get_base("optical.optical_mix")), 1.0), "Actual optical control enables full shared response for living matter")
	await key(KEY_F4)
	var material: HSlider = life.parameters["material"].input
	var numerical_digest: String = world.digest()
	var geometry_builds: int = app.spatial_ecology.topology_builds
	await slide(material, 0.1)
	check(float(app.spatial_ecology.family_materials[0].get_shader_parameter("ecology_material_gain")) < 0.5, "Actual material slider updates paused spatial optical shader")
	await key(KEY_H)
	await frames(4)
	var dim: Image = await capture(prefix + "-material-low.png")
	await key(KEY_H)
	await slide(material, 0.9)
	await key(KEY_H)
	await frames(4)
	var bright: Image = await capture(prefix + "-material-high.png")
	material_comparison = image_difference(dim, bright)
	check(float(material_comparison.get("mean_rgb_difference", 0.0)) > 0.000001 and int(material_comparison.get("changed_samples", 0)) >= 5, "Full-optical eco.material has measurable viewport response with all clocks frozen")
	check(world.digest() == numerical_digest and app.spatial_ecology.topology_builds == geometry_builds, "Optical material comparison leaves numerical history and shared topology unchanged")
	await key(KEY_H)
	await finish()

func finish() -> void:
	await frames(4)
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(prefix + ".png") == OK, "Spatial authoring capture written")
	var receipt = {"suite": "spatial ecology real graphical input", "checks": checks, "failures": failures,
		"status": "PASS" if failures.is_empty() else "FAIL", "ecology": app.ecology.convergence_metrics(),
		"representation": app.spatial_ecology.metrics(), "digest": app.ecology.world.digest(),
		"material_comparison": material_comparison, "option_trace": option_trace}
	var file = FileAccess.open(prefix + ".json", FileAccess.WRITE)
	if file == null:
		failures.append("Cannot write spatial graphical receipt")
	else:
		file.store_string(JSON.stringify(receipt, "\t"))
	print("SPATIAL_ECOLOGY_GUI ", checks - failures.size(), "/", checks)
	quit(0 if failures.is_empty() else 1)
