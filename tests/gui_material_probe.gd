extends SceneTree
## Real authoring of optical material on inherited procedural geometry.
## The same script runs from source and res://qualification/ in the exported pack.
var application
var checks := 0
var failures: Array[String] = []
var output_prefix := "user://gui-material"
var input_events := 0

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output-prefix="):
			output_prefix = argument.trim_prefix("--output-prefix=")
	_run.call_deferred()

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Material GUI probe requires a real graphical display")
		quit(2)
		return
	application = load("res://main.tscn").instantiate()
	root.add_child(application)
	root.grab_focus()
	await frames(8)
	check(RenderingServer.get_current_rendering_method() == "forward_plus","Material authoring executes Forward+ renderer")
	await select_preset("living")
	if not application.matter.active:
		check(false,"Inherited Living weather membrane opens through actual preset picker")
		await finish({})
		return
	check(str(application.presets[application.preset_index].id) == "living","Real preset selection retains the inherited editable membrane")
	if not application.bus.paused:
		await key(KEY_SPACE)
	var clocks_before: Dictionary = application.bus.get_clocks()
	var source_revision: String = application.dataset.manifest.revision
	var camera_before: Transform3D = application.camera.global_transform
	var region = application.matter.regions[0]
	var mesh: Mesh = region.surface.mesh
	var material: ShaderMaterial = region.shader
	var builds: int = region.builds
	await choose_tab("Matter")
	await slide_target("matter.edit.optical_mix",1.0)
	check(is_equal_approx(float(application.bus.get_base("matter.region0.optical_mix")),1.0),"Actual Matter slider assigns the shared optical material")
	await choose_tab("Optics")
	await toggle_target("optical.enabled",true)
	await slide_target("optical.optical_thickness",0.67)
	await slide_target("optical.illumination_direction",0.73)
	await slide_target("optical.illumination_intensity",0.68)
	await slide_target("optical.optical_mix",1.0)
	await frames(4)
	check(is_equal_approx(float(region.shader.get_shader_parameter("xeno_optical_mix")),1.0),"Actual global optical slider activates the generated material")
	var effective: Dictionary = application.bus.get_parameters()
	check(is_equal_approx(float(region.shader.get_shader_parameter("xeno_thickness")),float(effective["optical.optical_thickness"])),"Pointer-authored thickness reaches the generated shader through the common registry")
	check(is_equal_approx(float(region.shader.get_shader_parameter("xeno_illumination_direction")),float(effective["optical.illumination_direction"])),"Pointer-authored independent illumination reaches the generated shader")
	check(application.camera.global_transform.is_equal_approx(camera_before),"Material controls and scrolling never capture camera navigation")
	check(application.bus.get_clocks() == clocks_before,"Actual pause preserves all independent clocks during authoring")
	check(region.builds == builds and region.surface.mesh == mesh and region.shader == material,"Real optical authoring preserves generated topology and material resources")
	await slide_target("optical.optical_mix",0.0)
	check(is_zero_approx(float(region.shader.get_shader_parameter("xeno_optical_mix"))),"Actual mix-zero slider restores legacy generated appearance")
	await key(KEY_H)
	await frames(4)
	var legacy: Image = await capture(output_prefix + "-legacy.png")
	await key(KEY_H)
	await slide_target("optical.optical_mix",1.0)
	await key(KEY_H)
	await frames(4)
	var enhanced: Image = await capture(output_prefix + "-optical.png")
	var visual := compare_images(legacy,enhanced)
	check(float(visual.get("mean_rgb_difference",0.0)) > 0.0001,"Same-camera optical-disabled comparison has a measurable material response")
	check(int(visual.get("legacy_lit_samples",0)) > 50 and int(visual.get("optical_lit_samples",0)) > 50,"Both material comparison captures contain visible generated geometry")
	check(region.builds == builds and region.surface.mesh == mesh,"Effect-disabled capture comparison performs no topology rebuild")
	check(application.dataset.manifest.revision == source_revision,"Cross-domain material authoring preserves exact scientific source")
	check(not bool(region.metrics().screen_copy),"Generated optical material remains outside the screen/depth-copy pass")
	await key(KEY_H)
	await frames(2)
	await capture(output_prefix + "-authoring.png")
	await finish({"comparison":visual,"region":region.metrics(),"source_revision":source_revision,
		"input_events":input_events,"clock_values":clocks_before})

func finish(details: Dictionary) -> void:
	var receipt := {"suite":"graphical-generated-optical-authoring","status":"PASS" if failures.is_empty() else "FAIL",
		"checks":checks,"passed":checks-failures.size(),"failures":failures,
		"display":DisplayServer.get_name(),"renderer":RenderingServer.get_current_rendering_method(),
		"device":RenderingServer.get_video_adapter_name(),"platform":OS.get_name(),
		"details":details,"evidence_kind":"Real graphical pointer and keyboard authoring; no physical GPU throughput claim"}
	var file := FileAccess.open(output_prefix+".json",FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(receipt,"\t"))
		file.close()
	print("CONVERGENCE_GUI_MATERIAL_RESULT ",JSON.stringify(receipt))
	application.free()
	await frames(2)
	quit(0 if failures.is_empty() else 1)

func select_preset(id: String) -> void:
	var index := -1
	for i in range(application.presets.size()):
		if str(application.presets[i].id) == id:
			index = i
	check(index >= 0,"Inherited preset identity exists: "+id)
	if index < 0:
		return
	var picker: OptionButton = application.ui.preset_picker
	await click(picker.get_global_rect().get_center())
	await frames(2)
	var popup: PopupMenu = picker.get_popup()
	check(popup.visible,"Actual preset picker click opens the composition menu")
	if not popup.visible:
		return
	for _attempt in range(application.presets.size()+2):
		var focused := popup.get_focused_item()
		if focused == index:
			break
		await key(KEY_DOWN if focused < index else KEY_UP)
	check(popup.get_focused_item() == index,"Actual menu key navigation locates the stable composition")
	await key(KEY_ENTER)
	await frames(5)

func choose_tab(title: String) -> void:
	var tabs: TabContainer = application.ui.tabs
	var bar: TabBar = tabs.get_tab_bar()
	var index := -1
	for i in range(tabs.get_tab_count()):
		if tabs.get_tab_title(i) == title:
			index = i
	check(index >= 0,"Authoring tab exists: "+title)
	if index < 0:
		return
	# Actual workspace shortcuts avoid clicking a clipped tab after the narrow
	# rail auto-scrolls to another domain; this exercises the production key path.
	if title == "Matter":
		await key(KEY_F2)
	elif title == "Optics":
		await key(KEY_F3)
	elif title == "Life":
		await key(KEY_F4)
	else:
		await click(bar.get_global_transform() * bar.get_tab_rect(index).get_center())
	await frames(2)
	check(tabs.current_tab == index,"Actual input activates "+title+" authoring")

func find_target(node: Node, target: String) -> Control:
	if node is Control and str(node.get_meta("target","")) == target:
		return node
	for child in node.get_children():
		var result := find_target(child,target)
		if result != null:
			return result
	return null

func target_control(target: String) -> Control:
	var control := find_target(application.ui,target)
	if control == null and application.ui._controls.has(target):
		control = application.ui._controls[target].input
	return control

func expose(control: Control) -> bool:
	var parent: Node = control.get_parent()
	while parent != null and not parent is ScrollContainer:
		parent = parent.get_parent()
	if not parent is ScrollContainer:
		return control.is_visible_in_tree()
	var scroll: ScrollContainer = parent
	for _attempt in range(90):
		var area := scroll.get_global_rect().grow(-8.0)
		var point := control.get_global_rect().get_center()
		if area.has_point(point):
			return true
		var direction := MOUSE_BUTTON_WHEEL_DOWN if point.y > area.end.y else MOUSE_BUTTON_WHEEL_UP
		var event_point := Vector2(scroll.get_global_rect().end.x-4.0,area.get_center().y)
		await wheel(event_point,direction,4.0 if absf(point.y-area.get_center().y)>350.0 else 1.0)
	return false

func slide_target(target: String, fraction: float) -> void:
	var control := target_control(target)
	check(control is HSlider,"Named optical authoring slider exists: "+target)
	if not control is HSlider:
		return
	var exposed := await expose(control)
	check(exposed,"Actual wheel input exposes slider: "+target)
	if not exposed:
		return
	var rect := control.get_global_rect()
	var point := Vector2(lerpf(rect.position.x+1.0,rect.end.x-1.0,fraction),rect.get_center().y)
	await click(point)
	await frames(2)

func toggle_target(target: String, desired: bool) -> void:
	var control := target_control(target)
	check(control is BaseButton,"Named optical toggle exists: "+target)
	if not control is BaseButton:
		return
	check(await expose(control),"Actual wheel input exposes toggle: "+target)
	if control.button_pressed != desired:
		await click(control.get_global_rect().get_center())
	await frames(2)
	check(control.button_pressed == desired,"Actual toggle sets "+target)

func capture(path: String) -> Image:
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	check(not image.is_empty() and image.save_png(path) == OK,"Rendered material evidence saved: "+path.get_file())
	return image

func compare_images(a: Image, b: Image) -> Dictionary:
	if a.is_empty() or b.is_empty() or a.get_size() != b.get_size():
		return {}
	var difference := 0.0
	var samples := 0
	var lit_a := 0
	var lit_b := 0
	for y in range(0,a.get_height(),4):
		for x in range(0,a.get_width(),4):
			var ca := a.get_pixel(x,y)
			var cb := b.get_pixel(x,y)
			difference += (absf(ca.r-cb.r)+absf(ca.g-cb.g)+absf(ca.b-cb.b))/3.0
			lit_a += int(maxf(ca.r,maxf(ca.g,ca.b))>0.06)
			lit_b += int(maxf(cb.r,maxf(cb.g,cb.b))>0.06)
			samples += 1
	return {"samples":samples,"mean_rgb_difference":difference/maxi(1,samples),
		"legacy_lit_samples":lit_a,"optical_lit_samples":lit_b,"pixels":[a.get_width(),a.get_height()]}

func frames(count: int) -> void:
	for _frame in range(count):
		await process_frame

func motion(point: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = root.get_screen_transform()*point
	event.global_position = event.position
	Input.parse_input_event(event)
	input_events += 1
	await frames(1)

func button(point: Vector2, code: MouseButton, pressed: bool, factor: float = 1.0) -> void:
	var event := InputEventMouseButton.new()
	event.position = root.get_screen_transform()*point
	event.global_position = event.position
	event.button_index = code
	event.pressed = pressed
	event.factor = factor
	Input.parse_input_event(event)
	input_events += 1
	await frames(1)

func click(point: Vector2) -> void:
	await motion(point)
	await button(point,MOUSE_BUTTON_LEFT,true)
	await button(point,MOUSE_BUTTON_LEFT,false)
	await frames(1)

func wheel(point: Vector2, direction: MouseButton, factor: float) -> void:
	await motion(point)
	await button(point,direction,true,factor)
	await button(point,direction,false,factor)
	await frames(1)

func key(code: Key) -> void:
	for pressed in [true,false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)
		input_events += 1
		await frames(1)

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
	print("PASS " if condition else "FAIL ",label)
