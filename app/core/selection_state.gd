extends RefCounted
## Exact source selection plus bounded, graphics-only undo. No source mutation.

signal changed

const MAX_HISTORY := 48
const MATERIALISATIONS := ["none", "knot", "ribbon", "membrane"]

var _dataset: Dictionary = {"manifest": {}, "nodes": [], "edges": []}
var _nodes: Dictionary = {}
var _edges: Dictionary = {}
var _incident: Dictionary = {}
var _state: Dictionary = _empty_state()
var _undo: Array = []
var _redo: Array = []


func bind_dataset(dataset: Dictionary) -> void:
	var old_revision: String = _dataset.manifest.get("revision", "")
	var old_source_id: String = _dataset.manifest.get("source_id", "")
	_dataset = dataset
	_nodes.clear()
	_edges.clear()
	_incident.clear()
	for node in dataset.get("nodes", []):
		_nodes[node.id] = node
		_incident[node.id] = []
	for edge in dataset.get("edges", []):
		_edges[edge.id] = edge
		var a: Dictionary = dataset.nodes[edge.from_index]
		var b: Dictionary = dataset.nodes[edge.to_index]
		_incident[a.id].append(edge.id)
		if a.id != b.id:
			_incident[b.id].append(edge.id)
	if old_revision != str(dataset.manifest.get("revision", "")) or old_source_id != str(dataset.manifest.get("source_id", "")):
		_state = _empty_state()
		_undo.clear()
		_redo.clear()
	changed.emit()


func select(node_ids: Array, edge_ids: Array, additive: bool = false, semantics: String = "exact-listed-elements") -> void:
	var next := _state.duplicate(true)
	var nodes: Dictionary = {}
	var edges: Dictionary = {}
	if additive:
		for id in _state.node_ids:
			nodes[id] = true
		for id in _state.edge_ids:
			edges[id] = true
	for id in node_ids:
		if _nodes.has(id):
			nodes[id] = true
	for id in edge_ids:
		if _edges.has(id):
			edges[id] = true
	next.node_ids = nodes.keys()
	next.edge_ids = edges.keys()
	next.node_ids.sort()
	next.edge_ids.sort()
	next.selection_origin = semantics
	if next.node_ids.is_empty() and next.edge_ids.is_empty():
		next.materialisation = "none"
	_commit(next)


func select_node(id: String, include_incident: bool = true, additive: bool = false) -> void:
	if not _nodes.has(id):
		return
	select([id], _incident.get(id, []) if include_incident else [], additive,
		"node-and-exact-incident-edges" if include_incident else "exact-node")


func select_edge(id: String, additive: bool = false) -> void:
	if not _edges.has(id):
		return
	select([], [id], additive, "exact-edge")


func select_layer(layer: int, include_incident: bool = true) -> void:
	var selected_nodes: Array = []
	var selected_edges: Dictionary = {}
	for node in _dataset.nodes:
		if int(node.layer) != layer:
			continue
		selected_nodes.append(node.id)
		if include_incident:
			for id in _incident[node.id]:
				selected_edges[id] = true
	select(selected_nodes, selected_edges.keys(), false, "layer-and-exact-incident-edges")


func select_band(layer: int, first_channel: int, channel_count: int) -> void:
	# A compact, exactly enumerated two-layer region for hybrid composition.
	var selected_nodes: Array = []
	var membership: Dictionary = {}
	for node in _dataset.nodes:
		if int(node.layer) in [layer, layer + 1] and int(node.channel) >= first_channel and int(node.channel) < first_channel + channel_count:
			selected_nodes.append(node.id)
			membership[node.index] = true
	var selected_edges: Array = []
	for edge in _dataset.edges:
		if membership.has(edge.from_index) and membership.has(edge.to_index):
			selected_edges.append(edge.id)
	select(selected_nodes, selected_edges, false, "exact-induced-two-layer-region")


func clear() -> void:
	var next := _state.duplicate(true)
	next.node_ids = []
	next.edge_ids = []
	next.materialisation = "none"
	_commit(next)


func set_isolated(active: bool) -> void:
	var next := _state.duplicate(true)
	next.isolate = active
	_commit(next)


func set_materialisation(kind: String) -> bool:
	if not kind in MATERIALISATIONS:
		return false
	if kind != "none" and _state.node_ids.is_empty() and _state.edge_ids.is_empty():
		return false
	var next := _state.duplicate(true)
	next.materialisation = kind
	_commit(next)
	return true


func set_layer_visible(layer: int, visible: bool) -> void:
	if layer < 0 or layer > 1024:
		return
	var next := _state.duplicate(true)
	if visible:
		next.hidden_layers.erase(layer)
	elif not layer in next.hidden_layers:
		next.hidden_layers.append(layer)
	next.hidden_layers.sort()
	_commit(next)


func reveal() -> void:
	var next := _state.duplicate(true)
	next.isolate = false
	next.hidden_layers = []
	_commit(next)


func restore_visual_state(state: Dictionary) -> bool:
	# One graphics-history entry and one renderer refresh for a recalled scene.
	if not state.get("node_ids", null) is Array or not state.get("edge_ids", null) is Array or not state.get("hidden_layers", null) is Array:
		return false
	if not state.get("isolate", null) is bool or not str(state.get("materialisation", "")) in MATERIALISATIONS:
		return false
	var next := _empty_state()
	var seen_nodes: Dictionary = {}
	var seen_edges: Dictionary = {}
	for id in state.node_ids:
		if not _nodes.has(id) or seen_nodes.has(id):
			return false
		seen_nodes[id] = true
		next.node_ids.append(id)
	for id in state.edge_ids:
		if not _edges.has(id) or seen_edges.has(id):
			return false
		seen_edges[id] = true
		next.edge_ids.append(id)
	for layer in state.hidden_layers:
		if not (layer is int or layer is float) or not is_finite(float(layer)) or float(layer) != floor(float(layer)) or int(layer) < 0 or int(layer) > 1024:
			return false
		if not int(layer) in next.hidden_layers:
			next.hidden_layers.append(int(layer))
	next.node_ids.sort()
	next.edge_ids.sort()
	next.hidden_layers.sort()
	next.isolate = state.isolate
	next.materialisation = state.materialisation if not (next.node_ids.is_empty() and next.edge_ids.is_empty()) else "none"
	next.selection_origin = str(state.get("selection_origin", "exact-listed-elements"))
	_commit(next)
	return true


func get_visual_state() -> Dictionary:
	return _state.duplicate(true)


func get_reference() -> Dictionary:
	var manifest: Dictionary = _dataset.manifest
	return {"schema": "xenovection.selection.v1",
		"source_id": manifest.get("source_id", ""), "source_revision": manifest.get("revision", ""),
		"projection_revision": manifest.get("projection_revision", ""),
		"upstream_revision": manifest.get("upstream_revision", ""),
		"coordinate_mapping": manifest.get("coordinate_mapping", ""),
		"selection_semantics": "exact-listed-elements", "selection_origin": _state.selection_origin,
		"node_ids": _state.node_ids.duplicate(), "edge_ids": _state.edge_ids.duplicate()}


func get_selected_points() -> PackedVector3Array:
	var indices: Dictionary = {}
	for id in _state.node_ids:
		indices[_nodes[id].index] = true
	for id in _state.edge_ids:
		indices[_edges[id].from_index] = true
		indices[_edges[id].to_index] = true
	var points := PackedVector3Array()
	for index in indices:
		points.append(_dataset.nodes[index].position)
	return points


func undo() -> bool:
	if _undo.is_empty():
		return false
	_redo.append(_state.duplicate(true))
	_state = _undo.pop_back()
	changed.emit()
	return true


func redo() -> bool:
	if _redo.is_empty():
		return false
	_undo.append(_state.duplicate(true))
	_state = _redo.pop_back()
	changed.emit()
	return true


func get_history_counts() -> Vector2i:
	return Vector2i(_undo.size(), _redo.size())


func _commit(next: Dictionary) -> void:
	if next == _state:
		return
	_undo.append(_state.duplicate(true))
	if _undo.size() > MAX_HISTORY:
		_undo.pop_front()
	_redo.clear()
	_state = next
	changed.emit()


static func _empty_state() -> Dictionary:
	return {"node_ids": [], "edge_ids": [], "isolate": false, "hidden_layers": [],
		"materialisation": "none", "selection_origin": "exact-listed-elements"}
