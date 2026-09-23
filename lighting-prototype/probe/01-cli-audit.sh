#!/bin/bash
# 01: capability audit of Lunar Pro's CLI, on your machine.
#   Q-A1  Can `lunar` read lux from the ESP32?
#   Q-A2  Can `lunar` write red/green/blue gain (VCP 0x16/0x18/0x1A)?
# Needs the Lunar app running. Costs 4 gain writes.
. "$(dirname "$0")/lib.sh"
OUT=01-cli-audit.txt; : > "$RESULTS/$OUT"
L="$LUNAR"
[ -x "$L" ] || { record $OUT "Lunar CLI not installed at $L"; exit 1; }
lunar_running || { record $OUT "Start the Lunar app first: the CLI forwards commands to it (127.0.0.1:23803)."; exit 1; }

say "A1. Lux"
cli="$("$L" lux 2>&1)"
direct="$(sse_avg sensor-ambient_light 6)"
record $OUT "lunar lux              → $cli"
record $OUT "ESP32 SSE (6 s mean)   → $direct"
record $OUT "lunar lux --average    → $("$L" lux --average 2>&1)"
note "lunar lux --listen streams one value per change (Ctrl-C to stop). Sampling 10 s:"
( "$L" lux --listen & p=$!; sleep 10; kill $p ) 2>/dev/null | head -5 | sed 's/^/     /' | tee -a "$RESULTS/$OUT"
if awk -v a="$cli" -v b="$direct" 'BEGIN { exit !(a > 0 && b > 0 && (a / b) > 0.5 && (a / b) < 2) }'; then
    record $OUT "RESULT A1: YES. \`lunar lux\` returns the ESP32's reading (within 2× of the direct SSE mean)."
else
    record $OUT "RESULT A1: CHECK. Values disagree or are -1; is Lunar in Sensor mode with the sensor detected?"
fi

say "A2. Colour gain"
"$L" displays 2>&1 | head -40 > "$RESULTS/01-lunar-displays.txt"
note "Display list saved to results/01-lunar-displays.txt"
for p in redGain greenGain blueGain; do record $OUT "cached $p = $("$L" displays external $p 2>&1)"; done
note "Reading 0x1A straight from the monitor (lunar ddc external 0x1A read):"
record $OUT "lunar ddc external 0x1A read → $("$L" ddc external 0x1A read 2>&1)"

pause "Open the AOC's OSD colour page so you can watch the Blue value, then press Enter"
before="$("$L" displays external blueGain 2>&1)"
"$L" displays external blueGain 30 >/dev/null 2>&1
if ask_yn "Did the screen turn visibly yellow and the OSD Blue value change to 30?"; then
    record $OUT "RESULT A2: YES. \`lunar displays external blueGain 30\` writes VCP 0x1A."
else
    record $OUT "RESULT A2: NO via displays property. Trying raw DDC…"
    "$L" ddc external 0x1A 30
    ask_yn "Did it change now?" && record $OUT "RESULT A2: raw \`lunar ddc external 0x1A 30\` works; property path doesn't." \
                                 || record $OUT "RESULT A2: NO. Check OSD is in User colour mode."
fi
"$L" displays external blueGain "${before:-50}" >/dev/null 2>&1
note "Restored blue to ${before:-50}."

say "A3. Is Lunar set to re-apply gains after wake? (this is what makes the Lunar backend robust)"
record $OUT "reapplyColorGain = $("$L" displays external reapplyColorGain 2>&1)"
note "To turn it on:  $L displays external reapplyColorGain true"
say "Done → $RESULTS/$OUT"
