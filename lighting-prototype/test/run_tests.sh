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
$1
EOF
}
calls() { local c; c="$(grep -c "$1" "$MOCK_DIR/calls.log" 2>/dev/null)"; echo "${c:-0}"; }
eng() { awk -f lib/engine.awk "$@"; }

PIDS=""
# Only the main test shell cleans up. A background job killed just after it was forked
# is still a copy of this shell and would otherwise run this trap too (bash 3.2 has no
# $BASHPID, so compare the trap runner's PID via a child's parent PID).
MAIN_PID=$$
# One run at a time: the fake devices use fixed ports (18080–18092, 4001–4003).
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
    "awk -f lib/engine.awk -v cmd=targets -v lf=2 -v mode=adaptive -v kdim_lux=1 -v kdim=5250 -v kbright_lux=10 -v kbright=5250 -v kstep=1 -v table='$GAIN_TABLE' -v critical_gains=50:50:50 -v curve=0:50 -v bmin=0 -v bmax=100 -v nits_min=0 -v nits_max=1 -v bias_k=0 -v bias_min=0 -v bias_max=0 | grep -q 'green=47' "
check "colour-critical ignores lux: 5 lux → 6500K 50/50/50" \
    "t 0.7 critical | grep -q kelvin=6500 && t 0.7 critical | grep -q green=50"
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
check "bias follows Lunar's actual brightness when Lunar owns it" \
    "[ \$(t 2 adaptive 100 | sed -n 's/bias=//p') -gt \$(t 2 adaptive 10 | sed -n 's/bias=//p') ]"

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
python3 test/fake_govee.py "$GLOG" 2>/dev/null & PIDS="$PIDS $!"
sleep 0.5
bin/govee brightness 127.0.0.1 10
bin/govee kelvin 127.0.0.1 5000
sleep 0.3
check "brightness packet on :4003" "grep -q '{\"msg\":{\"cmd\":\"brightness\",\"data\":{\"value\":10}}}' '$GLOG'"
check "colorwc Kelvin packet on :4003" "grep -q 'colorTemInKelvin\":5000' '$GLOG'"
disc="$(GOVEE_MCAST=127.0.0.1 bin/govee discover 1)"
check "discovery: scan → reply on :4002 parsed (unicast)" "echo '$disc' | grep -q '\"sku\": \"H6046\"'"
disc_m="$(bin/govee discover 1)"
if echo "$disc_m" | grep -q H6046; then ok "discovery over real multicast 239.255.255.250"
else echo "  SKIP multicast discovery (no multicast route in this container; unicast path above is the same code)"; fi

echo "── 4. End to end: lightd + fake ESP32 (SSE) + fake Govee, m1ddc backend"
fresh "KELVIN_MIN_INTERVAL=0"
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

fresh "KELVIN_MIN_INTERVAL=3600 GOVEE_IPS="; . lib/common.sh; . lib/ddc.sh; . lib/govee.sh; . lib/apply.sh
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

check "the suite left the real probe/results folder (your hardware data) untouched" \
    "[ \"\$(real_results)\" = \"\$REAL_RESULTS_BEFORE\" ]"

echo
echo "$PASS passed, $FAIL failed"
[ $FAIL = 0 ]
