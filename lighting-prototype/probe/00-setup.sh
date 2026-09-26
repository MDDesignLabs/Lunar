#!/bin/bash
# 00: check tools, build m1ddc twice (stock double-write + single-write), find the AOC.
. "$(dirname "$0")/lib.sh"
OUT=00-setup.txt; : > "$RESULTS/$OUT"

say "Tools"
[ "$(uname)" = Darwin ] || { echo "Run this on the Mac."; exit 1; }
record $OUT "macOS $(sw_vers -productVersion) on $(uname -m)"
xcode-select -p >/dev/null 2>&1 || { note "Installing Command Line Tools (needed for m1ddc)…"; xcode-select --install; pause "Finish the installer"; }
for t in curl nc python3 git make clang; do
    command -v $t >/dev/null && record $OUT "ok   $t" || record $OUT "MISSING $t"
done

say "Building m1ddc"
src="$TOOLS/m1ddc-src"
[ -d "$src" ] || git clone -q --depth 1 https://github.com/waydabber/m1ddc "$src"
( cd "$src" && make -s clean >/dev/null 2>&1; make -s ) && cp "$src/m1ddc" "$M1"
# Single-write variant: same source with DDC_ITERATIONS 2 → 1.
rm -rf "$src-1x"; cp -R "$src" "$src-1x"
sed 's/# define DDC_ITERATIONS[[:space:]]*2/# define DDC_ITERATIONS 1/' "$src/headers/i2c.h" > "$src-1x/headers/i2c.h"
grep -q 'DDC_ITERATIONS 1' "$src-1x/headers/i2c.h" || { echo "Couldn't patch DDC_ITERATIONS; m1ddc changed upstream."; exit 1; }
( cd "$src-1x" && make -s clean >/dev/null 2>&1; make -s ) && cp "$src-1x/m1ddc" "$M1X"
record $OUT "m1ddc (2 writes): $M1  @ $(cd "$src" && git rev-parse --short HEAD)"
record $OUT "m1ddc-1x (1 write): $M1X"

say "Displays seen by m1ddc"
"$M1" display list | tee -a "$RESULTS/$OUT"
n="$("$M1" display list 2>/dev/null | grep -c '^\[')"
[ "$n" -gt 1 ] && note "More than one external display: export M1DDC_DISPLAY='display <n>' for the AOC before other probes."

say "Lunar"
if [ -x "$LUNAR" ]; then
    record $OUT "ok   Lunar CLI at $LUNAR"
    if lunar_running; then
        record $OUT "     Lunar app is running"
        l_auto="$("$LUNAR" lux 2>&1 | tail -n 1)"
        l_remote="$("$LUNAR" --remote lux 2>&1 | tail -n 1)"
        record $OUT "     lunar lux          → $l_auto"
        record $OUT "     lunar --remote lux → $l_remote"
        case "$l_remote" in
            *"Can't connect"*|*Unauthorized*|*rror*)
                record $OUT "     DIAGNOSIS: the CLI can't reach the running app, so plain \`lunar lux\` ran a separate copy of Lunar that isn't connected to the sensor." ;;
            -1*)
                record $OUT "     DIAGNOSIS: the CLI reaches Lunar, but Lunar has no external-sensor reading right now (see the sensor check below)." ;;
            *)
                record $OUT "     DIAGNOSIS: Lunar returns the sensor's lux over the CLI. OK." ;;
        esac
    else
        record $OUT "     Lunar app is NOT running (lux/displays need it)"
    fi
else
    record $OUT "MISSING Lunar CLI. Run: /Applications/Lunar.app/Contents/MacOS/Lunar install-cli"
fi

say "Sensor"
if curl -s -m 5 -o /dev/null "$SENSOR_URL" 2>/dev/null || [ $? = 28 ]; then
    record $OUT "ok   $SENSOR_URL reachable. Published ids:"
    sse_ids 6 | sed 's/^/     /' | tee -a "$RESULTS/$OUT"
else
    record $OUT "FAIL $SENSOR_URL not reachable (mDNS? Local Network permission for Terminal?)"
fi
say "Done → $RESULTS/$OUT"
