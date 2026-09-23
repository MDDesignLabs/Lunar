#!/usr/bin/env python3
"""Fake ESPHome sensor: serves /events as Server-Sent Events like ESPHome's web_server.

Emits the ambient-light sensor interleaved with the other TSL2591 channels and pings,
so the prototype's parser has to pick the right id.

    fake_sensor.py <port> <interval_s> <lux> [<lux> ...]    (values are cycled once, then the last repeats)
"""
import json
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT = int(sys.argv[1])
INTERVAL = float(sys.argv[2])
VALUES = [float(v) for v in sys.argv[3:]] or [100.0]


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def do_GET(self):
        if self.path != "/events":
            self.send_response(404)
            self.end_headers()
            return
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.end_headers()
        try:
            self.wfile.write(b'event: ping\ndata: {"title":"lunarsensor"}\n\n')
            i = 0
            while True:
                lux = VALUES[min(i, len(VALUES) - 1)]
                for sid, name, val, unit in (
                    ("sensor-tsl2591_infrared_light", "TSL2591 Infrared Light", lux * 0.4, ""),
                    ("sensor-ambient_light", "Ambient Light", lux, " lx"),
                    ("sensor-tsl2591_full_spectrum_light", "TSL2591 Full Spectrum Light", lux * 1.3, ""),
                ):
                    payload = {"id": sid, "name": name, "value": round(val, 1), "state": f"{val:.1f}{unit}"}
                    self.wfile.write(f"event: state\ndata: {json.dumps(payload, separators=(',', ':'))}\n\n".encode())
                self.wfile.flush()
                i += 1
                time.sleep(INTERVAL)
        except (BrokenPipeError, ConnectionResetError):
            pass


ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
