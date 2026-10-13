#!/bin/bash
# 07: the Govee bias light (H6056 "Flow Plus"). Answers Q7, Q17, Q18 and Q19 by checks A–I of
# docs/lighting-app/RESEARCH_08 section 5, and offers to save what it measures (GOVEE_IPS,
# BIAS_CAL, BIAS_WALL_RHO) to ~/.lighting/config.sh. Nothing is saved without a "y".
#
#   probe/07-govee.sh              every check, in order: A B C D E F R G H I (about 30 minutes)
#   probe/07-govee.sh --only FR    some of them (letters). R = the wall reflectance (ρ) check
#
#   A  discovery: who replies, with which fields; how many lights (Q17)
#   B  turn and brightness work; does `brightness` switch on a bar that's off? (FR-66)
#   C  Kelvin 2200 … 9000: does it change, does it stop at 6500?
#   D  devStatus: does it answer, and how long until it shows a command?
#   E  white path: LAN 6500 K vs the app's own white (Q18)
#   F  wall calibration: wall lux at 1…100 %, the BIAS_CAL table (Q19); bezel lux, bias on vs off
#   R  wall reflectance ρ: the wall against white paper (Q19)
#   G  gaps between two commands to one bar: 0, 50, 200, 300 ms; are both applied?
#   H  LAN still works with the bars paired to Apple Home (Matter)
#   I  flicker at low % (phone slow-motion video)
#
# Before: Govee Home app → each light → 2.4 GHz Wi-Fi, Settings → "LAN Control" ON (the switch
# can take minutes to appear). Needs the ESP32 + TSL2591 for E, F and R. lightd must be stopped.
# On exit (also Ctrl-C) each bar goes back to what devStatus said at the start, or off.
ENV_SENSOR_URL="${SENSOR_URL:-}"
. "$(dirname "$0")/lib.sh"
. "$PROBE_DIR/../lib/common.sh"
. "$PROBE_DIR/../lib/govee.sh"
. "$PROBE_DIR/../lib/config_migrate.sh"
[ -n "$ENV_SENSOR_URL" ] && SENSOR_URL="$ENV_SENSOR_URL"   # the test suite's fake sensor
ID="${SENSOR_ID:-sensor-ambient_light}"
IR_ID="${IR_ID:-sensor-tsl2591_infrared_light}"
FULL_ID="${FULL_ID:-sensor-tsl2591_full_spectrum_light}"

CHECKS=ABCDEFRGHI
if [ "$1" = --only ]; then CHECKS="$(echo "$2" | tr 'a-z' 'A-Z')"; fi
run() { case "$CHECKS" in *"$1"*) return 0 ;; esac; return 1; }

SETTLE="${SETTLE:-17}"            # ESPHome's sliding window is 15 samples at 1 s: wait it out
WINDOW="${WINDOW:-6}"             # seconds of readings averaged per step
STATUS_WAIT="${STATUS_WAIT:-3}"   # devStatus lags "several seconds" (RESEARCH_08 section 3)
HOLD="${HOLD:-2}"                 # seconds to look at each step
FLICKER_HOLD="${FLICKER_HOLD:-8}"
F_STEPS="${F_STEPS:-1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 40 50 60 70 80 90 100}"
CAL_K="${CAL_K:-5000}"            # Kelvin during the calibration: the night-time screen white (KELVIN_DIM)
R_PCT="${R_PCT:-50}"              # bars' level during the ρ check: plenty of signal
PAPER_RHO="${PAPER_RHO:-0.85}"    # white printer paper. UNVERIFIED for your paper (0.8–0.9 is typical)
GAP="${GOVEE_GAP_MS:-300}"

require_lightd_stopped
OUT=07-govee.txt
CSV="$RESULTS/07-wall-cal.csv"
[ "$CHECKS" = ABCDEFRGHI ] && : > "$RESULTS/$OUT"
record $OUT "probe 07 $(date '+%Y-%m-%d %H:%M'), checks $CHECKS"
cfg="$(cm_config_path)"

# ── helpers ──
all() {  # all <json>...: send to every bar, GAP ms apart per bar, bars in parallel
    local ip pids=""
    for ip in $IPS; do govee_send_seq "$ip" "$GAP" "$@" & pids="$pids $!"; done
    # shellcheck disable=SC2086
    wait $pids
}
one() { local ip="$1"; shift; govee_send_seq "$ip" "$GAP" "$@"; }
T() { govee_j_turn "$1"; }; B() { govee_j_brightness "$1"; }; K() { govee_j_kelvin "$1"; }
jfields() {  # <devStatus json> → "onOff brightness K r g b"
    printf '%s' "$1" | python3 -c 'import json, sys
try: d = json.load(sys.stdin)
except ValueError: sys.exit(1)
c = d.get("color") or {}
print(d.get("onOff", "?"), d.get("brightness", "?"), d.get("colorTemInKelvin", "?"), c.get("r", "?"), c.get("g", "?"), c.get("b", "?"))'
}
status() { local r; r="$(govee_query "$1" 2)" || return 1; jfields "$r"; }   # → "on b K r g b"
read3() {  # mean "lux ir full" over WINDOW seconds ("nan" for a channel with no reading)
    python3 - "$SENSOR_URL" "$WINDOW" "$ID" "$IR_ID" "$FULL_ID" <<'PY'
import json, sys, time, urllib.request
url, secs, ids = sys.argv[1], float(sys.argv[2]), sys.argv[3:]
vals, end = {i: [] for i in ids}, time.time() + secs
try:
    with urllib.request.urlopen(url, timeout=10) as r:
        while time.time() < end:
            line = r.readline().decode(errors="replace").strip()
            if line.startswith("data:"):
                try: d = json.loads(line[5:])
                except ValueError: continue
                if d.get("id") in vals and isinstance(d.get("value"), (int, float)):
                    vals[d["id"]].append(float(d["value"]))
except Exception as e:
    print(f"sensor: {e}", file=sys.stderr)
print(" ".join("%.2f" % (sum(v) / len(v)) if v else "nan" for v in (vals[i] for i in ids)))
PY
}
# measure: wait out the sensor's window, then set M_LUX, M_IR, M_FULL. Two failed readings in a
# row stop the probe (nan_check); this runs in the main shell, not in $(…), so that can exit.
measure() { sleep "$SETTLE"; set -- $(read3); M_LUX="${1:-nan}"; M_IR="${2:-nan}"; M_FULL="${3:-nan}"; nan_check "$M_LUX"; }
save_offer() {  # save_offer KEY value note
    ask_yn "Save $1=\"$2\" to $cfg?" && { config_save_key "$1" "$2" "$3" | tee -a "$RESULTS/$OUT"; return 0; }
    record $OUT "  (not saved: $1)"; return 1
}

say "Probe 07: the Govee bias light"
note "Before starting: in the Govee Home app, each bar is on 2.4 GHz Wi-Fi and Settings → LAN Control is ON."
note "This Mac and the bars must be on the same network. macOS may ask to let Terminal find devices on"
note "the local network: allow it (System Settings → Privacy & Security → Local Network)."
note "The bars will switch on, change and go off during the checks. At the end they go back to how they were."

# ── A: discovery ──
IPS="$GOVEE_IPS"; Q7="" ; Q17=""
if run A; then
    say "Check A: discovery"
    note "Joins 239.255.255.250, scans by multicast, and by unicast to GOVEE_IPS (${GOVEE_IPS:-none set}); replies on UDP 4002."
    replies="$(govee_discover 4 2>"$RESULTS/07-discover.log")"
    record $OUT "A: $(grep -h 'multicast group' "$RESULTS/07-discover.log" | sed 's/^govee: //' | head -1)"
    if [ -z "$replies" ]; then
        record $OUT "A: no replies. Check: LAN Control on for each light (it can take minutes to appear); Mac and bars on"
        record $OUT "   the same subnet; the router passes multicast on Wi-Fi; nothing else on this Mac owns UDP 4002 (Home"
        record $OUT "   Assistant, Homebridge); Terminal allowed under Privacy & Security → Local Network."
        Q7="no scan replies (LAN Control off, another network, or multicast blocked)"
        IPS="$(ask 'Type the bars'"'"' IPs from your router (space-separated) to test commands anyway, or Enter to stop:')"
        [ -z "$IPS" ] && { record $OUT "RESULT Q7: $Q7"; record $OUT "RESULT Q17: unknown (no replies)"; exit 1; }
        Q17="no scan replies; IPs typed by hand: $IPS"
    else
        n=0
        while IFS= read -r l; do
            n=$(( n + 1 ))
            record $OUT "A: $(printf '%s' "$l" | python3 -c 'import json, sys
d = json.load(sys.stdin)
print("ip %s  sku %s  device %s  wifi hw/sw %s/%s  ble hw/sw %s/%s%s" % (d.get("ip"), d.get("sku"), d.get("device"),
    d.get("wifiVersionHard"), d.get("wifiVersionSoft"), d.get("bleVersionHard"), d.get("bleVersionSoft"),
    "  (no ip in the reply: sender address used)" if d.get("ip_from") == "sender" else ""))')"
        done <<EOF
$replies
EOF
        IPS="$(printf '%s\n' "$replies" | python3 -c 'import json, sys
for l in sys.stdin:
    try: print(json.loads(l)["ip"])
    except Exception: pass' | sort -u | tr '\n' ' ' | sed 's/ $//')"
        skus="$(printf '%s\n' "$replies" | sed -n 's/.*"sku": "\([^"]*\)".*/\1/p' | sort -u | tr '\n' ' ' | sed 's/ $//')"
        record $OUT "A: $n light(s) replied: $IPS (sku: $skus)"
        Q17="$n light(s) replied (sku $skus): $IPS"
        [ "$n" = 2 ] && Q17="$Q17. The pair is two lights with two IPs."
        [ "$n" = 1 ] && Q17="$Q17. The pair answers as one light (or one bar isn't on LAN yet: check the app)."
        case " $skus " in *" H6056 "*) ;; *) Q17="$Q17 Not H6056: check the model on the box (RESEARCH_08 section 7)." ;; esac
        if [ "$(echo $IPS)" != "$(echo $GOVEE_IPS)" ]; then
            note "Reserve these addresses for the bars in your router (DHCP reservation), so they don't change."
            save_offer GOVEE_IPS "$IPS" "found by probe 07 check A" && GOVEE_IPS="$IPS"
        else
            record $OUT "A: GOVEE_IPS already holds these addresses"
        fi
    fi
fi
[ -z "$IPS" ] && { echo "No bars: set GOVEE_IPS in $cfg, or run check A (probe/07-govee.sh --only A)."; exit 1; }
FIRST="${IPS%% *}"

# Remember each bar's state; put it back on exit.
ORIG=""
for ip in $IPS; do s="$(status "$ip")" && ORIG="$ORIG$ip $s
"; done
restore() {
    local ip line
    for ip in $IPS; do
        line="$(printf '%s' "$ORIG" | awk -v ip="$ip" '$1 == ip')"
        set -- $line
        if [ "$2" = 1 ]; then
            local b="$3"; case "$b" in ''|*[!0-9]*|0) b=50 ;; esac; [ "$b" -gt 100 ] && b=100
            if [ -n "$4" ] && [ "$4" != 0 ] && [ "$4" != "?" ]; then one "$ip" "$(T 1)" "$(T 1)" "$(B "$b")" "$(K "$4")"
            else one "$ip" "$(T 1)" "$(T 1)" "$(B "$b")" "$(govee_j_rgb "${5:-255}" "${6:-255}" "${7:-255}")"; fi
            note "$ip: back to on, $b %"
        else
            one "$ip" "$(T 0)" "$(T 0)"; note "$ip: off"
        fi
    done
}
trap 'say "Restoring the bars"; restore' EXIT
trap 'exit 130' INT TERM

# ── B: turn and brightness ──
B_OK=""; B_WAKES=""
if run B; then
    say "Check B: turn and brightness (each bar in turn)"
    for ip in $IPS; do
        one "$ip" "$(T 1)" "$(T 1)" "$(B 100)"; sleep "$HOLD"; one "$ip" "$(B 10)"; sleep "$HOLD"
        if ask_yn "Did the bar at $ip switch on, go bright, then dim to about 10 %?"; then
            record $OUT "B: $ip: turn + brightness WORK"; B_OK="${B_OK:-yes}"
        else
            record $OUT "B: $ip: turn/brightness did NOT work"; B_OK=no
        fi
        one "$ip" "$(T 0)" "$(T 0)"; sleep "$HOLD"; one "$ip" "$(B 40)"; sleep "$STATUS_WAIT"
        s="$(status "$ip")"; set -- $s
        if ask_yn "The bar at $ip was switched off, then sent only a brightness. Is it ON now?"; then w=yes; else w=no; fi
        record $OUT "B: $ip: brightness sent to an OFF bar → it turns on: $w (devStatus onOff=${1:-no reply})"
        [ "$w" = yes ] && B_WAKES=yes; B_WAKES="${B_WAKES:-no}"
        one "$ip" "$(T 1)" "$(T 1)" "$(B 60)"
    done
    [ "$B_WAKES" = yes ] && record $OUT "B: NOTE: brightness switches a bar on, so lightd's 60 s refresh would undo an off from the Govee app (FR-66). Tell Claude."
fi

# ── C: Kelvin range ──
C_RANGE=""
if run C; then
    say "Check C: Kelvin (both bars, 60 %)"
    all "$(T 1)" "$(B 60)"
    lo="" hi="" prev=""
    for k in 2200 2700 4000 5000 6000 6500 7000 9000; do
        all "$(K "$k")"; sleep "$HOLD"
        s="$(status "$FIRST")"; set -- $s; ks="${3:-no reply}"
        if [ -z "$prev" ]; then q="${k} K: is it a warm (yellowish) white?"; else q="${k} K: does it look different from ${prev} K?"; fi
        if ask_yn "$q"; then d=yes; [ -z "$lo" ] && lo=$k; hi=$k; else d=no; fi
        record $OUT "C: ${k} K → looks different: $d; devStatus colorTemInKelvin=$ks"
        prev=$k
    done
    C_RANGE="${lo:-?}–${hi:-?} K"
    record $OUT "C: Kelvin visibly changes from ${lo:-?} K to ${hi:-?} K (lightd sends only 2200–6500)"
fi

# ── D: devStatus ──
D_LAG=""
if run D; then
    say "Check D: devStatus (on $FIRST)"
    one "$FIRST" "$(T 1)" "$(B 37)"; t0="$(now_ms)"; D_LAG="no devStatus reply"
    for i in 1 2 3 4 5 6 7 8 9 10 11 12; do
        s="$(status "$FIRST")" || { sleep 0.5; continue; }
        set -- $s
        if [ "$2" = 37 ]; then D_LAG="answers; showed brightness 37 after $(( $(now_ms) - t0 )) ms"; break; fi
        D_LAG="answers, but still showed brightness $2 after $(( ($(now_ms) - t0) / 1000 )) s"
        sleep 0.5
    done
    record $OUT "D: devStatus $D_LAG"
fi

say "Sensor placement for checks E, F and R"
if run E || run F || run R; then
    note "Room as dark as you can make it: blinds closed, lights off, phone and laptop screens away."
    note "Put the TSL2591 FLAT ON THE WALL behind the monitor, at the centre of the lit area, facing out into"
    note "the room (tape it). Don't stand between it and the bars. Keep the monitor as it is."
    pause "Sensor on the wall and the room dark? Press Enter"
fi

# ── E: white path ──
E_VERDICT=""
if run E; then
    say "Check E: white path (LAN 6500 K vs the Govee app's own white)"
    all "$(T 1)" "$(B 50)" "$(K 6500)"
    measure; el="$M_LUX"; eir="$M_IR"; efull="$M_FULL"
    sleep "$STATUS_WAIT"; s="$(status "$FIRST")"; set -- $s; ergb="${4:-?}/${5:-?}/${6:-?}"
    record $OUT "E: LAN 6500 K at 50 %: wall $el lx, IR $eir, full $efull; devStatus colour after the Kelvin command: $ergb"
    note "Look closely at a bar (a phone camera helps; don't stare into it). Coloured specks (red, green, blue)"
    note "mean the white is mixed from RGB; an even white or amber means the white (WW) chips."
    ask_yn "LAN 6500 K: do you see separate coloured specks?" && especk=yes || especk=no
    pause "Now in the Govee app: set both bars to WHITE at 6500 K (Colour → White/Temperature) and 50 % brightness. Then press Enter"
    measure; al="$M_LUX"; air="$M_IR"
    ask_yn "App white 6500 K: do you see separate coloured specks?" && aspeck=yes || aspeck=no
    record $OUT "E: app white 6500 K at 50 %: wall $al lx, IR $air; specks: LAN $especk, app $aspeck"
    E_VERDICT="$(awk -v el="$el" -v al="$al" -v ei="$eir" -v ai="$air" -v rgb="$ergb" -v es="$especk" -v as="$aspeck" 'BEGIN {
        v = "unclear"; why = ""
        if (rgb ~ /[1-9]/) { v = "probably RGB-mixed"; why = why "devStatus reports RGB " rgb " after a Kelvin command; " }
        if (es == "yes" && as == "no") { v = "RGB-mixed"; why = why "coloured specks over LAN, not in the app; " }
        else if (es == "no" && as == "no" && v == "unclear") { v = "probably the white (WW) chips"; why = why "no coloured specks either way; " }
        if (el + 0 > 0 && al + 0 > 0 && el != "nan" && al != "nan") {
            r = el / al; why = why sprintf("wall lux LAN/app %.2f", r)
            if (ei != "nan" && ai != "nan" && ei + 0 > 0 && ai + 0 > 0) why = why sprintf(", IR share LAN %.3f vs app %.3f", ei / el, ai / al)
        }
        print v " (" why ")" }')"
    record $OUT "E: white path: $E_VERDICT"
    all "$(T 1)" "$(B 50)" "$(K "$CAL_K")"     # take the bars back from the app
fi

# ── F: wall calibration ──
CAL=""; FLOOR=""
if run F; then
    say "Check F: wall lux at each strip % (both bars, ${CAL_K} K)"
    done_steps=""
    if [ -s "$CSV" ] && [ "$(wc -l < "$CSV")" -gt 2 ]; then
        if ask_yn "A calibration from earlier is in results/07-wall-cal.csv ($(( $(wc -l < "$CSV") - 2 )) steps). Resume it (n = start again)?"; then
            done_steps=" $(awk -F, 'NR > 2 { printf "%s ", $1 }' "$CSV")"
            FLOOR="$(awk -F, 'NR == 2 { print $2 }' "$CSV")"
        fi
    fi
    if [ -z "$done_steps" ]; then
        all "$(T 0)" "$(T 0)"
        note "Bars off: reading the dark-room floor."
        measure; FLOOR="$M_LUX"
        printf 'pct,lux,net\nfloor,%s,0\n' "$FLOOR" > "$CSV"
        all "$(T 1)" "$(T 1)" "$(K "$CAL_K")"
    else
        all "$(T 1)" "$(T 1)" "$(K "$CAL_K")"
    fi
    record $OUT "F: dark floor (bars off) $FLOOR lx"
    nsteps=$(echo $F_STEPS | wc -w | tr -d ' '); i=0
    note "$nsteps steps, about $(awk -v n="$nsteps" -v s="$SETTLE" -v w="$WINDOW" 'BEGIN { printf "%d", n * (s + w) / 60 + 0.5 }') min. Don't move the sensor. Ctrl-C stops; rerun to resume."
    for p in $F_STEPS; do
        i=$(( i + 1 ))
        case "$done_steps" in *" $p "*) continue ;; esac
        all "$(B "$p")"
        measure; v="$M_LUX"
        net="$(awk -v v="$v" -v f="$FLOOR" 'BEGIN { n = v - f; printf "%.1f", n < 0 ? 0 : n }')"
        echo "$p,$v,$net" >> "$CSV"
        printf '    %3s %%  → %s lx (net %s)   [%d/%d]\n' "$p" "$v" "$net" "$i" "$nsteps" >&2
    done
    CAL="$(awk -F, 'NR > 2 { printf "%s%s:%s", (n++ ? "," : ""), $1, $3 }' "$CSV")"
    record $OUT "F: BIAS_CAL=\"$CAL\"   (wall lux above the dark floor, at ${CAL_K} K; raw: results/07-wall-cal.csv)"
    save_offer BIAS_CAL "$CAL" "probe 07 check F, ${CAL_K} K, floor ${FLOOR} lx" && BIAS_CAL="$CAL"
fi

# ── R: wall reflectance ──
RHO=""; RHO_SRC="BIAS_WALL_RHO=$BIAS_WALL_RHO from the config (not measured)"
if run R; then
    say "Check R: wall reflectance ρ (bars at ${R_PCT} %)"
    all "$(T 1)" "$(B "$R_PCT")" "$(K "$CAL_K")"
    note "Hold (or prop) the sensor 3–5 cm from the wall, FACING the wall, in the lit area. Don't shadow the spot."
    pause "Sensor facing the wall? Press Enter"
    measure; w="$M_LUX"
    note "Now put a sheet of white printer paper flat on the wall at that spot, sensor at the same distance."
    pause "Paper in place? Press Enter"
    measure; pp="$M_LUX"
    RHO="$(awk -v w="$w" -v p="$pp" -v r="$PAPER_RHO" 'BEGIN { if (p + 0 <= 0) exit; printf "%.2f", r * w / p }')"
    record $OUT "R: facing the wall $w lx, facing white paper $pp lx → ρ = $PAPER_RHO × $w / $pp = ${RHO:-?} (paper ρ $PAPER_RHO assumed)"
    if [ -n "$RHO" ] && awk -v r="$RHO" 'BEGIN { exit !(r >= 0.05 && r <= 0.98) }'; then
        save_offer BIAS_WALL_RHO "$RHO" "probe 07 check R (paper rho $PAPER_RHO assumed)" && BIAS_WALL_RHO="$RHO"
        RHO_SRC="ρ = $RHO measured (wall vs paper)"
    else
        record $OUT "R: ρ ${RHO:-?} is implausible (outside 0.05–0.98): not saved. Rerun with --only R."
    fi
fi

# ── The level this gives, and the bezel check (part of F) ──
if run F && [ -n "$CAL" ]; then
    eval "$(awk -f "$ENGINE" -v cmd=biaspct -v bias_nits="$BIAS_TARGET_NITS" -v bias_rho="$BIAS_WALL_RHO" \
        -v bias_cal="$CAL" -v bias_fallback="$BIAS_FALLBACK_PCT" -v bias_max=100)"
    got="$(awk -F, -v p="$bias" 'NR > 2 && $1 == p { print $3 }' "$CSV")"
    nb="$(awk -F, -v p="$bias" 'NR > 2 && ($1 == p - 1 || $1 == p + 1) { printf "%s%s%% %s lx", (n++ ? ", " : ""), $1, $3 }' "$CSV")"
    LEVEL="$BIAS_TARGET_NITS cd/m2 on a ρ $BIAS_WALL_RHO wall = ${target_lux} lx → ${bias} % (exactly ${exact_pct} %)"
    [ -n "$got" ] && LEVEL="$LEVEL, which measured $got lx = $(awk -v l="$got" -v r="$BIAS_WALL_RHO" 'BEGIN { printf "%.1f", r * l / 3.14159265 }') cd/m2 (neighbours: ${nb:-none measured})"
    [ "$bias" -gt "$BIAS_MAX" ] && LEVEL="$LEVEL. Above BIAS_MAX ($BIAS_MAX %): lightd will stop at $BIAS_MAX %"
    record $OUT "F: $LEVEL"
    say "Check F, last part: does the bias light reach the sensor at its usual place?"
    note "Move the sensor back to its everyday spot on the top bezel, facing you."
    pause "Sensor back on the bezel? Press Enter"
    all "$(T 1)" "$(T 1)" "$(B "$bias")" "$(K "$CAL_K")"; measure; bon="$M_LUX"
    all "$(T 0)" "$(T 0)"; measure; boff="$M_LUX"
    record $OUT "F: bezel lux with the bias at ${bias} %: $bon; bias off: $boff (difference $(awk -v a="$bon" -v b="$boff" 'BEGIN { printf "%+.2f", a - b }') lx)"
fi

# ── G: gaps between commands ──
if run G; then
    say "Check G: two commands to one bar, close together"
    set -- 0:20:3000 50:30:4000 200:40:5000 300:50:6000
    for spec in "$@"; do
        g="${spec%%:*}"; rest="${spec#*:}"; bb="${rest%%:*}"; kk="${rest#*:}"
        for ip in $IPS; do
            govee_send_seq "$ip" "$g" "$(T 1)" "$(B "$bb")" "$(K "$kk")"; sleep "$STATUS_WAIT"
            s="$(status "$ip")"
            if [ -n "$s" ]; then
                set -- $s
                res="brightness $( [ "$2" = "$bb" ] && echo applied || echo "NOT applied ($2)" ), Kelvin $( [ "$3" = "$kk" ] && echo applied || echo "NOT applied ($3)" ) (devStatus)"
            else
                ask_yn "$ip: did it go to about $bb % at ${kk} K?" && res="both applied (by eye)" || res="NOT both applied (by eye)"
            fi
            record $OUT "G: gap $g ms, $ip: $res"
        done
    done
    note "lightd keeps ${GAP} ms between datagrams to one bar."
fi

# ── H: Matter ──
if run H; then
    say "Check H: LAN with Apple Home (Matter)"
    if ask_yn "Are the bars paired with Apple Home (Matter) right now?"; then
        all "$(T 0)" "$(T 0)"; sleep "$HOLD"; all "$(T 1)" "$(T 1)" "$(B 30)" "$(K 4000)"; sleep "$HOLD"
        ask_yn "Did both bars go off, then come back at about 30 %, warm white?" \
            && record $OUT "H: LAN works with Matter paired" || record $OUT "H: LAN did NOT work with Matter paired"
    else
        record $OUT "H: not tested (not paired with Matter). To test later: pair in Apple Home, then probe/07-govee.sh --only H"
    fi
fi

# ── I: flicker ──
if run I; then
    say "Check I: flicker at low brightness"
    note "For each step: film the bars (or the wall behind them) with the phone's SLOW-MOTION video for ~5 s."
    flick=""
    all "$(T 1)" "$(K "$CAL_K")"
    for p in 1 3 5 10; do
        all "$(B "$p")"; sleep "$FLICKER_HOLD"
        pause "Bars at $p %: film in slow motion, then press Enter"
        ask_yn "In the slow-motion video at $p %, do you see dark bands or flicker?" && flick="$flick $p"
    done
    if [ -n "$flick" ]; then record $OUT "I: flicker (dark bands in slow motion = PWM) at:$flick % (of 1 3 5 10 %)"
    else record $OUT "I: no flicker seen at 1 3 5 10 %"; fi
fi

# ── Results ──
say "Results"
if run A || run B || run C || run D; then
    q7="LAN API"
    [ -n "$Q17" ] && q7="$q7: ${Q17%%:*}"
    [ -n "$B_OK" ] && q7="$q7; turn + brightness on :4003 $( [ "$B_OK" = yes ] && echo work || echo 'did NOT work on every bar')"
    [ -n "$B_WAKES" ] && q7="$q7; brightness switches an off bar on: $B_WAKES"
    [ -n "$C_RANGE" ] && q7="$q7; Kelvin visibly changes over $C_RANGE"
    [ -n "$D_LAG" ] && q7="$q7; devStatus $D_LAG"
    [ -n "$Q7" ] && q7="$Q7"
    record $OUT "RESULT Q7: $q7"
fi
run A && record $OUT "RESULT Q17: ${Q17:-unknown}"
if run A || run E; then
    q18="LAN Control: $( [ -n "$Q7" ] && echo 'no scan reply' || echo 'works (scan replied, commands land)')"
    [ -n "$E_VERDICT" ] && q18="$q18; white path: $E_VERDICT" || q18="$q18; white path not checked (check E)"
    q18="$q18. The TSL2591 can't tell chromaticity, CRI or how close 6500 K is to D65 (a colorimeter can); it only shows brightness and the infrared share, which differ when the emitters differ"
    record $OUT "RESULT Q18: $q18"
fi
if run F || run R; then
    q19="$RHO_SRC"
    if [ -n "$CAL" ]; then q19="$q19; BIAS_CAL measured ($(echo "$CAL" | tr ',' '\n' | wc -l | tr -d ' ') steps at ${CAL_K} K); ${LEVEL:-}"
    else q19="$q19; BIAS_CAL not measured (check F)"; fi
    record $OUT "RESULT Q19: $q19"
fi
note "Full results: $RESULTS/$OUT. Saved settings take effect when lightd restarts:"
note "  launchctl kickstart -k gui/\$(id -u)/com.lighting.lightd   (or stop and start bin/lightd)"
