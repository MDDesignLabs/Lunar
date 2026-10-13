#!/bin/bash
# Runs the prototype against simulated hardware: a fake ESPHome SSE sensor, a fake
# Govee strip (real UDP on 4001/4002/4003) and mock m1ddc/lunar binaries.
# Proves the logic, packet formats and rate limits. It does NOT prove anything
# about the real AOC. That's what probe/ is for.

cd "$(dirname "$0")/.." || exit 1
ROOT="$(pwd)"
# Every temp file and directory lives under one root, removed on exit.
TMPDIR_ORIG="${TMPDIR:-/tmp}"; TEST_TMP="$(mktemp -d)"; export TMPDIR="$TEST_TMP"
real_results() { ls -la probe/results 2>/dev/null; cat probe/results/* 2>/dev/null; }
REAL_RESULTS_BEFORE="$(real_results)"
PASS=0; FAIL=0
ok()   { PASS=$((PASS + 1)); printf '  \033[32mPASS\033[0m %s\n' "$1"; }
bad()  { FAIL=$((FAIL + 1)); printf '  \033[31mFAIL\033[0m %s\n' "$1"; [ -n "$2" ] && printf '       %s\n' "$2"; }
check() { if eval "$2"; then ok "$1"; else bad "$1" "$3"; fi; }

fresh() {
    export LIGHT_HOME; LIGHT_HOME="$(mktemp -d)"
    export MOCK_DIR; MOCK_DIR="$(mktemp -d)"
    export LIGHT_CONFIG="$LIGHT_HOME/config.sh"
    cat > "$LIGHT_CONFIG" <<EOF
BACKEND=m1ddc
M1DDC=$ROOT/test/mocks/m1ddc
LUNAR=$ROOT/test/mocks/lunar
LUX_SOURCE=sse
SENSOR_URL=http://127.0.0.1:18080/events
STALE_SECS=5
KELVIN_MIN_INTERVAL=0
BRIGHTNESS_MIN_INTERVAL=0
GAIN_GAP_MS=0
GOVEE_IPS=127.0.0.1
BIAS_REFRESH=3600
OTHER_DDC_APPS=FakeDDCApp
GAIN_TABLE="6500:50:50:50,5500:50:47:44,5000:50:46:40,4500:50:44:36"
$1
EOF
}
# GAIN_TABLE above: the original example table, which §1–§9 were written against (50/46/40 at
# 5000K, 50/44/36 at 4500K). The measured default (probe 05) is checked in §10.
calls() { local c; c="$(grep -c "$1" "$MOCK_DIR/calls.log" 2>/dev/null)"; echo "${c:-0}"; }
eng() { awk -f lib/engine.awk "$@"; }

PIDS=""
# Only the main test shell cleans up. A background job killed just after it was forked
# is still a copy of this shell and would otherwise run this trap too (bash 3.2 has no
# $BASHPID, so compare the trap runner's PID via a child's parent PID).
MAIN_PID=$$
# One run at a time: the fake devices use fixed ports (18080–18099, 4001–4003).
# The Govee checks (§12) use 127.0.0.2 and 127.0.0.3 too where the loopback allows it.
SUITE_LOCK="${TMPDIR_ORIG:-/tmp}/lighting-tests.lock"
if ! mkdir "$SUITE_LOCK" 2>/dev/null; then
    other="$(cat "$SUITE_LOCK/pid" 2>/dev/null)"
    if [ -n "$other" ] && kill -0 "$other" 2>/dev/null; then echo "another test run is in progress (pid $other)"; exit 2; fi
    rm -rf "$SUITE_LOCK"; mkdir "$SUITE_LOCK"
fi
echo $$ > "$SUITE_LOCK/pid"
cleanup() {
    [ "$(exec sh -c 'echo $PPID')" = "$MAIN_PID" ] || return 0
    for p in $PIDS; do kill "$p" 2>/dev/null; done; rm -rf "$TEST_TMP" "$SUITE_LOCK"
}
trap cleanup EXIT

echo "── 1. Engine maths"
f1="$(eng -v cmd=filter -v lux=1000 -v prev=1 -v dt=2 -v tau_up=8 -v tau_down=45)"
f2="$(eng -v cmd=filter -v lux=1 -v prev=3 -v dt=2 -v tau_up=8 -v tau_down=45)"
check "filter brightens faster than it dims" \
    "awk -v u=$f1 -v d=$f2 'BEGIN { exit !((u - 1) > (3 - d) * 3) }'" "up=$f1 down=$f2"
fresh
. lib/common.sh
t() { engine_targets "$1" "${2:-adaptive}" "$3"; }
check "300 lux → 6500K neutral 50/50/50" \
    "t 2.4771 | grep -q 'kelvin=6500' && t 2.4771 | grep -q 'red=50' && t 2.4771 | grep -q 'blue=50'"
check "10 lux → 5000K → your row 50/46/40" \
    "t 1 | grep -q kelvin=5000 && t 1 | grep -q green=46 && t 1 | grep -q blue=40"
check "Kelvin is quantised to 250K steps" \
    "[ \$(( \$(t 1.7 | sed -n 's/kelvin=//p') % 250 )) = 0 ]"
check "between table rows the gains interpolate (5250K → 50/47/42)" \
    "awk -f lib/engine.awk -v cmd=targets -v lf=2 -v mode=adaptive -v kdim_lux=1 -v kdim=5250 -v kbright_lux=10 -v kbright=5250 -v kstep=1 -v table='$GAIN_TABLE' -v critical_gains=50:50:50 -v curve=0:50 -v bmin=0 -v bmax=100 | grep -q 'green=47' "
check "colour-critical ignores lux: 5 lux → 6500K 50/50/50" \
    "t 0.7 critical | grep -q kelvin=6500 && t 0.7 critical | grep -q green=50"
check "example defaults (RESEARCH_07): 0.5 lux → brightness 0, 300 lux → 22" \
    "[ \$(t -0.30103 | sed -n 's/brightness=//p') = 0 ] && [ \$(t 2.4771 | sed -n 's/brightness=//p') = 22 ]" \
    "0.5 lux → $(t -0.30103 | sed -n 's/brightness=//p'), 300 lux → $(t 2.4771 | sed -n 's/brightness=//p')"
# The next checks need compensation on, a floor of 5 and a curve that is above 0 in a dim room.
# Those are no longer the defaults, so say so here.
fresh 'LUMINANCE_COMPENSATION=1
BRIGHTNESS_MIN=5
BRIGHTNESS_CURVE="0:10,10:20,40:35,100:50,300:70,1000:100"'
. lib/common.sh
b_nocomp="$(LUMINANCE_COMPENSATION=0 engine_targets 1 adaptive | sed -n 's/brightness=//p')"
b_comp="$(engine_targets 1 adaptive | sed -n 's/brightness=//p')"
check "luminance compensation raises backlight when warm ($b_nocomp → $b_comp)" "[ $b_comp -gt $b_nocomp ]"
check "a malformed or out-of-order curve entry is ignored, not read as 0%" \
    "[ \$(BRIGHTNESS_CURVE='0:21,134,100:45,1000:100' LUMINANCE_COMPENSATION=0 engine_targets 2 adaptive | sed -n 's/brightness=//p') = 45 ]"
check "Kelvin never goes below KELVIN_FLOOR, whatever the config (KELVIN_DIM=3000 → 4000)" \
    "KELVIN_DIM=3000 engine_targets 0 adaptive | grep -q kelvin=4000"
check "no gain above neutral, even if the table has one (red 55 → 50)" \
    "GAIN_TABLE='6500:55:50:50,5000:55:46:40' engine_targets 2.4771 adaptive | grep -q red=50"
check "brightness is clamped to BRIGHTNESS_MIN/MAX (curve asks 1% → 5, 200% → 100)" \
    "[ \$(BRIGHTNESS_CURVE=0:1 LUMINANCE_COMPENSATION=0 engine_targets 2 adaptive | sed -n 's/brightness=//p') = 5 ] && [ \$(BRIGHTNESS_CURVE=0:200 engine_targets 2 adaptive | sed -n 's/brightness=//p') = 100 ]"
check "compensation uses the gains on the monitor when given (neutral on → no boost)" \
    "[ \$(engine_targets 1 adaptive '' 50:50:50 | sed -n 's/brightness=//p') = \$(LUMINANCE_COMPENSATION=0 engine_targets 1 adaptive | sed -n 's/brightness=//p') ]"
python3 test/synth_gain.py 2.2 0 0.03 > "$TEST_TMP/g22.csv"; a22="$(python3 probe/analyze_gain.py "$TEST_TMP/g22.csv")"
python3 test/synth_gain.py 1.0 1 0.03 > "$TEST_TMP/g10.csv"; a10="$(python3 probe/analyze_gain.py "$TEST_TMP/g10.csv")"
check "gain analysis with 3% sensor noise: exponent 2.2, no headroom → GAMMA-ENCODED, and no false headroom" \
    "echo \"\$a22\" | grep -q 'RESULT Q3: GAMMA' && ! echo \"\$a22\" | grep -q 'HEADROOM exists'"
check "gain analysis with 3% noise: exponent 1.0 with real headroom → LINEAR-LIGHT, headroom found" \
    "echo \"\$a10\" | grep -q 'RESULT Q3: LINEAR' && echo \"\$a10\" | grep -q 'HEADROOM exists'"
check "the bias level no longer follows screen brightness (Lunar's 100 vs 10: same %; FR-62)" \
    "[ \$(t 0 adaptive 100 | sed -n 's/^bias=//p') = \$(t 0 adaptive 10 | sed -n 's/^bias=//p') ]"

echo "── 2. DDC scheduler (mock m1ddc)"
fresh "BRIGHTNESS_MIN_INTERVAL=0"
. lib/common.sh; . lib/ddc.sh
ddc_brightness 40; ddc_brightness 40
check "no-op: same value is never re-sent" "[ \$(calls 'set luminance') = 1 ]"
ddc_brightness 41
check "dead-band: a 1-unit change is skipped (no interval in play)" "[ \$(calls 'set luminance') = 1 ]"
BRIGHTNESS_MIN_INTERVAL=3600
ddc_brightness 60
check "min interval: 2nd adaptive write inside 1h is deferred" "[ \$(calls 'set luminance') = 1 ]"
ddc_brightness 60 1
check "force (user action) bypasses interval" "[ \$(calls 'set luminance 60') = 1 ]"
fresh "BRIGHTNESS_DAILY_CAP=3"
. lib/common.sh; . lib/ddc.sh
for v in 10 20 30 40 50 60; do ddc_brightness $v; done
check "daily cap: only 3 of 6 writes reach the monitor" "[ \$(calls 'set luminance') = 3 ]"
check "cap is logged once" "[ \$(grep -c CAP \"$LIGHT_HOME/lightd.log\") = 1 ]"
check "write log records every attempt" "[ \$(wc -l < \"$LIGHT_HOME/writes.log\") = 3 ]"
fresh "GAIN_DAILY_CAP=2 OVERRIDE_RESERVE=1"
. lib/common.sh; . lib/ddc.sh
ddc_gains 50 50 48 1; ddc_gains 50 50 46 1; ddc_gains 50 50 44 1
check "gain cap: an adaptive set past the cap is refused (rc 3)" "[ \$(calls 'set blue') = 2 ]"
fresh "GAIN_DAILY_CAP=2 OVERRIDE_RESERVE=1"
. lib/common.sh; . lib/ddc.sh
MOCK_FAIL=1 ddc_gains 50 50 48 1; MOCK_FAIL=1 ddc_gains 50 50 47 1; ddc_gains 50 50 46 1; rc=$?
check "failed attempts count: after 2 failures the cap refuses the 3rd (rc 3)" "[ $rc = 3 ] && [ \$(cat \"$LIGHT_HOME/state/count_$(today)_blue\") = 2 ]"
ddc_gains 50 50 50 1 neutral; rc=$?
check "a write back to neutral may use the reserve past the cap" "[ $rc = 0 ] && [ \$(cat \$MOCK_DIR/m1ddc_blue) = 50 ]"
fresh "KELVIN_MIN_INTERVAL=3600"
. lib/common.sh; . lib/ddc.sh
state_set last_t_gainset "$(now)"
ddc_gains 50 47 44; rc=$?
check "an adaptive gain set inside the interval is deferred and marked pending" "[ $rc = 2 ] && [ \$(state_get gains_pending 0) = 1 ]"
state_set last_t_gainset 0; ddc_gains 50 47 44
check "…and once the interval has passed it is written and the flag cleared" "[ \$(state_get gains_pending 1) = 0 ] && [ \$(cat \$MOCK_DIR/m1ddc_blue) = 44 ]"
state_set mode critical; ddc_gains 50 46 40 1 adaptive; state_set mode adaptive
check "an adaptive set that finds the override on (after waiting for the lock) is skipped" "[ \$(cat \$MOCK_DIR/m1ddc_blue) = 44 ]"
sh -c 'exit 0' & DEADP=$!; wait $DEADP
mkdir "$STATE/.lock"; echo $DEADP > "$STATE/.lock/pid"
t0=$(date +%s); ddc_brightness 33 1; t1=$(date +%s)
check "a lock left by a dead process is broken at once, not after 30 s" "[ \$(cat \$MOCK_DIR/m1ddc_luminance) = 33 ] && [ $(( t1 - t0 )) -le 2 ]"
sleep 30 & LIVEP=$!; PIDS="$PIDS $LIVEP"
mkdir "$STATE/.lock"; echo $LIVEP > "$STATE/.lock/pid"
ddc_brightness 44 1 & BW=$!; sleep 1.2
held="$(cat $MOCK_DIR/m1ddc_luminance)"; rm -rf "$STATE/.lock"; wait $BW
check "a lock held by a live process blocks the write until it is released ($held while held)" \
    "[ $held = 33 ] && [ \$(cat \$MOCK_DIR/m1ddc_luminance) = 44 ]"
t0="$(now_ms)"; ddc_brightness 10 1; ddc_brightness 20 1; ddc_brightness 30 1; t1="$(now_ms)"
check "user writes to one control are spaced ≥ 250 ms (3 writes took $(( t1 - t0 )) ms)" \
    "[ $(( t1 - t0 )) -ge 500 ] && [ \$(cat \$MOCK_DIR/m1ddc_luminance) = 30 ]"
fresh; . lib/common.sh; . lib/ddc.sh
ddc_gains 50 46 40 1; ddc_gains 50 46 38 1
check "gain set only re-sends channels that changed" \
    "[ \$(calls 'set red') = 1 ] && [ \$(calls 'set blue') = 2 ]"
MOCK_FAIL=1 ddc_brightness 70 1
check "a failed write is logged as FAIL and not remembered" \
    "grep -q 'FAIL' \"$LIGHT_HOME/writes.log\" && [ \"\$(state_get last_brightness)\" != 70 ]"

echo "── 3. Govee UDP (real sockets, fake strip)"
GLOG="$(mktemp)"
python3 test/fake_govee.py "$GLOG" 2>/dev/null & GPID=$!; PIDS="$PIDS $GPID"
sleep 0.5
bin/govee brightness 127.0.0.1 10
bin/govee kelvin 127.0.0.1 5000
sleep 0.3
check "brightness packet on :4003" "grep -q '{\"msg\":{\"cmd\":\"brightness\",\"data\":{\"value\":10}}}' '$GLOG'"
check "colorwc Kelvin packet on :4003" "grep -q 'colorTemInKelvin\":5000' '$GLOG'"
disc="$(GOVEE_MCAST=127.0.0.1 bin/govee discover 1 2>/dev/null)"
check "discovery: scan → reply on :4002 parsed (unicast)" "echo '$disc' | grep -q '^127.0.0.1 *H6046 '"
disc_m="$(bin/govee discover 1 2>/dev/null)"
if echo "$disc_m" | grep -q H6046; then ok "discovery over real multicast 239.255.255.250"
else echo "  SKIP multicast discovery (no multicast route in this container; unicast path above is the same code)"; fi

echo "── 4. End to end: lightd + fake ESP32 (SSE) + fake Govee, m1ddc backend"
fresh "KELVIN_MIN_INTERVAL=0 BIAS_OFF_LUX=100000 BIAS_ON_LUX=99999"   # bias on all the way from 300 lux down
python3 test/fake_sensor.py 18080 0.2 300 300 300 200 100 50 20 10 5 5 5 5 5 5 5 5 5 5 5 5 & PIDS="$PIDS $!"
sleep 0.5
: > "$GLOG"
bin/lightd & DPID=$!; PIDS="$PIDS $DPID"
# Wait until lightd has caught up with the stream (≤ 20 s), not a fixed time.
for i in $(seq 1 100); do [ "$(cat $LIGHT_HOME/state/lux 2>/dev/null)" = 5.0 ] && break; sleep 0.2; done
sleep 1
kill -TERM $DPID; wait $DPID 2>/dev/null
n_red="$(calls 'set red')"; n_blue="$(calls 'set blue')"; n_lum="$(calls 'set luminance')"
check "parsed lux from the right SSE id (last lux ≈ 5)" "[ \"\$(cat $LIGHT_HOME/state/lux)\" = 5.0 ]" "lux=$(cat $LIGHT_HOME/state/lux 2>/dev/null)"
check "white point warmed as the room dimmed (blue went below 50)" "grep 'set blue' $MOCK_DIR/calls.log | grep -qv 'blue 50$'"
check "filter + dead-band kept writes low: $n_lum brightness, $n_blue blue writes for ~35 samples" "[ $n_lum -le 12 ] && [ $n_blue -le 8 ]"
check "exit wrote neutral gains (monitor not left warm)" "tail -n 3 $MOCK_DIR/calls.log | grep -q 'set blue 50'"
check "bias light received brightness + Kelvin" "grep -q '\"cmd\":\"brightness\"' '$GLOG' && grep -q colorTemInKelvin '$GLOG'"

echo "── 5. Override while running (m1ddc backend)"
fresh "KELVIN_MIN_INTERVAL=3600 BRIGHTNESS_MIN_INTERVAL=3600 CRITICAL_BRIGHTNESS=40"
. lib/common.sh
state_set filtered 0.7   # a dim room: 5 lux
state_set last_brightness 30; state_set last_t_brightness "$(now)"   # a brightness write just happened
bin/light kelvin 4500 >/dev/null
check "manual Kelvin writes your 4500K row 50/44/36" "grep -q 'set blue 36' $MOCK_DIR/calls.log"
bin/light critical on >/dev/null
check "critical ON → neutral gains immediately despite 1h gain interval" "tail -n 4 $MOCK_DIR/calls.log | grep -q 'set blue 50'"
check "critical ON → brightness frozen at 40, despite the 1 h brightness interval" "grep -q 'set luminance 40' $MOCK_DIR/calls.log"
check "status shows the mode" "bin/light status | grep -q 'mode:      critical'"
check "light kelvin is refused while colour-critical is on" "! bin/light kelvin 4500 2>/dev/null && [ \$(cat \$MOCK_DIR/m1ddc_blue) = 50 ]"
bin/light critical toggle >/dev/null
check "toggle → back to adaptive, warm again immediately" "tail -n 3 $MOCK_DIR/calls.log | grep -q 'set blue [0-4]'"

echo "── 6. Lunar backend (mock lunar CLI: lux --listen + display properties)"
fresh "BACKEND=lunar LUX_SOURCE=lunar KELVIN_MIN_INTERVAL=0 CRITICAL_BRIGHTNESS=40"
printf '%s\n' 300 300 100 30 10 5 5 5 5 5 > "$MOCK_DIR/lux_values"
echo 55 > "$MOCK_DIR/lunar_brightness"
MOCK_LUX_INTERVAL=0.3 bin/lightd & DPID=$!; PIDS="$PIDS $DPID"
sleep 5
check "lux read via 'lunar lux --listen'" "grep -q 'lunar lux --listen' $MOCK_DIR/calls.log"
check "gains written via Lunar properties (displays external blueGain)" "grep -q 'displays external blueGain' $MOCK_DIR/calls.log"
check "never writes brightness while Lunar owns it" "[ -s $MOCK_DIR/calls.log ] && ! grep -q 'displays external brightness [0-9]' $MOCK_DIR/calls.log"
bin/light critical on >/dev/null
check "critical ON with Lunar → adaptivePaused true BEFORE brightness 40 (not learned)" \
    "grep -n 'adaptivePaused true\|brightness 40' $MOCK_DIR/calls.log | head -1 | grep -q adaptivePaused"
check "Lunar's two-line property output is parsed (lunar_get returns 55)" \
    "echo 55 > $MOCK_DIR/lunar_brightness; . lib/common.sh; [ \"\$(LUNAR=$ROOT/test/mocks/lunar lunar_get external brightness)\" = 55 ]"
bin/light critical off >/dev/null
check "critical OFF → Lunar adaptation resumed" "grep -q 'adaptivePaused false' $MOCK_DIR/calls.log"
kill -TERM $DPID; wait $DPID 2>/dev/null

echo "── 7. Hardware probes against a simulated AOC + sensor (plumbing, not the real monitor)"
FAKEBIN="$(mktemp -d)"; printf '#!/bin/sh\nexit 0\n' > "$FAKEBIN/open"; chmod +x "$FAKEBIN/open"
probe_env() {
    export MOCK_DIR; MOCK_DIR="$(mktemp -d)"; export LIGHT_HOME; LIGHT_HOME="$(mktemp -d)"
    mkdir -p "$LIGHT_HOME/tools"
    cp test/mocks/m1ddc "$LIGHT_HOME/tools/m1ddc"; cp test/mocks/m1ddc "$LIGHT_HOME/tools/m1ddc-1x"
    printf '#!/bin/sh\nexec sleep 3600\n' > "$LIGHT_HOME/tools/whitepatch"; chmod +x "$LIGHT_HOME/tools/whitepatch"
    # Never the real probe/results: that holds your hardware measurements.
    export PROBE_RESULTS; PROBE_RESULTS="$(mktemp -d)"
    # A shifted baseline (as BetterDisplay might leave it) proves probes restore it, not 50.
    printf 'luminance 60 ddc\nred 50 ddc\ngreen 47 ddc\nblue 44 ddc\n' > "$PROBE_RESULTS/baseline.txt"
}
for model in "1.0 0 LINEAR-LIGHT 5403K" "2.2 1 GAMMA-ENCODED 4512K"; do
    set -- $model
    probe_env
    python3 test/fake_screen_sensor.py 18090 "$1" "$2" & SP=$!; PIDS="$PIDS $SP"; sleep 0.5
    res="$(yes "" | PATH="$FAKEBIN:$PATH" SENSOR_URL=http://127.0.0.1:18090/events SETTLE=0.2 WINDOW=0.6 bash probe/05-gain-domain.sh 2>&1)"
    kill $SP
    check "probe 05 identifies a simulated exponent-$1 monitor as $3" "echo \"\$res\" | grep -q 'RESULT Q3: $3'"
    check "probe 05 reports its 4500K row as ≈$4" "echo \"\$res\" | grep -q '4500K  50/44/36  → measured ≈  $4'"
    check "probe 05 restores the recorded baseline (50/47/44), not 50/50/50" "[ \$(cat \$MOCK_DIR/m1ddc_blue) = 44 ] && [ \$(cat \$MOCK_DIR/m1ddc_green) = 47 ]"
done
probe_env
FAKE_BLIND=1 python3 test/fake_screen_sensor.py 18091 1.0 0 & SP=$!; PIDS="$PIDS $SP"; sleep 0.5
res="$(yes "" | SENSOR_URL=http://127.0.0.1:18091/events SETTLE=0.2 WINDOW=0.6 bash probe/05-gain-domain.sh 2>&1)"
kill $SP
check "probe 05 stops at preflight when the sensor can't see the screen" "echo \"\$res\" | grep -q 'PREFLIGHT FAILED'"
check "…and it stops before the sweep (no per-channel rows written)" "[ -f \$PROBE_RESULTS/05-gain-measurements.csv ] && ! grep -q '^red,' \$PROBE_RESULTS/05-gain-measurements.csv"
check "…and still restores the baseline gains" "[ \$(cat \$MOCK_DIR/m1ddc_blue) = 44 ]"
check "…and puts brightness back to the baseline (60)" "[ \$(cat \$MOCK_DIR/m1ddc_luminance) = 60 ]"
probe_env
sleep 3600 & FAKE_LIGHTD=$!; PIDS="$PIDS $FAKE_LIGHTD"
mkdir -p "$LIGHT_HOME/state"; echo $FAKE_LIGHTD > "$LIGHT_HOME/state/lightd.pid"
res="$(yes "" | bash probe/04-single-write.sh 2>&1)"
check "a pid file pointing at a non-lightd process doesn't block the probes" "! echo \"\$res\" | grep -q 'lightd (the adaptive loop) is running'"
kill $FAKE_LIGHTD
probe_env
bash -c 'exec -a lightd sleep 30' & FAKE_LIGHTD=$!; PIDS="$PIDS $FAKE_LIGHTD"; sleep 0.3
mkdir -p "$LIGHT_HOME/state"; echo $FAKE_LIGHTD > "$LIGHT_HOME/state/lightd.pid"
res="$(yes "" | bash probe/04-single-write.sh 2>&1)"
check "a live lightd blocks the probes (and nothing is written)" \
    "echo \"\$res\" | grep -q 'lightd (the adaptive loop) is running' && ! grep -qs ' set ' \$MOCK_DIR/calls.log"
kill $FAKE_LIGHTD
probe_env
res="$(yes "" | bash probe/04-single-write.sh 2>&1)"
check "probe 04: monitor that accepts single writes → 'takes single writes'" "echo \"\$res\" | grep -q 'RESULT Q1: NO'"
check "probe 04 puts blue back to the baseline (44)" "[ \$(cat \$MOCK_DIR/m1ddc_blue) = 44 ]"
rm -f "$PROBE_RESULTS/baseline.txt"
res="$(yes "" | bash probe/04-single-write.sh 2>&1)"
check "probe 04 refuses to run before probe 03 has recorded a baseline" "echo \"\$res\" | grep -q 'Run probe/03-ddc-read.sh first'"
probe_env
res="$(yes "" | MOCK_DROP_SINGLE=1 bash probe/04-single-write.sh 2>&1)"
check "probe 04: monitor that drops single writes → 'keep double-send'" "echo \"\$res\" | grep -q 'RESULT Q1: YES'"
probe_env
printf '#!/bin/sh\nexec sleep 1\n' > "$LIGHT_HOME/tools/whitepatch"   # the user clicks the white screen after ~1 s
python3 test/fake_screen_sensor.py 18092 1.0 0 & SP=$!; PIDS="$PIDS $SP"; sleep 0.5
res="$(yes "" | SENSOR_URL=http://127.0.0.1:18092/events SETTLE=0.2 WINDOW=0.6 bash probe/05-gain-domain.sh 2>&1)"
kill $SP
check "probe 05 stops when the white screen is closed (no verdict from desktop readings)" \
    "echo \"\$res\" | grep -q 'ABORTED: the white screen' && ! echo \"\$res\" | grep -q 'RESULT Q3'"
check "…and restores the baseline" "[ \$(cat \$MOCK_DIR/m1ddc_blue) = 44 ]"

# Probe 08 (brightness response + self-illumination). The fake follows KitGuru's table, so Part A
# should find a match and rebuild the research curve. Ports 18093 (Part A) and 18094 (Part B).
probe_env
FAKE_BRIGHTNESS=1 python3 test/fake_screen_sensor.py 18093 1.0 0 & SP=$!; PIDS="$PIDS $SP"; sleep 0.5
res="$(yes "" | PATH="$FAKEBIN:$PATH" SENSOR_URL=http://127.0.0.1:18093/events SETTLE=0.2 WINDOW=0.6 bash probe/08-brightness.sh --part-a-only 2>&1)"
kill $SP
check "probe 08 Part A: a monitor that follows KitGuru's table → 'RESULT Q16a: MATCHES'" "echo \"\$res\" | grep -q 'RESULT Q16a: MATCHES'" "$(echo "$res" | tail -25)"
check "probe 08 prints the recommended curve (rebuilds the RESEARCH_07 one from the measurements)" \
    "echo \"\$res\" | grep -q 'BRIGHTNESS_CURVE=\"0:0,10:0,50:1,100:7,200:17,300:22,500:31,1000:76,2000:100\"'"
check "probe 08 reports the 50% drift check (none in a steady fake)" "echo \"\$res\" | grep -q 'Drift check: 50% read .*: OK'"
check "probe 08 restores the recorded baseline (gains 50/47/44, brightness 60)" \
    "[ \$(cat \$MOCK_DIR/m1ddc_red) = 50 ] && [ \$(cat \$MOCK_DIR/m1ddc_green) = 47 ] && [ \$(cat \$MOCK_DIR/m1ddc_blue) = 44 ] && [ \$(cat \$MOCK_DIR/m1ddc_luminance) = 60 ]"
check "probe 08 Part A makes 19 writes plus 4 to restore (the figure in its header)" "[ \$(calls ' set ') = 23 ]" "writes: $(calls ' set ')"
probe_env
FAKE_BRIGHTNESS=1 python3 test/fake_screen_sensor.py 18093 1.0 0 & SP=$!; PIDS="$PIDS $SP"; sleep 0.5
printf '\ny\n\n' | PATH="$FAKEBIN:$PATH" SENSOR_URL=http://127.0.0.1:18093/events SETTLE=0.1 WINDOW=0.3 bash probe/08-brightness.sh >/dev/null 2>&1
kill $SP
check "probe 08 with both parts: 30 writes in all (19 + 7 + 4 restore), baseline restored" \
    "[ \$(calls ' set ') = 30 ] && [ \$(cat \$MOCK_DIR/m1ddc_blue) = 44 ] && [ \$(cat \$MOCK_DIR/m1ddc_luminance) = 60 ]" "writes: $(calls ' set ')"
probe_env
printf '#!/bin/sh\nexec sleep 1\n' > "$LIGHT_HOME/tools/whitepatch"   # the user clicks the white screen after ~1 s
FAKE_BRIGHTNESS=1 python3 test/fake_screen_sensor.py 18093 1.0 0 & SP=$!; PIDS="$PIDS $SP"; sleep 0.5
res="$(yes "" | SENSOR_URL=http://127.0.0.1:18093/events SETTLE=0.2 WINDOW=0.6 bash probe/08-brightness.sh --part-a-only 2>&1)"
kill $SP
check "probe 08 stops when the white screen is closed (no verdict from desktop readings)" \
    "echo \"\$res\" | grep -q 'ABORTED: the white screen' && ! echo \"\$res\" | grep -q 'RESULT Q16a'"
check "…and restores the baseline gains and brightness" "[ \$(cat \$MOCK_DIR/m1ddc_blue) = 44 ] && [ \$(cat \$MOCK_DIR/m1ddc_luminance) = 60 ]"
probe_env
FAKE_BRIGHTNESS=1 FAKE_BEZEL=1 python3 test/fake_screen_sensor.py 18094 1.0 0 & SP=$!; PIDS="$PIDS $SP"; sleep 0.5
res="$(yes "" | PATH="$FAKEBIN:$PATH" SENSOR_URL=http://127.0.0.1:18094/events SETTLE=0.2 WINDOW=0.6 bash probe/08-brightness.sh --part-b-only 2>&1)"
kill $SP
check "probe 08 Part B: a sensor the screen doesn't light → 'negligible'" "echo \"\$res\" | grep -q 'RESULT Q16b: negligible'" "$(echo "$res" | tail -8)"
check "…and Part B restores the baseline (50/47/44, brightness 60)" \
    "[ \$(cat \$MOCK_DIR/m1ddc_green) = 47 ] && [ \$(cat \$MOCK_DIR/m1ddc_blue) = 44 ] && [ \$(cat \$MOCK_DIR/m1ddc_luminance) = 60 ]"
probe_env
FAKE_BRIGHTNESS=1 FAKE_BEZEL=1 FAKE_SELF=0.002 python3 test/fake_screen_sensor.py 18094 1.0 0 & SP=$!; PIDS="$PIDS $SP"; sleep 0.5
res="$(yes "" | PATH="$FAKEBIN:$PATH" SENSOR_URL=http://127.0.0.1:18094/events SETTLE=0.2 WINDOW=0.6 bash probe/08-brightness.sh --part-b-only 2>&1)"
kill $SP
check "probe 08 Part B: a small spill in a dark room (well over 20% of a ~0.6 lux floor) that can't move brightness → 'negligible'" \
    "echo \"\$res\" | grep -q 'RESULT Q16b: negligible'" "$(echo "$res" | tail -10)"
probe_env
FAKE_BRIGHTNESS=1 FAKE_BEZEL=1 FAKE_SELF=0.5 python3 test/fake_screen_sensor.py 18094 1.0 0 & SP=$!; PIDS="$PIDS $SP"; sleep 0.5
res="$(yes "" | PATH="$FAKEBIN:$PATH" SENSOR_URL=http://127.0.0.1:18094/events SETTLE=0.2 WINDOW=0.6 bash probe/08-brightness.sh --part-b-only 2>&1)"
kill $SP
check "probe 08 Part B: a screen that lights the sensor → 'significant' with the advice" \
    "echo \"\$res\" | grep -q 'RESULT Q16b: significant' && echo \"\$res\" | grep -q 'consider moving it or tell Claude'" "$(echo "$res" | tail -8)"

echo "── 8. No-Lunar setup: direct lux, DDC-app guard, nudges, display sleep"
fresh "LUX_SOURCE=direct KELVIN_MIN_INTERVAL=0 GOVEE_IPS= SENSOR_URL=http://127.0.0.1:18084/events"
python3 test/fake_sensor.py 18084 0.2 40 40 40 & SP=$!; PIDS="$PIDS $SP"; sleep 0.5
bin/lightd & DPID=$!; sleep 3; kill -TERM $DPID; wait $DPID 2>/dev/null; kill $SP
check "LUX_SOURCE=direct reads the ESP32 stream" "[ \"\$(cat $LIGHT_HOME/state/lux 2>/dev/null)\" = 40.0 ]"

fresh; . lib/common.sh; . lib/ddc.sh
FAKEAPP="$(mktemp -d)"; cp "$(command -v sleep)" "$FAKEAPP/FakeDDCApp"; "$FAKEAPP/FakeDDCApp" 30 & LP=$!; PIDS="$PIDS $LP"; sleep 0.3
ddc_brightness 55 1; rc=$?
check "while another DDC app runs, m1ddc writes are refused (rc 4, nothing sent)" "[ $rc = 4 ] && [ \$(calls 'set luminance') = 0 ]"
state_set mode adaptive
bin/light critical on >/dev/null 2>"$LIGHT_HOME/err"; rc=$?
check "…and 'light critical on' says the override is NOT neutral yet (exit 1), not 'ON'" \
    "[ $rc = 1 ] && grep -q 'NOT neutral' $LIGHT_HOME/err && bin/light status | grep -q INCOMPLETE"
state_set mode adaptive; state_set critical_rc 0
check "the refusal is logged once" "[ \$(grep -c BLOCKED $LIGHT_HOME/lightd.log) = 1 ]"
kill $LP; wait $LP 2>/dev/null; sleep 0.2
ddc_brightness 55 1
check "once that app quits, writes go through again" "[ \$(calls 'set luminance 55') = 1 ]"

fresh "GAIN_DAILY_CAP=2 OVERRIDE_RESERVE=3 KELVIN_MIN_INTERVAL=3600"; . lib/common.sh
state_set filtered 0.7
state_set "count_$(today)_blue" 2; state_set "count_$(today)_green" 2; state_set "count_$(today)_red" 2
state_set last_red 50; state_set last_green 46; state_set last_blue 40
bin/light critical on >/dev/null; rc=$?
check "override still reaches neutral after the adaptive cap is used up (reserve)" \
    "[ $rc = 0 ] && [ \$(cat \$MOCK_DIR/m1ddc_blue) = 50 ] && [ \$(cat \$MOCK_DIR/m1ddc_green) = 50 ]"
bin/light critical off >/dev/null
check "…but adaptive writes stay stopped at the cap" "[ \$(cat \$MOCK_DIR/m1ddc_blue) = 50 ]"

fresh "GOVEE_IPS="; . lib/common.sh
state_set filtered 2              # 100 lux
bin/light offset 0 >/dev/null
b0="$(cat $LIGHT_HOME/state/last_brightness)"
bin/light brighter >/dev/null
b1="$(cat $LIGHT_HOME/state/last_brightness)"
check "light brighter raises brightness by 5 ($b0 → $b1), written immediately" "[ $b1 = \$(( b0 + 5 )) ]"
bin/light dimmer 10 >/dev/null
check "light dimmer 10 → offset -5" "[ \$(cat $LIGHT_HOME/state/bright_offset) = -5 ]"
. lib/ddc.sh; . lib/govee.sh; . lib/apply.sh
apply_targets 1.2 1                # room dropped from 100 to ~16 lux (0.8 decades)
check "the nudge is dropped when the room light changes by more than ~3×" "[ \$(cat $LIGHT_HOME/state/bright_offset) = 0 ]"

fresh "KELVIN_MIN_INTERVAL=0 GOVEE_IPS= WAKE_DELAY=0 SENSOR_URL=http://127.0.0.1:18085/events"
HELPER="$LIGHT_HOME/tools/displaystate"; mkdir -p "$LIGHT_HOME/tools"
printf '#!/bin/sh\ncat "%s/display"\n' "$MOCK_DIR" > "$HELPER"; chmod +x "$HELPER"
echo awake > "$MOCK_DIR/display"
python3 test/fake_sensor.py 18085 0.2 300 300 300 300 300 5 5 5 5 5 5 5 5 5 5 5 5 5 5 5 5 5 5 5 5 5 5 5 5 5 5 & SP=$!; PIDS="$PIDS $SP"; sleep 0.5
bin/lightd & DPID=$!; PIDS="$PIDS $DPID"
sleep 1.5; echo asleep > "$MOCK_DIR/display"; sleep 0.5
n_sleep_start="$(wc -l < $MOCK_DIR/calls.log)"
sleep 3
n_sleep_end="$(wc -l < $MOCK_DIR/calls.log)"
echo awake > "$MOCK_DIR/display"; sleep 2
kill -TERM $DPID; wait $DPID 2>/dev/null; kill $SP
check "no DDC writes while the display sleeps, even as the room dims" "[ $n_sleep_start = $n_sleep_end ]"
check "display sleep and wake are logged" "grep -q 'display asleep' $LIGHT_HOME/lightd.log && grep -q 'display woke' $LIGHT_HOME/lightd.log"
check "after wake, values are re-sent (writes resume)" "[ \$(wc -l < $MOCK_DIR/calls.log) -gt $n_sleep_end ]"

echo "── 9. lightd robustness: bad samples, second copy, deferred gain sets"
fresh "GOVEE_IPS= SENSOR_URL=http://127.0.0.1:18086/events"
python3 test/fake_sensor.py 18086 0.2 300 300 300 -1 -1 -1 -1 -1 -1 -1 & SP=$!; PIDS="$PIDS $SP"; sleep 0.5
bin/lightd & DPID=$!; PIDS="$PIDS $DPID"; sleep 3
res2="$(bin/lightd 2>&1)"; rc=$?
kill -TERM $DPID; wait $DPID 2>/dev/null; kill $SP
check "a negative lux sample (Lunar's -1) is ignored, not treated as darkness" \
    "[ \"\$(cat $LIGHT_HOME/state/lux)\" = 300.0 ] && ! grep -q 'set blue 40' $MOCK_DIR/calls.log"
check "a second lightd refuses to start while one is running" "[ $rc = 1 ] && echo \"\$res2\" | grep -q 'already running'"

fresh "GOVEE_IPS= KELVIN_MIN_INTERVAL=4 TAU_DOWN=1 SENSOR_URL=http://127.0.0.1:18087/events"
python3 test/fake_sensor.py 18087 0.2 300 300 300 300 300 5 & SP=$!; PIDS="$PIDS $SP"; sleep 0.5
bin/lightd & DPID=$!; PIDS="$PIDS $DPID"; sleep 7
kill -TERM $DPID; wait $DPID 2>/dev/null; kill $SP
check "a gain set deferred by the interval is applied later, though lux has stopped moving" \
    "grep -q 'set blue 40' $MOCK_DIR/calls.log"

fresh "GOVEE_IPS= KELVIN_MIN_INTERVAL=3600 SENSOR_URL=http://127.0.0.1:18089/events"
. lib/common.sh
state_set last_red 50; state_set last_green 50; state_set last_blue 50; state_set last_t_gainset "$(now)"   # the previous run just wrote neutral on exit
python3 test/fake_sensor.py 18089 0.2 5 & SP=$!; PIDS="$PIDS $SP"; sleep 0.5
bin/lightd & DPID=$!; PIDS="$PIDS $DPID"; sleep 2.5
kill -TERM $DPID; wait $DPID 2>/dev/null; kill $SP
check "after a restart in a dim room, the warm white point is applied at once, not after the gain interval" \
    "grep -q 'set blue 40' $MOCK_DIR/calls.log"

fresh "GOVEE_IPS= BRIGHTNESS_MIN_INTERVAL=4 TAU_UP=1 BRIGHTNESS_CURVE=\"0:10,10:20,40:35,100:50,300:70,1000:100\" SENSOR_URL=http://127.0.0.1:18088/events"
python3 test/fake_sensor.py 18088 0.2 5 5 5 5 5 1000 & SP=$!; PIDS="$PIDS $SP"; sleep 0.5
bin/lightd & DPID=$!; PIDS="$PIDS $DPID"; sleep 7
kill -TERM $DPID; wait $DPID 2>/dev/null; kill $SP
check "a brightness write deferred by the interval is applied later, though lux has stopped moving" \
    "[ \$(cat $LIGHT_HOME/state/last_brightness) = 100 ]" "last brightness=$(cat $LIGHT_HOME/state/last_brightness 2>/dev/null)"

fresh "GOVEE_IPS= KELVIN_MIN_INTERVAL=3600 NEUTRAL_ON_EXIT=0 SENSOR_URL=http://127.0.0.1:18099/events"   # sensor offline; no neutral-on-exit, so only the start path can write
. lib/common.sh
state_set mode critical; state_set running 0; state_set last_red 50; state_set last_green 46; state_set last_blue 40
bin/lightd & DPID=$!; PIDS="$PIDS $DPID"; sleep 2
kill -TERM $DPID; wait $DPID 2>/dev/null
check "lightd restores the override at start, before any lux arrives (sensor offline)" \
    "grep -q 'set blue 50' $MOCK_DIR/calls.log && [ \$(cat $LIGHT_HOME/state/mode) = critical ]"

fresh "GOVEE_IPS= NEUTRAL_ON_EXIT=0 SENSOR_URL=http://127.0.0.1:18099/events"
. lib/common.sh
state_set running 1; state_set last_red 50; state_set last_green 46; state_set last_blue 40
bin/lightd & DPID=$!; PIDS="$PIDS $DPID"; sleep 2
kill -TERM $DPID; wait $DPID 2>/dev/null
check "after an unclean exit, lightd resets gains to neutral first" \
    "grep -q 'did not exit cleanly' $LIGHT_HOME/lightd.log && grep -q 'set blue 50' $MOCK_DIR/calls.log"

fresh "CRITICAL_GAINS=50:49:48 GOVEE_IPS="; . lib/common.sh
state_set filtered 1
bin/light critical on >/dev/null
check "the override writes the configured CRITICAL_GAINS (50:49:48), not an assumed 50/50/50" \
    "[ \$(cat \$MOCK_DIR/m1ddc_green) = 49 ] && [ \$(cat \$MOCK_DIR/m1ddc_blue) = 48 ]"

fresh 'KELVIN_MIN_INTERVAL=3600 GOVEE_IPS= LUMINANCE_COMPENSATION=1 BRIGHTNESS_CURVE="0:10,10:20,40:35,100:50,300:70,1000:100"'; . lib/common.sh; . lib/ddc.sh; . lib/govee.sh; . lib/apply.sh
state_set last_red 50; state_set last_green 50; state_set last_blue 50; state_set last_t_gainset "$(now)"
apply_targets 1                     # 10 lux wants 5000K, but the gain set is deferred
b_on="$(cat $MOCK_DIR/m1ddc_luminance)"; b_plain="$(LUMINANCE_COMPENSATION=0 engine_targets 1 adaptive | sed -n 's/brightness=//p')"
check "while a warm gain set is deferred, brightness isn't boosted for gains not yet on the monitor ($b_on vs $b_plain)" \
    "[ $b_on = $b_plain ]"

fresh "BACKEND=lunar OTHER_DDC_APPS='Lunar FakeDDCApp'"; . lib/common.sh; . lib/ddc.sh
FAKEAPP2="$(mktemp -d)"; cp "$(command -v sleep)" "$FAKEAPP2/Lunar"; "$FAKEAPP2/Lunar" 30 & LP=$!; PIDS="$PIDS $LP"; sleep 0.3
ddc_brightness 55 1; rc=$?
check "with BACKEND=lunar, Lunar running is expected (not a rival): the write goes through" "[ $rc = 0 ]"
cp "$(command -v sleep)" "$FAKEAPP2/FakeDDCApp"; "$FAKEAPP2/FakeDDCApp" 30 & LP2=$!; PIDS="$PIDS $LP2"; sleep 0.3
ddc_brightness 56 1; rc=$?
check "…but another DDC app alongside Lunar is refused (rc 4)" "[ $rc = 4 ]"
kill $LP $LP2 2>/dev/null; wait $LP $LP2 2>/dev/null   # later sections must not see a "DDC app" running

echo "── 10. Config migration, lightd's stale-config warning, bin/light update (temp dirs and repos only)"
SEED="0:21,13:31,23:34,39:39,71:41,80:44,100:45,135:47,160:49,190:54,224:58,313:69,565:91,702:99,800:100,1000:100"
SEED_BAD="0:21,134,100:45,135:47,160:49,190:54,224:58,313:69,565:91,702:99,800:100,1000:100"   # the corrupted paste
OLD_TABLE="6500:50:50:50,5500:50:47:44,5000:50:46:40,4500:50:44:36"
NEW_TABLE="6500:50:50:50,6000:50:48:47,5500:50:46:43,5000:50:43:35,4500:50:40:27,4000:50:37:21"
RESEARCH_CURVE="0:0,10:0,50:1,100:7,200:17,300:22,500:31,1000:76,2000:100"
export LIGHT_HOME; LIGHT_HOME="$(mktemp -d)"; export LIGHT_CONFIG="$LIGHT_HOME/config.sh"
cat > "$LIGHT_CONFIG" <<EOF
# Lighting prototype configuration.
# my own note: keep this comment
BACKEND=m1ddc
M1DDC_DISPLAY=""                  # e.g. "display 1"
LUNAR=$HOME/.local/bin/lunar
LUX_SOURCE=direct
STALE_SECS=60
BRIGHTNESS_CURVE="$SEED_BAD"
BRIGHTNESS_MIN=5
BRIGHTNESS_MAX=90
LUMINANCE_COMPENSATION=1
GAIN_TABLE="$OLD_TABLE"
GAIN_GAMMA=2.2
MONITOR_NITS_MAX=350
FOO=\$(echo hi)
EOF
mig1="$(bash lib/config_migrate.sh 2>&1)"
check "migration removes the seed curve (with the corrupt 134 entry), GAIN_GAMMA=2.2, the old GAIN_TABLE and old defaults" \
    "! grep -qE '^(BRIGHTNESS_CURVE|GAIN_GAMMA|GAIN_TABLE|BRIGHTNESS_MIN|LUMINANCE_COMPENSATION|MONITOR_NITS_MAX)=' $LIGHT_CONFIG" "$mig1"
check "…and values equal to the current defaults (BACKEND, LUX_SOURCE, STALE_SECS, LUNAR as \$HOME/…, empty M1DDC_DISPLAY)" \
    "! grep -qE '^(BACKEND|LUX_SOURCE|STALE_SECS|LUNAR|M1DDC_DISPLAY)=' $LIGHT_CONFIG"
check "…keeps a custom value (BRIGHTNESS_MAX=90), the comments, and adds the header once" \
    "grep -qx BRIGHTNESS_MAX=90 $LIGHT_CONFIG && grep -q 'my own note' $LIGHT_CONFIG && [ \$(grep -c 'Personal overrides only' $LIGHT_CONFIG) = 1 ]"
check "…leaves a line it can't parse (\$(…)) as it is, and reports it" \
    "grep -qx 'FOO=\$(echo hi)' $LIGHT_CONFIG && echo \"\$mig1\" | grep -q 'left .*FOO='"
check "…backs up first and logs a one-line summary to lightd.log" \
    "[ \$(ls $LIGHT_HOME | grep -c '^config.sh.bak-[0-9]\{8\}-[0-9]\{6\}\$') = 1 ] && grep -q 'BRIGHTNESS_CURVE=\"0:21,134' $LIGHT_HOME/config.sh.bak-* && grep -q 'config migrate: removed 11' $LIGHT_HOME/lightd.log" \
    "$(cat $LIGHT_HOME/lightd.log 2>/dev/null)"
sum1="$(cksum < $LIGHT_CONFIG)"
mig2="$(bash lib/config_migrate.sh 2>&1)"
check "migration is idempotent: second run changes nothing, makes no second backup" \
    "[ \"\$(cksum < $LIGHT_CONFIG)\" = \"\$sum1\" ] && [ \$(ls $LIGHT_HOME | grep -c '^config.sh.bak-') = 1 ] && echo \"\$mig2\" | grep -q 'nothing to change'"
eff="$( . lib/common.sh; echo "$BRIGHTNESS_CURVE|$GAIN_TABLE|$GAIN_GAMMA|$BRIGHTNESS_MIN|$LUMINANCE_COMPENSATION|$BRIGHTNESS_MAX" )"
check "after migration the effective config is the research curve and the measured GAIN_TABLE (1.23), with BRIGHTNESS_MAX=90" \
    "[ \"\$eff\" = \"$RESEARCH_CURVE|$NEW_TABLE|1.23|0|0|90\" ]" "effective: $eff"
printf 'BACKEND=lunar\nLUX_SOURCE=lunar\nSTALE_SECS=300\nM1DDC=~/.lighting/tools/m1ddc-1x   # probe 04\nBRIGHTNESS_CURVE="0:21,13:31,40:36,100:45,1000:100"\n' > "$LIGHT_CONFIG"
bash lib/config_migrate.sh >/dev/null 2>&1
check "migration keeps M1DDC=…m1ddc-1x, the Lunar choices (BACKEND/LUX_SOURCE=lunar, STALE_SECS=300) and a curve with a learned point" \
    "grep -q '^M1DDC=~/.lighting/tools/m1ddc-1x' $LIGHT_CONFIG && grep -qx BACKEND=lunar $LIGHT_CONFIG && grep -qx LUX_SOURCE=lunar $LIGHT_CONFIG && grep -qx STALE_SECS=300 $LIGHT_CONFIG && grep -q '^BRIGHTNESS_CURVE=' $LIGHT_CONFIG"
check "…and lightd's check finds nothing stale in it" "[ -z \"\$(. lib/config_migrate.sh; config_stale_keys)\" ]"
fresh "GOVEE_IPS= NEUTRAL_ON_EXIT=0 SENSOR_URL=http://127.0.0.1:18099/events
BRIGHTNESS_CURVE=\"$SEED\"
GAIN_GAMMA=2.2
BRIGHTNESS_MAX=90"
bin/lightd & DPID=$!; PIDS="$PIDS $DPID"; sleep 1.5
kill -TERM $DPID; wait $DPID 2>/dev/null
check "lightd warns once at start for each key with an old value (seed curve, GAIN_GAMMA=2.2), not for a custom one" \
    "[ \$(grep -c 'config.sh overrides BRIGHTNESS_CURVE with an old value; run bin/light update' $LIGHT_HOME/lightd.log) = 1 ] && [ \$(grep -c 'overrides GAIN_GAMMA with an old value' $LIGHT_HOME/lightd.log) = 1 ] && ! grep -q 'overrides BRIGHTNESS_MAX' $LIGHT_HOME/lightd.log" \
    "$(grep overrides $LIGHT_HOME/lightd.log)"

# bin/light update against a temp bare repo and clone. HOME is a temp dir too, so there is no
# git identity (the stash fallback is exercised), no launchd agent, and launchctl is a stub.
UPH="$(mktemp -d)"; UPBIN="$(mktemp -d)"
printf '#!/bin/sh\necho "launchctl $*" >> "%s/launchctl.log"\n' "$UPH" > "$UPBIN/launchctl"; chmod +x "$UPBIN/launchctl"
upenv() { env -u LIGHT_UPDATE_NO_RELOAD HOME="$UPH" LIGHT_HOME="$UPH/.lighting" LIGHT_CONFIG="$UPH/.lighting/config.sh" \
    PATH="$UPBIN:$PATH" GIT_CONFIG_NOSYSTEM=1 LIGHT_UPDATE_BACKOFF=0 "$@"; }
ugit() { upenv git -c user.name=t -c user.email=t@t "$@"; }
SRC="$UPH/src"; BARE="$UPH/remote.git"; CLONE="$UPH/lunar-lighting"
mkdir -p "$SRC"; cp -R "$ROOT" "$SRC/lighting-prototype"; rm -rf "$SRC/lighting-prototype/probe/results" "$SRC/lighting-prototype/probe/__pycache__"
ugit init -q "$SRC"; ugit -C "$SRC" symbolic-ref HEAD refs/heads/main
ugit -C "$SRC" add -A; ugit -C "$SRC" commit -qm "one"
ugit clone -q --bare "$SRC" "$BARE"; ugit -C "$SRC" remote add origin "$BARE"; ugit -C "$SRC" fetch -q origin
ugit -C "$SRC" branch -q -u origin/main
ugit clone -q "$BARE" "$CLONE"
# The next commit changes bin/light itself: the update must run the new version after the pull.
awk 'NR == 2 { print "[ \"$2\" = --after-pull ] && echo \"new bin/light ran\"" } { print }' "$SRC/lighting-prototype/bin/light" > "$UPH/light.new"
cat "$UPH/light.new" > "$SRC/lighting-prototype/bin/light"
ugit -C "$SRC" commit -qam "two: a newer bin/light"; ugit -C "$SRC" push -q origin main
mkdir -p "$UPH/.lighting"; printf 'GAIN_GAMMA=2.2\nBRIGHTNESS_MAX=90\n' > "$UPH/.lighting/config.sh"
echo "my local edit" >> "$CLONE/lighting-prototype/README.md"
mkdir -p "$CLONE/lighting-prototype/probe/results"; echo "measurement" > "$CLONE/lighting-prototype/probe/results/05-gain.txt"
up1="$(upenv bash "$CLONE/lighting-prototype/bin/light" update 2>&1)"; rc=$?
check "light update: a fast-forward pull works, lists the new commits, and runs the new bin/light" \
    "[ $rc = 0 ] && [ \"\$(git -C $CLONE rev-parse HEAD)\" = \"\$(git -C $SRC rev-parse HEAD)\" ] && echo \"\$up1\" | grep -q 'two: a newer bin/light' && echo \"\$up1\" | grep -q 'new bin/light ran'" "$up1"
check "…a dirty tracked file is stashed (stash kept, edit recoverable), untracked probe/results untouched" \
    "git -C $CLONE stash list | grep -q 'light update [0-9-]* [0-9:]*' && git -C $CLONE stash show -p | grep -q 'my local edit' && ! grep -q 'my local edit' $CLONE/lighting-prototype/README.md && [ \"\$(cat $CLONE/lighting-prototype/probe/results/05-gain.txt)\" = measurement ] && echo \"\$up1\" | grep -q 'git -C .* stash show -p'"
check "…the config is migrated (GAIN_GAMMA=2.2 removed, BRIGHTNESS_MAX=90 kept, backup made)" \
    "! grep -q GAIN_GAMMA $UPH/.lighting/config.sh && grep -qx BRIGHTNESS_MAX=90 $UPH/.lighting/config.sh && ls $UPH/.lighting | grep -q '^config.sh.bak-' && echo \"\$up1\" | grep -q 'removed  GAIN_GAMMA=2.2'"
check "…and with no launchd agent installed, launchctl is never called" \
    "[ ! -e $UPH/launchctl.log ] && echo \"\$up1\" | grep -q 'no launchd agent installed'"
mkdir -p "$UPH/Library/LaunchAgents"; : > "$UPH/Library/LaunchAgents/com.lighting.lightd.plist"
echo three >> "$SRC/lighting-prototype/README.md"; ugit -C "$SRC" commit -qam "three"; ugit -C "$SRC" push -q origin main
up2="$(upenv bash "$CLONE/lighting-prototype/bin/light" update 2>&1)"; rc=$?
check "with the agent installed, update reloads it through install.sh (launchctl bootstrap)" \
    "[ $rc = 0 ] && grep -q 'launchctl bootstrap' $UPH/launchctl.log && echo \"\$up2\" | grep -q 'reloaded=yes'" "$up2"
echo "local work" > "$CLONE/lighting-prototype/local.txt"; ugit -C "$CLONE" add lighting-prototype/local.txt; ugit -C "$CLONE" commit -qm "local commit"
echo four >> "$SRC/lighting-prototype/README.md"; ugit -C "$SRC" commit -qam "four"; ugit -C "$SRC" push -q origin main
head_before="$(git -C $CLONE rev-parse HEAD)"; stashes_before="$(git -C $CLONE stash list | wc -l)"; cfg_before="$(cksum < $UPH/.lighting/config.sh)"
echo "dirty again" >> "$CLONE/lighting-prototype/README.md"
up3="$(upenv bash "$CLONE/lighting-prototype/bin/light" update 2>&1)"; rc=$?
check "a non-fast-forward stops with a clear message and changes nothing (HEAD, stash, edit, config)" \
    "[ $rc != 0 ] && echo \"\$up3\" | grep -q 'diverged' && [ \"\$(git -C $CLONE rev-parse HEAD)\" = $head_before ] && [ \$(git -C $CLONE stash list | wc -l) = $stashes_before ] && grep -q 'dirty again' $CLONE/lighting-prototype/README.md && [ \"\$(cksum < $UPH/.lighting/config.sh)\" = \"$cfg_before\" ]" "$up3"
ugit -C "$CLONE" remote set-url origin "$UPH/missing.git"
up4="$(upenv bash "$CLONE/lighting-prototype/bin/light" update 2>&1)"; rc=$?
check "a fetch that keeps failing is tried 3 times, then stops with nothing changed" \
    "[ $rc != 0 ] && [ \$(echo \"\$up4\" | grep -c 'retrying') = 2 ] && echo \"\$up4\" | grep -q 'failed 3 times' && [ \"\$(git -C $CLONE rev-parse HEAD)\" = $head_before ]" "$up4"

check "the suite left the real probe/results folder (your hardware data) untouched" \
    "[ \"\$(real_results)\" = \"\$REAL_RESULTS_BEFORE\" ]"

echo "── 11. Daily report: lightd's 5-minute samples and \`light report\`"
fresh "GOVEE_IPS= SAMPLE_LOG_SECS=1 SENSOR_URL=http://127.0.0.1:18096/events"
python3 test/fake_sensor.py 18096 0.2 300 300 300 100 30 10 5 5 5 5 5 5 5 5 5 & SP=$!; PIDS="$PIDS $SP"; sleep 0.5
bin/lightd & DPID=$!; PIDS="$PIDS $DPID"; sleep 4
bin/light brighter >/dev/null
sleep 1; kill -TERM $DPID; wait $DPID 2>/dev/null; kill $SP
SF="$LIGHT_HOME/samples-$(date +%Y-%m-%d).csv"
check "lightd records lux and targets for the report (samples-<date>.csv, several rows)" \
    "[ -f \"$SF\" ] && [ \$(( \$(wc -l < \"$SF\") - 1 )) -ge 2 ] && head -1 \"$SF\" | grep -q '^time,lux,display,mode,target_brightness'" "$(head -3 "$SF" 2>/dev/null)"
rep="$(bin/light report 2>&1)"
check "light report prints the config, an hourly row, the write counts and the events" \
    "echo \"\$rep\" | grep -q '== Lighting report for' && echo \"\$rep\" | grep -q '^  [0-2][0-9]:00 ' && echo \"\$rep\" | grep -q 'brightness [1-9][0-9]*, red' && echo \"\$rep\" | grep -q 'lightd start'" "$(echo "$rep" | head -20)"
check "…and counts your nudges (light brighter is logged as a user action)" "echo \"\$rep\" | grep -q '(1 nudges or manual changes by you)'"
check "light report rejects a malformed date" "! bin/light report 12-10-2026 >/dev/null 2>&1"

echo "── 12. Bias light (Govee H6056): transport, level, states, rate limits (FR-60–FR-66)"
kill $GPID 2>/dev/null; wait $GPID 2>/dev/null; sleep 0.3          # §3's single fake light
# Two lights on 127.0.0.2/.3 where the loopback allows it (Linux); one on 127.0.0.1 otherwise.
if python3 -c 'import socket; socket.socket(socket.AF_INET, socket.SOCK_DGRAM).bind(("127.0.0.2", 0))' 2>/dev/null; then
    GA=127.0.0.2; GB=127.0.0.3; NDEV=2
else
    GA=127.0.0.1; GB=""; NDEV=1; echo "  (127.0.0.2 can't be bound here: the checks use one fake light, and the two-light ones are skipped)"
fi
IPS="$GA${GB:+ $GB}"
GLOG2="$TEST_TMP/govee2.log"; GST="$TEST_TMP/govee2.state"; : > "$GLOG2"
python3 test/fake_govee.py "$GLOG2" H6056 --dev "$GA" ${GB:+--dev "$GB:noip:nomcast"} --state "$GST" 2>/dev/null & GPID2=$!; PIDS="$PIDS $GPID2"
sleep 0.5
gcount() { local c; c="$(grep -c -- "$1" "$GLOG2" 2>/dev/null)"; echo "${c:-0}"; }
gseq() { awk -v ip="$1" '$1 == ip { c = $3; sub(/.*"cmd":"/, "", c); sub(/".*/, "", c); v = $3; sub(/.*"(value|colorTemInKelvin)":/, "", v); sub(/[^0-9].*/, "", v); printf "%s%s=%s", (n++ ? " " : ""), c, v }' "$GLOG2"; }
# Every datagram to one light ≥ 300 ms after the previous one (290: timer jitter at the receiver).
gaps_ok() { awk '{ if (($1 in t) && $2 - t[$1] < 290) { bad = 1; print "gap " $2 - t[$1] " ms to " $1 > "/dev/stderr" } t[$1] = $2 } END { exit bad }' "$GLOG2"; }
fstate() { python3 -c 'import json, sys; d = json.load(open(sys.argv[1]))[sys.argv[2]]; print(d["onOff"], d["brightness"], d["colorTemInKelvin"])' "$GST" "$1"; }

if [ $NDEV = 2 ]; then
    fresh "GOVEE_IPS=\"$GB\""      # only the light that ignores multicast is configured
    disc="$(GOVEE_MCAST=$GA bin/govee discover 1 2>"$TEST_TMP/disc.err")"
    check "discovery joins the multicast group 239.255.255.250 before it scans" "grep -q 'joined multicast group 239.255.255.250' $TEST_TMP/disc.err" "$(cat $TEST_TMP/disc.err)"
    check "discovery: the scan finds one light, and a unicast scan to GOVEE_IPS finds one that ignores multicast" \
        "echo \"\$disc\" | grep -q '^$GA ' && echo \"\$disc\" | grep -q '^$GB '" "$disc"
    check "a scan reply without ip is listed by the sender's address (ip, sku, device id printed)" \
        "echo \"\$disc\" | grep '^$GB ' | grep -q 'H6056 *AA:BB:CC:DD:EE:00:00:03 *no ip in reply: sender address used'" "$disc"
    disc_m="$(bin/govee discover 1 2>/dev/null)"
    if echo "$disc_m" | grep -q "^$GA "; then ok "discovery over real multicast reaches the fake light (and not the one that ignores it)"
    else echo "  SKIP real multicast to the two fake lights (no multicast route here)"; fi
fi

fresh "GOVEE_IPS=\"$IPS\" BIAS_REFRESH=3600"; . lib/common.sh; . lib/govee.sh
: > "$GLOG2"; govee_apply 0 5000 1
check "off is turn 0, sent twice to every light, and nothing else (FR-64, FR-65)" \
    "[ \$(gcount '\"cmd\":\"turn\",\"data\":{\"value\":0}') = $(( 2 * NDEV )) ] && [ \$(wc -l < $GLOG2) = $(( 2 * NDEV )) ] && [ \$(state_get govee_on) = 0 ]" "$(cat $GLOG2)"
govee_apply 4 5000 1
check "coming back on: turn 1 twice, then brightness, then Kelvin, in that order" \
    "[ \"\$(gseq $GA)\" = 'turn=0 turn=0 turn=1 turn=1 brightness=4 colorwc=5000' ]" "$(gseq $GA)"
check "…every light gets the same sequence" "[ -z '$GB' ] || [ \"\$(gseq $GB)\" = \"\$(gseq $GA)\" ]"
govee_apply 150 5000 1; govee_apply 0.3 5000 1
check "brightness is clamped to 1–100: 150 → 100, 0.3 → 1 (never 0)" \
    "gseq $GA | grep -q 'brightness=100 colorwc=5000 brightness=1 colorwc=5000\$'" "$(gseq $GA)"
govee_apply 5 1500 1; govee_apply 5 9000 1
check "Kelvin is clamped to GOVEE_K_MIN/MAX: 1500 → 2200, 9000 → 6500 (FR-63)" \
    "gseq $GA | grep -q 'colorwc=2200 brightness=5 colorwc=6500\$'" "$(gseq $GA)"
: > "$GLOG2"; govee_apply 6 6500; govee_apply 7 6500; govee_apply 8 6500
check "a change within 2 s of the last update is held back, not sent (marked pending)" \
    "[ \$(wc -l < $GLOG2) = 0 ] && [ \$(state_get govee_pending) = 1 ]"
sleep 2.1; govee_tick
check "…and the next tick sends only the latest target (coalesced: 8, not 6 or 7), without turn 1" \
    "[ \"\$(gseq $GA)\" = 'brightness=8' ] && [ \$(state_get govee_pending) = 0 ]" "$(gseq $GA)"
sleep 2.1; : > "$GLOG2"; govee_apply 8 6450
check "no send for a change under 100 K at the same %" "[ \$(wc -l < $GLOG2) = 0 ]"
govee_apply 8 6300
check "…a change of ≥ 100 K sends only colorwc" "[ \"\$(gseq $GA)\" = 'colorwc=6300' ]" "$(gseq $GA)"
sleep 2.1; : > "$GLOG2"
for i in 10 11 12 13 14 15 16 17 18 19 20; do govee_apply $i 6300; sleep 0.3; done; govee_tick
nb="$(grep "^$GA " "$GLOG2" | grep -c brightness)"
check "a target changing every 0.3 s for 3.3 s gives ≤ 2 updates, ≥ 2 s apart (FR-65)" \
    "[ $nb -le 2 ] && awk '/brightness/ && \$1 == \"$GA\" { if (p && \$2 - p < 1950) exit 1; p = \$2 }' $GLOG2" "$(cat $GLOG2)"
check "datagrams to one light are always ≥ 300 ms apart, across calls too" "gaps_ok"
sleep 2.1; govee_tick; sleep 2.1            # flush the coalesced target first
[ -n "$GB" ] && bin/govee off "$GB"; sleep 0.3; : > "$GLOG2"
BIAS_REFRESH=1; state_set govee_t 0; govee_tick; BIAS_REFRESH=3600
check "the refresh resends brightness and Kelvin, never turn 1 (FR-66)" \
    "[ \"\$(gseq $GA)\" = 'brightness=$(state_get govee_pct) colorwc=6300' ] && [ \$(gcount '\"turn\"') = 0 ]" "$(cat $GLOG2)"
check "…so a light switched off in the Govee app stays off" "[ -z '$GB' ] || [ \"\$(fstate $GB | cut -d' ' -f1)\" = 0 ]"
sleep 2.1; : > "$GLOG2"; govee_apply 0 6300; govee_apply 0 6300; sleep 2.1; govee_tick; govee_tick
check "while off, nothing is refreshed or resent (one off transition only)" "[ \$(wc -l < $GLOG2) = $(( 2 * NDEV )) ]"

eng_b() { eng -v cmd=biaspct -v bias_nits="${1:-5}" -v bias_rho="${2:-0.8}" -v bias_cal="$3" -v bias_fallback=5 -v bias_max="${4:-15}"; }
check "absolute level: 5 cd/m2 on a ρ 0.80 wall = 19.6 lx → 3 % through BIAS_CAL 1:6,2:12,5:30,10:60 (FR-62)" \
    "eng_b 5 0.8 '1:6,2:12,5:30,10:60' | tr '\n' ' ' | grep -q 'bias=3 target_lux=19.6 exact_pct=3.27 calibrated=1'" "$(eng_b 5 0.8 '1:6,2:12,5:30,10:60' | tr '\n' ' ')"
check "…ρ 0.60 needs more light (26.2 lx → 4 %); a darker target less (2 cd/m2 → 1 %)" \
    "eng_b 5 0.6 '1:6,2:12,5:30,10:60' | grep -q bias=4 && eng_b 2 0.8 '1:6,2:12,5:30,10:60' | grep -q bias=1"
check "…a noisy (non-monotonic), unsorted table with a malformed entry still inverts (2.4 %)" \
    "eng_b 5 0.8 '3:25,1:6,junk,2:5,4:31' | grep -q 'exact_pct=2.44'"
check "…the result is capped at BIAS_MAX (50 cd/m2 → 15 %) and is never below 1 % when on" \
    "eng_b 50 0.8 '1:6,10:60,100:600' | grep -q bias=15 && eng_b 0.1 0.8 '1:6,10:60' | grep -q bias=1"
check "an empty BIAS_CAL uses BIAS_FALLBACK_PCT (5 %) and says it isn't calibrated" \
    "eng_b 5 0.8 '' | tr '\n' ' ' | grep -q 'bias=5 .*calibrated=0'"

fresh "GOVEE_IPS=\"$IPS\" BIAS_CAL=\"1:6,2:12,5:30,10:60\" BIAS_REFRESH=3600"; . lib/common.sh; . lib/ddc.sh; . lib/govee.sh; . lib/apply.sh
bt() { engine_targets "$1" "${2:-adaptive}" "$3" | sed -n "s/^${4:-bias}=//p"; }
check "the bias doesn't depend on screen brightness (Lunar at 100 vs 10, or another curve: 3 % each)" \
    "[ \$(bt 0 adaptive 100) = 3 ] && [ \$(bt 0 adaptive 10) = 3 ] && [ \$(BRIGHTNESS_CURVE=0:100 bt 0) = 3 ]"
check "adaptive: the bars' Kelvin is the screen's target (10 lux → 5000 K), clamped to 2200 (KELVIN_DIM 1800, no floor)" \
    "[ \$(bt 1 adaptive '' bias_k) = 5000 ] && [ \$(KELVIN_FLOOR= KELVIN_DIM=1800 bt 0 adaptive '' bias_k) = 2200 ]"
: > "$GLOG2"; rm -f "$STATE/bias_room"
for lux in 50 70 50 30 50; do
    apply_targets "$(awk -v l=$lux 'BEGIN { printf "%.4f", log(l) / log(10) }')" 1
    printf '%s:%s ' "$lux" "$(state_get govee_on)"
done > "$TEST_TMP/hyst"
check "room hysteresis: 50 lx on, 70 off (> BIAS_OFF_LUX 60), 50 stays off, 30 on (< BIAS_ON_LUX 40), 50 stays on" \
    "[ \"\$(cat $TEST_TMP/hyst)\" = '50:1 70:0 50:0 30:1 50:1 ' ]" "$(cat $TEST_TMP/hyst)"
check "…and each switch is logged" "grep -q 'bias: room above 60 lx: off' $LIGHT_HOME/lightd.log && grep -q 'bias: room below 40 lx' $LIGHT_HOME/lightd.log"
state_set mode critical; : > "$GLOG2"
apply_targets 2.4771 1                     # 300 lux, colour-critical
check "colour-critical: 6500 K at the calibrated level, even in a bright room (FR-61)" \
    "[ \"\$(gseq $GA)\" = 'brightness=3 colorwc=6500' ] && [ \$(state_get govee_on) = 1 ]" "$(gseq $GA)"
BIAS_IN_CRITICAL=off; apply_targets 2.4771 1; BIAS_IN_CRITICAL=on
check "…with BIAS_IN_CRITICAL=off the bars go off instead" "[ \$(state_get govee_on) = 0 ] && gseq $GA | grep -q 'turn=0 turn=0\$'"
state_set mode adaptive
fresh "GOVEE_IPS=\"$IPS\" BIAS_REFRESH=3600"; . lib/common.sh; . lib/ddc.sh; . lib/govee.sh; . lib/apply.sh
apply_targets 0 1; apply_targets 0.3 1; apply_targets 0 1
check "an empty BIAS_CAL runs at the fallback 5 % and logs 'not calibrated' once" \
    "gseq $GA | grep -q 'brightness=5' && [ \$(grep -c 'bias: not calibrated yet' $LIGHT_HOME/lightd.log) = 1 ]"

# lightd end to end: start, display sleep, wake, clean exit.
fresh "GOVEE_IPS=\"$IPS\" KELVIN_MIN_INTERVAL=0 WAKE_DELAY=0 BIAS_CAL=\"1:6,2:12,5:30,10:60\" SENSOR_URL=http://127.0.0.1:18098/events"
. lib/common.sh; state_set govee_on 1; state_set govee_pct 3; state_set govee_k 5000   # as a crash would leave it
HELPER="$LIGHT_HOME/tools/displaystate"; mkdir -p "$LIGHT_HOME/tools"
printf '#!/bin/sh\ncat "%s/display"\n' "$MOCK_DIR" > "$HELPER"; chmod +x "$HELPER"; echo awake > "$MOCK_DIR/display"
python3 test/fake_sensor.py 18098 0.3 5 & SP=$!; PIDS="$PIDS $SP"; sleep 0.5
: > "$GLOG2"
bin/lightd & DPID=$!; PIDS="$PIDS $DPID"
for i in $(seq 1 40); do grep -q colorwc "$GLOG2" && break; sleep 0.2; done
check "lightd start sends the full on sequence, though the state said on (a crash is corrected)" \
    "gseq $GA | grep -q '^turn=1 turn=1 brightness=3 colorwc=5000'" "$(gseq $GA)"
sleep 2.2; echo asleep > "$MOCK_DIR/display"; t_sleep="$(now_ms)"
for i in $(seq 1 40); do [ "$(gcount '"value":0')" -ge $(( 2 * NDEV )) ] && break; sleep 0.2; done
t_off="$(awk -v ip=$GA '$1 == ip && /"value":0/ { print $2; exit }' "$GLOG2")"
check "display asleep → the bars get turn 0 (twice) within 5 s (US-7 AC3)" \
    "[ \$(gcount '\"turn\",\"data\":{\"value\":0}') = $(( 2 * NDEV )) ] && [ \$(( ${t_off:-0} - t_sleep )) -lt 5000 ]" "$(gseq $GA)"
sleep 2; n_asleep="$(wc -l < "$GLOG2")"; sleep 1.5
check "…and nothing more is sent while the display sleeps" "[ \$(wc -l < $GLOG2) = $n_asleep ]"
echo awake > "$MOCK_DIR/display"
for i in $(seq 1 40); do [ "$(gcount 'colorTemInKelvin')" -ge $(( 2 * NDEV )) ] && break; sleep 0.2; done
check "display wakes → the bars come back on (turn 1 before brightness)" \
    "gseq $GA | grep -q 'turn=0 turn=0 turn=1 turn=1 brightness=3'" "$(gseq $GA)"
sleep 2.2; kill -TERM $DPID; wait $DPID 2>/dev/null; kill $SP
check "clean exit → turn 0, twice, as the last datagrams to each light (FR-64)" \
    "[ \"\$(gseq $GA | awk '{ print \$(NF - 1), \$NF }')\" = 'turn=0 turn=0' ] && grep -q 'exit: bias light off' $LIGHT_HOME/lightd.log" "$(gseq $GA)"
check "every lightd datagram to one light was ≥ 300 ms after the previous one" "gaps_ok"

# GOVEE_IPS="" = everything disabled: no packets, no state, no log lines, in lightd and in `light`.
fresh "GOVEE_IPS= KELVIN_MIN_INTERVAL=0 WAKE_DELAY=0 SENSOR_URL=http://127.0.0.1:18098/events"
HELPER="$LIGHT_HOME/tools/displaystate"; mkdir -p "$LIGHT_HOME/tools"
printf '#!/bin/sh\ncat "%s/display"\n' "$MOCK_DIR" > "$HELPER"; chmod +x "$HELPER"; echo awake > "$MOCK_DIR/display"
python3 test/fake_sensor.py 18098 0.3 5 5 5 300 300 300 & SP=$!; PIDS="$PIDS $SP"; sleep 0.5
: > "$GLOG2"
bin/lightd & DPID=$!; PIDS="$PIDS $DPID"; sleep 2; echo asleep > "$MOCK_DIR/display"; sleep 1.5; echo awake > "$MOCK_DIR/display"; sleep 1.5
bin/light critical on >/dev/null; bin/light critical off >/dev/null; bin/light bias 5 >/dev/null
kill -TERM $DPID; wait $DPID 2>/dev/null; kill $SP
check "GOVEE_IPS=\"\": lightd and light send nothing, store no bias state and log nothing about it" \
    "[ ! -s $GLOG2 ] && ! ls $LIGHT_HOME/state | grep -q '^govee_\|^bias_' && ! grep -qi 'govee\|bias' $LIGHT_HOME/lightd.log" \
    "$(cat $GLOG2; ls $LIGHT_HOME/state; grep -i 'govee\|bias' $LIGHT_HOME/lightd.log)"
check "brightness sent was 1–100 in every Govee check above (0 never sent as a level)" \
    "! grep -h '\"cmd\":\"brightness\"' $GLOG $GLOG2 | sed 's/.*\"value\"://; s/}.*//' | awk '\$1 < 1 || \$1 > 100 { bad = 1 } END { exit !bad }'"

# config_migrate: the retired bias keys go, the measured ones stay (also when they equal a default).
export LIGHT_HOME; LIGHT_HOME="$(mktemp -d)"; export LIGHT_CONFIG="$LIGHT_HOME/config.sh"
printf 'BIAS_K=0.05\nMONITOR_NITS_MIN=55\nMONITOR_NITS_MAX=400\nBIAS_MIN=2\nBIAS_MAX=40\nBIAS_OFF_LUX=80\nGOVEE_IPS=""\nBIAS_WALL_RHO="0.80"   # probe 07 check R, 2026-10-13\nBIAS_CAL="1:6,2:12"   # probe 07 check F, 2026-10-13\n' > "$LIGHT_CONFIG"
stale="$(. lib/config_migrate.sh; config_stale_keys | LC_ALL=C sort | tr '\n' ' ')"
bash lib/config_migrate.sh >/dev/null 2>&1
check "config migration removes the retired bias keys (BIAS_K, MONITOR_NITS_*, BIAS_MIN, any value) and BIAS_MAX=40" \
    "! grep -qE '^(BIAS_K|MONITOR_NITS_MIN|MONITOR_NITS_MAX|BIAS_MIN|BIAS_MAX)=' $LIGHT_CONFIG && [ \"\$stale\" = 'BIAS_K BIAS_MAX BIAS_MIN MONITOR_NITS_MAX MONITOR_NITS_MIN ' ]" "stale: $stale; $(cat $LIGHT_CONFIG)"
check "…and keeps a custom BIAS_OFF_LUX and the measured GOVEE_IPS, BIAS_WALL_RHO (even = default) and BIAS_CAL" \
    "grep -qx BIAS_OFF_LUX=80 $LIGHT_CONFIG && grep -qx 'GOVEE_IPS=\"\"' $LIGHT_CONFIG && grep -q '^BIAS_WALL_RHO=\"0.80\"   # probe 07' $LIGHT_CONFIG && grep -q '^BIAS_CAL=\"1:6,2:12\"' $LIGHT_CONFIG"

# Probe 07 against the fake lights and a fake TSL2591 on the wall (lit by them).
kill $GPID2 2>/dev/null; wait $GPID2 2>/dev/null; sleep 0.3
probe_env
PLOG="$TEST_TMP/govee-probe.log"; PST="$TEST_TMP/govee-probe.state"; : > "$PLOG"
python3 test/fake_govee.py "$PLOG" H6056 --dev "$GA" ${GB:+--dev "$GB:noip"} --state "$PST" 2>/dev/null & GPID3=$!; PIDS="$PIDS $GPID3"
python3 test/fake_wall_sensor.py 18097 "$PST" & SP=$!; PIDS="$PIDS $SP"; sleep 0.6
export LIGHT_CONFIG="$LIGHT_HOME/config.sh"
printf '# my overrides\nBRIGHTNESS_MAX=90\nGOVEE_IPS="%s"   # typed by hand\nFOO="a b"   # keep me\n' "$GA" > "$LIGHT_CONFIG"
cp "$LIGHT_CONFIG" "$TEST_TMP/cfg.before"
st0="$(fstate $GA)"
bash -c 'exec -a lightd sleep 30' & FAKE_LIGHTD=$!; PIDS="$PIDS $FAKE_LIGHTD"; sleep 0.3
mkdir -p "$LIGHT_HOME/state"; echo $FAKE_LIGHTD > "$LIGHT_HOME/state/lightd.pid"
res="$(yes "" | head -5 | bash probe/07-govee.sh 2>&1)"
check "probe 07 refuses to run while lightd runs, and sends nothing" \
    "echo \"\$res\" | grep -q 'lightd (the adaptive loop) is running' && [ ! -s $PLOG ]" "$res"
kill $FAKE_LIGHTD; rm -f "$LIGHT_HOME/state/lightd.pid"
P07ENV="GOVEE_MCAST=${GB:-127.0.0.9} SENSOR_URL=http://127.0.0.1:18097/events SETTLE=0.05 WINDOW=0.3 STATUS_WAIT=0.1 HOLD=0.05 FLICKER_HOLD=0.05"
res="$(yes y | env $P07ENV F_STEPS="1 2 3 4 5 6 8 10 20 50 100" bash probe/07-govee.sh 2>&1)"
R07="$PROBE_RESULTS/07-govee.txt"
check "probe 07 writes RESULT Q7, Q17 (the device count), Q18 (white path, and what the TSL2591 can't tell) and Q19" \
    "grep -q '^RESULT Q7: LAN API: $NDEV light(s) replied' $R07 && grep -q '^RESULT Q17: $NDEV light(s) replied (sku H6056)' $R07 && grep -q \"^RESULT Q18: .*white path: .*can't tell chromaticity\" $R07 && grep -q '^RESULT Q19: ρ = 0.85 measured' $R07" \
    "$(grep RESULT $R07; echo "$res" | tail -5)"
check "probe 07 covers checks A–I and the ρ check" \
    "for c in A B C D E F R G H I; do grep -q \"^\$c: \" $R07 || exit 1; done"
check "probe 07 check F prints a BIAS_CAL line from the wall readings, and the % it gives (3 % ≈ 18 lx)" \
    "grep -q '^F: BIAS_CAL=\"1:6.0,2:12.0,3:18.0,4:24.0,' $R07 && grep -q '18.5 lx → 3 %' $R07" "$(grep '^F:' $R07)"
check "probe 07 saved GOVEE_IPS (replaced in place), BIAS_CAL and BIAS_WALL_RHO, each with a dated comment" \
    "sed -n 3p $LIGHT_CONFIG | grep -q '^GOVEE_IPS=\"$IPS\"   # found by probe 07 check A, $(date +%Y-%m-%d)\$' && grep -q '^BIAS_CAL=\"1:6.0,.*\"   # probe 07 check F, .*$(date +%Y-%m-%d)\$' $LIGHT_CONFIG && grep -q '^BIAS_WALL_RHO=\"0.85\"   # probe 07 check R' $LIGHT_CONFIG" \
    "$(cat $LIGHT_CONFIG)"
check "…touched no other line, and backed up the config first" \
    "[ \"\$(grep -vE '^(GOVEE_IPS|BIAS_CAL|BIAS_WALL_RHO)=' $LIGHT_CONFIG)\" = \"\$(grep -v '^GOVEE_IPS=' $TEST_TMP/cfg.before)\" ] && cmp -s \$(ls $LIGHT_HOME/config.sh.bak-* | head -1) $TEST_TMP/cfg.before"
bash lib/config_migrate.sh >/dev/null 2>&1
check "…and config_migrate keeps the three saved keys afterwards" \
    "grep -q '^GOVEE_IPS=\"$IPS\"' $LIGHT_CONFIG && grep -q '^BIAS_CAL=' $LIGHT_CONFIG && grep -q '^BIAS_WALL_RHO=\"0.85\"' $LIGHT_CONFIG"
check "probe 07 puts each light back as it found it ($st0)" "[ \"\$(fstate $GA)\" = '$st0' ]" "$(fstate $GA)"
check "probe 07 never sent colorwc to the bars outside the probe's own Kelvin list" \
    "! grep -o 'colorTemInKelvin\":[0-9]*' $PLOG | sed 's/.*://' | grep -qvxE '2200|2700|4000|5000|6000|6500|7000|9000|3000'"
kill $GPID3 $SP 2>/dev/null

echo
echo "$PASS passed, $FAIL failed"
[ $FAIL = 0 ]
