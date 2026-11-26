extends RefCounted
## Bounded wall-frame samples and real rendering-server timing when available.
## GPU timestamp queries on software devices are labelled as software rendering.

const WINDOW := 1800
var _wall := PackedFloat64Array()
var _cpu := PackedFloat64Array()
var _gpu := PackedFloat64Array()
var _script := PackedFloat64Array()
var _cursor: int = 0
var _count: int = 0
var _viewport: RID
var _last_usec: int = 0
var _total_frames: int = 0
var _first_usec: int = 0
var _metadata: Dictionary = {}

func setup(viewport: Viewport) -> void:
	_viewport = viewport.get_viewport_rid()
	_wall.resize(WINDOW)
	_cpu.resize(WINDOW)
	_gpu.resize(WINDOW)
	_script.resize(WINDOW)
	if DisplayServer.get_name() != "headless":
		RenderingServer.viewport_set_measure_render_time(_viewport, true)
	var device: String = RenderingServer.get_video_adapter_name()
	_metadata = {"godot": Engine.get_version_info().string, "os": OS.get_name(),
		"device": device, "driver": RenderingServer.get_current_rendering_driver_name(),
		"rendering_method": RenderingServer.get_current_rendering_method(),
		"api": RenderingServer.get_video_adapter_api_version(),
		"display": DisplayServer.get_name(),
		"software_device": device.to_lower().contains("llvmpipe") or device.to_lower().contains("lavapipe") or device.to_lower().contains("swiftshader") or device.to_lower().contains("basic render"),
		"headless": DisplayServer.get_name() == "headless"}
	reset()

func reset() -> void:
	_cursor = 0
	_count = 0
	_total_frames = 0
	_first_usec = Time.get_ticks_usec()
	_last_usec = _first_usec

func sample(script_usec: int) -> void:
	var now: int = Time.get_ticks_usec()
	_wall[_cursor] = float(now - _last_usec) / 1000.0
	_last_usec = now
	_script[_cursor] = float(script_usec) / 1000.0
	_cpu[_cursor] = 0.0
	_gpu[_cursor] = 0.0
	if not _metadata.headless:
		_cpu[_cursor] = RenderingServer.viewport_get_measured_render_time_cpu(_viewport) + RenderingServer.get_frame_setup_time_cpu()
		_gpu[_cursor] = RenderingServer.viewport_get_measured_render_time_gpu(_viewport)
	_cursor = (_cursor + 1) % WINDOW
	_count = mini(_count + 1, WINDOW)
	_total_frames += 1

func _distribution(values: PackedFloat64Array) -> Dictionary:
	if _count == 0:
		return {"p50_ms": 0.0, "p95_ms": 0.0, "mean_ms": 0.0, "max_ms": 0.0}
	var sorted: PackedFloat64Array = values.slice(0, _count)
	sorted.sort()
	var total: float = 0.0
	for value in sorted:
		total += value
	return {"p50_ms": sorted[int((_count - 1) * 0.5)],
		"p95_ms": sorted[int(ceil((_count - 1) * 0.95))],
		"mean_ms": total / _count, "max_ms": sorted[-1]}

func snapshot(extra: Dictionary = {}) -> Dictionary:
	var wall: Dictionary = _distribution(_wall)
	var cpu: Dictionary = _distribution(_cpu)
	var gpu: Dictionary = _distribution(_gpu)
	var result: Dictionary = {
		"schema": "xenovection.performance.v1", "platform": _metadata,
		"samples": _count, "total_frames": _total_frames,
		"duration_seconds": float(Time.get_ticks_usec() - _first_usec) / 1000000.0,
		"fps_from_mean_frame": 1000.0 / maxf(wall.mean_ms, 0.0001),
		"wall_frame": wall, "render_cpu": cpu,
		"gpu_timing_available": gpu.mean_ms > 0.0 and not _metadata.headless,
		"render_gpu": gpu if gpu.mean_ms > 0.0 and not _metadata.headless else null,
		"application_update": _distribution(_script),
		"draw_calls_3d": RenderingServer.viewport_get_render_info(_viewport, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME),
		"draw_calls_total": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		"rendered_primitives": RenderingServer.viewport_get_render_info(_viewport, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME),
		"primitive_count_scope": "Visible 3D viewport; UI canvas excluded",
		"engine_static_bytes": int(Performance.get_monitor(Performance.MEMORY_STATIC)),
		"engine_video_bytes": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED),
		"memory_scope": "Engine allocations/proxies, not process RSS or total driver VRAM",
		"timestamp": Time.get_datetime_string_from_system(true)}
	result.merge(extra)
	return result

func save(path: String, extra: Dictionary = {}) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(snapshot(extra), "\t"))
	return OK
