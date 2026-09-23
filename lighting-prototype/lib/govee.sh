# Govee LAN API over UDP. Sourced after common.sh.
#
#   discovery : {"msg":{"cmd":"scan",...}}  →  multicast 239.255.255.250:4001
#   replies   : devices → this Mac, unicast UDP 4002
#   commands  : → <device ip>:4003 (unicast). UDP has no acknowledgement.
#
# Protocol taken from wez/govee-py (govee_led_wez/govee.py). The official doc,
# app-h5.govee.com/user-manual/wlan-guide, is the reference to check against.

GOVEE_CMD_PORT="${GOVEE_CMD_PORT:-4003}"
GOVEE_SCAN_PORT="${GOVEE_SCAN_PORT:-4001}"
GOVEE_REPLY_PORT="${GOVEE_REPLY_PORT:-4002}"
GOVEE_MCAST="${GOVEE_MCAST:-239.255.255.250}"

# Fire-and-forget one datagram. -w1 makes BSD/OpenBSD nc exit after sending.
govee_send() {  # <ip> <json>
    printf '%s' "$2" | nc -u -w1 "$1" "$GOVEE_CMD_PORT" >/dev/null 2>&1
}

govee_turn()       { govee_send "$1" "{\"msg\":{\"cmd\":\"turn\",\"data\":{\"value\":$2}}}"; }
govee_brightness() { govee_send "$1" "{\"msg\":{\"cmd\":\"brightness\",\"data\":{\"value\":$2}}}"; }
govee_kelvin()     { govee_send "$1" "{\"msg\":{\"cmd\":\"colorwc\",\"data\":{\"color\":{\"r\":0,\"g\":0,\"b\":0},\"colorTemInKelvin\":$2}}}"; }
govee_rgb()        { govee_send "$1" "{\"msg\":{\"cmd\":\"colorwc\",\"data\":{\"color\":{\"r\":$2,\"g\":$3,\"b\":$4},\"colorTemInKelvin\":0}}}"; }
govee_status()     { govee_send "$1" '{"msg":{"cmd":"devStatus","data":{}}}'; }

# Discovery: listen on 4002, send one scan, collect replies for N seconds.
# Prints one JSON reply per line. Fails if something else already owns 4002
# (Home Assistant/Homebridge Govee plugins on this Mac).
# python3 is preferred: `nc -u -l` locks onto the FIRST sender, so with nc you
# only ever hear one strip per scan.
govee_discover() {  # [seconds]
    local secs="${1:-3}" out pid
    if python3 -c 'import socket' 2>/dev/null; then
        python3 - "$secs" "$GOVEE_REPLY_PORT" "$GOVEE_MCAST" "$GOVEE_SCAN_PORT" <<'PY'
import socket, sys, time
secs, reply_port, mcast, scan_port = float(sys.argv[1]), int(sys.argv[2]), sys.argv[3], int(sys.argv[4])
rx = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
rx.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
rx.bind(("", reply_port))
rx.settimeout(0.2)
tx = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
tx.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_TTL, 1)
tx.sendto(b'{"msg":{"cmd":"scan","data":{"account_topic":"reserve"}}}', (mcast, scan_port))
end = time.time() + secs
while time.time() < end:
    try:
        data, addr = rx.recvfrom(4096)
        print(data.decode(errors="replace"), flush=True)
    except socket.timeout:
        pass
PY
        return
    fi
    out="$(mktemp)"
    nc -u -l "$GOVEE_REPLY_PORT" > "$out" 2>/dev/null &
    pid=$!
    sleep 0.3
    printf '%s' '{"msg":{"cmd":"scan","data":{"account_topic":"reserve"}}}' \
        | nc -u -w1 "$GOVEE_MCAST" "$GOVEE_SCAN_PORT" >/dev/null 2>&1
    sleep "$secs"
    kill "$pid" 2>/dev/null
    wait "$pid" 2>/dev/null
    awk '{ gsub(/}}{/, "}}\n{"); print }' "$out"
    rm -f "$out"
}

# Send bias state to every configured strip, rate-limited and with periodic refresh.
govee_apply() {  # <pct> <kelvin> [force]
    local pct="$1" k="$2" force="${3:-0}" last_pct last_k last_t ip pids=""
    [ -z "$GOVEE_IPS" ] && return 0
    last_pct="$(state_get govee_pct "")"
    last_k="$(state_get govee_k "")"
    last_t="$(state_get govee_t 0)"
    if [ "$force" != 1 ] && [ "$pct" = "$last_pct" ] && [ "$k" = "$last_k" ] \
        && [ $(( $(now) - last_t )) -lt "$BIAS_REFRESH" ]; then
        return 0
    fi
    for ip in $GOVEE_IPS; do
        # Sequential per strip (they drop back-to-back packets), parallel across strips.
        ( govee_brightness "$ip" "$pct"; sleep 0.2; govee_kelvin "$ip" "$k" ) &
        pids="$pids $!"
    done
    # Wait only for our own sends: a bare `wait` would also wait for lightd's
    # background sensor stream and freeze the loop.
    # shellcheck disable=SC2086
    wait $pids
    state_set govee_pct "$pct"; state_set govee_k "$k"; state_set govee_t "$(now)"
    log "govee: ${pct}% ${k}K → $GOVEE_IPS"
}
