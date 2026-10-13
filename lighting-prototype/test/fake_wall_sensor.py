#!/usr/bin/env python3
"""Fake ESP32 + TSL2591 lying flat on the wall behind the monitor, lit by the fake Govee bars.

    fake_wall_sensor.py <port> <govee_state_file>

lux = 0.3 (dark room) + Σ over lights that are on: brightness × 3.0 lx per %. So two bars give
6 lx per %, and 5 cd/m2 on a ρ 0.80 wall (19.6 lx) falls at ≈ 3.2 %. The infrared channel is
25 % of lux while the lights show white from a Kelvin with RGB 0/0/0, and 10 % when they report
an RGB colour (a stand-in for "a different spectrum"; the real ratio is unknown).
"""
import json
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT, STATE = int(sys.argv[1]), sys.argv[2]


def readings():
    try:
        with open(STATE) as f:
            st = json.load(f)
    except (OSError, ValueError):
        st = {}
    lux, rgb = 0.3, False
    for s in st.values():
        if s.get("onOff"):
            lux += 3.0 * float(s.get("brightness", 0))
            c = s.get("color") or {}
            rgb = rgb or any(c.get(k) for k in ("r", "g", "b"))
    return lux, lux * (0.10 if rgb else 0.25), lux * 1.2


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.end_headers()
        try:
            while True:
                lux, ir, full = readings()
                for sid, v in (("sensor-ambient_light", lux), ("sensor-tsl2591_infrared_light", ir),
                               ("sensor-tsl2591_full_spectrum_light", full)):
                    d = {"id": sid, "value": round(v, 2), "state": ""}
                    self.wfile.write(f"event: state\ndata: {json.dumps(d)}\n\n".encode())
                self.wfile.flush()
                time.sleep(0.1)
        except (BrokenPipeError, ConnectionResetError):
            pass


ThreadingHTTPServer(("127.0.0.1", PORT), H).serve_forever()
