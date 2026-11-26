extends RefCounted
## Complete deterministic starting points, sharing one source and one renderer.

static func all() -> Array:
	return [
		{"id": "hybrid", "title": "01  Convergence", "description": "Fine currents around selected optical matter",
			"filament": {"opacity": 0.19, "line_width_px": 0.52, "fibres": 1, "selection_fade": 0.48, "palette_amount": 0.08},
			"optical": {"sky_intensity": 2.2, "roughness": 0.15, "displacement": 0.07, "normal_strength": 0.19, "domain_warp": 0.12, "background_strength": 0.009},
			"materialisation": "knot", "band": [2, 8, 10], "distance": 16.0, "yaw": 0.43, "pitch": 0.20, "density": 48, "modulation": true},
		{"id": "filaments", "title": "02  Counterflow loom", "description": "Travelling luminous phase · torsion · opposing fibres",
			"filament": {"opacity": 0.19, "line_width_px": 0.50, "phase_speed": 1.1, "wave_amplitude": 0.15, "braid_radius": 0.07, "fibres": 2, "palette_amount": 0.1},
			"optical": {"sky_visible": false}, "materialisation": "none", "distance": 15.0, "yaw": 0.45, "pitch": 0.20, "density": 48, "modulation": true},
		{"id": "optical", "title": "03  Spectral knot", "description": "Moving environment · fixed source membership",
			"filament": {"enabled": false},
			"optical": {"sky_intensity": 2.7, "roughness": 0.14, "normal_strength": 0.28, "displacement": 0.08, "sky_frequency": Vector2(2.1, 1.4), "background_strength": 0.005},
			"materialisation": "knot", "band": [2, 8, 12], "focus": true, "distance": 5.0, "yaw": 0.34, "pitch": 0.24, "density": 48, "modulation": true},
		{"id": "membrane", "title": "04  Weather membrane", "description": "Normal, domain and geometric weather are independent",
			"filament": {"opacity": 0.12, "line_width_px": 0.42, "fibres": 0, "selection_fade": 0.22},
			"optical": {"palette": "ember", "sky_intensity": 2.3, "sky_frequency": Vector2(0.52, 0.26), "sky_radius": 0.2, "sky_diagonal": 0.48, "sky_warp": 0.4, "sky_contrast": 2.65, "normal_strength": 0.34, "displacement": 0.32, "domain_warp": 0.15, "background_strength": 0.006, "surface_opacity": 0.72},
			"materialisation": "membrane", "band": [2, 8, 14], "focus": true, "distance": 7.5, "yaw": 0.30, "pitch": 0.20, "density": 48, "modulation": true},
		{"id": "scientific", "title": "05  Scientific / no FX", "description": "Exact coefficients and IDs · all decoration disabled",
			"filament": {"opacity": 0.24, "line_width_px": 0.55, "fibres": 0},
			"optical": {}, "materialisation": "none", "scientific": true, "distance": 19.0, "yaw": 0.32, "pitch": 0.16, "density": 48, "modulation": false},
		{"id": "stress", "title": "06  Dense interference", "description": "46,080 primary edges · explicit density stress specimen",
			"filament": {"opacity": 0.08, "line_width_px": 0.35, "fibres": 1, "segments": 16, "wave_amplitude": 0.09, "braid_radius": 0.04, "phase_speed": 0.9, "node_radius": 0.012},
			"optical": {"sky_visible": false}, "materialisation": "none", "distance": 19.0, "yaw": 0.52, "pitch": 0.28, "density": 96, "modulation": false},
	]
