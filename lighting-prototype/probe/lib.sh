# Shared helpers for the hardware probes. Sourced. macOS bash 3.2.
# Probes need the Xcode Command Line Tools (for m1ddc) and therefore have python3.

PROBE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLS="${LIGHT_HOME:-$HOME/.lighting}/tools"
RESULTS="${PROBE_RESULTS:-$PROBE_DIR/results}"   # the test suite points this at a temp dir
mkdir -p "$RESULTS" "$TOOLS"

M1="$TOOLS/m1ddc"         # stock m1ddc: every write sent twice (DDC_ITERATIONS 2)
M1X="$TOOLS/m1ddc-1x"     # patched: every write sent once
SENSOR_URL="${SENSOR_URL:-http://lunarsensor.local/events}"
LUNAR="${LUNAR:-$HOME/.local/bin/lunar}"
M1DDC_DISPLAY="${M1DDC_DISPLAY:-}"

say()   { printf '\n\033[1m%s\033[0m\n' "$*"; }
note()  { printf '  %s\n' "$*"; }
# Prompts go to stderr, so they still show when a probe captures a function's output.
pause() { printf '\n  → %s  [Enter] ' "$*" >&2; read -r _; }
ask_yn() {  # ask_yn "question" → returns 0 for yes
    local a
    while true; do
        printf '  ? %s [y/n] ' "$1" >&2; read -r a
        case "$a" in y|Y) return 0 ;; n|N) return 1 ;; esac
    done
}
ask() { local a; printf '  ? %s ' "$1" >&2; read -r a; echo "$a"; }

# record <file> <line...>: print and append to results/<file>
record() { local f="$RESULTS/$1"; shift; printf '%s\n' "$*" | tee -a "$f"; }

# shellcheck disable=SC2086
m1()  { "$M1"  $M1DDC_DISPLAY "$@"; }
# shellcheck disable=SC2086
m1x() { "$M1X" $M1DDC_DISPLAY "$@"; }

need_m1ddc() {
    [ -x "$M1" ] && [ -x "$M1X" ] || { echo "Run probe/00-setup.sh first (builds m1ddc)."; exit 1; }
}

lunar_running() { pgrep -xq Lunar; }
betterdisplay_running() { pgrep -xq BetterDisplay; }
monitorcontrol_running() { pgrep -xq MonitorControl; }

# Lunar prints a property as "0: <name>" then "<TAB><Property>: <value>". Return the value.
lunar_get() { "$LUNAR" displays external "$1" 2>/dev/null | awk -F': ' '/^\t/ { print $NF; exit }'; }

# BetterDisplay and MonitorControl are also DDC clients. Any probe that touches the
# monitor needs them closed.
require_betterdisplay_quiet() {
    local app check
    for app in BetterDisplay MonitorControl; do
        check=betterdisplay_running; [ $app = MonitorControl ] && check=monitorcontrol_running
        if $check; then
            say "$app is running."
            note "It's another app on the same DDC bus. Quit it for the probes (menu bar icon → Quit)."
            pause "Quit $app, then press Enter"
            $check && { echo "$app still running; stopping."; exit 1; }
        fi
    done
}

# lightd (the adaptive loop) also writes brightness and gains. It must not run during a probe.
# Checks the PID lightd records at start. (Matching command lines with `pgrep -f` would also
# match any shell whose command merely mentions "bin/lightd", e.g. the one used to stop it.)
lightd_running() {
    local f="${LIGHT_HOME:-$HOME/.lighting}/state/lightd.pid" pid
    [ -f "$f" ] || return 1
    pid="$(cat "$f")"
    kill -0 "$pid" 2>/dev/null && ps -p "$pid" -o command= 2>/dev/null | grep -q 'lightd'
}
require_lightd_stopped() {
    if lightd_running; then
        say "lightd (the adaptive loop) is running."
        note "It would write its own brightness and gains in the middle of the measurement."
        note "Stop it:  launchctl bootout gui/\$(id -u)/com.lighting.lightd 2>/dev/null; kill \$(cat ~/.lighting/state/lightd.pid)"
        pause "Stop lightd, then press Enter"
        lightd_running && { echo "lightd still running; stopping."; exit 1; }
    fi
}

require_lunar_quiet() {
    require_lightd_stopped
    require_betterdisplay_quiet
    if lunar_running; then
        say "Lunar is running."
        note "This probe writes DDC directly. Two apps on the bus at once can corrupt"
        note "packets, and Lunar may re-adapt brightness mid-measurement."
        pause "Quit Lunar (menu bar → Quit), then press Enter"
        lunar_running && { echo "Lunar still running; stopping."; exit 1; }
    fi
}

# ── Baseline: what the monitor actually held before any probe touched it.
# Written once by probe 03 (from DDC reads if they're trustworthy, else from the OSD
# values you typed). Every probe that changes gains restores THIS, never an assumed 50.
BASELINE="$RESULTS/baseline.txt"
baseline_get() {  # baseline_get luminance|red|green|blue → value, or empty if no baseline yet
    [ -f "$BASELINE" ] && awk -v k="$1" '$1 == k { print $2 }' "$BASELINE"
}
baseline_restore() {
    local c v
    if [ ! -f "$BASELINE" ]; then
        note "No baseline yet (probe 03 records it). Leaving gains as they are."
        return
    fi
    for c in red green blue; do v="$(baseline_get $c)"; [ -n "$v" ] && m1 set $c "$v" >/dev/null; done
    note "Restored baseline gains $(baseline_get red)/$(baseline_get green)/$(baseline_get blue)."
}
require_baseline() {
    [ -f "$BASELINE" ] || { echo "Run probe/03-ddc-read.sh first: it records the monitor's real starting values."; exit 1; }
}

# sse_avg <sensor-id> <seconds>: mean value of that id over a window, "nan" if none
sse_avg() {
    python3 - "$SENSOR_URL" "$1" "$2" <<'PY'
import json, sys, time, urllib.request
url, sid, secs = sys.argv[1], sys.argv[2], float(sys.argv[3])
vals, end = [], time.time() + secs
try:
    with urllib.request.urlopen(url, timeout=10) as r:
        while time.time() < end:
            line = r.readline().decode(errors="replace").strip()
            if line.startswith("data:"):
                try:
                    d = json.loads(line[5:])
                except ValueError:
                    continue
                if d.get("id") == sid and isinstance(d.get("value"), (int, float)):
                    vals.append(float(d["value"]))
except Exception as e:
    print(f"nan  # {e}", file=sys.stderr)
print(sum(vals) / len(vals) if vals else "nan")
PY
}

# sse_ids <seconds>: list sensor ids the ESP32 publishes
sse_ids() {
    python3 - "$SENSOR_URL" "$1" <<'PY'
import json, sys, time, urllib.request
url, secs = sys.argv[1], float(sys.argv[2])
ids, end = {}, time.time() + secs
with urllib.request.urlopen(url, timeout=10) as r:
    while time.time() < end:
        line = r.readline().decode(errors="replace").strip()
        if line.startswith("data:"):
            try:
                d = json.loads(line[5:])
            except ValueError:
                continue
            if "id" in d:
                ids[d["id"]] = d.get("state", d.get("value"))
for k, v in ids.items():
    print(f"{k}\t{v}")
PY
}

# Full-screen solid colour page for measurements. Opens in Safari.
show_patch() {  # show_patch <css colour>
    local f="$RESULTS/patch.html"
    printf '<!doctype html><html><body style="margin:0;background:%s;cursor:none"></body></html>' "$1" > "$f"
    open -a Safari "$f"
}
