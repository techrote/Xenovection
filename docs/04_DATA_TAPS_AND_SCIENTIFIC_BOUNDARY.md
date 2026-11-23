# Optional data taps, provenance and scientifically faithful selection

## Boundary

Xenovection is a visual synthesis environment first. A source adapter can feed it measured properties, tensors, activation traces, time series, graph topology or selected index ranges. **The source system remains authoritative.** RustySpork is the owner of all LLM checkpoint, inference, intervention and validation logic.

No renderer code should import PyTorch, GGUF decoders, quantisation kernels, weight-edit operators or RustySpork implementation internals. A model surgery workflow must run headlessly and independently of Xenovection.

## Minimal conceptual layers

1. **Source provider:** files, synthetic generator, live instrument, RustySpork model tap, CyberSand simulation.
2. **Transport/adaptor:** snapshots or live streams, capability negotiation, immutable manifests, local replay.
3. **Data model:** stable IDs, types, timestamp, unit, coordinate system, source hash, data scopes and quality flags.
4. **Visual mapping:** declared mapping from source properties to geometry/material field, with parameters and provenance.
5. **Renderer:** visual synth/scene graph and GPU.
6. **Interaction:** pointer/brush/volume selection returns a source-addressable selection *reference*, not an instruction to modify source data.
7. **Optional external editor:** own validation, request confirmation, commit patch, retain complete evidence.

## Proposed message families (not implemented)

| Message | Content | Direction |
| --- | --- | --- |
| HELLO / CAPABILITIES | schema version, source identity, allowed streams, limits, edit support | both |
| SOURCE_MANIFEST | immutable dataset/model hash, shape, axes, dtype, coordinate mapping, aggregation history | source -> viewer |
| TOPOLOGY | stable vertex/edge IDs, source addresses, structural relations | source -> viewer |
| TENSOR_TILES | index ranges + exact summary statistics and quantisation notes | source -> viewer |
| SIGNAL_SAMPLES | time series, probe ID, units, scope, sample cadence, validity | source -> viewer |
| TRACES | experiment ID, input and intervention, recorded activations or differences | source -> viewer |
| SELECTION | exact IDs/index ranges, ref, selection semantics, source version/hash | viewer -> source |
| PROPOSED_OPERATION | explicit external action request with dry-run and safety data; opt-in only | viewer -> source |
| ACK / ERROR / BACKPRESSURE | flow control, transport errors and missing-data reporting | both |

### Illustrative exact selection reference

~~~json
{
  "schema": "xenovection.selection.v0-proposal",
  "source_id": "synthetic-foundry",
  "source_revision": "sha256:...",
  "coordinate_mapping": "layer-channel-v1",
  "items": [
    {"kind": "node", "layer": 2, "channel": 17},
    {"kind": "edge", "layer": 2, "input": 17, "output": 9}
  ],
  "selection_semantics": "exact-listed-elements"
}
~~~

The sample is a **proposal**, not an accepted wire protocol or proof of valid source revision. A projected 3D selection must either resolve to exact items or be explicitly labelled approximate/aggregated, with users offered refinement.

## Scientific mapping and artefact semantics

- **Primary connection:** actual source edge when available; stable edge ID.
- **Secondary fibre:** visual embellishment attached to primary, not additional connection.
- **Feature position:** an embedding/projection selected for a declared purpose; never intrinsic 3D neuron geometry.
- **Colour:** typed legend; signed response, magnitude, weight, activation, aggregate, or decorative LUT identified explicitly.
- **Temporal animation:** measured sample cadence distinguished from interpolated/artistic animation.
- **Statistics:** display sample count, aggregation range, zeros, outliers, positive/negative contributions, and confidence/invalid flags where relevant.
- **Causality:** visually traced influence requires a causal intervention or valid sensitivity computation, never assumed from adjacency or attention weight alone.

## Synthetic specimen policy

FOUND-001's 6 × 48 tanh MLP is a **synthetic numerical specimen**, not a transformer, with exactly addressable weights and channels. Its displayed finite-difference response and signed preactivation contributions serve as an example of scientifically tethered visuals, not evidence about actual language-model semantic topology.

## If later paired with RustySpork

RustySpork exposes data taps; Xenovection supplies visualization, selection masks and optional requested operation plans. RustySpork validates source hashes, masks, dtypes, structural compatibility, budgets and frozen donor paths, asks for/receives explicit authority to commit, then returns traceable results. No live render update is equivalent to a successful checkpoint edit.

A surgery patch shall never be issued solely because a user visually dragged or tore a decorative surface. Cosmetic deformation always stays in Xenovection until an explicit, externally verified operation is requested.

## Security and performance

Localhost transport first. No remote arbitrary file access, code execution, model loading, weight mutation or unbounded binary streaming. Bound payload size and update frequency; use separate CPU/GPU queues. Instrumentation should never stall rendering and viewer GPU allocations must be limited when paired with large model inference.
