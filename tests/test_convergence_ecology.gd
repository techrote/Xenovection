extends SceneTree
## Cross-domain numerical/presentation contracts, separate from the untouched 81 ecology assertions.
const World = preload("res://ecology/world.gd")
const Snapshot = preload("res://ecology/snapshot.gd")
const Adapter = preload("res://ecology/spatial_adapter.gd")
const Workspace = preload("res://ecology/workspace.gd")
const Bus = preload("res://core/modulation_bus.gd")
const Graph = preload("res://core/synth_graph.gd")
const Examples = preload("res://core/synth_examples.gd")
const Clock = preload("res://convergence/instrument_clock.gd")
var checks: int = 0
var failures: Array[String] = []
var receipts: Array = []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		print("FAIL: ", label)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1440, 900)
	for preset in range(6):
		var world = World.new()
		world.reset(World.initial_config(preset, 6219))
		var producer = Snapshot.new()
		producer.reset_generation()
		var before = world.digest()
		var snapshot: Dictionary = producer.capture(world)
		check(world.digest() == before, "Snapshot does not mutate numerical state %d" % preset)
		check(snapshot.is_read_only() and snapshot.organisms.is_read_only() and snapshot.organisms[0].is_read_only() and snapshot.resource_field.is_read_only() and snapshot.organisms[0].segments.is_read_only(), "Snapshot containers frozen %d" % preset)
		check(snapshot.organisms.size() == world.organisms.size() and snapshot.organisms.size() <= World.MAX_POP, "Snapshot bounded population %d" % preset)
		var row: Dictionary = snapshot.organisms[0]
		var observed: float = world.resource[0]
		var copied: Array = snapshot.resource_field.duplicate()
		copied[0] = 0.0 if observed != 0.0 else 1.0
		check(world.resource[0] == observed and snapshot.resource_field[0] == observed, "Copied field remains detached from frozen snapshot and solver %d" % preset)
		check(row.organism_id.begins_with("eco.organism.") and row.lineage_id.begins_with("eco.lineage.") and row.id == world.organisms[0].id, "Stable identity namespaces %d" % preset)
		for i in range(18):
			world.step()
		var fresh = producer.capture(world)
		check(snapshot.tick == 0 and fresh.tick == 18 and fresh.organisms[0].age_ticks == 18, "Completed tick snapshot remains stable %d" % preset)
		check(fresh.organisms[0].position == world.organisms[0].p and fresh.organisms[0].previous_position == world.organisms[0].prev_p, "Current and previous positions exact %d" % preset)
		if preset == 0:
			check(fresh.topology_revision > snapshot.topology_revision and fresh.organisms[0].segments.size() <= World.MAX_SEGMENTS * 2, "Branch topology revision and bounds")
	var world = World.new()
	world.reset(World.initial_config(3, 2024))
	var producer = Snapshot.new()
	producer.reset_generation()
	var adapter = Adapter.new()
	root.add_child(adapter)
	for endpoint in [Vector3(2, 0, 0), Vector3(0, 2, 0), Vector3(0, -2, 0), Vector3(0, 0, 2), Vector3(1.5, -0.7, 0.4)]:
		var origin = Vector3(-0.3, 0.7, 0.2)
		var transform: Transform3D = adapter._segment_transform(origin, origin + endpoint, 0.013)
		check((transform * Vector3(0, -0.5, 0)).distance_to(origin) < 0.00001 and (transform * Vector3(0, 0.5, 0)).distance_to(origin + endpoint) < 0.00001, "Cylinder endpoints preserve segment orientation %s" % endpoint)
		check(absf(transform.basis.x.length() - 0.013) < 0.00001 and absf(transform.basis.z.length() - 0.013) < 0.00001, "Cylinder width remains local to its orientation %s" % endpoint)
	check(adapter._segment_transform(Vector3.ZERO, Vector3.ZERO, 0.01).basis.is_finite(), "Degenerate segment has finite bounded transform")
	var snapshot = producer.capture(world)
	check(adapter.apply_snapshot(snapshot), "Snapshot adapter accepts typed bounded snapshot")
	adapter.update_presentation(1.0)
	var initial: Dictionary = adapter.metrics()
	check(initial.organism_resources == world.organisms.size() and initial.shared_meshes == 2 and initial.shared_materials == 5 and initial.family_materials == 4 and initial.guide_materials == 1, "One identity record per organism, four family materials and exactly one persistent guide")
	var guide_id: int = adapter.guide_material.get_instance_id()
	var guide_colour: Color = adapter.guide_material.albedo_color
	check(adapter.boundary_instances.material_override == adapter.guide_material and adapter.guide_material.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED and adapter.guide_material.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED and not adapter.guide_material.no_depth_test, "Numerical plane uses a separate opaque unshaded guide with normal depth testing")
	var handles: Dictionary = {}
	var organism_resources_unchanged: bool = true
	for id in adapter.records:
		var record: Dictionary = adapter.records[id]
		handles[id] = record.core.get_instance_id()
		organism_resources_unchanged = organism_resources_unchanged and record.core.mesh == adapter.body_mesh and record.strands.multimesh.mesh == adapter.branch_mesh and record.core.material_override == adapter.family_materials[record.family] and record.strands.material_override == adapter.family_materials[record.family]
	check(organism_resources_unchanged, "Adding the guide leaves every organism on its existing shared geometry and optical family material")
	for i in range(12):
		world.step()
		adapter.apply_snapshot(producer.capture(world))
		adapter.update_presentation(1.0)
	check(adapter.transform_uploads > 0 and adapter.upload_bytes > 0, "Growing branches and moving trails issue bounded buffer uploads")
	check(adapter.allocations == initial.allocations and adapter.topology_builds == initial.topology_builds, "New branches use reserved capacity without mesh reconstruction")
	var before = world.digest()
	for i in range(20):
		adapter.quality = i % 3
		adapter.depth_strength = float(i) * 0.025
		adapter.update_presentation(float(i) / 20.0, {"parameters": {"enabled": true, "optical_mix": 1.0, "optical_thickness": 0.2 + float(i) * 0.01, "illumination_intensity": 1.0}}, {"sky": float(i), "palette": float(i)})
	check(world.digest() == before, "Quality, interpolation, optical context and depth leave digest unchanged")
	check(adapter.allocations == initial.allocations and adapter.topology_builds == initial.topology_builds, "Ordinary rendering reuses topology and identity resources")
	check(adapter.guide_material.get_instance_id() == guide_id and adapter.guide_material.albedo_color == guide_colour, "Optical context, clocks and quality leave the numerical-domain guide unchanged")
	var identities_stable = true
	for id in handles:
		identities_stable = identities_stable and adapter.records[id].core.get_instance_id() == handles[id]
	check(identities_stable, "Persistent resource identity under material and quality changes")
	var material_bus = Bus.new()
	world.register_targets(material_bus)
	material_bus.set_base("eco.material", 0.4)
	var material_uploads_before: int = adapter.transform_uploads
	before = world.digest()
	world.apply_effective(material_bus.evaluate())
	adapter.apply_snapshot(producer.capture(world))
	adapter.update_presentation()
	var material_gain: float = adapter.family_materials[0].get_shader_parameter("ecology_material_gain")
	check(is_equal_approx(material_gain, 0.4), "Shared eco.material target changes actual spatial shader intensity")
	check(adapter.allocations == initial.allocations and adapter.topology_builds == initial.topology_builds, "Ecology material modulation retains geometry and organism resources")
	check(adapter.transform_uploads == material_uploads_before, "Paused material-only snapshot avoids branch, trail and source-buffer uploads")
	check(world.digest() == before, "Spatial material presentation never changes numerical digest")
	material_bus.set_base("eco.material", 99.0)
	world.apply_effective(material_bus.evaluate())
	adapter.apply_snapshot(producer.capture(world))
	adapter.update_presentation()
	material_gain = adapter.family_materials[0].get_shader_parameter("ecology_material_gain")
	check(is_equal_approx(material_bus.get_base("eco.material"), 2.0) and is_equal_approx(material_gain, 1.4), "Ecology material scalar and presentation gain remain bounded")
	check(adapter.guide_material.get_instance_id() == guide_id and adapter.guide_material.albedo_color == guide_colour and adapter.guide_material.albedo_color.a == 1.0, "Low and saturated organism material gain cannot dim or replace the domain guide")
	world.apply_effective({})
	world.plant(2, Vector2(0.5, 0.5))
	adapter.apply_snapshot(producer.capture(world))
	adapter.update_presentation()
	check(adapter.allocations == initial.allocations + 1 and adapter.records.size() == world.organisms.size(), "Birth allocates exactly one identity record")
	world.organisms.remove_at(world.organisms.size() - 1)
	adapter.apply_snapshot(producer.capture(world))
	check(adapter.deallocations == 1 and adapter.records.size() == initial.organism_resources, "Death releases exactly its identity record")
	var camera = Camera3D.new()
	root.add_child(camera)
	camera.position = Vector3(0, 0, 18)
	camera.look_at(Vector3.ZERO)
	camera.current = true
	await process_frame
	for point in [Vector2(0.1, 0.2), Vector2(0.5, 0.5), Vector2(0.85, 0.73)]:
		var screen: Vector2 = adapter.domain_to_screen(camera, point)
		var hit: Dictionary = adapter.ray_to_domain(camera, screen)
		check(hit.valid and hit.point.distance_to(point) < 0.00001, "Explicit pointer inverse maps %s" % point)
	camera.position = Vector3(7, 4, 16)
	camera.look_at(Vector3.ZERO)
	var point = Vector2(0.32, 0.62)
	var hit = adapter.ray_to_domain(camera, adapter.domain_to_screen(camera, point))
	check(hit.valid and hit.point.distance_to(point) < 0.00001, "Oblique camera preserves numerical input mapping")
	adapter.position = Vector3(2, -1, 0.4)
	adapter.rotation = Vector3(0.1, 0.2, 0.0)
	hit = adapter.ray_to_domain(camera, adapter.domain_to_screen(camera, point))
	check(hit.valid and hit.point.distance_to(point) < 0.00001, "Authored domain transform has exact inverse interaction")
	adapter.clear_organisms()
	check(adapter.records.is_empty() and adapter.allocations == adapter.deallocations, "Explicit adapter cleanup balances allocations")
	for i in range(6):
		producer.reset_generation()
		adapter.apply_snapshot(producer.capture(world))
		adapter.update_presentation()
		adapter.clear_organisms()
	check(adapter.allocations == adapter.deallocations and adapter.topology_builds == 2, "Repeated activation cleanup preserves only shared geometry")
	check(adapter.guide_material.get_instance_id() == guide_id and adapter.metrics().shared_materials == 5 and adapter.metrics().guide_materials == 1, "Repeated activation retains exactly one guide alongside four family materials")
	receipts.append(adapter.metrics())
	adapter.free()
	camera.free()
	# Run the same shared signal graph and world under 30 / 60 / 120 Hz presentation.
	var digests: Array = []
	for presentation_hz in [30, 60, 120]:
		var bus = Bus.new()
		var a = World.new()
		a.reset(World.initial_config(1, 8181))
		a.register_targets(bus)
		var graph = Graph.new()
		var patch = Graph.blank()
		patch.sources = [Examples.node("motion", "sine", {"rate": 0.7, "seed": 87}), Examples.node("growth", "noise", {"rate": 1.5, "seed": 43})]
		patch.routes = [Examples.route("alignment", "motion", "eco.alignment", 0.4), Examples.route("grow", "growth", "eco.growth", 0.3)]
		check(graph.configure(patch, bus) and graph.attach(bus), "Shared graph binds ecology %d" % presentation_hz)
		var clock = Clock.new()
		var sample_ticks: Array = []
		var callback = func(values, _force):
			a.apply_effective(values)
			a.step()
			sample_ticks.append(clock.ticks)
		for i in range(presentation_hz * 4):
			clock.advance(bus, graph, 1.0 / presentation_hz, false, callback)
		check(a.tick == 120 and graph.ticks == 480 and sample_ticks.size() == 120, "Exact graph/world fixed rates %d" % presentation_hz)
		var boundaries_valid = true
		for i in range(sample_ticks.size()):
			boundaries_valid = boundaries_valid and sample_ticks[i] == (i + 1) * 4
		check(boundaries_valid, "Only completed fourth graph tick sampled %d" % presentation_hz)
		digests.append(a.digest())
		receipts.append({"presentation_hz": presentation_hz, "digest": a.digest(), "clock": clock.metrics(), "world": a.metrics()})
	check(digests[0] == digests[1] and digests[1] == digests[2], "Numerical replay invariant across different rendering cadence")
	# Hosted workspace keeps one authoritative bus and state while hidden.
	var shared = Bus.new()
	var workspace = Workspace.new()
	workspace.configure_shared(shared)
	root.add_child(workspace)
	await process_frame
	check(workspace.bus == shared and shared.targets.size() == World.BOUNDS.size(), "Hosted workspace uses exactly one injected registry")
	workspace.simulation_enabled = true
	workspace.paused = true
	before = workspace.world.digest()
	var paused_topology: int = workspace.latest_snapshot.topology_revision
	workspace._parameter(0.6, "material")
	check(workspace.world.tick == 0 and workspace.world.digest() == before, "Paused authored material edit preserves numerical tick and digest")
	check(is_equal_approx(float(workspace.latest_snapshot.effective.material), 0.6) and workspace.latest_snapshot.topology_revision == paused_topology, "Paused material edit publishes current immutable presentation without topology event")
	workspace.step_resolved(shared.evaluate())
	check(workspace.world.digest() == before, "Paused ecology ignores scheduled boundaries")
	workspace.step_resolved(shared.evaluate(), true)
	check(workspace.world.tick == 1, "Forced manual boundary advances exactly one world tick")
	workspace.hide()
	before = workspace.world.digest()
	await process_frame
	workspace.show()
	await process_frame
	check(workspace.world.digest() == before, "Planar hide/show preserves numerical histories")
	workspace.paused = false
	shared.set_base("eco.alignment", 1.8)
	workspace.step_resolved(shared.evaluate())
	check(is_equal_approx(workspace.world.effective.alignment, 1.8), "Shared modulation sampled at the world boundary")
	var authored = workspace.authoring_snapshot()
	workspace.world.plant(0, Vector2(0.5, 0.4))
	check(workspace.restore_authored(authored) and workspace.world.tick == 0 and workspace.bus == shared, "Unified authored recall resets histories without replacing shared registry")
	workspace.tools.select(1)
	workspace.family.select(2)
	var population = workspace.world.organisms.size()
	check(workspace.intervene_at(Vector2(0.5, 0.5)) and workspace.world.organisms.size() == population + 1, "Mapped spatial planting uses same bounded world command")
	workspace.tools.select(0)
	workspace.intervene_at(Vector2(0.5, 0.5))
	check(workspace.selected == workspace.world.organisms[-1].id, "Mapped spatial inspection preserves stable organism identity")
	workspace.tools.select(2)
	var sources = workspace.world.config.sources.size()
	workspace.intervene_at(Vector2(0.3, 0.4))
	check(workspace.world.config.sources.size() == sources + 1, "Mapped resource placement shares authored source contract")
	workspace.tools.select(4)
	workspace.intervene_at(Vector2(0.6, 0.6))
	check(workspace.world.sample(workspace.world.signal_field, Vector2(0.6, 0.6)) > 0.3, "Mapped signal disturbance changes only explicit numerical intervention")
	before = workspace.world.digest()
	check(not workspace.intervene_at(Vector2(-0.1, 0.5)) and workspace.world.digest() == before, "Out-of-domain spatial pointer is refused")
	receipts.append(workspace.convergence_metrics())
	workspace.free()
	print("CONVERGENCE_ECOLOGY_RECEIPTS ", JSON.stringify(receipts))
	print("CONVERGENCE_ECOLOGY ", checks - failures.size(), "/", checks, " PASS; ", failures.size(), " FAIL")
	quit(0 if failures.is_empty() else 1)
