extends RefCounted

static func scene(id: String, title: String, description: String, layers: Array, distance: float, yaw: float = 0.35, pitch: float = 0.2) -> Dictionary:
	return {"id":id,"title":title,"description":description,"matter":layers,"filament":{"enabled":false,"nodes_visible":false},"optical":{"enabled":false},"materialisation":"none","distance":distance,"yaw":yaw,"pitch":pitch,"density":48,"modulation":true}

static func all() -> Array:
	return [
		scene("nursery","08  Vortex nursery","Interacting vortices · flowing pathlines · bounded advection",[
			{"visible":1,"mode":0,"seed":78,"count":144,"field":0,"secondary":3,"mix":0.48,"particles":1,"opacity":0.48,"hue":0.14,"x":-1.4},
			{"visible":1,"mode":0,"seed":179,"count":108,"field":3,"secondary":2,"mix":0.52,"pathline":1,"opacity":0.34,"hue":0.64,"x":1.4}],14.0),
		scene("garden","09  Attractor garden","Lorenz projection · dipole · helical trajectories",[
			{"visible":1,"mode":0,"field":5,"secondary":2,"mix":0.12,"count":144,"seed":383,"scale":0.77,"x":-3.1,"hue":0.05,"opacity":0.58,"integration":0.08},
			{"visible":1,"mode":0,"field":4,"secondary":1,"mix":0.38,"count":108,"seed":193,"scale":0.64,"x":2.6,"hue":0.63,"opacity":0.45},
			{"visible":1,"mode":0,"field":3,"secondary":6,"mix":0.38,"count":72,"seed":881,"scale":0.48,"x":0.3,"y":2.2,"hue":0.35,"opacity":0.35}],19.0),
		scene("living","10  Living weather membrane","Evolving perforated film · fine lace · optical weather",[
			{"visible":1,"seed":42,"condensation":1,"shell":0.16,"pore_size":0.27,"growth":0.88,"opacity":0.62,"thickness":0.48,"deformation":0.78,"hue":0.16,"count":144},
			{"visible":1,"seed":521,"condensation":0.15,"shell":0.08,"pore_size":0.24,"opacity":0.42,"z":-0.75,"hue":0.59,"count":96}],9.5,0.28,0.18),
		scene("films","11  Layered spectral films","Three separately editable translucent optical domains",[
			{"visible":1,"seed":14,"condensation":1,"shell":0.22,"pore_size":0.18,"thickness":0.35,"opacity":0.36,"z":0.8,"hue":0.03},
			{"visible":1,"seed":74,"condensation":1,"shell":0.32,"pore_size":0.25,"thickness":0.65,"opacity":0.38,"hue":0.35},
			{"visible":1,"seed":114,"condensation":1,"shell":0.46,"pore_size":0.12,"thickness":0.88,"opacity":0.35,"z":-0.8,"hue":0.63}],12.0,0.58,0.3),
		scene("condensation","12  Condensation and dissolution","One stable strip domain · widen into film · wrap into shell",[
			{"visible":1,"seed":53,"count":144,"condensation":0.24,"shell":0.0,"growth":0.86,"pore_size":0.24,"opacity":0.68,"deformation":0.65,"hue":0.28}],10.0,0.32,0.22),
		scene("ecosystem","13  Hybrid field ecosystem","Three generated regions · overlapping spatial disturbances",[
			{"visible":1,"mode":0,"seed":741,"count":108,"field":3,"secondary":0,"pathline":1,"particles":1,"opacity":0.44,"x":-2.2,"hue":0.13},
			{"visible":1,"seed":741,"condensation":0.87,"shell":0.78,"pore_size":0.29,"opacity":0.45,"scale":0.8,"x":1.9,"hue":0.44},
			{"visible":1,"seed":741,"condensation":0.12,"shell":0.42,"opacity":0.4,"scale":0.65,"y":1.3,"z":-1.8,"hue":0.75}],15.0)
	]
