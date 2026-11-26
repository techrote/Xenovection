extends RefCounted
## Bounded, read-only sample overlay. These samples never overwrite source values.

const SCHEMA := "xenovection.samples.v1"
const MAX_SAMPLES := 8192
const MAX_BYTES := 4 * 1024 * 1024
const MAX_STREAMS := 128
const MAX_DRAIN_PER_FRAME := 256

var enabled := true
var loop := true
var last_error := ""
var coalesced_samples := 0
var source_id := ""
var source_revision := ""
var duration := 0.0
var _samples: Array = []
var _streams: Dictionary = {}
var _latest: Dictionary = {}
var _cursor := 0
var _last_time := -1.0


func load_json(path: String, dataset: Dictionary) -> bool:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _error("Cannot open replay file")
	if file.get_length() > MAX_BYTES:
		return _error("Replay exceeds the 4 MiB input bound")
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK or not parser.data is Dictionary:
		return _error("Malformed replay JSON")
	return set_validated(parser.data, dataset)


func set_validated(input: Dictionary, dataset: Dictionary) -> bool:
	if input.get("schema", "") != SCHEMA or not input.get("samples", null) is Array:
		return _error("Unsupported replay schema")
	var manifest: Dictionary = dataset.get("manifest", {})
	if input.get("source_id", "") != manifest.get("source_id", "") or input.get("source_revision", "") != manifest.get("revision", ""):
		return _error("Replay source identity/revision does not match the active dataset")
	if input.samples.size() > MAX_SAMPLES:
		return _error("Replay sample count exceeds the bounded capacity")
	var node_ids: Dictionary = {}
	var edge_ids: Dictionary = {}
	for node in dataset.get("nodes", []):
		node_ids[node.id] = true
	for edge in dataset.get("edges", []):
		edge_ids[edge.id] = true
	var samples: Array = []
	var streams: Dictionary = {}
	var previous_time := -1.0
	for raw in input.samples:
		if not raw is Dictionary:
			return _error("Replay sample must be an object")
		var time = raw.get("time", null)
		var value = raw.get("value", null)
		if not _number(time) or not _number(value) or float(time) < previous_time or float(time) < 0.0 or float(time) > 86400.0 or absf(float(value)) > 1.0e12:
			return _error("Replay samples must have finite, bounded values and monotonically ordered times")
		var kind := str(raw.get("kind", ""))
		var id := str(raw.get("id", ""))
		if not ((kind == "node" and node_ids.has(id)) or (kind == "edge" and edge_ids.has(id))):
			return _error("Replay sample references an absent source item")
		var value_kind := str(raw.get("value_kind", ""))
		if not value_kind in ["measured", "derived", "artistic"]:
			return _error("Replay samples must declare measured, derived or artistic semantics")
		var key := kind + ":" + id
		if not streams.has(key):
			streams[key] = []
		if streams.size() > MAX_STREAMS:
			return _error("Replay exceeds the 128-stream bound")
		var sample := {"time": float(time), "kind": kind, "id": id, "value": float(value),
			"value_kind": value_kind, "units": str(raw.get("units", "unitless")),
			"operation": str(raw.get("operation", "recorded source sample")), "key": key}
		samples.append(sample)
		streams[key].append(sample)
		previous_time = float(time)
	_samples = samples
	_streams = streams
	source_id = str(manifest.source_id)
	source_revision = str(manifest.revision)
	duration = maxf(previous_time, 0.0)
	reset()
	last_error = ""
	return true


func generate_synthetic(dataset: Dictionary, seconds: float = 12.0, sample_hz: float = 30.0) -> bool:
	var nodes: Array = dataset.get("nodes", [])
	var samples: Array = []
	var stream_count := mini(nodes.size(), 4)
	var length := clampf(seconds, 0.1, 60.0)
	var hz := clampf(sample_hz, 1.0, 60.0)
	var count := mini(int(length * hz) + 1, MAX_SAMPLES / maxi(stream_count, 1))
	for frame in range(count):
		var t := float(frame) / hz
		for index in range(stream_count):
			var node: Dictionary = nodes[index]
			samples.append({"time": t, "kind": "node", "id": node.id,
				"value": sin(t * TAU * float(index + 1) / length + index * 0.5) * 0.65,
				"value_kind": "derived", "units": "unitless",
				"operation": "Synthetic sine calibration stream; not measured activation or causal influence"})
	return set_validated({"schema": SCHEMA, "source_id": dataset.manifest.source_id,
		"source_revision": dataset.manifest.revision, "samples": samples}, dataset)


func advance(seconds: float) -> Dictionary:
	if not enabled or _samples.is_empty() or not is_finite(seconds):
		return _latest
	var time := seconds
	if loop and duration > 0.0:
		time = fposmod(time, duration)
	else:
		time = clampf(time, 0.0, duration)
	if time < _last_time:
		_cursor = 0
		_latest.clear()
	_last_time = time
	var stop := _upper_bound(time)
	var count := stop - _cursor
	if count > MAX_DRAIN_PER_FRAME:
		# Binary search each bounded stream: latest values survive arbitrary bursts,
		# while no frame drains more than 256 samples or scans the whole recording.
		for key in _streams:
			var stream: Array = _streams[key]
			var index := _upper_bound_in(stream, time) - 1
			if index >= 0:
				_latest[key] = stream[index]
		coalesced_samples += count - _streams.size()
	else:
		for index in range(_cursor, stop):
			var sample: Dictionary = _samples[index]
			_latest[sample.key] = sample
	_cursor = stop
	return _latest


func get_latest(kind: String, id: String) -> Dictionary:
	return _latest.get(kind + ":" + id, {})


func get_metrics() -> Dictionary:
	return {"enabled": enabled, "samples": _samples.size(), "streams": _streams.size(),
		"cursor": _cursor, "duration_seconds": duration, "coalesced_samples": coalesced_samples,
		"maximum_samples_per_frame": MAX_DRAIN_PER_FRAME}


func reset() -> void:
	_cursor = 0
	_last_time = -1.0
	_latest.clear()
	coalesced_samples = 0


func export_json(path: String) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify({"schema": SCHEMA, "source_id": source_id,
		"source_revision": source_revision, "samples": _samples}, "", true, true))
	return OK


func _upper_bound(time: float) -> int:
	return _upper_bound_in(_samples, time)


static func _upper_bound_in(samples: Array, time: float) -> int:
	var low := 0
	var high := samples.size()
	while low < high:
		var mid := (low + high) / 2
		if float(samples[mid].time) <= time:
			low = mid + 1
		else:
			high = mid
	return low


func _error(message: String) -> bool:
	last_error = message
	return false


static func _number(value) -> bool:
	return (value is float or value is int) and is_finite(float(value))
