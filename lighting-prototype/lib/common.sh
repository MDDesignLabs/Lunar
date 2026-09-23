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

now() { date +%s; }
today() { date +%Y-%m-%d; }
# Milliseconds, for write timing. perl ships with macOS; fall back to whole seconds.
now_ms() { perl -MTime::HiRes=time -e 'printf "%d", time * 1000' 2>/dev/null || echo $(( $(date +%s) * 1000 )); }

log() {
    printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LIGHT_HOME/lightd.log"
    [ -n "$VERBOSE" ] && printf '%s\n' "$*" >&2
    return 0
}

state_get() { cat "$STATE/$1" 2>/dev/null || printf '%s' "$2"; }
state_set() { printf '%s' "$2" > "$STATE/$1.tmp" && mv "$STATE/$1.tmp" "$STATE/$1"; }

# Integer absolute difference.
absdiff() { local d=$(( $1 - $2 )); [ $d -lt 0 ] && d=$(( -d )); echo $d; }

# Serialise every hardware transaction across processes (daemon + `light` command).
# mkdir is atomic; locks older than 30 s are treated as stale.
lock() {
    local tries=0
    while ! mkdir "$STATE/.lock" 2>/dev/null; do
        tries=$(( tries + 1 ))
        if [ $tries -gt 150 ]; then
            log "lock: breaking stale lock"
            rmdir "$STATE/.lock" 2>/dev/null
        fi
        sleep 0.2
    done
}
unlock() { rmdir "$STATE/.lock" 2>/dev/null; }

# Compute targets for a filtered log-lux value. Prints key=value lines.
engine_targets() {
    local lf="$1" mode="$2" actual_b="$3"
    awk -f "$ENGINE" -v cmd=targets -v lf="$lf" -v mode="$mode" -v actual_b="$actual_b" \
        -v curve="$BRIGHTNESS_CURVE" -v bmin="$BRIGHTNESS_MIN" -v bmax="$BRIGHTNESS_MAX" \
        -v comp="$LUMINANCE_COMPENSATION" -v gamma="$GAIN_GAMMA" \
        -v kdim_lux="$KELVIN_DIM_LUX" -v kdim="$KELVIN_DIM" \
        -v kbright_lux="$KELVIN_BRIGHT_LUX" -v kbright="$KELVIN_BRIGHT" -v kstep="$KELVIN_STEP" \
        -v table="$GAIN_TABLE" -v critical_gains="$CRITICAL_GAINS" \
        -v critical_brightness="$CRITICAL_BRIGHTNESS" \
        -v nits_min="$MONITOR_NITS_MIN" -v nits_max="$MONITOR_NITS_MAX" \
        -v bias_k="$BIAS_K" -v bias_min="$BIAS_MIN" -v bias_max="$BIAS_MAX"
}

engine_filter() {
    awk -f "$ENGINE" -v cmd=filter -v lux="$1" -v prev="$2" -v dt="$3" \
        -v tau_up="$TAU_UP" -v tau_down="$TAU_DOWN"
}
