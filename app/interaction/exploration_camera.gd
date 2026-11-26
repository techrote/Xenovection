extends Camera3D
## MMB orbit; Shift+MMB pan; hold RMB to fly; wheel to approach; Esc releases.

signal navigation_changed

var pivot := Vector3.ZERO
var orbit_distance := 17.0
var yaw := 0.32
var pitch := 0.18
var fly_speed := 5.0
var sensitivity := 0.004
var navigation_enabled := true

var _orbiting := false
var _panning := false
var _flying := false
var _old_mouse_mode: Input.MouseMode = Input.MOUSE_MODE_VISIBLE


func _ready() -> void:
	near = 0.025
	far = 1000.0
	fov = 48.0
	reset_view()


func reset_view() -> void:
	release_pointer()
	pivot = Vector3.ZERO
	orbit_distance = 17.0
	yaw = 0.32
	pitch = 0.18
	_apply_orbit()


func _unhandled_input(event: InputEvent) -> void:
	if not navigation_enabled:
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_begin_fly()
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_MIDDLE and event.pressed:
			_orbiting = not event.shift_pressed
			_panning = event.shift_pressed
			get_viewport().set_input_as_handled()
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var direction := -1.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0
			if _flying:
				fly_speed = clampf(fly_speed * exp(-direction * 0.18), 0.1, 80.0)
			else:
				orbit_distance = clampf(orbit_distance * exp(direction * 0.12), 0.12, 250.0)
				_apply_orbit()
			get_viewport().set_input_as_handled()


func _input(event: InputEvent) -> void:
	# Release must work even when the pointer is now over a UI control.
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE and (_flying or _orbiting or _panning):
		release_pointer()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and not event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT and _flying:
			_end_fly()
			get_viewport().set_input_as_handled()
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			_orbiting = false
			_panning = false
	if event is InputEventMouseMotion and navigation_enabled:
		if _flying:
			yaw -= event.relative.x * sensitivity
			pitch = clampf(pitch - event.relative.y * sensitivity, -1.48, 1.48)
			rotation = Vector3(pitch, yaw, 0.0)
			get_viewport().set_input_as_handled()
			navigation_changed.emit()
		elif _orbiting:
			yaw -= event.relative.x * sensitivity
			pitch = clampf(pitch + event.relative.y * sensitivity, -1.48, 1.48)
			_apply_orbit()
			get_viewport().set_input_as_handled()
		elif _panning:
			var scale := orbit_distance * 0.0012
			pivot += (-global_basis.x * event.relative.x + global_basis.y * event.relative.y) * scale
			_apply_orbit()
			get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not _flying or not navigation_enabled:
		return
	var motion := Vector3.ZERO
	if Input.is_physical_key_pressed(KEY_W):
		motion -= global_basis.z
	if Input.is_physical_key_pressed(KEY_S):
		motion += global_basis.z
	if Input.is_physical_key_pressed(KEY_A):
		motion -= global_basis.x
	if Input.is_physical_key_pressed(KEY_D):
		motion += global_basis.x
	if Input.is_physical_key_pressed(KEY_Q):
		motion -= Vector3.UP
	if Input.is_physical_key_pressed(KEY_E):
		motion += Vector3.UP
	var multiplier := 3.0 if Input.is_physical_key_pressed(KEY_SHIFT) else 1.0
	if Input.is_physical_key_pressed(KEY_CTRL):
		multiplier *= 0.2
	if motion.length_squared() > 0.0:
		global_position += motion.normalized() * fly_speed * multiplier * minf(delta, 0.1)
		navigation_changed.emit()


func focus_points(points: PackedVector3Array) -> void:
	if points.is_empty():
		return
	release_pointer()
	var centre := Vector3.ZERO
	for point in points:
		centre += point
	centre /= float(points.size())
	var radius := 0.15
	for point in points:
		radius = maxf(radius, centre.distance_to(point))
	pivot = centre
	orbit_distance = clampf(radius / sin(deg_to_rad(fov * 0.5)) * 1.18, 0.5, 250.0)
	_apply_orbit()


func get_pose() -> Dictionary:
	return {"pivot": pivot, "distance": orbit_distance, "yaw": yaw, "pitch": pitch,
		"position": global_position, "fov": fov}


func set_pose(pose: Dictionary) -> void:
	release_pointer()
	var candidate = pose.get("pivot", pivot)
	if candidate is Vector3 and candidate.is_finite():
		pivot = candidate
	for key in ["distance", "yaw", "pitch", "fov"]:
		if pose.has(key) and not is_finite(float(pose[key])):
			return
	orbit_distance = clampf(float(pose.get("distance", orbit_distance)), 0.12, 250.0)
	yaw = float(pose.get("yaw", yaw))
	pitch = clampf(float(pose.get("pitch", pitch)), -1.48, 1.48)
	fov = clampf(float(pose.get("fov", fov)), 15.0, 110.0)
	_apply_orbit()


func is_navigating() -> bool:
	return _flying or _orbiting or _panning


func release_pointer() -> void:
	if _flying:
		_end_fly()
	_orbiting = false
	_panning = false


func _begin_fly() -> void:
	_orbiting = false
	_panning = false
	_flying = true
	yaw = rotation.y
	pitch = rotation.x
	_old_mouse_mode = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _end_fly() -> void:
	_flying = false
	Input.mouse_mode = _old_mouse_mode
	pivot = global_position - global_basis.z * orbit_distance
	# Orbit uses elevation whereas Camera3D Euler pitch has the opposite sign.
	pitch = -rotation.x
	yaw = rotation.y
	_apply_orbit()


func _apply_orbit() -> void:
	global_position = pivot + Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * orbit_distance
	look_at(pivot, Vector3.UP)
	navigation_changed.emit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		release_pointer()


func _exit_tree() -> void:
	release_pointer()
