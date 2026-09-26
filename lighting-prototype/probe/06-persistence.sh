#!/bin/bash
# 06: Q5 does the AOC reset gains after sleep / input change / power off?
#     EEPROM question: does a write reach non-volatile memory at once, or after a delay?
#
# Software cannot count EEPROM cycles. What it CAN do is bound the commit delay by
# cutting power at a known time after a write (pull the cord, not the power button).
#   - survives a cut 1 s after the write   → committed (almost) immediately: every write costs a cycle
#   - lost at 1 s but survives at 30 s     → buffered, committed on a timer: bursts coalesce
#   - lost even at 60 s                    → committed only on OSD exit/soft power-off
# Either way, writes spaced further apart than the delay each cost one cycle, so the
# rate limits in lib/ddc.sh stay necessary. This only tells you whether BURSTS are cheap.
#
#   probe/06-persistence.sh                   Part A only (default)
#   probe/06-persistence.sh --with-power-cut  Part A + Part B (pulls the cord 3×; read the risk note first)
. "$(dirname "$0")/lib.sh"
need_m1ddc; require_lunar_quiet; require_baseline
trap baseline_restore EXIT   # even if you Ctrl-C part-way
OUT=06-persistence.txt; : > "$RESULTS/$OUT"

reads_ok=0; m1 set blue 50 >/dev/null; sleep 0.5; [ "$(m1 get blue 2>/dev/null)" = 50 ] && reads_ok=1
check_blue() {  # check_blue <expected> <label>
    local got
    if [ $reads_ok = 1 ]; then got="$(m1 get blue 2>/dev/null)"
    else got="$(ask "Open the OSD: what's the Blue value now?")"; fi
    [ "$got" = "$1" ] && record $OUT "$2: KEPT (blue=$got)" || record $OUT "$2: RESET/LOST (blue=$got, expected $1)"
}

say "Part A: what resets the gains?"
m1 set blue 40 >/dev/null
note "Blue set to 40 (yellowish)."
pause "Put the Mac to sleep ( menu → Sleep), wait 30 s, wake it, then press Enter"
check_blue 40 "Mac sleep/wake"
m1 set blue 40 >/dev/null
pause "Switch the AOC to another input and back (OSD → Input), then press Enter"
check_blue 40 "input switch"
m1 set blue 40 >/dev/null
pause "Turn the AOC off with its power BUTTON, wait 10 s, turn it on, then press Enter"
check_blue 40 "soft power off/on"

if [ "$1" != --with-power-cut ]; then
    baseline_restore
    record $OUT "Part B (power-cut commit test): SKIPPED. Conservative rate limits assume every write costs an EEPROM cycle."
    exit 0
fi
say "Part B: commit delay (you'll pull the monitor's power cord 3 times)"
for pair in 1:42 30:44 60:46; do
    delay="${pair%%:*}"; v="${pair##*:}"        # a fresh value each round
    m1 set blue 38 >/dev/null; sleep 3          # known previous value
    m1 set blue $v >/dev/null
    note "Blue written = $v. PULL THE CORD at the beep, ${delay}s from now."
    sleep "$delay"; printf '\a'; note "BEEP: pull the cord now."
    pause "Wait 10 s, plug it back in, wait for the picture, then press Enter"
    check_blue $v "hard power cut ${delay}s after write"
done
baseline_restore

say "Interpretation"
grep 'hard power cut' "$RESULTS/$OUT" | sed 's/^/  /'
if grep -q 'hard power cut 1s after write: KEPT' "$RESULTS/$OUT"; then
    record $OUT "RESULT EEPROM: commits within ~1 s. Assume every write costs a cycle, bursts included (worst-case model applies)."
elif grep -q 'hard power cut 30s after write: KEPT' "$RESULTS/$OUT"; then
    record $OUT "RESULT EEPROM: buffered, commit delay between 1 and 30 s. Bursts shorter than that cost one cycle; spaced writes still cost one each."
elif grep -q 'hard power cut 60s after write: KEPT' "$RESULTS/$OUT"; then
    record $OUT "RESULT EEPROM: buffered, commit delay between 30 and 60 s."
else
    record $OUT "RESULT EEPROM: not committed within 60 s; likely commits only on soft power-off/OSD exit. DDC writes are cheap; the risk is losing values on a hard cut."
fi
