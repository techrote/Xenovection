extends RefCounted
## Read-only, versioned source snapshots. Visual state never lives in this object.

const SCHEMA := "xenovection.source.v1"
const MAX_NODES := 8192
const MAX_EDGES := 262144
const MAX_FILE_BYTES := 32 * 1024 * 1024
const VALUE_KINDS := ["measured", "derived", "artistic"]
const HISTORICAL_SPECIMEN_SHA256 := "745d47fa3ebd6a91ce1c9bd11181688ce4237199bbbce11e2e330dc76d78947c"
const HISTORICAL_SOURCE_ID := "found-001-synthetic-foundry"

static var _historical_reference: Dictionary = {}

var _dataset: Dictionary = {"manifest": {}, "nodes": [], "edges": []}
var _node_lookup: Dictionary = {}
var _edge_lookup: Dictionary = {}
var _incident: Dictionary = {}
var last_error := ""


func get_dataset() -> Dictionary:
	# Treat this shared snapshot as read-only. Copy only at the import/export boundary.
	return _dataset


func get_node(source_id: String) -> Dictionary:
	return _node_lookup.get(source_id, {})


func get_edge(source_id: String) -> Dictionary:
	return _edge_lookup.get(source_id, {})


func incident_edges(node_id: String) -> Array:
	return _incident.get(node_id, []).duplicate()


func load_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _failure("Cannot open source file: %s" % path)
	if file.get_length() > MAX_FILE_BYTES:
		return _failure("Source file exceeds the 32 MiB input limit")
	var parser := JSON.new()
	var json_bytes := file.get_buffer(file.get_length())
	var json_text := json_bytes.get_string_from_utf8()
	var code := parser.parse(json_text)
	if code != OK or not parser.data is Dictionary:
		return _failure("Invalid source JSON: %s" % parser.get_error_message())
	if parser.data.get("schema", "") == "frankenfield.synthetic-dense-tanh.v1":
		return _import_historical(parser.data, _hash_bytes(json_bytes), true)
	return set_validated(parser.data)


func import_historical(input: Dictionary, specimen_sha256: String) -> Dictionary:
	# The public adapter cannot confer custody merely from a caller-supplied hash.
	return _import_historical(input, specimen_sha256, false)


func _import_historical(input: Dictionary, specimen_sha256: String, verified_bytes: bool) -> Dictionary:
	# Exact archived coefficients, in original [layer][output][input] order.
	var recovered_baseline := specimen_sha256 == HISTORICAL_SPECIMEN_SHA256
	if input.get("layers", 0) != 6 or input.get("channels", 0) != 48:
		return _failure("Historical specimen must contain exactly six layers and 48 channels")
	if not input.get("input", null) is Array or input.input.size() != 48:
		return _failure("Historical input dimension is invalid")
	if not input.get("weights", null) is Array or input.weights.size() != 5:
		return _failure("Historical matrix count is invalid")
	var activations: Array = []
	for value in input.input:
		if not _finite_number(value) or absf(float(value)) > 1.0e6:
			return _failure("Historical input contains a non-finite or unbounded value")
		activations.append(float(value))
	var nodes: Array = []
	var edges: Array = []
	for layer in range(6):
		if layer > 0:
			var matrix = input.weights[layer - 1]
			if not matrix is Array or matrix.size() != 48:
				return _failure("Historical matrix row count is invalid")
			var next: Array = []
			for output in range(48):
				var row = matrix[output]
				if not row is Array or row.size() != 48:
					return _failure("Historical matrix column count is invalid")
				var z := 0.0
				for input_index in range(48):
					if not _finite_number(row[input_index]) or absf(float(row[input_index])) > 1.0e6:
						return _failure("Historical weight is non-finite or unbounded")
					var weight := float(row[input_index])
					z += weight * float(activations[input_index])
					edges.append({"id": "e:%d:%d:%d" % [layer - 1, output, input_index],
						"from_index": (layer - 1) * 48 + input_index,
						"to_index": layer * 48 + output,
						"weight": weight, "value_kind": "derived"})
				next.append(tanh(z))
			activations = next
		for channel in range(48):
			nodes.append({"id": "n:%d:%d" % [layer, channel], "layer": layer,
				"channel": channel, "position": project_node(layer, channel, 48),
				"value": activations[channel], "value_kind": "derived"})
	return _validate_and_set({"schema": SCHEMA, "manifest": {
		"source_id": HISTORICAL_SOURCE_ID if recovered_baseline else "frankenfield-import-" + specimen_sha256.substr(0, 12),
		"source_kind": "synthetic-historical" if recovered_baseline else "synthetic-imported",
		"coordinate_mapping": "layered-orbits-v1", "upstream_revision": "sha256:" + specimen_sha256,
		"description": "Exact recovered FOUND-001 coefficients; analytical tanh values; new artistic coordinate projection" if recovered_baseline else "Imported FRANKENFIELD-format synthetic specimen; distinct from the recovered historical baseline"},
		"nodes": nodes, "edges": edges}, "sha256:" + specimen_sha256, verified_bytes and recovered_baseline)


func set_validated(input: Dictionary) -> Dictionary:
	return _validate_and_set(input)


func _validate_and_set(input: Dictionary, verified_revision: String = "", historical_bytes_verified: bool = false) -> Dictionary:
	# Validate completely before replacing the current snapshot.
	if input.get("schema", "") != SCHEMA:
		return _failure("Unsupported source schema")
	if not input.get("manifest", null) is Dictionary:
		return _failure("Source manifest is required")
	var manifest_in: Dictionary = input.manifest
	var source_id := str(manifest_in.get("source_id", ""))
	if source_id.is_empty() or source_id.length() > 128:
		return _failure("Source ID must contain 1–128 characters")
	if not input.get("nodes", null) is Array or not input.get("edges", null) is Array:
		return _failure("Source nodes and edges must be arrays")
	if input.nodes.size() > MAX_NODES or input.edges.size() > MAX_EDGES:
		return _failure("Source exceeds bounded node/edge capacity")
	var nodes: Array = []
	var edges: Array = []
	var node_lookup: Dictionary = {}
	var edge_lookup: Dictionary = {}
	var incident: Dictionary = {}
	for raw in input.nodes:
		if not raw is Dictionary:
			return _failure("Node must be an object")
		var id := str(raw.get("id", ""))
		if id.is_empty() or id.length() > 128 or node_lookup.has(id):
			return _failure("Missing, duplicated or oversized node ID")
		var point = _as_vector3(raw.get("position", null))
		if point == null:
			return _failure("Node %s has invalid coordinates" % id)
		var value = raw.get("value", 0.0)
		if raw.has("value_f64_le"):
			value = _decode_exact(raw.value_f64_le)
		if not _finite_number(value) or absf(float(value)) > 1.0e12:
			return _failure("Node %s has invalid scalar value" % id)
		var value_kind := str(raw.get("value_kind", "derived"))
		if not value_kind in VALUE_KINDS:
			return _failure("Unknown node value classification")
		var layer = raw.get("layer", 0)
		var channel = raw.get("channel", nodes.size())
		if not _whole_number(layer, 0, 1024) or not _whole_number(channel, 0, MAX_NODES):
			return _failure("Invalid layer/channel source address")
		var node := {
			"id": id, "index": nodes.size(), "position": point,
			"layer": int(layer), "channel": int(channel), "value": float(value),
			"value_kind": value_kind, "units": str(raw.get("units", "unitless")),
			"position_kind": "derived"
		}
		nodes.append(node)
		node_lookup[id] = node
		incident[id] = []
	for raw in input.edges:
		if not raw is Dictionary:
			return _failure("Edge must be an object")
		var id := str(raw.get("id", ""))
		if id.is_empty() or id.length() > 128 or edge_lookup.has(id):
			return _failure("Missing, duplicated or oversized edge ID")
		var from_index = raw.get("from_index", -1)
		var to_index = raw.get("to_index", -1)
		if not _whole_number(from_index, 0, nodes.size() - 1) or not _whole_number(to_index, 0, nodes.size() - 1):
			return _failure("Edge %s references an absent node" % id)
		var weight = raw.get("weight", 0.0)
		if raw.has("weight_f64_le"):
			weight = _decode_exact(raw.weight_f64_le)
		if not _finite_number(weight) or absf(float(weight)) > 1.0e12:
			return _failure("Edge %s has invalid weight" % id)
		var value_kind := str(raw.get("value_kind", "derived"))
		if not value_kind in VALUE_KINDS:
			return _failure("Unknown edge value classification")
		var relation := str(raw.get("relation", "connection"))
		var units := str(raw.get("units", "unitless"))
		if relation.length() > 128 or units.length() > 128:
			return _failure("Edge relation or units exceed the bounded metadata length")
		var a: Dictionary = nodes[int(from_index)]
		var b: Dictionary = nodes[int(to_index)]
		var edge := {
			"id": id, "index": edges.size(),
			"from_index": int(from_index), "to_index": int(to_index),
			"source": a.id, "target": b.id, "a": a.position, "b": b.position,
			"weight": float(weight), "value": float(weight), "value_kind": value_kind,
			"relation": relation, "units": units,
			"layer": a.layer, "contribution": float(weight) * float(a.value)
		}
		edges.append(edge)
		edge_lookup[id] = edge
		incident[a.id].append(id)
		if a.id != b.id:
			incident[b.id].append(id)
	var mapping := str(manifest_in.get("coordinate_mapping", "explicit-3d-v1"))
	var canonical := _canonical(source_id, mapping, nodes, edges)
	var digest := canonical.sha256_text()
	if manifest_in.has("content_sha256") and str(manifest_in.content_sha256) != digest:
		return _failure("Content hash does not match the declared source snapshot")
	var scientific_digest := _canonical(source_id, "", nodes, edges, false).sha256_text()
	var revision := "sha256:" + scientific_digest
	# A self-hash proves internal consistency, not custody of the recovered specimen.
	var historical_revision := "sha256:" + HISTORICAL_SPECIMEN_SHA256
	var reserved_claim := source_id == HISTORICAL_SOURCE_ID \
		or str(manifest_in.get("revision", "")) == historical_revision \
		or str(manifest_in.get("source_kind", "")) == "synthetic-historical" \
		or verified_revision == historical_revision
	var historical_custody_verified := historical_bytes_verified and verified_revision == historical_revision
	if reserved_claim and not historical_custody_verified:
		var reference := _get_verified_historical_reference()
		if reference.is_empty() or not _matches_historical_source(source_id, nodes, edges, reference):
			return _failure("Reserved FOUND-001 identity does not match the locally verified recovered scientific source")
		historical_custody_verified = true
	var revision_basis := "Scientific source values and topology; projection is separately hashed"
	# Ordinary upstream revisions are declared provenance. The content hash does not
	# authenticate their origin; only the reserved historical identity is verified.
	if manifest_in.has("content_sha256") and str(manifest_in.get("revision", "")).begins_with("sha256:"):
		revision = str(manifest_in.revision)
		revision_basis = "Declared upstream revision; snapshot content verified separately; historical custody unverified"
	var manifest := {
		"schema": SCHEMA, "source_id": source_id, "revision": revision,
		"projection_revision": "sha256:" + digest,
		"revision_basis": revision_basis,
		"historical_custody_verified": historical_custody_verified,
		"content_sha256": digest, "coordinate_mapping": mapping,
		"upstream_revision": str(manifest_in.get("upstream_revision", manifest_in.get("revision", ""))),
		"description": str(manifest_in.get("description", "Imported read-only source")),
		"source_kind": str(manifest_in.get("source_kind", "imported")),
		"read_only": true, "node_count": nodes.size(), "edge_count": edges.size(),
		"positions": "derived visual projection; not measured physical positions"
	}
	if not verified_revision.is_empty():
		manifest.revision = verified_revision
		manifest.revision_basis = "SHA-256 of the exact imported specimen bytes"
	if historical_custody_verified:
		manifest.revision = historical_revision
		manifest.source_kind = "synthetic-historical"
		manifest.revision_basis = "Recovered raw specimen SHA-256; scientific values and topology verified against local custody reference"
	# Freeze every nested mutable container once, at the source boundary. Renderers
	# share the snapshot without per-frame copies and cannot accidentally edit it.
	for node in nodes:
		node.make_read_only()
	for edge in edges:
		edge.make_read_only()
	nodes.make_read_only()
	edges.make_read_only()
	manifest.make_read_only()
	_dataset = {"schema": SCHEMA, "manifest": manifest, "nodes": nodes, "edges": edges}
	_dataset.make_read_only()
	if historical_bytes_verified and historical_custody_verified:
		_historical_reference = _dataset
	_node_lookup = node_lookup
	_edge_lookup = edge_lookup
	_incident = incident
	last_error = ""
	return {"ok": true, "revision": manifest.revision, "nodes": nodes.size(), "edges": edges.size()}


func _get_verified_historical_reference() -> Dictionary:
	if not _historical_reference.is_empty():
		return _historical_reference
	var raw_bytes := FileAccess.get_file_as_bytes("res://data/synthetic_foundry.json")
	if _hash_bytes(raw_bytes) != HISTORICAL_SPECIMEN_SHA256:
		return {}
	var raw = JSON.parse_string(raw_bytes.get_string_from_utf8())
	if not raw is Dictionary:
		return {}
	var reference_source = get_script().new()
	var result: Dictionary = reference_source._import_historical(raw, HISTORICAL_SPECIMEN_SHA256, true)
	return reference_source.get_dataset() if result.get("ok", false) else {}


static func _matches_historical_source(source_id: String, nodes: Array, edges: Array, reference: Dictionary) -> bool:
	if source_id != HISTORICAL_SOURCE_ID or nodes.size() != reference.nodes.size() or edges.size() != reference.edges.size():
		return false
	var expected_nodes: Dictionary = {}
	var expected_edges: Dictionary = {}
	for node in reference.nodes:
		expected_nodes[node.id] = node
	for edge in reference.edges:
		expected_edges[edge.id] = edge
	for node in nodes:
		if not expected_nodes.has(node.id):
			return false
		var expected: Dictionary = expected_nodes[node.id]
		if node.layer != expected.layer or node.channel != expected.channel \
			or node.value_kind != expected.value_kind or node.units != expected.units:
			return false
		# Inputs are exact source bytes; later activations are derived tanh values.
		# Permit only tiny libm differences across operating systems for the latter.
		if (node.layer == 0 and _encode_exact(node.value) != _encode_exact(expected.value)) \
			or (node.layer > 0 and absf(node.value - expected.value) > 1.0e-13):
			return false
	for edge in edges:
		if not expected_edges.has(edge.id):
			return false
		var expected: Dictionary = expected_edges[edge.id]
		if edge.source != expected.source or edge.target != expected.target \
			or edge.value_kind != expected.value_kind or edge.units != expected.units \
			or edge.relation != expected.relation or _encode_exact(edge.weight) != _encode_exact(expected.weight):
			return false
	return true


func generate_synthetic(density: int = 48) -> Dictionary:
	# New FOUND-002 specimen; explicitly distinct from the recovered FOUND-001 archive.
	var channels := clampi(density, 1, 192)
	var nodes: Array = []
	var edges: Array = []
	var activations: Array = []
	var state: int = 0x58454e4f
	for channel in range(channels):
		activations.append(sin(float(channel + 1) * 0.31) * 0.6)
	for layer in range(6):
		if layer > 0:
			var next: Array = []
			for output in range(channels):
				var z := 0.0
				for input_index in range(channels):
					state = (state * 1664525 + 1013904223) & 0xffffffff
					var weight := (float(state >> 8) / 8388607.5 - 1.0) * 1.7 / sqrt(float(channels))
					z += weight * float(activations[input_index])
					edges.append({"id": "e/%d/%d/%d" % [layer - 1, input_index, output],
						"from_index": (layer - 1) * channels + input_index,
						"to_index": layer * channels + output,
						"weight": weight, "value_kind": "derived"})
				next.append(tanh(z))
			activations = next
		for channel in range(channels):
			nodes.append({"id": "n/%d/%d" % [layer, channel], "layer": layer,
				"channel": channel, "position": project_node(layer, channel, channels),
				"value": activations[channel], "value_kind": "derived"})
	return set_validated({"schema": SCHEMA,
		"manifest": {"source_id": "found-002-synthetic-%d" % channels,
			"source_kind": "synthetic", "coordinate_mapping": "layered-orbits-v1",
			"description": "Deterministic six-layer tanh specimen; new FOUND-002 synthesis, not the historical archive"},
		"nodes": nodes, "edges": edges})


func generate_spatial_flow() -> Dictionary:
	# A static analytical specimen, not a fluid simulation or measured velocity.
	# Each ring is an independently addressed neighbouring streamline. Sparse
	# cross-couplings make its source topology more than disconnected decoration.
	const STREAMS := 64
	const SAMPLES := 72
	var nodes: Array = []
	var edges: Array = []
	for stream in range(STREAMS):
		var alpha := TAU * float(stream) / float(STREAMS)
		var radius := 0.58 + 0.24 * sin(5.0 * alpha + 0.3)
		for sample_index in range(SAMPLES):
			var t := TAU * float(sample_index) / float(SAMPLES)
			var radial := Vector3(cos(2.0 * t), 0.0, sin(2.0 * t))
			var ring_radius := 4.2 + 1.3 * cos(3.0 * t)
			var center := radial * ring_radius + Vector3.UP * (1.3 * sin(3.0 * t))
			var radial_derivative := Vector3(-2.0 * sin(2.0 * t), 0.0, 2.0 * cos(2.0 * t))
			var tangent := (radial_derivative * ring_radius - radial * (3.9 * sin(3.0 * t))
				+ Vector3.UP * (3.9 * cos(3.0 * t))).normalized()
			var normal := (radial - tangent * radial.dot(tangent)).normalized()
			var binormal := tangent.cross(normal).normalized()
			var twist := alpha + 2.0 * t + 0.28 * sin(3.0 * t + alpha)
			var position := center + radius * (normal * cos(twist) + binormal * (0.78 * sin(twist)))
			var field := 0.6 * sin(3.0 * t + alpha) + 0.25 * cos(2.0 * t - alpha)
			nodes.append({"id": "flow:n:%02d:%02d" % [stream, sample_index],
				"layer": stream / 8, "channel": sample_index, "position": position,
				"value": field, "value_kind": "derived", "units": "synthetic_field"})
	for stream in range(STREAMS):
		var alpha := TAU * float(stream) / float(STREAMS)
		var polarity := 1.0 if stream % 2 == 0 else -1.0
		for sample_index in range(SAMPLES):
			var t := TAU * float(sample_index) / float(SAMPLES)
			var here := stream * SAMPLES + sample_index
			var next := stream * SAMPLES + (sample_index + 1) % SAMPLES
			edges.append({"id": "flow:e:%02d:%02d" % [stream, sample_index],
				"from_index": here, "to_index": next,
				"weight": polarity * (0.5 + 0.2 * sin(4.0 * t + alpha)),
				"value_kind": "derived", "units": "synthetic_transport", "relation": "streamline_step"})
			if (sample_index + stream) % 3 == 0:
				edges.append({"id": "flow:c:%02d:%02d" % [stream, sample_index],
					"from_index": here, "to_index": ((stream + 1) % STREAMS) * SAMPLES + sample_index,
					"weight": 0.08 * cos(alpha + 2.0 * t), "value_kind": "derived",
					"units": "synthetic_coupling", "relation": "neighbour_coupling"})
	return set_validated({"schema": SCHEMA,
		"manifest": {"source_id": "xenovection-spatial-flow-v1", "source_kind": "synthetic-spatial",
			"coordinate_mapping": "toroidal-neighbour-streamlines-v1",
			"description": "Analytical synthetic torus-knot field: 64 closed neighbouring streamlines, signed transport and sparse cross-couplings; not measured fluid data"},
		"nodes": nodes, "edges": edges})


static func project_node(layer: int, channel: int, channels: int) -> Vector3:
	var theta := TAU * float(channel) / float(maxi(channels, 1)) + float(layer) * 0.31
	var radius := 2.2 + 0.35 * sin(float(channel) * 2.39996 + float(layer) * 0.9)
	return Vector3((float(layer) - 2.5) * 2.2,
		cos(theta) * radius + 0.3 * sin(float(layer) * 1.1),
		sin(theta) * radius * 0.82)


func selection_reference(node_ids: Array, edge_ids: Array) -> Dictionary:
	var valid_nodes: Array = []
	var valid_edges: Array = []
	var seen_nodes: Dictionary = {}
	var seen_edges: Dictionary = {}
	for id in node_ids:
		if _node_lookup.has(id) and not seen_nodes.has(id):
			seen_nodes[id] = true
			valid_nodes.append(id)
	for id in edge_ids:
		if _edge_lookup.has(id) and not seen_edges.has(id):
			seen_edges[id] = true
			valid_edges.append(id)
	valid_nodes.sort()
	valid_edges.sort()
	return {"schema": "xenovection.selection.v1", "source_id": _dataset.manifest.get("source_id", ""),
		"source_revision": _dataset.manifest.get("revision", ""),
		"projection_revision": _dataset.manifest.get("projection_revision", ""),
		"coordinate_mapping": _dataset.manifest.get("coordinate_mapping", ""),
		"selection_semantics": "exact-listed-elements", "node_ids": valid_nodes, "edge_ids": valid_edges}


func export_json(path: String) -> Error:
	var value := _dataset.duplicate(true)
	for node in value.nodes:
		var p: Vector3 = node.position
		node.position = [p.x, p.y, p.z]
		# Decimal JSON parsers can round a binary64 value by one ULP. Preserve the
		# exact coefficient bits alongside ordinary readable numeric fields.
		node.value_f64_le = _encode_exact(float(node.value))
	for edge in value.edges:
		edge.weight_f64_le = _encode_exact(float(edge.weight))
		edge.erase("a")
		edge.erase("b")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(value, "", true, true))
	return OK


func _failure(message: String) -> Dictionary:
	last_error = message
	return {"ok": false, "error": message}


static func _finite_number(value) -> bool:
	return (value is float or value is int) and is_finite(float(value))


static func _hash_bytes(value: PackedByteArray) -> String:
	var hash_context := HashingContext.new()
	hash_context.start(HashingContext.HASH_SHA256)
	hash_context.update(value)
	return hash_context.finish().hex_encode()


static func _encode_exact(value: float) -> String:
	var bytes := PackedByteArray()
	bytes.resize(8)
	bytes.encode_double(0, value)
	return bytes.hex_encode()


static func _decode_exact(value):
	if not value is String or value.length() != 16 or not value.is_valid_hex_number(false):
		return null
	return value.hex_decode().decode_double(0)


static func _whole_number(value, minimum: int, maximum: int) -> bool:
	return _finite_number(value) and float(value) == floor(float(value)) and float(value) >= minimum and float(value) <= maximum


static func _as_vector3(value):
	var p: Vector3
	if value is Vector3:
		p = value
	elif value is Array and value.size() == 3:
		for component in value:
			if not _finite_number(component):
				return null
		p = Vector3(float(value[0]), float(value[1]), float(value[2]))
	else:
		return null
	if not p.is_finite():
		return null
	if absf(p.x) > 1.0e6 or absf(p.y) > 1.0e6 or absf(p.z) > 1.0e6:
		return null
	return p


static func _canonical(source_id: String, mapping: String, nodes: Array, edges: Array, include_projection: bool = true) -> String:
	var rows := PackedStringArray([SCHEMA, source_id, mapping])
	for node in nodes:
		var p: Vector3 = node.position
		var values: Array = [node.id, node.layer, node.channel, node.value, node.value_kind, node.units]
		if include_projection:
			values.append_array([p.x, p.y, p.z])
		rows.append(JSON.stringify(values, "", true, true))
	for edge in edges:
		var values: Array = [edge.id, edge.from_index, edge.to_index, edge.weight, edge.value_kind]
		# Preserve hashes of existing v1 snapshots using the implicit defaults.
		if edge.get("relation", "connection") != "connection" or edge.get("units", "unitless") != "unitless":
			values.append_array([edge.get("relation", "connection"), edge.get("units", "unitless")])
		rows.append(JSON.stringify(values, "", true, true))
	return "\n".join(rows)
