# Shared helpers. Sourced, not executed. Written for macOS's bash 3.2.

LIGHT_HOME="${LIGHT_HOME:-$HOME/.lighting}"
PROTO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENGINE="$PROTO_DIR/lib/engine.awk"
STATE="$LIGHT_HOME/state"
mkdir -p "$STATE"

# Defaults first, then the user's overrides.
. "$PROTO_DIR/config.example.sh"
if [ -f "${LIGHT_CONFIG:-$LIGHT_HOME/config.sh}" ]; then
    . "${LIGHT_CONFIG:-$LIGHT_HOME/config.sh}"
fi
LUNAR="${LUNAR/#\~/$HOME}"
M1DDC="${M1DDC/#\~/$HOME}"
[ "$LUX_SOURCE" = direct ] && LUX_SOURCE=sse     # "direct" = straight from the ESP32
DISPLAY_STATE="${DISPLAY_STATE:-$LIGHT_HOME/tools/displaystate}"

now() { date +%s; }
# "asleep" / "awake" / "unknown" (helper not built; see helpers/displaystate.swift).
display_state() { [ -x "$DISPLAY_STATE" ] && "$DISPLAY_STATE" 2>/dev/null || echo unknown; }
today() { date +%Y-%m-%d; }
# Milliseconds, for write timing. perl ships with macOS; fall back to whole seconds.
now_ms() { perl -MTime::HiRes=time -e 'printf "%d", time * 1000' 2>/dev/null || echo $(( $(date +%s) * 1000 )); }

log() {
    printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LIGHT_HOME/lightd.log"
    [ -n "$VERBOSE" ] && printf '%s\n' "$*" >&2
    return 0
}

# Lunar prints a property as two lines:  "0: AOC CU34G4Z" / "<TAB>Blue Gain: 50".
# Return just the value from the indented line.
lunar_get() {  # lunar_get <display-filter> <property>
    "$LUNAR" displays "$1" "$2" 2>/dev/null | awk -F': ' '/^\t/ { print $NF; exit }'
}

state_get() { cat "$STATE/$1" 2>/dev/null || printf '%s' "$2"; }
state_set() { printf '%s' "$2" > "$STATE/$1.tmp.$$" && mv "$STATE/$1.tmp.$$" "$STATE/$1"; }   # per-process temp: two writers can't clobber each other's

# Integer absolute difference.
absdiff() { local d=$(( $1 - $2 )); [ $d -lt 0 ] && d=$(( -d )); echo $d; }

# Serialise every hardware transaction across processes (daemon + `light` command).
# mkdir is atomic. The owner's PID is kept inside, so a lock is only broken when its
# owner has died; a live owner is waited for up to 60 s, then this write is given up.
lock() {
    local tries=0 empty=0 owner
    while ! mkdir "$STATE/.lock" 2>/dev/null; do
        [ -d "$STATE" ] || { echo "lock: no state directory $STATE" >&2; return 1; }
        tries=$(( tries + 1 ))
        owner="$(cat "$STATE/.lock/pid" 2>/dev/null)"
        if [ -z "$owner" ]; then empty=$(( empty + 1 )); else empty=0; fi
        # Break it if its owner is dead, or if it has had no owner for 5 s (killed between
        # mkdir and writing the pid, or left by an older version of this code).
        if { [ -n "$owner" ] && ! kill -0 "$owner" 2>/dev/null; } || [ $empty -ge 25 ]; then
            log "lock: owner ${owner:-unknown} is gone; breaking its lock"
            rm -rf "$STATE/.lock"; empty=0
        fi
        if [ $tries -ge 300 ]; then
            log "lock: still held by ${owner:-unknown} after 60 s; skipping this write"
            return 1
        fi
        sleep 0.2
    done
    echo $$ > "$STATE/.lock/pid"
}
unlock() { [ "$(cat "$STATE/.lock/pid" 2>/dev/null)" = "$$" ] && rm -rf "$STATE/.lock"; return 0; }

# Epoch seconds of the Mac's last wake from sleep (sysctl kern.waketime), or empty if unknown.
last_wake() { sysctl -n kern.waketime 2>/dev/null | sed -n 's/.*sec = \([0-9]*\).*/\1/p'; }

# Compute targets for a filtered log-lux value. Prints key=value lines.
engine_targets() {  # <lf> <mode> [actual_b] [on_gains r:g:b]
    local lf="$1" mode="$2" actual_b="$3" on_gains="$4"
    awk -f "$ENGINE" -v cmd=targets -v lf="$lf" -v mode="$mode" -v actual_b="$actual_b" -v on_gains="$on_gains" \
        -v curve="$BRIGHTNESS_CURVE" -v bmin="$BRIGHTNESS_MIN" -v bmax="$BRIGHTNESS_MAX" \
        -v comp="$LUMINANCE_COMPENSATION" -v gamma="$GAIN_GAMMA" \
        -v kdim_lux="$KELVIN_DIM_LUX" -v kdim="$KELVIN_DIM" \
        -v kbright_lux="$KELVIN_BRIGHT_LUX" -v kbright="$KELVIN_BRIGHT" -v kstep="$KELVIN_STEP" \
        -v kfloor="$KELVIN_FLOOR" -v table="$GAIN_TABLE" -v critical_gains="$CRITICAL_GAINS" \
        -v critical_brightness="$CRITICAL_BRIGHTNESS" \
        -v nits_min="$MONITOR_NITS_MIN" -v nits_max="$MONITOR_NITS_MAX" \
        -v bias_k="$BIAS_K" -v bias_min="$BIAS_MIN" -v bias_max="$BIAS_MAX" \
        -v boffset="$(state_get bright_offset 0)"
}

engine_filter() {
    awk -f "$ENGINE" -v cmd=filter -v lux="$1" -v prev="$2" -v dt="$3" \
        -v tau_up="$TAU_UP" -v tau_down="$TAU_DOWN"
}
