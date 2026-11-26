extends RefCounted
## Click and through-depth rectangle selection of exact source items.
## A supplied curve provider reproduces rendered primary bends on click only.
## Decorative fibres and proxies never create new scientific source IDs.

const MAX_CURVE_CANDIDATES := 1024


static func pick(camera: Camera3D, dataset: Dictionary, screen_point: Vector2, radius: float = 9.0, hidden_layers: Array = [], curve_provider: Node = null) -> Dictionary:
	var nearest := {"kind": "none", "id": "", "distance_px": radius}
	var projected: Dictionary = {}
	var depths: Dictionary = {}
	var nodes: Array = dataset.get("nodes", [])
	var best_depth := INF
	for node in nodes:
		if int(node.layer) in hidden_layers or camera.is_position_behind(node.position):
			continue
		var p: Vector2 = camera.unproject_position(node.position)
		projected[node.index] = p
		depths[node.index] = camera.global_position.distance_to(node.position)
		if is_instance_valid(curve_provider) and curve_provider.has_method("source_node_is_visible") and not curve_provider.source_node_is_visible(node.id):
			continue
		var distance := p.distance_to(screen_point)
		if distance < float(nearest.distance_px) - 0.25 or (distance <= float(nearest.distance_px) and float(depths[node.index]) < best_depth):
			nearest = {"kind": "node", "id": node.id, "distance_px": distance}
			best_depth = depths[node.index]
	# Give tiny nodes a stable acquisition target instead of a forest of incident links.
	if nearest.kind == "node":
		nearest["hit_semantics"] = "exact-source-node"
		return nearest
	if is_instance_valid(curve_provider) and curve_provider.has_method("curve_world_position"):
		return _pick_curves(camera, dataset, screen_point, radius, projected, curve_provider)
	best_depth = INF
	for edge in dataset.get("edges", []):
		if not projected.has(edge.from_index) or not projected.has(edge.to_index):
			continue
		var a: Vector2 = projected[edge.from_index]
		var b: Vector2 = projected[edge.to_index]
		var ab := b - a
		var t := clampf((screen_point - a).dot(ab) / maxf(ab.length_squared(), 0.00001), 0.0, 1.0)
		var distance := screen_point.distance_to(a + ab * t)
		var depth := lerpf(float(depths[edge.from_index]), float(depths[edge.to_index]), t)
		if distance < float(nearest.distance_px) - 0.25 or (distance <= float(nearest.distance_px) and depth < best_depth):
			nearest = {"kind": "edge", "id": edge.id, "distance_px": distance, "hit_semantics": "exact-source-segment"}
			best_depth = depth
	return nearest


static func _pick_curves(camera: Camera3D, dataset: Dictionary, point: Vector2, radius: float, projected: Dictionary, provider: Node) -> Dictionary:
	var candidates: Array = []
	var offset: float = provider.max_primary_offset()
	var viewport := camera.get_viewport().get_visible_rect().size
	var focal := viewport.y / (2.0 * tan(deg_to_rad(camera.fov * 0.5)))
	var forward := -camera.global_basis.z
	var camera_position := camera.global_position
	for edge in dataset.get("edges", []):
		if not provider.source_edge_is_visible(edge.id):
			continue
		if not projected.has(edge.from_index) or not projected.has(edge.to_index):
			# At extreme close-up a visible segment can cross the camera plane.
			# Missing endpoint projections are conservative candidates, not grounds
			# to discard the curve; the segment loop clips to the near plane below.
			var depth_a: float = (edge.a - camera_position).dot(forward)
			var depth_b: float = (edge.b - camera_position).dot(forward)
			if maxf(depth_a, depth_b) + offset >= camera.near:
				candidates.append({"id": edge.id, "distance": 0.0})
			continue
		var a: Vector2 = projected[edge.from_index]
		var b: Vector2 = projected[edge.to_index]
		var near_depth := minf((edge.a - camera_position).dot(forward), (edge.b - camera_position).dot(forward))
		var off_axis := maxf((a - viewport * 0.5).length(), (b - viewport * 0.5).length()) / maxf(focal, 1.0)
		var expansion := radius + offset * focal * (1.0 + off_axis) / maxf(near_depth - offset, camera.near)
		if not Rect2(a, b - a).abs().grow(expansion).has_point(point):
			continue
		var ab := b - a
		var t := clampf((point - a).dot(ab) / maxf(ab.length_squared(), 0.00001), 0.0, 1.0)
		var distance := point.distance_squared_to(a + ab * t)
		candidates.append({"id": edge.id, "distance": distance})
	# A very dense crossing is deliberately a bounded hit query. The selected ID
	# still addresses the actual tested primary curve, never an inferred edge.
	candidates.sort_custom(func(a: Dictionary, b: Dictionary):
		return a.distance < b.distance if a.distance != b.distance else a.id < b.id)
	var count := mini(candidates.size(), MAX_CURVE_CANDIDATES)
	var segments := clampi(int(provider.curve_sample_count()), 1, 128)
	var nearest := {"kind": "none", "id": "", "distance_px": radius,
		"hit_semantics": "rendered-primary-polyline", "curve_candidates": count,
		"candidate_limit_reached": candidates.size() > MAX_CURVE_CANDIDATES,
		"warning": "Dense hit region: tested the nearest %d primary-curve candidates; chosen source ID is exact, absolute nearest curve is not guaranteed." % MAX_CURVE_CANDIDATES if candidates.size() > MAX_CURVE_CANDIDATES else ""}
	var best_depth := INF
	for candidate_index in range(count):
		var id: String = candidates[candidate_index].id
		var previous: Vector3 = provider.curve_world_position(id, 0.0)
		for step in range(1, segments + 1):
			var current: Vector3 = provider.curve_world_position(id, float(step) / segments)
			var a3 := previous
			var b3 := current
			previous = current
			var da := (a3 - camera_position).dot(forward)
			var db := (b3 - camera_position).dot(forward)
			if da < camera.near and db < camera.near:
				continue
			if da < camera.near:
				a3 = a3.lerp(b3, (camera.near - da) / maxf(db - da, 0.000001))
			elif db < camera.near:
				b3 = b3.lerp(a3, (camera.near - db) / maxf(da - db, 0.000001))
			var a := camera.unproject_position(a3)
			var b := camera.unproject_position(b3)
			var ab := b - a
			var t := clampf((point - a).dot(ab) / maxf(ab.length_squared(), 0.00001), 0.0, 1.0)
			var distance := point.distance_to(a + ab * t)
			var depth := lerpf(da, db, t)
			if distance < float(nearest.distance_px) - 0.05 or (distance <= float(nearest.distance_px) and depth < best_depth):
				nearest.kind = "edge"
				nearest.id = id
				nearest.distance_px = distance
				best_depth = depth
	return nearest


static func box(camera: Camera3D, dataset: Dictionary, rectangle: Rect2, hidden_layers: Array = []) -> Dictionary:
	var region := rectangle.abs()
	var node_ids: Array = []
	var edge_ids: Array = []
	var membership: Dictionary = {}
	for node in dataset.get("nodes", []):
		if int(node.layer) in hidden_layers or camera.is_position_behind(node.position):
			continue
		if region.has_point(camera.unproject_position(node.position)):
			node_ids.append(node.id)
			membership[node.index] = true
	for edge in dataset.get("edges", []):
		if membership.has(edge.from_index) and membership.has(edge.to_index):
			edge_ids.append(edge.id)
	return {"node_ids": node_ids, "edge_ids": edge_ids,
		"selection_origin": "projected-through-depth-box-induced-edges"}


static func brush(camera: Camera3D, dataset: Dictionary, point: Vector2, radius: float, hidden_layers: Array = []) -> Dictionary:
	var node_ids: Array = []
	var edge_ids: Array = []
	var membership: Dictionary = {}
	for node in dataset.get("nodes", []):
		if int(node.layer) in hidden_layers or camera.is_position_behind(node.position):
			continue
		if camera.unproject_position(node.position).distance_squared_to(point) <= radius * radius:
			node_ids.append(node.id)
			membership[node.index] = true
	for edge in dataset.get("edges", []):
		if membership.has(edge.from_index) and membership.has(edge.to_index):
			edge_ids.append(edge.id)
	return {"node_ids": node_ids, "edge_ids": edge_ids,
		"selection_origin": "projected-through-depth-brush-induced-edges"}
