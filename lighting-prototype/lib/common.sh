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
# ── Time of day (FR-23) ──
# The Mac's time-zone name (Europe/Berlin), from $TZ or /etc/localtime. LIGHT_TZ overrides (tests).
tz_name() {
    local z="${LIGHT_TZ:-${TZ:-}}"
    [ -n "$z" ] || z="$(readlink /etc/localtime 2>/dev/null)"
    echo "${z#*zoneinfo/}"
}
# "lat lon" for the time zone: a city in it, close enough for sunset (±10 min). LATITUDE and
# LONGITUDE override. Unknown zones fall back to the UTC offset (15° per hour) at 45° N.
tz_coords() {
    if [ -n "$LATITUDE" ] && [ -n "$LONGITUDE" ]; then echo "$LATITUDE $LONGITUDE"; return; fi
    case "$(tz_name)" in
        Europe/Berlin)                echo "52.52 13.40" ;;
        Asia/Amman)                   echo "31.95 35.93" ;;
        Europe/London)                echo "51.51 -0.13" ;;
        Europe/Paris|Europe/Brussels) echo "48.86 2.35" ;;
        Europe/Amsterdam)             echo "52.37 4.90" ;;
        Europe/Vienna)                echo "48.21 16.37" ;;
        Europe/Zurich)                echo "47.37 8.54" ;;
        Asia/Dubai)                   echo "25.20 55.27" ;;
        Asia/Riyadh)                  echo "24.71 46.68" ;;
        Africa/Cairo)                 echo "30.04 31.24" ;;
        Asia/Beirut)                  echo "33.89 35.50" ;;
        Asia/Jerusalem|Asia/Hebron|Asia/Gaza) echo "31.77 35.21" ;;
        America/New_York)             echo "40.71 -74.01" ;;
        America/Los_Angeles)          echo "34.05 -118.24" ;;
        *) date +%z | awk '{ s = (substr($1, 1, 1) == "-") ? -1 : 1; printf "45 %.2f\n", s * (substr($1, 2, 2) + substr($1, 4, 2) / 60) * 15 }' ;;
    esac
}
# "doy:minute:utcoffset" now, e.g. 290:1215:+0200. LIGHT_CLOCK overrides (tests).
clock_now() {
    [ -n "$LIGHT_CLOCK" ] && { echo "$LIGHT_CLOCK"; return; }
    date '+%j %H %M %z' | awk '{ printf "%d:%d:%s\n", $1, $2 * 60 + $3, $4 }'
}
tod_args() {
    local ll; ll="$(tz_coords)"
    TOD_ARGS="-v tod=${TIME_OF_DAY:-0} -v clock=$(clock_now) -v lat=${ll% *} -v lon=${ll#* } -v bed=${BEDTIME:-23:00} -v knight=${KELVIN_NIGHT:-4000} -v ramp=${TOD_RAMP_MIN:-60}"
}
# phase=…, warm_end=…, sunrise=…, sunset=… for `light status`.
tod_info() {
    tod_args
    # shellcheck disable=SC2086
    awk -f "$ENGINE" -v cmd=tod $TOD_ARGS -v kdim="$KELVIN_DIM" -v kbright="$KELVIN_BRIGHT"
}

engine_targets() {  # <lf> <mode> [actual_b] [on_gains r:g:b]
    local lf="$1" mode="$2" actual_b="$3" on_gains="$4"
    tod_args
    # shellcheck disable=SC2086
    awk -f "$ENGINE" -v cmd=targets $TOD_ARGS -v lf="$lf" -v mode="$mode" -v actual_b="$actual_b" -v on_gains="$on_gains" \
        -v curve="$BRIGHTNESS_CURVE" -v bmin="$BRIGHTNESS_MIN" -v bmax="$BRIGHTNESS_MAX" \
        -v comp="$LUMINANCE_COMPENSATION" -v gamma="$GAIN_GAMMA" \
        -v kdim_lux="$KELVIN_DIM_LUX" -v kdim="$KELVIN_DIM" \
        -v kbright_lux="$KELVIN_BRIGHT_LUX" -v kbright="$KELVIN_BRIGHT" -v kstep="$KELVIN_STEP" \
        -v kfloor="$KELVIN_FLOOR" -v table="$GAIN_TABLE" -v critical_gains="$CRITICAL_GAINS" \
        -v critical_brightness="$CRITICAL_BRIGHTNESS" \
        -v bias_nits="$BIAS_TARGET_NITS" -v bias_rho="$BIAS_WALL_RHO" -v bias_cal="$BIAS_CAL" \
        -v bias_fallback="$BIAS_FALLBACK_PCT" -v bias_max="$BIAS_MAX" -v bias_critical="$BIAS_IN_CRITICAL" \
        -v off_lux="$BIAS_OFF_LUX" -v on_lux="$BIAS_ON_LUX" -v bias_prev="$(state_get bias_room "")" \
        -v gk_min="$GOVEE_K_MIN" -v gk_max="$GOVEE_K_MAX" \
        -v boffset="$(state_get bright_offset 0)"
}

engine_filter() {
    awk -f "$ENGINE" -v cmd=filter -v lux="$1" -v prev="$2" -v dt="$3" \
        -v tau_up="$TAU_UP" -v tau_down="$TAU_DOWN"
}
