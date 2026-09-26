#!/bin/bash
# 05: Q3 linear-light or gamma-encoded gain?  Q4 is there headroom above 50?
#
# Uses the TSL2591 you already own as the meter. No colorimeter needed.
# Two gains at 0 + full-screen white = one primary only, so the sensor sees a fixed
# spectrum and its reading is proportional to that channel's output.
# Takes ~15 minutes. Cost: ~35 gain writes.
. "$(dirname "$0")/lib.sh"
need_m1ddc; require_lunar_quiet; require_baseline
OUT=05-gain-domain.txt; : > "$RESULTS/$OUT"
CSV="$RESULTS/05-gain-measurements.csv"
SETTLE="${SETTLE:-17}"     # ESPHome sliding window is 15 samples @ 1 s: wait it out
WINDOW="${WINDOW:-6}"
ID="${SENSOR_ID:-sensor-ambient_light}"

PATCH="${WHITEPATCH:-$TOOLS/whitepatch}"
PROBE_BRIGHTNESS="${PROBE_BRIGHTNESS:-80}"   # brighter backlight = more signal over room light; restored after

if [ ! -x "$PATCH" ]; then
    swiftc -O -o "$PATCH" "$PROBE_DIR/../helpers/whitepatch.swift" 2>"$RESULTS/whitepatch-build.log" || {
        echo "Couldn't build the white-screen helper (see results/whitepatch-build.log)."; exit 1; }
fi

say "Setup (read carefully)"
note "1. Room as dark as you can make it: blinds closed, lights off, phone/laptop screens away."
note "2. AOC OSD: colour mode = User; DCR/Dynamic Contrast OFF; Eco modes OFF; Low Blue Light OFF."
note "   macOS: Night Shift OFF, HDR OFF for this display."
note "3. The sensor's window must face the glass, flat and centred, within ~5 mm, and not move."
note "4. When you press Enter, the WHOLE monitor turns white for ~16 minutes. That's the"
note "   measurement: don't touch anything. Click the white screen only if you need to abort."
pause "Sensor in place? Press Enter to start"

orig_l="$(baseline_get luminance)"; orig_l="${orig_l:-50}"
PATCH_PID=""
restore() {
    [ -n "$PATCH_PID" ] && kill "$PATCH_PID" 2>/dev/null
    [ -n "$CAF_PID" ] && kill "$CAF_PID" 2>/dev/null
    baseline_restore; m1 set luminance "$orig_l" >/dev/null 2>&1
}
trap 'restore; say "Restored baseline gains and brightness $orig_l"' EXIT

# Keep the display awake: nobody touches the Mac for 16 minutes.
CAF_PID=""
if command -v caffeinate >/dev/null; then caffeinate -d & CAF_PID=$!; fi
m1 set luminance "$PROBE_BRIGHTNESS" >/dev/null
"$PATCH" & PATCH_PID=$!
sleep 2

measure() {  # measure <channel> <gain> → appends CSV row, prints the value
    sleep "$SETTLE"
    local v; v="$(sse_avg "$ID" "$WINDOW")"
    printf '%s,%s,%s\n' "$1" "$2" "$v" >> "$CSV"
    printf '    %-6s %3s → %s lux\n' "$1" "$2" "$v" >&2
    echo "$v"
}
gains() { m1 set red "$1" >/dev/null; m1 set green "$2" >/dev/null; m1 set blue "$3" >/dev/null; }

echo "channel,gain,lux" > "$CSV"

# ── Preflight (~40 s): can the sensor actually see the screen?
say "Preflight: white vs black"
gains 50 50 50; white="$(measure white 50)"
gains 0 0 0;    black="$(measure floor 0)"
if ! awk -v w="$white" -v b="$black" 'BEGIN { exit !(w != "nan" && b != "nan" && w - b > 20 && w > 5 * b) }'; then
    kill "$PATCH_PID" 2>/dev/null; PATCH_PID=""
    record $OUT "PREFLIGHT FAILED: white screen = $white lux, black screen = $black lux."
    record $OUT "  The sensor isn't seeing controlled light from the monitor. Stopped before the 15-minute sweep."
    record $OUT "  Check: sensor window facing the glass and centred; nothing (tape, enclosure lip) over it;"
    record $OUT "  the monitor actually turned fully white; room dark. Then rerun."
    exit 1
fi
record $OUT "preflight ok: white $white lux vs black $black lux"

# ── Sweep. Floor re-measured before each channel, so room-light drift is tracked.
for ch in red green blue; do
    say "Channel $ch (others at 0)"
    gains 0 0 0; measure floor 0 >/dev/null
    for g in 50 40 30 20 45 36 25 55 60 50; do
        m1 set $ch $g >/dev/null
        measure $ch $g >/dev/null
    done
    m1 set $ch 0 >/dev/null
done
gains 0 0 0; measure floor 0 >/dev/null
kill "$PATCH_PID" 2>/dev/null; PATCH_PID=""

say "Analysis"
cfg="${LIGHT_CONFIG:-$HOME/.lighting/config.sh}"
table="$( [ -f "$cfg" ] && . "$cfg"; echo "${GAIN_TABLE:-6500:50:50:50,5500:50:47:44,5000:50:46:40,4500:50:44:36}")"
python3 "$PROBE_DIR/analyze_gain.py" "$CSV" --table "$table" | tee -a "$RESULTS/$OUT"
note "Raw data: $CSV. Primaries assumed sRGB; the AOC is wider-gamut, so absolute Kelvin"
note "is approximate. The linear-vs-encoded verdict does not depend on primaries."
