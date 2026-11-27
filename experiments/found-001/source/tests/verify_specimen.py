#!/usr/bin/env python3
"""Offline mathematical checks for the bundled synthetic model (no Godot required)."""
import json
from pathlib import Path
import hashlib
import numpy as np

p = Path(__file__).resolve().parents[1] / 'data' / 'synthetic_foundry.json'
raw = p.read_bytes()
spec = json.loads(raw)
assert spec['schema'] == 'frankenfield.synthetic-dense-tanh.v1'
L = spec['layers']
N = spec['channels']
W = np.array(spec['weights'], dtype=np.float64)
x = np.array(spec['input'], dtype=np.float64)
eps = spec['epsilon']
assert (L, N) == (6, 48)
assert W.shape == (L-1, N, N)
assert np.isfinite(W).all() and np.isfinite(x).all()

def forward(vec):
    states = [vec.copy()]
    for m in W:
        states.append(np.tanh(m @ states[-1]))
    return np.array(states)

states = forward(x)
report = []
for k in range(N):
    e = np.zeros_like(x)
    e[k] = 1.0
    deriv = e.copy()
    for li, m in enumerate(W):
        deriv = (1.0-states[li+1]**2)*(m @ deriv)
    h = 1e-6
    numerical = (forward(x + h*e)[-1] - forward(x - h*e)[-1]) / (2*h)
    error = np.max(np.abs(deriv - numerical))
    assert error < 1e-8, (k, error)
    perturbation = forward(x + eps*e) - states
    assert np.abs(perturbation[0, k] - eps) < 1e-10
    assert all(np.max(np.abs(perturbation[l])) > 0 for l in range(L))
    report.append(error)
print('Specimen  ', spec['name'])
print('SHA-256   ', hashlib.sha256(raw).hexdigest())
print('Matrices  ', W.shape, '= ', W.size, 'precise stored coefficients')
print('Channels  ', N, 'input probes')
print('Derivative max error ', f'{max(report):.3e}')
print('PASS: deterministic dimensions, finite values, finite differences, forward response')
