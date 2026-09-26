#!/usr/bin/env python3
"""Fake ESP32 taped to a fake AOC: lux = floor + Σ ref_c · f(gain_c), where the gains are
whatever the mock m1ddc last wrote to $MOCK_DIR. Simulates a monitor whose gain acts with
exponent <gamma>, optionally clipping above 50.
    fake_screen_sensor.py <port> <gamma> <headroom 0|1>"""
import json, os, sys, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
PORT, GAM, HEAD = int(sys.argv[1]), float(sys.argv[2]), sys.argv[3] == "1"
MOCK = os.environ["MOCK_DIR"]
REF = {"red": 60.0, "green": 200.0, "blue": 25.0}
def gain(c):
    try: return float(open(f"{MOCK}/m1ddc_{c}").read())
    except OSError: return 50.0
def lux():
    if os.environ.get("FAKE_BLIND") == "1":   # sensor not facing the screen: room light only
        return 2.6
    tot = 0.6
    for c, r in REF.items():
        g = gain(c); rel = (g / 50) ** GAM
        if g > 50 and not HEAD: rel = 1.0
        tot += r * rel
    return tot
class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_GET(self):
        self.send_response(200); self.send_header("Content-Type", "text/event-stream"); self.end_headers()
        try:
            while True:
                d = {"id": "sensor-ambient_light", "name": "Ambient Light", "value": round(lux(), 2), "state": ""}
                self.wfile.write(f"event: state\ndata: {json.dumps(d)}\n\n".encode()); self.wfile.flush()
                time.sleep(0.1)
        except (BrokenPipeError, ConnectionResetError): pass
ThreadingHTTPServer(("127.0.0.1", PORT), H).serve_forever()
