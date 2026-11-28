extends SceneTree
## Exercise actual Control GUI routing through Input.parse_input_event.
var failures: Array[String] = []
var checks: int = 0
var app
var prefix: String = "user://gui-ecology"
const SAVE = "user://ecosystem-configuration.json"

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--output-prefix="):
			prefix = a.trim_prefix("--output-prefix=")
	_run.call_deferred()

func frames(n: int) -> void:
	for i in range(n):
		await process_frame

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures.append(description)
		print("FAIL: ", description)

func screen_point(p: Vector2) -> Vector2:
	# Control.get_global_rect() is expressed in the root viewport's logical
	# canvas. Input.parse_input_event expects screen coordinates. Keep this
	# identical to the already-qualified general graphical-input probe so
	# window decoration, DPI and stretch transforms cannot offset gestures.
	return root.get_screen_transform() * p

func click(p: Vector2) -> void:
	var mapped := screen_point(p)
	var motion = InputEventMouseMotion.new()
	motion.position = mapped
	motion.global_position = mapped
	Input.parse_input_event(motion)
	await frames(1)
	for pressed in [true, false]:
		var e = InputEventMouseButton.new()
		e.position = mapped
		e.global_position = mapped
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		e.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		Input.parse_input_event(e)
		await frames(2)

func key(code: Key) -> void:
	for pressed in [true, false]:
		var event = InputEventKey.new()
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

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		quit(2)
		return
	var had_save = FileAccess.file_exists(SAVE)
	var old = FileAccess.get_file_as_bytes(SAVE) if had_save else PackedByteArray()
	change_scene_to_file("res://main.tscn")
	await frames(10)
	root.grab_focus()
	var main = current_scene
	var button = find_button(main, "Open Ecosystem")
	check(button != null, "Life entry control exists in original instrument")
	if button == null:
		quit(1)
		return
	var tabs: TabContainer = main.ui.tabs
	tabs.current_tab = tabs.get_tab_count() - 1
	await frames(4)
	check(button.is_visible_in_tree() and button.get_global_rect().has_area(), "Life entry control is laid out and visible before input")
	await click(button.get_global_rect().get_center())
	await frames(8)
	app = current_scene
	check(app != null and app.scene_file_path == "res://ecology/workspace.tscn", "Actual Open Ecosystem button changes workspace")
	if app == null or app.scene_file_path != "res://ecology/workspace.tscn":
		quit(1)
		return
	await key(KEY_SPACE)
	check(app.paused, "Actual Space pauses simulation")
	var frozen = app.world.tick
	await frames(5)
	check(app.world.tick == frozen, "Paused ticks remain stable")
	var step = find_button(app, "Step")
	check(step != null, "Single step control exists")
	if step != null:
		await click(step.get_global_rect().get_center())
		check(app.world.tick == frozen + 1, "Actual Step button advances exactly one fixed tick")
	var area: Rect2 = app._area()
	var count: int = app.world.organisms.size()
	app.tools.select(1)
	app.family.select(2)
	await click(area.position + area.size * Vector2(0.5, 0.5))
	check(app.world.organisms.size() == count + 1, "Real canvas click plants selected organism")
	var planted: Dictionary = app.world.organisms[-1]
	app.tools.select(0)
	await click(app._screen(planted.p, area))
	check(app.selected == planted.id, "Real canvas click selects planted identity")
	app.tools.select(2)
	var sources: int = app.world.config.sources.size()
	await click(area.position + area.size * Vector2(0.3, 0.4))
	check(app.world.config.sources.size() == sources + 1, "Real canvas click adds resource source")
	app.tools.select(4)
	await click(area.position + area.size * Vector2(0.6, 0.6))
	check(app.world.sample(app.world.signal_field, Vector2(0.6, 0.6)) > 0.3, "Real canvas click deposits excitation")
	var digest: String = app.world.digest()
	app.quality_picker.select(2)
	app.quality_picker.item_selected.emit(2)
	await frames(4)
	check(app.stride == 4 and app.world.digest() == digest, "Render detail does not affect paused simulation")
	await key(KEY_F5)
	check(FileAccess.file_exists(SAVE), "F5 saves authored configuration")
	app.picker.select(1)
	app.picker.item_selected.emit(1)
	await frames(3)
	await key(KEY_F6)
	check(app.world.config.preset == 0 and app.world.organisms.size() == count + 1 and app.world.config.sources.size() == sources + 1, "F6 restores authored initial placements and sources")
	await frames(4)
	await RenderingServer.frame_post_draw
	var error = root.get_texture().get_image().save_png(prefix + ".png")
	check(error == OK, "Actual graphical workspace capture")
	var file = FileAccess.open(prefix + ".json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"suite": "ecology graphical input", "checks": checks, "failures": failures, "status": "PASS" if failures.is_empty() else "FAIL"}, "\t"))
	else:
		failures.append("Cannot write receipt")
	if had_save:
		var restore = FileAccess.open(SAVE, FileAccess.WRITE)
		if restore != null: restore.store_buffer(old)
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	print("ECOLOGY_GUI ", checks - failures.size(), "/", checks)
	quit(0 if failures.is_empty() else 1)
