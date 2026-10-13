# Govee LAN API over UDP. Sourced after common.sh.
#
#   discovery : {"msg":{"cmd":"scan",...}} → multicast 239.255.255.250:4001 (after joining the
#               group) and unicast to each GOVEE_IPS:4001; replies → this Mac, UDP 4002
#   commands  : → <device ip>:4003 (unicast). UDP has no acknowledgement.
#
# Protocol: Govee's WLAN guide (app-h5.govee.com/user-manual/wlan-guide), cross-checked against
# wez/govee-py and govee-local-api (RESEARCH_08 §1). Only these commands are used: scan, turn,
# brightness, colorwc (with colorTemInKelvin) and devStatus. Nothing here has been tested on
# the H6056 yet: probe/07-govee.sh is what checks it.
#
# The sockets are in lib/govee_udp.py (python3 ships with the Command Line Tools). Without a
# working python3, sends fall back to nc and discovery to `nc -u -l` (hears one strip only).
#
# GOVEE_IPS="" disables all of this: govee_apply returns before sending or storing anything.

GOVEE_CMD_PORT="${GOVEE_CMD_PORT:-4003}"
GOVEE_SCAN_PORT="${GOVEE_SCAN_PORT:-4001}"
GOVEE_REPLY_PORT="${GOVEE_REPLY_PORT:-4002}"
GOVEE_MCAST="${GOVEE_MCAST:-239.255.255.250}"
GOVEE_PY="$PROTO_DIR/lib/govee_udp.py"

_govee_py=""
govee_py_ok() {
    if [ -z "$_govee_py" ]; then
        if python3 -c 'import socket' >/dev/null 2>&1; then _govee_py=1; else _govee_py=0; fi
    fi
    [ "$_govee_py" = 1 ]
}

# The datagrams. Only fields from Govee's guide; the r/g/b of 0 with a Kelvin is the guide's form.
govee_j_turn()       { printf '{"msg":{"cmd":"turn","data":{"value":%s}}}' "$1"; }
govee_j_brightness() { printf '{"msg":{"cmd":"brightness","data":{"value":%s}}}' "$1"; }
govee_j_kelvin()     { printf '{"msg":{"cmd":"colorwc","data":{"color":{"r":0,"g":0,"b":0},"colorTemInKelvin":%s}}}' "$1"; }
govee_j_rgb()        { printf '{"msg":{"cmd":"colorwc","data":{"color":{"r":%s,"g":%s,"b":%s},"colorTemInKelvin":0}}}' "$1" "$2" "$3"; }

# govee_send_seq <ip> <gap_ms> <json>...: send in order, gap_ms apart (one device).
govee_send_seq() {
    local ip="$1" gap="$2" d first=1
    shift 2
    if govee_py_ok; then
        python3 "$GOVEE_PY" send "$ip" "$GOVEE_CMD_PORT" "$gap" "$@" 2>/dev/null
        return
    fi
    for d in "$@"; do
        [ $first = 1 ] || sleep "$(awk -v g="$gap" 'BEGIN { printf "%.3f", g / 1000 }')"
        first=0
        # -w1 makes BSD nc exit about a second after stdin closes; don't wait for it.
        printf '%s' "$d" | nc -u -w1 "$ip" "$GOVEE_CMD_PORT" >/dev/null 2>&1 &
    done
}
govee_send() { govee_send_seq "$1" 0 "$2"; }  # <ip> <json>: fire-and-forget one datagram

# Raw, single-device commands (bin/govee, probe 07). No clamping here: probe 07 check C sends
# Kelvin outside 2200–6500 on purpose. govee_apply is the only path lightd uses, and it clamps.
govee_turn()       { govee_send "$1" "$(govee_j_turn "$2")"; }
govee_brightness() { govee_send "$1" "$(govee_j_brightness "$2")"; }
govee_kelvin()     { govee_send "$1" "$(govee_j_kelvin "$2")"; }
govee_rgb()        { govee_send "$1" "$(govee_j_rgb "$2" "$3" "$4")"; }
govee_status()     { govee_send "$1" '{"msg":{"cmd":"devStatus","data":{}}}'; }

# govee_query <ip> [secs]: ask for devStatus and print the reply's data as one JSON line
# (onOff, brightness, color, colorTemInKelvin), or return 1 if none came. Govee says the
# state can lag "several seconds" behind a command, so ask ≥ 3 s after it (RESEARCH_08 §3).
govee_query() {
    govee_py_ok || return 1
    python3 "$GOVEE_PY" status "$1" "$GOVEE_CMD_PORT" "$GOVEE_REPLY_PORT" "${2:-2}"
}

# govee_discover [secs] [extra-ip...]: join 239.255.255.250, scan by multicast and by unicast to
# every GOVEE_IPS (and extra) address, print one JSON line per device: the reply's data, with
# "ip" taken from the sender when the reply has none. Fails if something else owns UDP 4002
# (Home Assistant/Homebridge Govee plugins on this Mac).
govee_discover() {
    local secs="${1:-3}" out pid
    shift
    if govee_py_ok; then
        # shellcheck disable=SC2086
        python3 "$GOVEE_PY" discover "$secs" "$GOVEE_REPLY_PORT" "$GOVEE_MCAST" "$GOVEE_SCAN_PORT" $GOVEE_IPS "$@"
        return
    fi
    # nc fallback: `nc -u -l` locks onto the FIRST sender, so only one strip is heard per scan,
    # and it can't join the multicast group.
    out="$(mktemp)"
    nc -u -l "$GOVEE_REPLY_PORT" > "$out" 2>/dev/null &
    pid=$!
    sleep 0.3
    printf '%s' '{"msg":{"cmd":"scan","data":{"account_topic":"reserve"}}}' \
        | nc -u -w1 "$GOVEE_MCAST" "$GOVEE_SCAN_PORT" >/dev/null 2>&1
    sleep "$secs"
    kill "$pid" 2>/dev/null
    wait "$pid" 2>/dev/null
    awk '{ gsub(/}}{/, "}}\n{"); print }' "$out" | sed -n 's/.*"data":\(.*\)}}$/\1/p'
    rm -f "$out"
}

# ── The bias light: what lightd and `light` send ─────────────────────────────
#
# govee_apply <pct> <kelvin> [force]
#   pct 0 = off (`turn 0`); 1–100 = on at that brightness. Brightness 0 is never sent: the
#   guide's range is 1–100. Kelvin is clamped to GOVEE_K_MIN..GOVEE_K_MAX (2200–6500).
#
# Rules (SPEC FR-64–FR-66, RESEARCH_08 §3):
#   - coalesce: the latest target is stored (govee_want); a send held back by the 2 s limit
#     goes out on the next call (govee_tick from lightd's loop), with whatever is latest then;
#   - send only on a change of ≥ 1 % or ≥ 100 K, at most one update per GOVEE_MIN_INTERVAL
#     (2 s), datagrams to one device ≥ GOVEE_GAP_MS (300 ms) apart, even across calls;
#   - on/off transitions are sent twice, 300 ms apart; coming on sends `turn 1` before
#     brightness and Kelvin;
#   - refresh every BIAS_REFRESH (60 s) while on: brightness + Kelvin only, never `turn 1`,
#     so bars you switched off in the Govee app stay off. UNVERIFIED: whether `brightness`
#     powers on a bar that's off (probe 07 check B). If it does, the refresh will too.
#     Nothing is refreshed while off.
#   - force (user actions, wake, clean exit): skips the 2 s limit and the change thresholds,
#     not the 300 ms gap, and still never adds `turn 1` to bars believed on.
# State: govee_on (1/0/empty = unknown), govee_pct, govee_k, govee_t (last full send, for the
# refresh), govee_ms / govee_end_ms (start/end of the last send), govee_want, govee_pending.
govee_apply() {
    local pct="$1" k="$2" force="${3:-0}" on cur_on cur_pct cur_k plan="" kind="" t ms wait_ms ip pids=""
    [ -z "$GOVEE_IPS" ] && return 0
    case "$pct" in ''|*[!0-9.]*|*.*.*) log "govee: ignoring a bad level '$pct'"; return 1 ;; esac
    case "$k" in ''|*[!0-9.]*|*.*.*) k=6500 ;; esac
    pct="$(awk -v p="$pct" 'BEGIN { if (p + 0 <= 0) print 0; else { r = int(p + 0.5); print (r < 1) ? 1 : (r > 100 ? 100 : r) } }')"
    k="$(awk -v k="$k" -v lo="${GOVEE_K_MIN:-2200}" -v hi="${GOVEE_K_MAX:-6500}" \
        'BEGIN { k = int(k + 0.5); print (k < lo) ? lo : (k > hi ? hi : k) }')"
    on=1; [ "$pct" = 0 ] && on=0
    state_set govee_want "$pct $k"

    cur_on="$(state_get govee_on "")"; cur_pct="$(state_get govee_pct "")"; cur_k="$(state_get govee_k "")"
    t="$(now)"
    if [ $on = 0 ]; then
        if [ "$cur_on" != 0 ] || [ "$force" = 1 ]; then kind=off; plan="$(govee_j_turn 0) $(govee_j_turn 0)"; fi
    elif [ "$cur_on" != 1 ]; then
        kind=on; plan="$(govee_j_turn 1) $(govee_j_turn 1) $(govee_j_brightness "$pct") $(govee_j_kelvin "$k")"
    elif [ "$force" = 1 ]; then
        kind=update; plan="$(govee_j_brightness "$pct") $(govee_j_kelvin "$k")"
    else
        [ "$pct" != "$cur_pct" ] && plan="$(govee_j_brightness "$pct")"
        if [ -z "$cur_k" ] || [ "$(absdiff "$k" "$cur_k")" -ge 100 ]; then
            plan="${plan:+$plan }$(govee_j_kelvin "$k")"
        else
            k="$cur_k"                     # under 100 K: keep what the bars have
        fi
        if [ -n "$plan" ]; then
            kind=update
        elif [ $(( t - $(state_get govee_t 0) )) -ge "${BIAS_REFRESH:-60}" ]; then
            kind=refresh; pct="$cur_pct"; k="$cur_k"; plan="$(govee_j_brightness "$cur_pct") $(govee_j_kelvin "$cur_k")"
        fi
    fi
    if [ -z "$plan" ]; then state_set govee_pending 0; return 0; fi

    ms="$(now_ms)"
    if [ "$force" != 1 ] && [ $(( ms - $(state_get govee_ms 0) )) -lt $(( ${GOVEE_MIN_INTERVAL:-2} * 1000 )) ]; then
        state_set govee_pending 1         # coalesced: govee_tick sends the latest target later
        return 0
    fi
    wait_ms=$(( ${GOVEE_GAP_MS:-300} - (ms - $(state_get govee_end_ms 0)) ))
    if [ $wait_ms -gt 0 ]; then
        sleep "$(awk -v w="$wait_ms" 'BEGIN { printf "%.3f", w / 1000 }')"; ms="$(now_ms)"
    fi
    for ip in $GOVEE_IPS; do
        # One sequence per device (≥ GOVEE_GAP_MS apart: they drop back-to-back packets),
        # devices in parallel.
        # shellcheck disable=SC2086
        govee_send_seq "$ip" "${GOVEE_GAP_MS:-300}" $plan &
        pids="$pids $!"
    done
    # Wait only for our own sends: a bare `wait` would also wait for lightd's
    # background sensor stream and freeze the loop.
    # shellcheck disable=SC2086
    wait $pids
    state_set govee_ms "$ms"; state_set govee_end_ms "$(now_ms)"; state_set govee_pending 0
    state_set govee_t "$t"
    if [ $on = 1 ]; then
        state_set govee_on 1; state_set govee_pct "$pct"; state_set govee_k "$k"
    else
        state_set govee_on 0
    fi
    case "$kind" in
        on)      log "govee: on ${pct}% ${k}K → $GOVEE_IPS" ;;
        off)     log "govee: off → $GOVEE_IPS" ;;
        update)  log "govee: ${pct}% ${k}K → $GOVEE_IPS" ;;
    esac
    return 0
}

# Re-apply the latest target: sends anything coalesced by the 2 s limit, and the refresh.
govee_tick() {
    [ -z "$GOVEE_IPS" ] && return 0
    local want; want="$(state_get govee_want "")"
    [ -z "$want" ] && return 0
    # shellcheck disable=SC2086
    govee_apply $want
}

# Forget what the bars are believed to show, so the next govee_apply sends a full transition
# (lightd start: a crash may have left them in any state).
govee_invalidate() { rm -f "$STATE/govee_on"; }
