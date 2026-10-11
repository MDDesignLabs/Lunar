#!/usr/bin/env python3
"""Fake ESP32 taped to a fake AOC: lux = floor + Σ ref_c · f(gain_c), where the gains are
whatever the mock m1ddc last wrote to $MOCK_DIR. Simulates a monitor whose gain acts with
exponent <gamma>, optionally clipping above 50.
    fake_screen_sensor.py <port> <gamma> <headroom 0|1>
Opt-in extras for probe 08 (all off by default, so probe 05's behaviour is unchanged):
    FAKE_BRIGHTNESS=1  screen light also scales with the mock's brightness ($MOCK_DIR/m1ddc_luminance),
                       following KitGuru's table for the AOC CU34G4Z (55.2 / 139.5 / 221.5 / 297.9 / 371.6 cd/m2).
    FAKE_BEZEL=1       the sensor is at the bezel, not on the glass: it sees only room light plus
                       FAKE_SELF (default 0) times the screen's output, i.e. self-illumination.
    FAKE_BLIND=1       sensor not facing the screen: room light only."""
import json, os, sys, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
PORT, GAM, HEAD = int(sys.argv[1]), float(sys.argv[2]), sys.argv[3] == "1"
MOCK = os.environ["MOCK_DIR"]
REF = {"red": 60.0, "green": 200.0, "blue": 25.0}
def gain(c):
    try: return float(open(f"{MOCK}/m1ddc_{c}").read())
    except OSError: return 50.0
KG = [(0, 55.2), (25, 139.5), (50, 221.5), (75, 297.9), (100, 371.6)]
def brightness_rel():
    try: b = float(open(f"{MOCK}/m1ddc_luminance").read())
    except OSError: b = 50.0
    b = max(0.0, min(100.0, b))
    for (x0, y0), (x1, y1) in zip(KG, KG[1:]):
        if b <= x1: return (y0 + (y1 - y0) * (b - x0) / (x1 - x0)) / KG[-1][1]
    return 1.0
def lux():
    if os.environ.get("FAKE_BLIND") == "1":   # sensor not facing the screen: room light only
        return 2.6
    tot = 0.6
    for c, r in REF.items():
        g = gain(c); rel = (g / 50) ** GAM
        if g > 50 and not HEAD: rel = 1.0
        tot += r * rel
    if os.environ.get("FAKE_BRIGHTNESS") == "1":
        tot = 0.6 + (tot - 0.6) * brightness_rel()
    if os.environ.get("FAKE_BEZEL") == "1":
        tot = 0.6 + (tot - 0.6) * float(os.environ.get("FAKE_SELF", "0"))
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
