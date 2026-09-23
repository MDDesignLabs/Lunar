#!/bin/bash
# 05: Q3 linear-light or gamma-encoded gain?  Q4 is there headroom above 50?
#
# Uses the TSL2591 you already own as the meter. No colorimeter needed.
# Two gains at 0 + full-screen white = one primary only, so the sensor sees a fixed
# spectrum and its reading is proportional to that channel's output.
# Takes ~15 minutes. Cost: ~35 gain writes.
. "$(dirname "$0")/lib.sh"
need_m1ddc; require_lunar_quiet
OUT=05-gain-domain.txt; : > "$RESULTS/$OUT"
CSV="$RESULTS/05-gain-measurements.csv"
SETTLE="${SETTLE:-17}"     # ESPHome sliding window is 15 samples @ 1 s: wait it out
WINDOW="${WINDOW:-6}"
ID="${SENSOR_ID:-sensor-ambient_light}"

say "Setup (read carefully)"
note "1. Room as dark as you can make it; close blinds, lights off."
note "2. AOC OSD: colour mode = User; Dynamic Contrast/DCR OFF; Eco/Smart modes OFF;"
note "   any 'Low Blue Light' OFF. macOS: HDR off for this display, True Tone n/a, Night Shift OFF."
note "3. Take the ESP32 off its perch; tape the TSL2591 face-on to the CENTRE of the screen."
note "   Don't move it until the probe ends."
pause "Ready"

orig_l="$(m1 get luminance 2>/dev/null)"; orig_l="${orig_l:-50}"
restore() { m1 set red 50; m1 set green 50; m1 set blue 50; m1 set luminance "$orig_l"; } >/dev/null 2>&1
trap 'restore; say "Restored gains 50/50/50 and brightness $orig_l"' EXIT
m1 set luminance "$orig_l" >/dev/null

show_patch '#ffffff'
pause "Safari opened a white page: make it full screen (⌃⌘F), move the pointer off-screen, then Enter"

measure() {  # measure <channel> <gain> → appends CSV row
    sleep "$SETTLE"
    local v; v="$(sse_avg "$ID" "$WINDOW")"
    printf '%s,%s,%s\n' "$1" "$2" "$v" >> "$CSV"
    printf '    %-6s %3s → %s lux\n' "$1" "$2" "$v"
}

echo "channel,gain,lux" > "$CSV"
say "Floor: all gains 0"
m1 set red 0; m1 set green 0; m1 set blue 0
measure floor 0
for ch in red green blue; do
    say "Channel $ch (others at 0)"
    for other in red green blue; do [ $other = $ch ] || m1 set $other 0; done
    for g in 50 40 30 20 45 36 25 55 60 50; do
        m1 set $ch $g >/dev/null
        measure $ch $g
    done
    m1 set $ch 0
done
m1 set red 0; m1 set green 0; m1 set blue 0
measure floor 0

say "Analysis"
cfg="${LIGHT_CONFIG:-$HOME/.lighting/config.sh}"
table="$( [ -f "$cfg" ] && . "$cfg"; echo "${GAIN_TABLE:-6500:50:50:50,5500:50:47:44,5000:50:46:40,4500:50:44:36}")"
python3 "$PROBE_DIR/analyze_gain.py" "$CSV" --table "$table" | tee -a "$RESULTS/$OUT"
note "Raw data: $CSV. Primaries assumed sRGB; the AOC is wider-gamut, so absolute Kelvin"
note "is approximate. The linear-vs-encoded verdict does not depend on primaries."
