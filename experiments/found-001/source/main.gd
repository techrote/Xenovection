extends Node3D
## FRANKENFIELD / FOUND-001
## Native Godot rendering of an EXACTLY indexed synthetic dense tanh network.
## Filaments depict fixed weighted connections. The pulse overlay depicts measured
## finite differences caused by adding epsilon to ONE selected input coordinate.
## Motion along filaments is artistic, not physical conduction or elapsed inference time.

const SPECIMEN_PATH: String = "res://data/synthetic_foundry.json"
const PI2: float = PI * 2.0
const CURVE_STEPS: int = 9
const STRANDS: int = 2

var weights: Array = []
var initial_vector: Array = []
var layer_count: int = 0
var channel_count: int = 0
var epsilon: float = 0.125
var specimen_name: String = ""
var positions: Array = []
var baseline: Array = []
var modified: Array = []
var delta_vectors: Array = []
var derivatives: Array = []
var layer_maxima: Array = []
var contribution_maxima: Array = []
var selected_channel: int = 16
var polarity: float = 1.0
var view_mode: int = 2 # 1 = structure, 2 = delta, 3 = hybrid
var show_ui: bool = true

var fly_camera: Camera3D
var line_object: MeshInstance3D
var node_instances: MultiMeshInstance3D
var heading: Label
var measurements: Label
var controls: Label
var ui_panel: PanelContainer
var shader_lines: ShaderMaterial
var shader_points: ShaderMaterial

func _ready() -> void:
    _load_specimen()
    _calculate_positions()
    _calculate_states()
    _create_environment()
    _create_camera()
    _create_materials()
    _create_instances()
    _build_ui()
    _rebuild_filaments()
    _refresh_ui()
    Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
    print("FOUND-001 loaded: %s; %d x %d; selected input %d" % [specimen_name, layer_count, channel_count, selected_channel])

func _load_specimen() -> void:
    var f: FileAccess = FileAccess.open(SPECIMEN_PATH, FileAccess.READ)
    if f == null:
        push_error("Missing signed synthetic specimen: " + SPECIMEN_PATH)
        return
    var decoded = JSON.parse_string(f.get_as_text())
    if typeof(decoded) != TYPE_DICTIONARY or str(decoded.get("schema", "")) != "frankenfield.synthetic-dense-tanh.v1":
        push_error("Invalid FOUND-001 specimen schema")
        return
    weights = decoded["weights"]
    initial_vector = decoded["input"]
    layer_count = int(decoded["layers"])
    channel_count = int(decoded["channels"])
    epsilon = float(decoded["epsilon"])
    specimen_name = str(decoded["name"])
    assert(layer_count > 1 and channel_count > 1)
    assert(weights.size() == layer_count - 1)
    assert(initial_vector.size() == channel_count)
    for layer in weights:
        assert(layer.size() == channel_count)
        for row in layer:
            assert(row.size() == channel_count)
    selected_channel = int(channel_count / 3)

func _calculate_positions() -> void:
    # The layout is deliberately PROCEDURAL, not an assertion that neurons exist
    # at these Euclidean positions. The (layer, channel) mapping is exact.
    positions.clear()
    for l in range(layer_count):
        var ring: Array = []
        for ch in range(channel_count):
            var theta: float = float(ch) * PI2 / float(channel_count)
            var x: float = (float(l) - float(layer_count - 1) * 0.5) * 4.5
            var radius: float = 3.65 + 0.7 * sin(theta * 7.0 + l * 0.8)
            var y: float = radius * sin(theta) + 0.65 * sin(theta * 5.0 + l * 0.41)
            var z: float = radius * cos(theta) + 0.68 * sin(theta * 4.0 - l * 0.55)
            ring.append(Vector3(x, y, z))
        positions.append(ring)

func _forward(first: Array) -> Array:
    var all_states: Array = [first.duplicate()]
    for layer_idx in range(layer_count - 1):
        var src: Array = all_states[layer_idx]
        var out: Array = []
        for j in range(channel_count):
            var total: float = 0.0
            for i in range(channel_count):
                total += float(weights[layer_idx][j][i]) * float(src[i])
            out.append(tanh(total))
        all_states.append(out)
    return all_states

func _calculate_states() -> void:
    baseline = _forward(initial_vector)
    var edited_input: Array = initial_vector.duplicate()
    edited_input[selected_channel] = float(edited_input[selected_channel]) + epsilon * polarity
    modified = _forward(edited_input)
    delta_vectors.clear()
    layer_maxima.clear()
    contribution_maxima.clear()
    derivatives.clear()
    var sensitivity: Array = []
    for i in range(channel_count):
        sensitivity.append(1.0 if i == selected_channel else 0.0)
    derivatives.append(sensitivity.duplicate())
    for l in range(layer_count):
        var differences: Array = []
        var max_abs: float = 0.0
        for j in range(channel_count):
            var diff: float = float(modified[l][j]) - float(baseline[l][j])
            differences.append(diff)
            max_abs = max(max_abs, abs(diff))
        delta_vectors.append(differences)
        layer_maxima.append(max_abs)
        if l < layer_count - 1:
            var deriv_next: Array = []
            for j in range(channel_count):
                var slope: float = 0.0
                for i in range(channel_count):
                    slope += float(weights[l][j][i]) * float(sensitivity[i])
                var activation: float = float(baseline[l + 1][j])
                deriv_next.append((1.0 - activation * activation) * slope)
            sensitivity = deriv_next
            derivatives.append(sensitivity.duplicate())
            var max_contribution: float = 0.0
            for j in range(channel_count):
                for i in range(channel_count):
                    max_contribution = max(max_contribution, abs(float(weights[l][j][i]) * float(differences[i])))
            contribution_maxima.append(max_contribution)

func _create_environment() -> void:
    var we: WorldEnvironment = WorldEnvironment.new()
    var env: Environment = Environment.new()
    env.background_mode = Environment.BG_COLOR
    env.background_color = Color(0.004, 0.006, 0.013)
    env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    env.ambient_light_color = Color(0.05, 0.08, 0.15)
    env.glow_enabled = true
    env.glow_intensity = 0.65
    we.environment = env
    add_child(we)

func _create_camera() -> void:
    fly_camera = Camera3D.new()
    fly_camera.fov = 63.0
    fly_camera.near = 0.03
    fly_camera.far = 250.0
    fly_camera.position = Vector3(0.6, 4.9, 27.0)
    add_child(fly_camera)
    fly_camera.current = true
    fly_camera.look_at(Vector3.ZERO, Vector3.UP)

func _create_materials() -> void:
    var lines: Shader = Shader.new()
    lines.code = """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
void fragment() {
    vec3 col = COLOR.rgb;
    // Decorative scintillation. This is NOT a simulated wave travel time.
    float shimmer = 0.86 + 0.14 * sin(UV.x * 47.0 - TIME * 2.1);
    ALBEDO = col;
    EMISSION = col * shimmer * 2.6;
    ALPHA = COLOR.a;
}
"""
    shader_lines = ShaderMaterial.new()
    shader_lines.shader = lines
    var points: Shader = Shader.new()
    points.code = """
shader_type spatial;
render_mode unshaded, cull_disabled;
void fragment() {
    ALBEDO = COLOR.rgb;
    EMISSION = COLOR.rgb * 2.4;
}
"""
    shader_points = ShaderMaterial.new()
    shader_points.shader = points

func _create_instances() -> void:
    line_object = MeshInstance3D.new()
    line_object.name = "Measured perturbation / filament geometry"
    line_object.material_override = shader_lines
    add_child(line_object)

    var sphere: SphereMesh = SphereMesh.new()
    sphere.radius = 0.12
    sphere.height = 0.24
    sphere.radial_segments = 8
    sphere.rings = 4
    sphere.material = shader_points
    var mm: MultiMesh = MultiMesh.new()
    mm.transform_format = MultiMesh.TRANSFORM_3D
    mm.use_colors = true
    mm.mesh = sphere
    mm.instance_count = layer_count * channel_count
    node_instances = MultiMeshInstance3D.new()
    node_instances.name = "Exact channel coordinate markers"
    node_instances.multimesh = mm
    add_child(node_instances)

    var distant: MultiMesh = MultiMesh.new()
    distant.transform_format = MultiMesh.TRANSFORM_3D
    distant.use_colors = true
    var star: SphereMesh = SphereMesh.new()
    star.radius = 0.018
    star.height = 0.036
    star.radial_segments = 6
    star.rings = 3
    star.material = shader_points
    distant.mesh = star
    distant.instance_count = 1100
    var rng: RandomNumberGenerator = RandomNumberGenerator.new()
    rng.seed = 455122
    for n in range(distant.instance_count):
        var p: Vector3 = Vector3(rng.randf_range(-21, 21), rng.randf_range(-13, 13), rng.randf_range(-20, 6))
        distant.set_instance_transform(n, Transform3D(Basis(), p))
        var intensity: float = rng.randf_range(0.02, 0.19)
        distant.set_instance_color(n, Color(intensity * 0.3, intensity * 0.6, intensity))
    var stars: MultiMeshInstance3D = MultiMeshInstance3D.new()
    stars.multimesh = distant
    stars.name = "Decorative distant field / no data meaning"
    add_child(stars)

func _filament_point(a: Vector3, b: Vector3, t: float, phase: float, strand: int) -> Vector3:
    var p: Vector3 = a.lerp(b, t)
    var envelope: float = sin(t * PI)
    var weave: float = 0.4 * sin(phase * 1.71) + 0.18 * cos(phase * 2.11)
    var side: Vector3 = Vector3(0.0, cos(phase), sin(phase))
    var normal: Vector3 = Vector3(0.0, -sin(phase), cos(phase))
    p += side * envelope * (0.65 + weave)
    p += normal * envelope * (float(strand) - 0.5) * (0.12 + 0.11 * sin(phase + t * 16.0))
    p += normal * envelope * 0.12 * sin(t * 24.0 + phase * 3.1)
    return p

func _stroke(st: SurfaceTool, a: Vector3, b: Vector3, col: Color, t0: float, t1: float) -> void:
    st.set_color(col)
    st.set_uv(Vector2(t0, 0.0))
    st.add_vertex(a)
    st.set_color(col)
    st.set_uv(Vector2(t1, 0.0))
    st.add_vertex(b)

func _connection_color(w: float, signed_contribution: float, relative_contribution: float, strand: int) -> Color:
    var warm: bool = signed_contribution < 0.0
    var magnitude: float = clamp(relative_contribution, 0.0, 1.0)
    var static_brightness: float = clamp(abs(w) * 4.2, 0.1, 0.9)
    var base: Color = Color(0.035, 0.20, 0.31, 0.16) if w >= 0.0 else Color(0.29, 0.095, 0.13, 0.14)
    if view_mode == 1:
        base = Color(0.08, 0.31, 0.42, 0.07 + static_brightness * 0.20) if w >= 0.0 else Color(0.45, 0.13, 0.12, 0.07 + static_brightness * 0.20)
    elif view_mode == 2:
        base = Color(0.008, 0.028, 0.045, 0.036)
    if view_mode != 1:
        var pulse: Color = Color(1.0, 0.37, 0.16, 0.8) if warm else Color(0.13, 0.91, 0.82, 0.82)
        var amount: float = pow(magnitude, 0.67) * (0.94 if view_mode == 2 else 0.76)
        base = base.lerp(pulse, amount)
        base.a = clamp(base.a + magnitude * 0.42, 0.035, 0.94)
    if strand == 1:
        base.a *= 0.44
        base.r *= 0.76
        base.g *= 0.76
        base.b *= 0.88
    return base

func _rebuild_filaments() -> void:
    var st: SurfaceTool = SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_LINES)
    for l in range(layer_count - 1):
        var max_impact: float = max(float(contribution_maxima[l]), 0.0000000001)
        for j in range(channel_count):
            var b: Vector3 = positions[l + 1][j]
            for i in range(channel_count):
                var w: float = float(weights[l][j][i])
                if abs(w) < 0.024:
                    continue
                var a: Vector3 = positions[l][i]
                var signed_flow: float = w * float(delta_vectors[l][i])
                var intensity: float = abs(signed_flow) / max_impact
                var phase: float = float(i * 47 + j * 67 + l * 131) * 0.035
                for strand in range(STRANDS):
                    var col: Color = _connection_color(w, signed_flow, intensity, strand)
                    var prev: Vector3 = _filament_point(a, b, 0.0, phase, strand)
                    for step in range(1, CURVE_STEPS + 1):
                        var t: float = float(step) / float(CURVE_STEPS)
                        var point: Vector3 = _filament_point(a, b, t, phase, strand)
                        _stroke(st, prev, point, col, t - 1.0 / float(CURVE_STEPS), t)
                        prev = point
    # Small local bristles emphasise the density and individuality of each channel.
    for l in range(layer_count):
        var vmax: float = max(float(layer_maxima[l]), 0.0000000001)
        for i in range(channel_count):
            var p: Vector3 = positions[l][i]
            var v: float = float(delta_vectors[l][i])
            var relative: float = abs(v) / vmax
            var c: Color = Color(1.0, 0.36, 0.16, 0.75) if v < 0.0 else Color(0.22, 0.90, 0.82, 0.75)
            if view_mode == 1:
                c = Color(0.23, 0.38, 0.51, 0.38)
            else:
                c.a = 0.12 + 0.58 * pow(relative, 0.6)
            for spoke in range(6):
                var angle: float = float(spoke) * PI2 / 6.0 + float(i) * 0.63
                var direction: Vector3 = Vector3(0.0, sin(angle), cos(angle))
                var extension: float = (0.16 + 0.32 * relative) * (1.0 if i != selected_channel or l != 0 else 2.5)
                _stroke(st, p, p + direction * extension, c, 0.0, 0.0)
    line_object.mesh = st.commit()
    var mm: MultiMesh = node_instances.multimesh
    for l in range(layer_count):
        var vmax: float = max(float(layer_maxima[l]), 0.0000000001)
        for i in range(channel_count):
            var idx: int = l * channel_count + i
            var v: float = float(delta_vectors[l][i])
            var relative: float = abs(v) / vmax
            var color: Color = Color(0.11, 0.47, 0.66) if view_mode == 1 else (Color(1.0, 0.30, 0.14) if v < 0.0 else Color(0.13, 0.93, 0.78))
            var scale: float = 0.72 + 1.95 * pow(relative, 0.6)
            if l == 0 and i == selected_channel:
                color = Color(1.0, 0.95, 0.68)
                scale = 3.5
            elif view_mode == 1:
                scale = 0.82
            mm.set_instance_transform(idx, Transform3D(Basis().scaled(Vector3.ONE * scale), positions[l][i]))
            mm.set_instance_color(idx, color)

func _make_label(text_value: String, point_size: int, tint: Color) -> Label:
    var lbl: Label = Label.new()
    lbl.text = text_value
    lbl.add_theme_font_size_override("font_size", point_size)
    lbl.add_theme_color_override("font_color", tint)
    lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    return lbl

func _build_ui() -> void:
    var layer: CanvasLayer = CanvasLayer.new()
    add_child(layer)
    ui_panel = PanelContainer.new()
    ui_panel.position = Vector2(18, 18)
    ui_panel.custom_minimum_size = Vector2(360, 0)
    var background: StyleBoxFlat = StyleBoxFlat.new()
    background.bg_color = Color(0.012, 0.025, 0.044, 0.91)
    background.border_color = Color(0.20, 0.53, 0.62, 0.65)
    background.set_border_width_all(1)
    background.set_corner_radius_all(7)
    background.content_margin_left = 18
    background.content_margin_right = 18
    background.content_margin_top = 16
    background.content_margin_bottom = 16
    ui_panel.add_theme_stylebox_override("panel", background)
    layer.add_child(ui_panel)
    var stack: VBoxContainer = VBoxContainer.new()
    stack.add_theme_constant_override("separation", 9)
    ui_panel.add_child(stack)
    var title: Label = _make_label("F R A N K E N F I E L D", 20, Color(0.69, 0.97, 0.94))
    stack.add_child(title)
    stack.add_child(_make_label("FOUND-001    /    COUPLED-FIELD STUDY", 11, Color(0.43, 0.72, 0.82)))
    stack.add_child(_make_label("SYNTHETIC · NOT AN LLM", 12, Color(1.0, 0.65, 0.40)))
    heading = _make_label("", 15, Color(0.91, 0.94, 0.98))
    stack.add_child(heading)
    measurements = _make_label("", 12, Color(0.65, 0.81, 0.88))
    stack.add_child(measurements)
    controls = _make_label("", 12, Color(0.79, 0.82, 0.90))
    stack.add_child(controls)

    var foot: Label = _make_label("SYNTHETIC LINK GEOMETRY  /  EXACT MATRIX INDICES\nHEIGHT / CURVATURE / SHIMMER ARE ARTISTIC", 10, Color(0.48, 0.58, 0.67))
    stack.add_child(foot)

func _refresh_ui() -> void:
    var mode: String = "STRUCTURE" if view_mode == 1 else ("MEASURED Δ" if view_mode == 2 else "HYBRID")
    heading.text = "MODE %d  /  %s\nInput channel: [0,%d]   ε = %+.3f" % [view_mode, mode, selected_channel, epsilon * polarity]
    var details: String = "Layer    max |Δh|     max |∂h/∂x|\n"
    for l in range(layer_count):
        var max_derivative: float = 0.0
        for d in derivatives[l]:
            max_derivative = max(max_derivative, abs(float(d)))
        details += "L%-2d      %0.5f        %0.5f\n" % [l, float(layer_maxima[l]), max_derivative]
    var final_l: int = layer_count - 1
    var numeric_error: float = 0.0
    for j in range(channel_count):
        numeric_error = max(numeric_error, abs(float(delta_vectors[final_l][j]) / (epsilon * polarity) - float(derivatives[final_l][j])))
    details += "\nFinal-layer finite-difference / derivative\nmax discrepancy: %.6f\n" % numeric_error
    details += "Each layer's glow is independently normalised.\nColour = signed contribution; not a semantic label."
    measurements.text = details
    controls.text = "LEFT CLICK: select first-layer pin\nRIGHT CLICK: capture/release mouse\nWASD + Q/E: fly     SHIFT: accelerate\n[ / ]: choose input channel\n1: structure   2: perturbation   3: hybrid\nP: reverse perturbation   F: focus\nESC: release mouse   F1: toggle panel"

func _set_channel(new_channel: int) -> void:
    selected_channel = posmod(new_channel, channel_count)
    _calculate_states()
    _rebuild_filaments()
    _refresh_ui()

func _pick_screen_channel(point: Vector2) -> void:
    var closest: float = 40.0
    var chosen: int = -1
    for i in range(channel_count):
        var p: Vector3 = positions[0][i]
        if fly_camera.is_position_behind(p):
            continue
        var distance: float = fly_camera.unproject_position(p).distance_to(point)
        if distance < closest:
            closest = distance
            chosen = i
    if chosen >= 0:
        _set_channel(chosen)

func _input(event: InputEvent) -> void:
    if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
        fly_camera.rotation.y -= event.relative.x * 0.0022
        fly_camera.rotation.x = clamp(fly_camera.rotation.x - event.relative.y * 0.0022, -1.55, 1.55)
    if event is InputEventMouseButton and event.pressed:
        if event.button_index == MOUSE_BUTTON_RIGHT:
            Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED
        elif event.button_index == MOUSE_BUTTON_LEFT and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
            _pick_screen_channel(event.position)
        elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
            fly_camera.position += -fly_camera.global_basis.z * 0.5
        elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
            fly_camera.position -= -fly_camera.global_basis.z * 0.5
    if event is InputEventKey and event.pressed and not event.echo:
        match event.keycode:
            KEY_ESCAPE:
                Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
            KEY_BRACKETLEFT, KEY_LEFT:
                _set_channel(selected_channel - 1)
            KEY_BRACKETRIGHT, KEY_RIGHT:
                _set_channel(selected_channel + 1)
            KEY_1, KEY_2, KEY_3:
                view_mode = event.keycode - KEY_1 + 1
                _rebuild_filaments()
                _refresh_ui()
            KEY_P:
                polarity *= -1.0
                _set_channel(selected_channel)
            KEY_F:
                fly_camera.look_at(positions[0][selected_channel], Vector3.UP)
            KEY_F1:
                show_ui = not show_ui
                ui_panel.visible = show_ui

func _process(dt: float) -> void:
    var move: Vector3 = Vector3.ZERO
    if Input.is_key_pressed(KEY_W):
        move -= fly_camera.global_basis.z
    if Input.is_key_pressed(KEY_S):
        move += fly_camera.global_basis.z
    if Input.is_key_pressed(KEY_D):
        move += fly_camera.global_basis.x
    if Input.is_key_pressed(KEY_A):
        move -= fly_camera.global_basis.x
    if Input.is_key_pressed(KEY_E):
        move += Vector3.UP
    if Input.is_key_pressed(KEY_Q):
        move -= Vector3.UP
    if move.length_squared() > 0.0:
        var speed: float = 17.0 if Input.is_key_pressed(KEY_SHIFT) else 5.0
        fly_camera.global_position += move.normalized() * dt * speed
