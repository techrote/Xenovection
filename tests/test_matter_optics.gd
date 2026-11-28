extends SceneTree
## Cross-domain resource qualification, independent of the application controller.
const Matter = preload("res://matter/laboratory.gd")
const Presets = preload("res://matter/presets.gd")
const Bus = preload("res://core/modulation_bus.gd")
const Optical = preload("res://rendering/optical/optical_layer.gd")
const Bridge = preload("res://rendering/optical/material_bridge.gd")
const OrganismShader = preload("res://rendering/optical/generated_optical.gdshader")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
	print("PASS " if condition else "FAIL ", label)

func _run() -> void:
	var bus = Bus.new()
	var laboratory = Matter.new()
	var optical = Optical.new()
	root.add_child(laboratory)
	root.add_child(optical)
	laboratory.register_targets(bus)
	bus.register_source("fixture",{"type":"manual","value":0.5})
	for topology_key in Matter.REBUILD_CONTROLS:
		var destination: String = Matter.target(0,topology_key)
		check(bus.targets[destination].get("policy", "") == "base_only"
			and not bus.add_route({"id":"blocked-"+topology_key,"target":destination,"source":"fixture"}),
			"Topology destination rejects continuous route: "+topology_key)
	for continuous_key in ["strength","mix","origin_x","origin_y","origin_z","condensation","optical_mix"]:
		check(bus.add_route({"id":"allowed-"+continuous_key,"target":Matter.target(0,continuous_key),"source":"fixture","amplitude":0.2}),
			"Continuous field/material destination accepts route: "+continuous_key)
	bus.clear_routes()
	var preset: Dictionary = Presets.all()[2]
	var immutable_preset := var_to_bytes(preset)
	laboratory.set_defaults(bus,preset)
	var region = laboratory.regions[0]
	var original_mesh: ArrayMesh = region.surface.mesh
	var original_material: ShaderMaterial = region.shader
	var original_particles: MultiMesh = region.dots.multimesh
	var builds: int = region.builds
	var geometry_bytes: int = region.geometry_upload_bytes
	optical.set_parameters({"enabled":true,"optical_mix":1.0,"optical_thickness":0.48,
		"transmission":0.82,"illumination_direction":0.72,"illumination_intensity":1.4})
	var context: Dictionary = optical.get_environment_context()
	var clocks: Dictionary = bus.get_clocks()
	laboratory.update(bus,bus.evaluate(),clocks,0.0,false,false,context)
	check(is_zero_approx(float(region.shader.get_shader_parameter("xeno_optical_mix"))),"Legacy matter defaults to exact zero optical assignment")
	check(bus.targets.has(Matter.target(0,"optical_mix")),"Generated optical assignment is registered on the common bus")
	laboratory.edit(bus,"optical_mix",1.0)
	laboratory.update(bus,bus.evaluate(),clocks,0.0,false,false,context)
	check(is_equal_approx(float(region.shader.get_shader_parameter("xeno_optical_mix")),1.0),"Generated matter accepts shared optical material")
	check(is_equal_approx(float(region.shader.get_shader_parameter("xeno_thickness")),0.48),"Bounded common thickness reaches generated film")
	check(is_equal_approx(float(region.shader.get_shader_parameter("xeno_transmission")),0.82),"Common transmission reaches generated film")
	check(is_equal_approx(float(region.shader.get_shader_parameter("xeno_illumination_direction")),0.72),"Independent illumination direction reaches generated film")
	check(region.shader.get_shader_parameter("palette_lut") == context.palette_lut,"Generated matter shares the qualified environment palette resource")
	var writes: int = region.material_updates
	for i in range(20):
		laboratory.update(bus,bus.evaluate(),clocks,0.0,false,false,context)
	check(region.material_updates == writes,"Unchanged material and paused clocks do not rewrite uniforms")
	for i in range(60):
		optical.set_parameters({"optical_thickness":0.1+i/80.0,"illumination_direction":i/40.0,
			"transmission":i/60.0,"refraction_strength":i/60.0})
		clocks.sky = i/60.0
		clocks.palette = -i/90.0
		laboratory.update(bus,bus.evaluate(),clocks,0.0,false,false,optical.get_environment_context())
	check(region.builds == builds and region.geometry_upload_bytes == geometry_bytes,"Material modulation causes zero generated topology rebuilds or mesh uploads")
	check(region.surface.mesh == original_mesh and region.shader == original_material,"Material modulation preserves mesh and material identities")
	check(region.dots.multimesh == original_particles,"Optical authoring preserves persistent particle resources")
	check(is_equal_approx(float(region.shader.get_shader_parameter("sky_clock")),59.0/60.0),"Optical illumination retains independent sky clock")
	check(is_equal_approx(float(region.shader.get_shader_parameter("palette_clock")),-59.0/90.0),"Spectral colour retains independent palette clock")
	check(not region.metrics().screen_copy,"Generated material requests no screen/depth-copy pass")
	context = optical.get_environment_context()
	context.parameters.optical_thickness = 1.99
	check(not is_equal_approx(float(optical.get_environment_context().parameters.optical_thickness),1.99),"Read-only optical context cannot mutate renderer-owned parameters")
	optical.set_parameters({"optical_mix":0.0})
	laboratory.update(bus,bus.evaluate(),clocks,0.0,false,false,optical.get_environment_context())
	check(is_zero_approx(float(region.shader.get_shader_parameter("xeno_optical_mix"))),"Shared optical_mix zero disables generated enhancement")
	optical.set_parameters({"optical_mix":1.0,"enabled":false})
	laboratory.update(bus,bus.evaluate(),clocks,0.0,false,false,optical.get_environment_context())
	check(is_zero_approx(float(region.shader.get_shader_parameter("xeno_optical_mix"))),"Disabled optical environment cannot enable generated optical pass")
	optical.set_parameters({"enabled":true,"scientific":true})
	laboratory.update(bus,bus.evaluate(),clocks,0.0,false,false,optical.get_environment_context())
	check(is_zero_approx(float(region.shader.get_shader_parameter("xeno_optical_mix"))),"Scientific optical context blocks generated enhancement")
	laboratory.update(bus,bus.evaluate(),clocks,0.0,true,false,context)
	check(not laboratory.visible,"Scientific mode hides generated geometry")
	check(var_to_bytes(preset) == immutable_preset,"Optical assignment does not mutate authored source preset")
	optical.set_parameters({"scientific":false,"enabled":true})
	var organism_material := ShaderMaterial.new()
	organism_material.shader = OrganismShader
	var cache: Dictionary = {}
	var count: int = Bridge.apply_context(organism_material,optical.get_environment_context(),clocks,1.0,cache)
	check(count > 0 and is_equal_approx(float(organism_material.get_shader_parameter("xeno_optical_mix")),1.0),"Spatial organism material uses the identical bounded optical contract")
	check(Bridge.apply_context(organism_material,optical.get_environment_context(),clocks,1.0,cache) == 0,"Spatial organism material shares uniform caching contract")
	# Exercise the identical optical contract on real persistent particle geometry.
	laboratory.set_defaults(bus,Presets.all()[0])
	region = laboratory.regions[0]
	var particle_mesh: MultiMesh = region.dots.multimesh
	var particle_material: ShaderMaterial = region.particle_shader
	laboratory.edit(bus,"optical_mix",1.0)
	laboratory.update(bus,bus.evaluate(),clocks,0.0,false,false,optical.get_environment_context())
	check(region.dots.visible and region.dots.material_override == particle_material,"Generated particles participate in the common optical environment")
	laboratory.edit(bus,"optical_mix",0.0)
	laboratory.update(bus,bus.evaluate(),clocks,0.0,false,false,optical.get_environment_context())
	check(region.dots.material_override == null and region.dots.multimesh == particle_mesh,"Particle optical zero restores the exact legacy material without resource recreation")
	var declared: Dictionary = {}
	for uniform in region.shader.shader.get_shader_uniform_list(): declared[uniform.name] = true
	var contract_declared := declared.has("xeno_optical_mix")
	for uniform in Bridge.UNIFORMS.values(): contract_declared = contract_declared and declared.has(uniform)
	check(contract_declared,"Parsed generated shader declares every forwarded optical uniform")
	var organism_declared: Dictionary = {}
	for uniform in OrganismShader.get_shader_uniform_list(): organism_declared[uniform.name] = true
	check(organism_declared.has("xeno_optical_mix") and organism_declared.has("xeno_thickness"),"Parsed spatial material shader implements the optical contract")
	var shader_source := FileAccess.get_file_as_string("res://matter/matter.gdshader")
	check(shader_source.contains("clip_tangent.xy * clip.w - clip.xy * clip_tangent.w"),"Qualified perspective-correct ribbon extrusion retained")
	check(shader_source.contains("min(width,1.0)"),"Qualified subpixel ribbon coverage retained")
	check(shader_source.contains("xeno_generated_optics(ALBEDO, ALPHA"),"Optical response preserves original strand/film coverage")
	check(not FileAccess.get_file_as_string("res://rendering/optical/generated_optical_contract.gdshaderinc").contains("hint_screen_texture"),"Generated contract cannot silently acquire screen copies")
	laboratory.free()
	optical.free()
	print("CONVERGENCE_MATTER_OPTICS_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"graphical_qualification":false}))
	quit(0 if failures.is_empty() else 1)
