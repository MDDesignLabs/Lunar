#!/usr/bin/env python3
"""Fake Hue Bridge (plain HTTP; the tests set HUE_SCHEME=http): the bits of CLIP v2 that lib/hue.sh uses.

    fake_hue.py <port> <dir>

<dir>/linkpressed  exists → POST /api returns a key (else error 101, "link button not pressed")
<dir>/fail         exists → every PUT answers 503
<dir>/puts.log     one line per accepted PUT: "<light-id> <json body>"
Lights: one Play gradient strip (has "gradient") and one ordinary bulb.
"""
import json
import os
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT, DIR = int(sys.argv[1]), sys.argv[2]
KEY = "fake-app-key-0123456789"
LIGHTS = {
    "11111111-aaaa-4bbb-8ccc-000000000001": {"name": "Play gradient PC", "gradient": True},
    "22222222-aaaa-4bbb-8ccc-000000000002": {"name": "Desk bulb", "gradient": False},
}
STATE = {lid: {"on": False, "brightness": 50.0, "mirek": 366} for lid in LIGHTS}


def light_json(lid):
    st, meta = STATE[lid], LIGHTS[lid]
    d = {"id": lid, "type": "light", "metadata": {"name": meta["name"]}, "on": {"on": st["on"]},
         "dimming": {"brightness": st["brightness"]}, "color_temperature": {"mirek": st["mirek"]}}
    if meta["gradient"]:
        d["gradient"] = {"points": [], "points_capable": 7}
    return d


class H(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def reply(self, code, obj):
        b = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(b)))
        self.end_headers()
        self.wfile.write(b)

    def body(self):
        n = int(self.headers.get("Content-Length") or 0)
        return self.rfile.read(n).decode() if n else ""

    def authed(self):
        if self.headers.get("hue-application-key") != KEY:
            self.reply(403, {"data": [], "errors": [{"description": "unauthorized user"}]})
            return False
        return True

    def do_POST(self):
        self.body()
        if self.path != "/api":
            return self.reply(404, {})
        if os.path.exists(os.path.join(DIR, "linkpressed")):
            return self.reply(200, [{"success": {"username": KEY}}])
        return self.reply(200, [{"error": {"type": 101, "address": "", "description": "link button not pressed"}}])

    def do_GET(self):
        if not self.authed():
            return
        p = self.path
        if p == "/clip/v2/resource/light":
            return self.reply(200, {"errors": [], "data": [light_json(i) for i in LIGHTS]})
        if p.startswith("/clip/v2/resource/light/") and p.rsplit("/", 1)[1] in LIGHTS:
            return self.reply(200, {"errors": [], "data": [light_json(p.rsplit("/", 1)[1])]})
        self.reply(404, {"errors": [{"description": "not found"}], "data": []})

    def do_PUT(self):
        raw = self.body()
        if not self.authed():
            return
        lid = self.path.rsplit("/", 1)[1]
        if not self.path.startswith("/clip/v2/resource/light/") or lid not in LIGHTS:
            return self.reply(404, {"errors": [{"description": "not found"}], "data": []})
        if os.path.exists(os.path.join(DIR, "fail")):
            return self.reply(503, {"errors": [{"description": "busy"}], "data": []})
        try:
            b = json.loads(raw)
        except ValueError:
            return self.reply(400, {"errors": [{"description": "invalid json"}], "data": []})
        st = STATE[lid]
        if "on" in b:
            st["on"] = b["on"]["on"]
        if "dimming" in b:
            st["brightness"] = float(b["dimming"]["brightness"])
        if "color_temperature" in b:
            st["mirek"] = int(b["color_temperature"]["mirek"])
        with open(os.path.join(DIR, "puts.log"), "a") as f:
            f.write("%s %s\n" % (lid, json.dumps(b, separators=(",", ":"))))
        self.reply(200, {"errors": [], "data": [{"rid": lid, "rtype": "light"}]})


ThreadingHTTPServer(("127.0.0.1", PORT), H).serve_forever()
