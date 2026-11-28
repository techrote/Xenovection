extends Node3D
## Bounded 3D presentation of the planar solver. Only detached snapshots enter this node.
## Identity-owned instance buffers persist; camera, quality and interpolation never write World.
const World = preload("res://ecology/world.gd")
const Bridge = preload("res://rendering/optical/material_bridge.gd")
const GeneratedShader = preload("res://rendering/optical/generated_optical.gdshader")
const FAMILY_TINTS = [Color(0.48, 0.96, 0.76), Color(0.30, 0.70, 1.0), Color(0.97, 0.43, 0.75), Color(1.0, 0.69, 0.30)]
var domain_extent: float = 12.0
var depth_strength: float = 0.45
var quality: int = 0
var selected: int = -1
var isolated: int = -1
var optical_mix: float = 1.0
var records: Dictionary = {}
var latest_snapshot: Dictionary = {}
var family_materials: Array[ShaderMaterial] = []
var material_caches: Array[Dictionary] = []
var body_mesh: SphereMesh
var branch_mesh: CylinderMesh
var allocations: int = 0
var deallocations: int = 0
var topology_builds: int = 0
var transform_uploads: int = 0
var upload_bytes: int = 0
var material_writes: int = 0
var instance_uniform_writes: int = 0
var body_transform_updates: int = 0
var update_usec: int = 0
var update_samples: Array[int] = []
var topology_events: int = 0
var source_instances: MultiMeshInstance3D
var boundary_instances: MultiMeshInstance3D
var _epoch: int = -1
var _last_snapshot_sequence: int = -1
var _last_topology_revision: int = -1
var _last_quality: int = -1
var _last_isolated: int = -2
var _last_depth_strength: float = -1.0
var _last_sources: Array = []

func _ensure_resources() -> void:
	if body_mesh != null:
		return
	body_mesh = SphereMesh.new()
	body_mesh.resource_name = "generated.ecology.body"
	body_mesh.radius = 1.0
	body_mesh.height = 2.0
	body_mesh.radial_segments = 16
	body_mesh.rings = 8
	branch_mesh = CylinderMesh.new()
	branch_mesh.resource_name = "generated.ecology.segment"
	branch_mesh.top_radius = 1.0
	branch_mesh.bottom_radius = 1.0
	branch_mesh.height = 1.0
	branch_mesh.radial_segments = 6
	branch_mesh.rings = 1
	for family in range(4):
		var material = ShaderMaterial.new()
		material.shader = GeneratedShader
		material.resource_name = "optical.ecology.family%d" % family
		material.set_shader_parameter("family_tint", FAMILY_TINTS[family])
		family_materials.append(material)
		material_caches.append({})
	topology_builds += 2
	source_instances = _new_buffer(16, body_mesh, family_materials[0])
	source_instances.name = "AuthoredResourceSources"
	add_child(source_instances)
	boundary_instances = _new_buffer(4, branch_mesh, family_materials[1])
	boundary_instances.name = "NumericalInteractionPlane"
	add_child(boundary_instances)
	var corners = [Vector2.ZERO, Vector2(1, 0), Vector2.ONE, Vector2(0, 1)]
	for i in range(4):
		boundary_instances.multimesh.set_instance_transform(i, _segment_transform(domain_point(corners[i]), domain_point(corners[(i + 1) % 4]), 0.008))
		boundary_instances.multimesh.set_instance_custom_data(i, Color(0.10, 0.0, 0.0, 0.0))
	boundary_instances.multimesh.visible_instance_count = 4

func _new_buffer(capacity: int, mesh: Mesh, material: Material) -> MultiMeshInstance3D:
	var instance = MultiMeshInstance3D.new()
	var buffer = MultiMesh.new()
	buffer.transform_format = MultiMesh.TRANSFORM_3D
	buffer.use_custom_data = true
	buffer.instance_count = capacity
	buffer.visible_instance_count = 0
	buffer.mesh = mesh
	instance.multimesh = buffer
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance

func _allocate(row: Dictionary) -> void:
	var holder = Node3D.new()
	holder.name = str(row.organism_id).replace(".", "_")
	add_child(holder)
	var family: int = int(row.family)
	var core = MeshInstance3D.new()
	core.name = "PersistentBody"
	core.mesh = body_mesh
	core.material_override = family_materials[family]
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(core)
	var capacity: int = World.MAX_SEGMENTS if family == 0 else World.MAX_TRAIL
	var strands = _new_buffer(capacity, branch_mesh, family_materials[family])
	strands.name = "BoundedBranchesOrTrail"
	strands.multimesh.resource_name = "generated.%s.strands" % str(row.organism_id)
	holder.add_child(strands)
	records[str(row.organism_id)] = {"root": holder, "core": core, "strands": strands,
		"family": family, "material_id": "optical.ecology.family%d" % family,
		"geometry_id": "generated.%s.strands" % str(row.organism_id), "row": row,
		"topology_revision": "", "last_geometry_revision": "", "last_tick": -1}
	allocations += 1

func apply_snapshot(snapshot: Dictionary) -> bool:
	if snapshot.get("schema") != "xenovection.ecology.snapshot.v1" or not snapshot.get("organisms") is Array:
		return false
	if snapshot.organisms.size() > World.MAX_POP:
		return false
	_ensure_resources()
	if _epoch != int(snapshot.epoch):
		clear_organisms()
		_epoch = int(snapshot.epoch)
	latest_snapshot = snapshot
	var wanted: Dictionary = {}
	for row in snapshot.organisms:
		var key: String = str(row.organism_id)
		wanted[key] = true
		if not records.has(key):
			_allocate(row)
		var record: Dictionary = records[key]
		if record.topology_revision != row.topology_revision:
			topology_events += 1
			record.topology_revision = row.topology_revision
		record.row = row
	for key in records.keys():
		if not wanted.has(key):
			_release(key)
	_last_topology_revision = int(snapshot.topology_revision)
	return true

func _release(key: String) -> void:
	var record: Dictionary = records[key]
	var holder: Node3D = record.root
	remove_child(holder)
	holder.free()
	records.erase(key)
	deallocations += 1

func clear_organisms() -> void:
	for key in records.keys():
		_release(key)
	latest_snapshot = {}
	_last_snapshot_sequence = -1
	_last_sources = []
	if source_instances != null:
		source_instances.multimesh.visible_instance_count = 0

func domain_point(p: Vector2, height: float = 0.0) -> Vector3:
	return Vector3((p.x - 0.5) * domain_extent, (0.5 - p.y) * domain_extent, height)

func _height(row: Dictionary, p: Vector2) -> float:
	return depth_strength * (sin(float(row.phase) + p.x * 8.0 + float(row.id) * 0.31) * 0.45 + float(row.family) * 0.15) * (0.3 + float(row.energy) * 0.7)

func _segment_transform(a: Vector3, b: Vector3, width: float) -> Transform3D:
	var delta = b - a
	var actual_length = delta.length()
	var length = maxf(actual_length, 0.00001)
	var direction = delta / actual_length if actual_length > 0.0000001 else Vector3.UP
	var basis = Basis(Quaternion(Vector3.UP, direction))
	basis = basis * Basis.from_scale(Vector3(width, length, width))
	return Transform3D(basis, (a + b) * 0.5)

func update_presentation(alpha: float = 1.0, context: Dictionary = {}, clocks: Dictionary = {}) -> void:
	if latest_snapshot.is_empty():
		return
	var started = Time.get_ticks_usec()
	var blend = clampf(alpha, 0.0, 1.0)
	var stride: int = [1, 2, 4][clampi(quality, 0, 2)]
	var tick_changed: bool = _last_snapshot_sequence != int(latest_snapshot.sequence)
	var detail_changed: bool = quality != _last_quality or isolated != _last_isolated or depth_strength != _last_depth_strength
	var gain = clampf(float(latest_snapshot.get("effective", {}).get("material", 1.0)), 0.15, 1.4)
	for family in range(family_materials.size()):
		material_writes += Bridge.set_uniform(family_materials[family], "ecology_material_gain", gain, material_caches[family])
		material_writes += Bridge.apply_context(family_materials[family], context, clocks, optical_mix, material_caches[family])
	for record in records.values():
		var row: Dictionary = record.row
		var holder: Node3D = record.root
		holder.visible = isolated < 0 or int(row.family) == isolated
		if not holder.visible:
			continue
		var core: MeshInstance3D = record.core
		var p: Vector2 = row.previous_position.lerp(row.position, blend)
		var body_position = domain_point(p, _height(row, p))
		if core.position != body_position:
			core.position = body_position
			body_transform_updates += 1
		var body_scale = Vector3.ONE
		var radius = 0.045 + float(row.energy) * 0.025
		if int(row.family) == 2:
			radius = maxf(0.08, float(row.radius) * domain_extent)
			body_scale = Vector3(radius, radius, maxf(0.035, radius * 0.18))
		elif int(row.family) == 3:
			radius = 0.045 + float(row.excitation) * 0.16
			body_scale = Vector3.ONE * radius
		else:
			body_scale = Vector3.ONE * radius
		if int(row.id) == selected:
			body_scale *= 1.45
		if core.scale != body_scale:
			core.scale = body_scale
			body_transform_updates += 1
		if tick_changed or detail_changed:
			core.set_instance_shader_parameter("organism_energy", float(row.energy))
			core.set_instance_shader_parameter("organism_excitation", float(row.excitation))
			core.set_instance_shader_parameter("organism_phase", fposmod(float(row.phase), TAU) / TAU)
			core.set_instance_shader_parameter("organism_signal", clampf(float(row.signal), 0.0, 1.0))
			instance_uniform_writes += 4
		if int(record.last_tick) != int(latest_snapshot.tick) or record.last_geometry_revision != row.topology_revision or detail_changed:
			_update_strands(record, stride)
			record.last_tick = int(latest_snapshot.tick)
			record.last_geometry_revision = row.topology_revision
	if tick_changed:
		_update_sources()
	_last_snapshot_sequence = int(latest_snapshot.sequence)
	_last_quality = quality
	_last_isolated = isolated
	_last_depth_strength = depth_strength
	update_usec = Time.get_ticks_usec() - started
	update_samples.append(update_usec)
	if update_samples.size() > 1024:
		update_samples.pop_front()

func _update_strands(record: Dictionary, stride: int) -> void:
	var row: Dictionary = record.row
	var mm: MultiMesh = record.strands.multimesh
	var points: Array = row.segments if int(row.family) == 0 else row.trail
	var count: int = 0
	var phase = fposmod(float(row.phase), TAU) / TAU
	if int(row.family) == 0:
		for j in range(0, points.size() - 1, stride * 2):
			mm.set_instance_transform(count, _segment_transform(domain_point(points[j], _height(row, points[j])), domain_point(points[j + 1], _height(row, points[j + 1])), 0.010 + float(row.energy) * 0.006))
			mm.set_instance_custom_data(count, Color(float(row.energy), float(row.excitation), phase, clampf(float(row.signal), 0.0, 1.0)))
			count += 1
	elif int(row.family) == 1:
		for j in range(0, points.size() - 1, stride):
			var next = mini(j + stride, points.size() - 1)
			mm.set_instance_transform(count, _segment_transform(domain_point(points[j], _height(row, points[j])), domain_point(points[next], _height(row, points[next])), 0.011))
			mm.set_instance_custom_data(count, Color(float(row.energy) * float(j + 1) / maxi(1, points.size()), float(row.excitation), phase, clampf(float(row.signal), 0.0, 1.0)))
			count += 1
	mm.visible_instance_count = count
	transform_uploads += count
	upload_bytes += count * (12 + 4) * 4

func _update_sources() -> void:
	var rows: Array = latest_snapshot.get("sources", [])
	if rows == _last_sources:
		return
	_last_sources = rows
	for i in range(mini(16, rows.size())):
		var row: Array = rows[i]
		var p = Vector2(float(row[0]), float(row[1]))
		var scale = 0.06 + absf(float(row[2])) * 0.04
		source_instances.multimesh.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3(scale, scale, 0.018)), domain_point(p, -0.035)))
		source_instances.multimesh.set_instance_custom_data(i, Color(0.22, 0.0 if float(row[2]) >= 0.0 else 0.8, 0.25, 1.0))
	source_instances.multimesh.visible_instance_count = mini(16, rows.size())
	transform_uploads += mini(16, rows.size())
	upload_bytes += mini(16, rows.size()) * (12 + 4) * 4

func ray_to_domain(camera: Camera3D, point: Vector2) -> Dictionary:
	if camera == null or not point.is_finite():
		return {"valid": false}
	var inverse = global_transform.affine_inverse()
	var origin: Vector3 = inverse * camera.project_ray_origin(point)
	var direction: Vector3 = inverse.basis * camera.project_ray_normal(point)
	if absf(direction.z) < 0.000001:
		return {"valid": false}
	var distance = -origin.z / direction.z
	if distance < 0.0:
		return {"valid": false}
	var local = origin + direction * distance
	var domain = Vector2(local.x / domain_extent + 0.5, 0.5 - local.y / domain_extent)
	return {"valid": domain.x >= 0.0 and domain.x <= 1.0 and domain.y >= 0.0 and domain.y <= 1.0,
		"point": domain, "local_position": local, "world_position": global_transform * local}

func domain_to_screen(camera: Camera3D, p: Vector2) -> Vector2:
	return camera.unproject_position(global_transform * domain_point(p))

func metrics() -> Dictionary:
	var samples: Array[int] = update_samples.duplicate()
	samples.sort()
	return {"numerical_domain": "planar", "representation": "bounded spatial snapshot adapter",
		"organism_resources": records.size(), "allocations": allocations, "deallocations": deallocations,
		"shared_meshes": 2 if body_mesh != null else 0, "shared_materials": family_materials.size(),
		"topology_builds": topology_builds, "topology_events": topology_events,
		"transform_uploads": transform_uploads, "upload_bytes": upload_bytes, "material_uniform_writes": material_writes,
		"body_transform_updates": body_transform_updates, "instance_uniform_writes": instance_uniform_writes,
		"active_nodes": records.size() * 3 + (2 if body_mesh != null else 0), "active_instance_buffers": records.size() + (2 if body_mesh != null else 0),
		"update_us_last": update_usec,
		"update_us_p50": samples[int((samples.size() - 1) * 0.5)] if not samples.is_empty() else 0,
		"update_us_p95": samples[int((samples.size() - 1) * 0.95)] if not samples.is_empty() else 0,
		"world_tick": int(latest_snapshot.get("tick", 0)), "quality": quality, "depth_strength": depth_strength}
