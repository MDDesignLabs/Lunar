#!/usr/bin/env python3
"""Fake Govee strip, speaking the LAN protocol as implemented by wez/govee-py.

  - joins 239.255.255.250 and listens on :4001 for {"cmd":"scan"} → replies to <sender>:4002
  - listens on :4003 for commands and appends each JSON datagram to <log>
  - replies to devStatus on <sender>:4002

    fake_govee.py <log> [sku]
"""
import json
import socket
import struct
import sys
import threading

LOG = sys.argv[1]
SKU = sys.argv[2] if len(sys.argv) > 2 else "H6046"
state = {"onOff": 1, "brightness": 100, "color": {"r": 255, "g": 255, "b": 255}, "colorTemInKelvin": 6500}


def reply(addr, payload):
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.sendto(json.dumps({"msg": payload}).encode(), (addr[0], 4002))
    s.close()


def scan_listener():
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind(("", 4001))
    try:
        mreq = struct.pack("4s4s", socket.inet_aton("239.255.255.250"), socket.inet_aton("0.0.0.0"))
        s.setsockopt(socket.IPPROTO_IP, socket.IP_ADD_MEMBERSHIP, mreq)
    except OSError as e:
        print(f"fake_govee: multicast join failed ({e}); unicast scans still work", file=sys.stderr)
    while True:
        data, addr = s.recvfrom(4096)
        msg = json.loads(data).get("msg", {})
        if msg.get("cmd") == "scan":
            reply(addr, {"cmd": "scan", "data": {
                "ip": "127.0.0.1", "device": "AA:BB:CC:DD:EE:FF:00:11", "sku": SKU,
                "bleVersionHard": "3.01.01", "bleVersionSoft": "1.03.01",
                "wifiVersionHard": "1.00.10", "wifiVersionSoft": "1.02.03"}})


def command_listener():
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.bind(("", 4003))
    while True:
        data, addr = s.recvfrom(4096)
        with open(LOG, "a") as f:
            f.write(data.decode() + "\n")
        msg = json.loads(data).get("msg", {})
        cmd, d = msg.get("cmd"), msg.get("data", {})
        if cmd == "turn":
            state["onOff"] = d["value"]
        elif cmd == "brightness":
            state["brightness"] = d["value"]
        elif cmd == "colorwc":
            state["color"] = d.get("color", state["color"])
            state["colorTemInKelvin"] = d.get("colorTemInKelvin", 0)
        elif cmd == "devStatus":
            reply(addr, {"cmd": "devStatus", "data": state})


threading.Thread(target=scan_listener, daemon=True).start()
command_listener()
