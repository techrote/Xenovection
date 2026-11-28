extends RefCounted
## The application owns one 120 Hz modulation timeline. Ecology samples every
## fourth completed tick, so render cadence never selects numerical parameters.
const STEP := 1.0 / 120.0
const ECOLOGY_DIVISOR := 4
const MAX_CATCHUP_TICKS := 30
var accumulator := 0.0
var ticks := 0
var ecology_boundaries := 0
var dropped_seconds := 0.0
var resolved: Dictionary = {}
var last_boundary_values: Dictionary = {}


func reset() -> void:
	accumulator = 0.0
	ticks = 0
	ecology_boundaries = 0
	dropped_seconds = 0.0
	resolved.clear()
	last_boundary_values.clear()


func advance(bus, graph, delta: float, scientific: bool = false, ecology_callback: Callable = Callable()) -> Dictionary:
	var elapsed := clampf(delta, 0.0, 0.25) if is_finite(delta) else 0.0
	if is_finite(delta) and delta > elapsed:
		dropped_seconds += delta - elapsed
	accumulator += elapsed
	var count := 0
	while accumulator + 1.0e-9 >= STEP and count < MAX_CATCHUP_TICKS:
		_tick(bus, graph, scientific, ecology_callback, false)
		accumulator = maxf(0.0, accumulator - STEP)
		count += 1
	# Zero-delta authoring resolves values without advancing a delay, world or
	# clock. Existing graphical qualification uses this to flush authored edits.
	if count == 0:
		graph.advance(bus, 0.0, scientific)
		resolved = bus.evaluate(0.0)
	return resolved


func _tick(bus, graph, scientific: bool, ecology_callback: Callable, force: bool) -> void:
	bus.advance_clocks(STEP)
	graph.advance(bus, STEP, scientific)
	resolved = bus.evaluate(0.0 if bus.paused else STEP)
	ticks += 1
	if ticks % ECOLOGY_DIVISOR == 0 and not scientific and ecology_callback.is_valid():
		# Snapshot by value: a consumer must not mutate the next graph sample.
		last_boundary_values = resolved.duplicate(true)
		ecology_callback.call(last_boundary_values.duplicate(true), force)
		ecology_boundaries += 1


func step_ecology(bus, graph, ecology_callback: Callable, scientific: bool = false) -> Dictionary:
	# A manual step reaches exactly the next ecology boundary. Partial elapsed
	# render time is discarded so resume cannot replay that authored step.
	accumulator = 0.0
	var count := ECOLOGY_DIVISOR - posmod(ticks, ECOLOGY_DIVISOR)
	for i in range(count):
		_tick(bus, graph, scientific, ecology_callback, true)
	return resolved


func metrics() -> Dictionary:
	return {"schema": "xenovection.instrument-clock.v1", "graph_hz": 120, "ecology_hz": 30,
		"fixed_ticks": ticks, "ecology_boundaries": ecology_boundaries,
		"accumulator_seconds": accumulator, "dropped_seconds": dropped_seconds,
		"feedback_boundary": "Ecology observes the completed fourth graph tick; observations may affect only later ticks."}
