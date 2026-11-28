extends SceneTree
## Real pointer/key events against the instrument in a graphical Godot window.
const Main = preload("res://main.gd")
const Graph = preload("res://core/synth_graph.gd")
var app
var panel
var failures: Array = []
var checks := 0
var prefix := "user://synth-gui"

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output-prefix="):
			prefix = argument.trim_prefix("--output-prefix=")
	_run.call_deferred()

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		quit(2)
		return
	app = Main.new()
	root.add_child(app)
	root.grab_focus()
	panel = app.synth_panel
	await frames(5)
	await key(KEY_F7)
	check(app.ui.tabs.current_tab == app.ui.tabs.get_tab_count() - 1, "F7 opens the Synth rail")
	await click("Blank")
	await click("New component")
	# Set the actual authoring widgets; commit via pointer events.
	panel._items(panel.kind_picker, Graph.KINDS, "manual")
	panel.value.value = 0.65
	await click("Apply component")
	check(app.synth.nodes.size() == 1, "Pointer commits a new component")
	await click("New route")
	panel._targets("filament.phase_speed")
	panel.amplitude.value = 0.8
	await click("Apply route")
	check(app.synth.patch.routes.size() == 1, "Pointer commits a new signal route")
	await click("Undo")
	check(app.synth.patch.routes.is_empty(), "Pointer undo")
	await click("Redo")
	check(app.synth.patch.routes.size() == 1, "Pointer redo")
	panel.example_picker.select(5)
	await click("Recall example")
	await click("Perform")
	await frames(3)
	check(panel.perform.visible and app.synth.nodes.has("xy_x"), "Performance recall")
	var ref: Dictionary = app.selection.get_reference()
	var revision: String = app.dataset.manifest.revision
	var before: Transform3D = app.camera.global_transform
	var scroll: ScrollContainer = panel.get_parent().get_parent()
	scroll.ensure_control_visible(panel.pad)
	await frames(3)
	var rect: Rect2 = panel.pad.get_global_rect()
	var start := rect.position + rect.size * Vector2(0.25, 0.75)
	var end := rect.position + rect.size * Vector2(0.82, 0.18)
	await motion(start, start)
	await button(start, true)
	await motion(start, end, MOUSE_BUTTON_MASK_LEFT)
	await button(end, false)
	await frames(4)
	check(float(app.synth.nodes.xy_x.value) > 0.5 and float(app.synth.nodes.xy_y.value) > 0.5, "Actual XY drag modulates both axes")
	check(not app._dragging and not app.camera.is_navigating() and app.camera.global_transform.is_equal_approx(before), "XY drag never reaches camera or selection")
	check(ref == app.selection.get_reference() and revision == app.dataset.manifest.revision, "Visual performance preserves source membership")
	var image := root.get_texture().get_image()
	check(image != null and not image.is_empty() and image.save_png(prefix + ".png") == OK, "Actual graphical viewport capture")
	var receipt := FileAccess.open(prefix + ".json", FileAccess.WRITE)
	if receipt != null:
		receipt.store_string(JSON.stringify({"checks": checks, "failures": failures, "renderer": RenderingServer.get_current_rendering_method(), "device": RenderingServer.get_video_adapter_name(), "metrics": app.synth.metrics()}, "\t"))
		receipt.close()
	print("SYNTH_GUI ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)

func frames(count: int) -> void:
	for i in range(count):
		await process_frame

func button(point: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = root.get_screen_transform() * point
	event.global_position = event.position
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
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
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)
		await frames(1)

func click(text_value: String) -> void:
	var control: Button = find_button(panel, text_value)
	if control == null:
		check(false, "Missing control " + text_value)
		return
	var scroll: ScrollContainer = panel.get_parent().get_parent()
	scroll.ensure_control_visible(control)
	await frames(3)
	var point := control.get_global_rect().get_center()
	await motion(point, point)
	await button(point, true)
	await button(point, false)
	await frames(2)

func find_button(node: Node, text_value: String) -> Button:
	if node is Button and node.text == text_value and node.is_visible_in_tree():
		return node
	for child in node.get_children():
		var found := find_button(child, text_value)
		if found != null:
			return found
	return null

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
		print("FAIL ", description)
	else:
		print("PASS ", description)
