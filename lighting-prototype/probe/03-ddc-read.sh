#!/bin/bash
# 03: Q2 do DDC reads return sane values? Q4 (part) what are the gain ranges?
# Read-only (reads are also DDC transactions, but they don't write settings).
. "$(dirname "$0")/lib.sh"
need_m1ddc; require_lunar_quiet
OUT=03-ddc-read.txt; : > "$RESULTS/$OUT"

pause "Open the AOC OSD and note Brightness, and R/G/B in the User colour mode. Press Enter"
osd_l="$(ask 'OSD Brightness value?')"
osd_r="$(ask 'OSD Red?')"; osd_g="$(ask 'OSD Green?')"; osd_b="$(ask 'OSD Blue?')"

say "Reading each control 10× (get) and its max"
sane=1
for c in luminance red green blue; do
    vals=""; fails=0
    for i in 1 2 3 4 5 6 7 8 9 10; do
        v="$(m1 get $c 2>/dev/null)"
        case "$v" in ''|*[!0-9]*) fails=$((fails + 1)) ;; *) vals="$vals $v" ;; esac
    done
    mx="$(m1 max $c 2>/dev/null)"
    uniq="$(echo $vals | tr ' ' '\n' | sort -u | tr '\n' ' ')"
    case $c in luminance) o=$osd_l ;; red) o=$osd_r ;; green) o=$osd_g ;; blue) o=$osd_b ;; esac
    record $OUT "$c: values=[${uniq% }] failures=$fails/10 max=$mx OSD=$o"
    first="${uniq%% *}"
    if [ $fails -gt 2 ] || [ "$(echo "$uniq" | wc -w)" -gt 1 ] || [ "$first" != "$o" ]; then sane=0; fi
done

if [ $sane = 1 ]; then
    record $OUT "RESULT Q2: YES. Reads are consistent and match the OSD. The app can verify writes."
else
    record $OUT "RESULT Q2: NO/PARTIAL. Treat reads as unreliable; never read-modify-write (see values above)."
    record $OUT "  (If reads are consistent but only differ from the OSD by a fixed scale, reads are usable. Judge from the values.)"
fi
record $OUT "RESULT Q4a: gain max reported by the monitor: red=$(m1 max red) green=$(m1 max green) blue=$(m1 max blue) (50 = neutral?)"
