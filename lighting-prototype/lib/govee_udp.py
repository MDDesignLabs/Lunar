#!/usr/bin/env python3
"""Govee LAN API sockets for lib/govee.sh (python3 ships with the Command Line Tools).

Protocol (Govee's WLAN guide, app-h5.govee.com/user-manual/wlan-guide; RESEARCH_08 §1):
  scan      → 239.255.255.250:4001 (the client joins that group first); replies → us on :4002
  commands  → <device>:4003; devStatus replies → us on :4002. UDP: no acknowledgement.

  govee_udp.py send <ip> <port> <gap_ms> <json> [<json> ...]
      Send each datagram in order, gap_ms apart. Exit 1 if a send raised (no route etc.).
  govee_udp.py discover <secs> <reply_port> <mcast> <scan_port> [<ip> ...]
      Join the group, send one multicast scan and one unicast scan to each <ip>, collect
      replies for <secs>. Prints one JSON object per device (the reply's "data", with "ip"
      filled in from the sender's address when the reply has none), deduplicated.
  govee_udp.py status <ip> <cmd_port> <reply_port> <secs>
      Send devStatus to <ip>, print the first reply's "data" from that address, or exit 1.
"""
import json
import socket
import struct
import sys
import time

SCAN = b'{"msg":{"cmd":"scan","data":{"account_topic":"reserve"}}}'


def note(msg):
    print("govee: " + msg, file=sys.stderr, flush=True)


def send(ip, port, gap_ms, datagrams):
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    rc = 0
    for i, d in enumerate(datagrams):
        if i:
            time.sleep(gap_ms / 1000.0)
        try:
            s.sendto(d.encode(), (ip, port))
        except OSError as e:
            note(f"send to {ip}:{port} failed: {e}")
            rc = 1
    s.close()
    return rc


def reply_socket(reply_port):
    rx = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    rx.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    if hasattr(socket, "SO_REUSEPORT"):
        try:
            rx.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEPORT, 1)
        except OSError:
            pass
    rx.bind(("", reply_port))
    rx.settimeout(0.2)
    return rx


def parse(data, addr):
    """The reply's msg.data, with ip from the sender when missing. None if not JSON."""
    try:
        msg = json.loads(data.decode(errors="replace")).get("msg", {})
    except (ValueError, AttributeError):
        return None, None
    d = msg.get("data")
    if not isinstance(d, dict):
        d = {}
    if not d.get("ip"):
        d["ip"] = addr[0]           # seen on other models: a reply without "ip" (RESEARCH_08 §4)
        d["ip_from"] = "sender"
    return msg.get("cmd"), d


def discover(secs, reply_port, mcast, scan_port, ips):
    try:
        rx = reply_socket(reply_port)
    except OSError as e:
        note(f"can't listen on UDP {reply_port} ({e}): another app (Home Assistant, Homebridge) may own it")
        return 2
    # The guide says the client "needs to join" the group. Join on the listening socket.
    try:
        mreq = struct.pack("4s4s", socket.inet_aton("239.255.255.250"), socket.inet_aton("0.0.0.0"))
        rx.setsockopt(socket.IPPROTO_IP, socket.IP_ADD_MEMBERSHIP, mreq)
        note("joined multicast group 239.255.255.250")
    except OSError as e:
        note(f"couldn't join multicast group 239.255.255.250 ({e}); unicast scans still work")
    tx = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    tx.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_TTL, 1)
    for target in [mcast] + ips:
        try:
            tx.sendto(SCAN, (target, scan_port))
        except OSError as e:
            note(f"scan to {target}:{scan_port} failed: {e}")
    seen = set()
    end = time.time() + secs
    while time.time() < end:
        try:
            data, addr = rx.recvfrom(4096)
        except socket.timeout:
            continue
        cmd, d = parse(data, addr)
        if cmd != "scan":
            continue
        key = (d.get("ip"), d.get("device"))
        if key in seen:
            continue
        seen.add(key)
        print(json.dumps(d), flush=True)
    return 0


def status(ip, cmd_port, reply_port, secs):
    try:
        rx = reply_socket(reply_port)
    except OSError as e:
        note(f"can't listen on UDP {reply_port} ({e})")
        return 2
    tx = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        tx.sendto(b'{"msg":{"cmd":"devStatus","data":{}}}', (ip, cmd_port))
    except OSError as e:
        note(f"devStatus to {ip} failed: {e}")
        return 1
    end = time.time() + secs
    while time.time() < end:
        try:
            data, addr = rx.recvfrom(4096)
        except socket.timeout:
            continue
        if addr[0] != ip:
            continue
        cmd, d = parse(data, addr)
        if cmd == "devStatus":
            if d.pop("ip_from", None):
                d.pop("ip", None)       # devStatus has no ip of its own; don't add one
            print(json.dumps(d), flush=True)
            return 0
    return 1


def main(a):
    if len(a) >= 4 and a[0] == "send":
        return send(a[1], int(a[2]), float(a[3]), a[4:])
    if len(a) >= 5 and a[0] == "discover":
        return discover(float(a[1]), int(a[2]), a[3], int(a[4]), a[5:])
    if len(a) == 5 and a[0] == "status":
        return status(a[1], int(a[2]), int(a[3]), float(a[4]))
    print(__doc__, file=sys.stderr)
    return 64


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
