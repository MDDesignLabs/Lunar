#!/bin/bash
# 04: Q1. Does the AOC need every DDC write sent twice (m1ddc/MonitorControl default)?
# Alternates blue gain 50 ↔ 40 with single-send writes and checks each one landed.
# If reads work (probe 03), verification is automatic; otherwise you confirm by eye.
# Cost: ~24 blue-gain writes.
. "$(dirname "$0")/lib.sh"
need_m1ddc; require_lunar_quiet; require_baseline
trap baseline_restore EXIT   # even if you Ctrl-C part-way
OUT=04-single-write.txt; : > "$RESULTS/$OUT"

reads_ok=0
m1x set blue 50 >/dev/null; sleep 0.5
[ "$(m1 get blue 2>/dev/null)" = 50 ] && reads_ok=1

trial() {  # trial <binary-fn> <n> → prints successes
    local fn="$1" n="$2" i v ok=0
    for i in $(seq 1 "$n"); do
        if [ $((i % 2)) = 1 ]; then v=40; else v=50; fi
        $fn set blue $v >/dev/null 2>&1
        sleep 0.6
        if [ $reads_ok = 1 ]; then
            [ "$(m1 get blue 2>/dev/null)" = $v ] && ok=$((ok + 1))
        else
            ask_yn "Blue now $v (40 = yellow tint, 50 = neutral)? Did the screen change?" && ok=$((ok + 1))
        fi
    done
    echo $ok
}

if [ $reads_ok = 1 ]; then n=12; note "Reads work; verifying automatically, 12 trials each."
else n=6; note "Reads don't work; 6 visual trials each. Watch the screen."; fi

say "Single-send (m1ddc-1x)"
s1="$(trial m1x $n)"
say "Double-send (stock m1ddc)"
s2="$(trial m1 $n)"
baseline_restore

record $OUT "single-send: $s1/$n landed"
record $OUT "double-send: $s2/$n landed"
if [ "$s1" = "$n" ]; then
    record $OUT "RESULT Q1: NO, the AOC takes single writes. Use 1 write cycle (halves DDC traffic)."
elif [ "$s1" -lt "$s2" ]; then
    record $OUT "RESULT Q1: YES, single writes get dropped ($s1/$n vs $s2/$n). Keep double-send, or add a retry-on-verify."
else
    record $OUT "RESULT Q1: INCONCLUSIVE. Both unreliable; check cable/port and OSD mode, then rerun."
fi
