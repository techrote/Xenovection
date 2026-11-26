#!/usr/bin/env python3
"""Generate an immutable deterministic synthetic network; no model downloads."""
import hashlib
import json
from pathlib import Path
import numpy as np

SEED = 12026
LAYERS = 6
CHANNELS = 48
rng = np.random.default_rng(SEED)
weights = []
for layer in range(LAYERS - 1):
    i = np.arange(CHANNELS)[None, :]
    j = np.arange(CHANNELS)[:, None]
    random_term = rng.standard_normal((CHANNELS, CHANNELS)) * (0.62 / np.sqrt(CHANNELS))
    braided = (0.055 * np.sin(0.34*i + 0.2*j + layer*0.85)
               * np.cos(0.19*i - 0.4*j - layer*0.4))
    local = 0.11 * np.exp(-abs(i-j) / 7.0) * np.cos((i-j)*0.85 + layer*0.5)
    weights.append(np.round(random_term + braided + local, 8).tolist())
x = (0.7*np.sin(np.arange(CHANNELS)*0.23)
     + 0.25*np.cos(np.arange(CHANNELS)*0.71)
     + 0.13*rng.standard_normal(CHANNELS))
model = {
    'schema': 'frankenfield.synthetic-dense-tanh.v1',
    'seed': SEED,
    'name': 'FOUND-001 / Coupled Tanh Foundry',
    'caveat': 'Synthetic 6-layer 48-channel tanh MLP, NOT a transformer or trained LLM.',
    'operation': 'h[0]=input; h[l+1]=tanh(W[l] @ h[l]); no bias.',
    'layers': LAYERS,
    'channels': CHANNELS,
    'epsilon': 0.125,
    'input': np.round(x, 8).tolist(),
    'weights': weights,
}
path = Path(__file__).parent / 'data' / 'synthetic_foundry.json'
payload = json.dumps(model, separators=(',', ':'), ensure_ascii=False).encode('utf-8')
path.write_bytes(payload)
print(f'{path.name}: {len(payload)} bytes SHA-256 {hashlib.sha256(payload).hexdigest()}')
