#!/bin/bash
# 03: Q2 do DDC reads return sane values? Q4 (part) what are the gain ranges?
# Read-only (reads are also DDC transactions, but they don't write settings).
. "$(dirname "$0")/lib.sh"
need_m1ddc; require_lunar_quiet
OUT=03-ddc-read.txt
if [ -f "$BASELINE" ] && [ "$1" != --rebaseline ]; then
    echo "A baseline already exists ($BASELINE):"; cat "$BASELINE"
    echo "Rerunning after an interrupted probe would record the shifted values as 'original'."
    echo "If the monitor really is back at its original settings, rerun with: $0 --rebaseline"
    exit 1
fi
: > "$RESULTS/$OUT"

pause "Open the AOC OSD and note Brightness, and R/G/B in the User colour mode. Press Enter"
ask_num() {  # ask until the answer is a whole number 0–100
    local a
    while true; do
        a="$(ask "$1")"
        case "$a" in ''|*[!0-9]*) note "Type a number from 0 to 100." >&2 ;; *) [ "$a" -le 100 ] && { echo "$a"; return; } ;; esac
    done
}
osd_l="$(ask_num 'OSD Brightness value?')"
osd_r="$(ask_num 'OSD Red?')"; osd_g="$(ask_num 'OSD Green?')"; osd_b="$(ask_num 'OSD Blue?')"

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

# Record the baseline every later probe restores to.
: > "$BASELINE"
for c in luminance red green blue; do
    case $c in luminance) o=$osd_l ;; red) o=$osd_r ;; green) o=$osd_g ;; blue) o=$osd_b ;; esac
    r="$(m1 get $c 2>/dev/null)"
    if [ $sane = 1 ] && [ -n "$r" ]; then echo "$c $r ddc" >> "$BASELINE"; else echo "$c $o osd" >> "$BASELINE"; fi
done
record $OUT "BASELINE (restored after every later probe): $(awk '{ printf "%s=%s(%s) ", $1, $2, $3 }' "$BASELINE")"
if [ "$(baseline_get red)/$(baseline_get green)/$(baseline_get blue)" != 50/50/50 ]; then
    record $OUT "NOTE: gains are NOT 50/50/50 right now; something (BetterDisplay?) left them shifted. Tell Claude before probe 05."
fi

if [ $sane = 1 ]; then
    record $OUT "RESULT Q2: YES. Reads are consistent and match the OSD. The app can verify writes."
else
    record $OUT "RESULT Q2: NO/PARTIAL. Treat reads as unreliable; never read-modify-write (see values above)."
    record $OUT "  (If reads are consistent but only differ from the OSD by a fixed scale, reads are usable. Judge from the values.)"
fi
record $OUT "RESULT Q4a: gain max reported by the monitor: red=$(m1 max red) green=$(m1 max green) blue=$(m1 max blue) (50 = neutral?)"
