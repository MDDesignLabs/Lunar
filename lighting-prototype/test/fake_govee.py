#!/usr/bin/env python3
"""Fake Govee lights speaking the LAN protocol (Govee's WLAN guide; RESEARCH_08 §1).

    fake_govee.py <log> [sku] [--dev IP[:opt[:opt]]] ... [--state FILE]

Each --dev is one light at that address (default: one at 127.0.0.1). Options:
    noip     the scan reply has no "ip" field (seen on other models): clients must use the sender
    nomcast  ignores multicast scans; only a unicast scan to IP:4001 finds it
    rgbwhite after a Kelvin command, devStatus reports a non-zero RGB colour (the guide's
             "converted into the color value of red, green and blue")
Per light: listens on IP:4003 for commands and IP:4001 for unicast scans; one shared socket on
:4001 joined to 239.255.255.250 takes multicast scans. Replies go from IP to <sender>:4002.
Every received command is appended to <log> as "<ip> <epoch_ms> <json>". With --state, the
lights' state (onOff, brightness, color, colorTemInKelvin) is kept in FILE as JSON {ip: state}.
A light whose address can't be bound (127.0.0.2 on macOS without an alias) is skipped with a
warning on stderr.
"""
import json
import os
import socket
import struct
import sys
import threading
import time

args = sys.argv[1:]
LOG = args.pop(0)
SKU = args.pop(0) if args and not args[0].startswith("--") else "H6046"
DEVS, STATE_FILE = [], None
while args:
    a = args.pop(0)
    if a == "--dev":
        parts = args.pop(0).split(":")
        DEVS.append((parts[0], set(parts[1:])))
    elif a == "--state":
        STATE_FILE = args.pop(0)
DEVS = DEVS or [("127.0.0.1", set())]
LOCK = threading.Lock()
STATE = {}


def reuse(s):
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    if hasattr(socket, "SO_REUSEPORT"):
        try:
            s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEPORT, 1)
        except OSError:
            pass


def save_state():
    if STATE_FILE:
        tmp = STATE_FILE + ".tmp"
        with open(tmp, "w") as f:
            json.dump(STATE, f)
        os.replace(tmp, STATE_FILE)


def reply(dev_ip, addr, payload):
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.bind((dev_ip, 0))        # so the client sees the light's own address as the sender
    except OSError:
        pass
    s.sendto(json.dumps({"msg": payload}).encode(), (addr[0], 4002))
    s.close()


def scan_reply(dev_ip, opts, addr):
    data = {"ip": dev_ip, "device": "AA:BB:CC:DD:EE:" + "%02X:%02X:%02X" % tuple(int(x) for x in dev_ip.split(".")[1:]),
            "sku": SKU, "bleVersionHard": "3.01.01", "bleVersionSoft": "1.03.01",
            "wifiVersionHard": "1.00.10", "wifiVersionSoft": "1.02.03"}
    if "noip" in opts:
        del data["ip"]
    reply(dev_ip, addr, {"cmd": "scan", "data": data})


def is_scan(data):
    try:
        return json.loads(data).get("msg", {}).get("cmd") == "scan"
    except ValueError:
        return False


def unicast_scan_listener(dev_ip, opts, s):
    while True:
        data, addr = s.recvfrom(4096)
        if is_scan(data):
            scan_reply(dev_ip, opts, addr)


def multicast_scan_listener(s, devs):
    while True:
        data, addr = s.recvfrom(4096)
        if is_scan(data):
            for dev_ip, opts in devs:
                if "nomcast" not in opts:
                    scan_reply(dev_ip, opts, addr)


def command_listener(dev_ip, opts, s):
    while True:
        data, addr = s.recvfrom(4096)
        text = data.decode(errors="replace")
        with LOCK:
            with open(LOG, "a") as f:
                f.write("%s %d %s\n" % (dev_ip, int(time.time() * 1000), text))
            try:
                msg = json.loads(text).get("msg", {})
            except ValueError:
                continue
            cmd, d, st = msg.get("cmd"), msg.get("data", {}), STATE[dev_ip]
            if cmd == "turn":
                st["onOff"] = d.get("value", st["onOff"])
            elif cmd == "brightness":
                st["brightness"] = d.get("value", st["brightness"])
            elif cmd == "colorwc":
                k = d.get("colorTemInKelvin", 0)
                st["colorTemInKelvin"] = k
                st["color"] = d.get("color", st["color"])
                if k and "rgbwhite" in opts:
                    st["color"] = {"r": 255, "g": 236 if k < 5000 else 250, "b": 200 if k < 5000 else 245}
            save_state()
            snapshot = dict(st)
        if cmd == "devStatus":
            reply(dev_ip, addr, {"cmd": "devStatus", "data": snapshot})


live = []
for dev_ip, opts in DEVS:
    try:
        cs = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        cs.bind((dev_ip, 4003))
        ss = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        reuse(ss)
        ss.bind((dev_ip, 4001))
    except OSError as e:
        print(f"fake_govee: can't bind {dev_ip} ({e}); that light is skipped", file=sys.stderr)
        continue
    STATE[dev_ip] = {"onOff": 1, "brightness": 100, "color": {"r": 255, "g": 255, "b": 255}, "colorTemInKelvin": 6500}
    live.append((dev_ip, opts))
    threading.Thread(target=command_listener, args=(dev_ip, opts, cs), daemon=True).start()
    threading.Thread(target=unicast_scan_listener, args=(dev_ip, opts, ss), daemon=True).start()
save_state()

ms = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
reuse(ms)
ms.bind(("", 4001))
try:
    mreq = struct.pack("4s4s", socket.inet_aton("239.255.255.250"), socket.inet_aton("0.0.0.0"))
    ms.setsockopt(socket.IPPROTO_IP, socket.IP_ADD_MEMBERSHIP, mreq)
except OSError as e:
    print(f"fake_govee: multicast join failed ({e}); unicast scans still work", file=sys.stderr)
multicast_scan_listener(ms, live)
