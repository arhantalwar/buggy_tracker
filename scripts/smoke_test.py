#!/usr/bin/env python3
"""HTTP checks against an already-running disposable demo server.
Usage: DRIVER_KEY=your-passphrase python3 scripts/smoke_test.py http://localhost:8080
This changes the first buggy's state, then marks it offline.
"""
import json
import os
import sys
import urllib.error
import urllib.request

base = (sys.argv[1] if len(sys.argv) > 1 else 'http://localhost:8080').rstrip('/')
key = os.environ['DRIVER_KEY']


def request(path, payload=None, password=None):
    headers = {'Content-Type': 'application/json'}
    if password is not None:
        headers['X-Driver-Key'] = password
    req = urllib.request.Request(base + path, headers=headers,
                                 data=None if payload is None else json.dumps(payload).encode(),
                                 method='GET' if payload is None else 'PUT')
    try:
        with urllib.request.urlopen(req, timeout=10) as response:
            return response.status, json.load(response)
    except urllib.error.HTTPError as error:
        return error.code, json.load(error)


status, state = request('/api/state')
assert status == 200
buggy = state['buggies'][0]
path = '/api/buggies/' + buggy['id']
payload = {'occupancy': buggy['capacity'], 'source': 'simulation', 'lat': 12.0, 'lng': 77.0}
assert request(path, payload, 'wrong')[0] == 401
assert request(path, {**payload, 'occupancy': -1}, key)[0] == 400
assert request(path, {**payload, 'lat': 100}, key)[0] == 400
assert request('/api/buggies/missing', payload, key)[0] == 400
assert request(path, payload, key)[0] == 200
_, observed = request('/api/state')
received = next(b for b in observed['buggies'] if b['id'] == buggy['id'])
assert received['occupancy'] == buggy['capacity']
assert received['lat'] == 12.0 and received['source'] == 'simulation'
assert received['positionAt'] is not None
assert request(path, {'occupancy': 0, 'source': 'offline'}, key)[0] == 200
print('HTTP smoke checks passed: auth, validation, sharing, occupancy, stop.')
