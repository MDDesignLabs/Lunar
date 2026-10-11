#!/bin/bash
# 08: Q16 how does this monitor's brightness setting map to light, and does the screen light the sensor?
#
# Part A, the brightness response: sensor flat on the screen centre, dark room. Steps the
#   backlight 0, 10, ... 100, then 50 again (drift check) and compares the shape with
#   KitGuru's colorimeter review of this model. Prints a recommended BRIGHTNESS_CURVE.
# Part B, self-illumination: sensor at its everyday spot, lights off. Compares the lux with a
#   white screen and with a black screen, and says whether the screen is lighting the sensor.
#
#   probe/08-brightness.sh                 both parts (asks before Part B)
#   probe/08-brightness.sh --part-a-only
#   probe/08-brightness.sh --part-b-only
#
# Optional: run after a few days on the new curve (RESEARCH_07), in a dark room. Uses the
# TSL2591 you already own. Lux can't give absolute cd/m², so absolute levels assume KitGuru's.
# Takes ~6 min (Part A) + ~1 min (Part B).
# Worst case, both parts: 30 m1ddc writes, each sent twice by stock m1ddc, so ~60 DDC packets:
#   Part A  19 = brightness 50 (1) + gains to 0 and back to baseline (6) + 12 brightness steps
#   Part B   7 = brightness 50 (1) + gains to baseline (3) + gains to 0 (3)
#   exit     4 = baseline gains (3) + baseline brightness (1), on every exit path
# Stopping early only ever adds the 4 restore writes. Probes pace themselves by SETTLE and
# don't touch lightd's daily counters (lightd and the apps that share the bus must be off).
. "$(dirname "$0")/lib.sh"

DO_A=1; DO_B=1; ASK_B=1
for arg in "$@"; do
    case "$arg" in
        --part-a-only) DO_B=0; ASK_B=0 ;;
        --part-b-only) DO_A=0; ASK_B=0 ;;
        *) echo "Usage: $0 [--part-a-only | --part-b-only]"; exit 1 ;;
    esac
done

need_m1ddc; require_lunar_quiet; require_baseline
OUT=08-brightness.txt; : > "$RESULTS/$OUT"
CSV_A="$RESULTS/08-brightness-measurements.csv"
CSV_B="$RESULTS/08-self-illumination.csv"
SETTLE="${SETTLE:-17}"     # ESPHome sliding window is 15 samples @ 1 s: wait it out
WINDOW="${WINDOW:-6}"
ID="${SENSOR_ID:-sensor-ambient_light}"
MID_BRIGHTNESS=50          # the floor and Part B are measured here

PATCH="${WHITEPATCH:-$TOOLS/whitepatch}"
if [ ! -x "$PATCH" ] || [ "$PROBE_DIR/../helpers/whitepatch.swift" -nt "$PATCH" ]; then
    swiftc -O -o "$PATCH" "$PROBE_DIR/../helpers/whitepatch.swift" 2>"$RESULTS/whitepatch-build.log" || {
        echo "Couldn't build the white-screen helper (see results/whitepatch-build.log)."; exit 1; }
fi

orig_l="$(baseline_get luminance)"; orig_l="${orig_l:-50}"
bred="$(baseline_get red)"; bgreen="$(baseline_get green)"; bblue="$(baseline_get blue)"
PATCH_PID=""; CAF_PID=""
restore() {
    [ -n "$PATCH_PID" ] && kill "$PATCH_PID" 2>/dev/null
    [ -n "$CAF_PID" ] && kill "$CAF_PID" 2>/dev/null
    baseline_restore; m1 set luminance "$orig_l" >/dev/null 2>&1
}
trap 'restore; say "Restored baseline gains and brightness $orig_l"' EXIT

measure() {  # measure <label> → appends "<label>,<lux>" to $CSV, prints the value
    sleep "$SETTLE"
    local v; v="$(sse_avg "$ID" "$WINDOW")"
    printf '%s,%s\n' "$1" "$v" >> "$CSV"
    printf '    %-6s → %s lux\n' "$1" "$v" >&2
    echo "$v"
}
gains() { m1 set red "$1" >/dev/null; m1 set green "$2" >/dev/null; m1 set blue "$3" >/dev/null; }
baseline_gains() { gains "${bred:-50}" "${bgreen:-50}" "${bblue:-50}"; }
start_patch() { "$PATCH" & PATCH_PID=$!; sleep 2; }
stop_patch() { [ -n "$PATCH_PID" ] && kill "$PATCH_PID" 2>/dev/null; PATCH_PID=""; }

# Keep the display awake while nobody touches the Mac.
if command -v caffeinate >/dev/null; then caffeinate -d & CAF_PID=$!; fi

# ── Part A ────────────────────────────────────────────────────────────────
if [ $DO_A = 1 ]; then
    CSV="$CSV_A"
    say "Part A: brightness response (read carefully)"
    note "1. Room as dark as you can make it: blinds closed, lights off, phone/laptop screens away."
    note "2. AOC OSD: colour mode = User; DCR/Dynamic Contrast OFF; Eco modes OFF; Low Blue Light OFF."
    note "   macOS: Night Shift OFF, HDR OFF for this display."
    note "3. Lay the sensor FLAT on the middle of the screen, its window touching the glass, and don't move it."
    note "4. When you press Enter, the WHOLE monitor turns white for ~6 minutes, covering"
    note "   Terminal too, with no progress shown. The brightness will step up and down: that's the test."
    note "   Don't touch anything. To abort: click the white screen. The probe notices, stops,"
    note "   and puts the monitor back as it was."
    pause "Sensor in place? Press Enter to start"

    echo "brightness,lux" > "$CSV"
    m1 set luminance "$MID_BRIGHTNESS" >/dev/null
    start_patch

    say "Black floor (gains 0), so the room light can be subtracted"
    gains 0 0 0
    v="$(measure floor)"; patch_check; nan_check "$v"
    baseline_gains

    say "Brightness sweep (white screen, your normal colour balance)"
    for b in 0 10 20 30 40 50 60 70 80 90 100 50; do
        m1 set luminance "$b" >/dev/null
        v="$(measure "$b")"; patch_check; nan_check "$v"
    done
    stop_patch

    say "Analysis (Part A)"
    python3 "$PROBE_DIR/analyze_brightness.py" "$CSV" | tee -a "$RESULTS/$OUT"
    note "Raw data: $CSV."
    note "Paste the BRIGHTNESS_CURVE line into ~/.lighting/config.sh only if the table looks sane."
fi

# ── Part B ────────────────────────────────────────────────────────────────
if [ $DO_A = 1 ] && [ $ASK_B = 1 ]; then
    say "Part A done. The screen is back to normal."
    ask_yn "Run Part B (is the screen lighting the sensor?) now? It takes about a minute" || DO_B=0
fi
if [ $DO_B = 1 ]; then
    CSV="$CSV_B"
    say "Part B: does the screen light the sensor? (read carefully)"
    note "1. Move the sensor back to its everyday spot: top edge of the monitor bezel, facing you,"
    note "   flat with the screen (the same place lightd will read it)."
    note "2. Lights off, like a normal evening. Sit where you usually sit."
    note "3. When you press Enter, the monitor turns white for ~20 s, then black for ~20 s."
    note "   You can't see Terminal meanwhile. Stay as you normally would; don't touch anything."
    note "   To abort: click the white screen."
    pause "Sensor at the bezel, lights off? Press Enter to start"

    echo "screen,lux" > "$CSV"
    m1 set luminance "$MID_BRIGHTNESS" >/dev/null
    baseline_gains
    start_patch

    say "White screen (your normal colour balance), brightness $MID_BRIGHTNESS"
    v="$(measure white)"; patch_check; nan_check "$v"
    say "Black screen (gains 0), brightness $MID_BRIGHTNESS"
    gains 0 0 0
    v="$(measure black)"; patch_check; nan_check "$v"
    stop_patch

    say "Analysis (Part B)"
    python3 "$PROBE_DIR/analyze_brightness.py" --self "$CSV" | tee -a "$RESULTS/$OUT"
    note "Raw data: $CSV."
fi
