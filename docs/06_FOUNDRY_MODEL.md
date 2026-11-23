# Foundry metaphor — physical intuition versus computational truth

**Status:** artistic and pedagogical source, not an implementation specification for LLM mechanics. The name *Transformer Foundry* belongs to the historical design dialogue, while the independent graphics project is Xenovection.

## Origin

The user's intuitive metaphor: tokens as weirdly shaped **steel marbles**, layers as stacked **sieves** whose holes contain tiny magnetic attractors/repulsors, **magical pipes** redirecting marbles along surprising vectors, and **pressure waves** as they interact.

This should be preserved as a generative visual language, not dismissed because a neural network is non-spatial.

## Improved mechanical mapping

### Tokens as shape-changing pin-covered marbles
- A token ID is a discrete vocabulary index; each token *position* carries a high-dimensional numerical hidden-state vector.
- Picture a numbered sphere with thousands of signed, telescoping pins. Their pattern evolves across layers, while the token ID for the existing position does not change.
- The representation for the same token in different contexts may change enormously.
- Pin dimensions are not necessarily independently interpretable semantic concepts; meaning may be distributed across vectors or feature directions.

### Sieves as weighted gearboxes
- Learned linear transformations are networks of signed adjustable gear ratios, summing all incoming coordinate contributions into outgoing coordinates.
- Mathematical prototype: y_j = Σ_i (W_ji x_i) + b_j.
- Positive/negative contributions and cancellation are meaningful; ordinary holes that pass/filter whole marbles are not an accurate picture.
- Most learned weights are fixed during normal inference; model surgery or training changes them, not an individual forward pass.

### Pipes as attention information routing
- Query, key and value are learned projections of hidden states. Query–key dot products define contextual compatibility, scaled and softmaxed into nonnegative weights summing to one over permitted source positions.
- Value **signals are copied and mixed**; whole token marbles do not physically migrate between layers or positions.
- Attention heads are parallel learned comparison/aggregation operations, not permanent semantic channels. Causal language models prohibit reading future positions.
- Effective source contributions change with prompt/context even if all learned parameters remain fixed.

### Nonlinear clutches and residual bypass
- SwiGLU or other MLP blocks expand and gate intermediate signals, then reduce them. They need not have an explicit semantic function per neuron.
- Residual additions keep and modify an existing state rather than discarding it each stage.
- Normalisation is a mechanical governor on signal magnitude, not an eraser of individual coordinates.
- Stack many blocks; at the end project last-position state into vocabulary logits and select a new token ID.

### Pressure waves as numerical sensitivity and perturbation
- A small delta at one coordinate may alter many later coordinates; some contributions reinforce, others cancel.
- Local linearisation: delta h_out ≈ J delta h_in (Jacobian). The operating sensitivity J depends on state in a nonlinear model.
- This is a **computational dependency cascade, not physical pressure, velocity, energy, literal charge or true travelling waves**.
- A wave-like visualization may faithfully encode measured sign/magnitude/phase sequencing *if* a trace or sensitivity calculation supplies it and an explicit legend explains its meaning.
- A cosmetic wave may also be beautiful and interactive without pretending to be measured influence.

## Original artistic corollaries

| Foundry object | Visual embodiment | Data truth boundary |
| --- | --- | --- |
| Pin porcupine marble | configurable radial microgeometry / visual glyph | derived vector dimensions must be declared |
| Sieve / aperture | perforated translucent sheet | only represents a learned transform when mapped by adapter |
| Magnetic orifice | signed colour, local field warp | don't imply independent local magnet physics |
| Pipes | original exact filaments / independently animated decorative braids | edge vs decorative fibre must be distinct |
| Pattern press | reflective knot, nonlinearly warped membranes | primarily artistic |
| Pressure wave | traveling interference, filigree wavefronts, volumetric field | measured perturbations separately identified |
| Frozen machinery | static calibration / scientific no-FX view | model weights not changed by animation |
| Changing gears | separate requested numerical surgery by owner tool | never automatically edit model from mesh manipulation |

## What is *not* implied

No intrinsic 3D neural coordinate system; no physical token movement along connection curves; no one-to-one fact-to-neuron mapping; no causal proof from glowing geometry; no pressure or conservation law in attention. Geometry can encode chosen structural, statistical or artist-authored layouts.

## Xenovection-specific implication

The actual graphical synthesizer need not contain transformer logic. It hosts pin-glyphs, knot materials, fill volumes, ribbons and filaments as **optional visual grammars**, fed by synthetic or real data mappings. The founder wanted ordinary physical objects and videogame-tier directness; keep those advantages without sacrificing provenance. The *foundry* is a mode, not the universal architecture of the render engine.
