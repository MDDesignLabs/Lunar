#!/bin/bash
# Runs the prototype against simulated hardware: a fake ESPHome SSE sensor, a fake
# Govee strip (real UDP on 4001/4002/4003) and mock m1ddc/lunar binaries.
# Proves the logic, packet formats and rate limits. It does NOT prove anything
# about the real AOC. That's what probe/ is for.

cd "$(dirname "$0")/.." || exit 1
ROOT="$(pwd)"
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
$1
EOF
}
calls() { local c; c="$(grep -c "$1" "$MOCK_DIR/calls.log" 2>/dev/null)"; echo "${c:-0}"; }
eng() { awk -f lib/engine.awk "$@"; }

PIDS=""
cleanup() { for p in $PIDS; do kill "$p" 2>/dev/null; done; }
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
check "bias follows Lunar's actual brightness when Lunar owns it" \
    "[ \$(t 2 adaptive 100 | sed -n 's/bias=//p') -gt \$(t 2 adaptive 10 | sed -n 's/bias=//p') ]"

echo "── 2. DDC scheduler (mock m1ddc)"
fresh "BRIGHTNESS_MIN_INTERVAL=3600"
. lib/common.sh; . lib/ddc.sh
ddc_brightness 40; ddc_brightness 40
check "no-op: same value is never re-sent" "[ \$(calls 'set luminance') = 1 ]"
ddc_brightness 41
check "dead-band: a 1-unit change is skipped" "[ \$(calls 'set luminance') = 1 ]"
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
sleep 7
kill -TERM $DPID; wait $DPID 2>/dev/null
n_red="$(calls 'set red')"; n_blue="$(calls 'set blue')"; n_lum="$(calls 'set luminance')"
check "parsed lux from the right SSE id (last lux ≈ 5)" "[ \"\$(cat $LIGHT_HOME/state/lux)\" = 5.0 ]" "lux=$(cat $LIGHT_HOME/state/lux 2>/dev/null)"
check "white point warmed as the room dimmed (blue went below 50)" "grep 'set blue' $MOCK_DIR/calls.log | grep -qv 'blue 50$'"
check "filter + dead-band kept writes low: $n_lum brightness, $n_blue blue writes for ~100 samples" "[ $n_lum -le 12 ] && [ $n_blue -le 8 ]"
check "exit wrote neutral gains (monitor not left warm)" "tail -n 3 $MOCK_DIR/calls.log | grep -q 'set blue 50'"
check "bias light received brightness + Kelvin" "grep -q '\"cmd\":\"brightness\"' '$GLOG' && grep -q colorTemInKelvin '$GLOG'"

echo "── 5. Override while running (m1ddc backend)"
fresh "KELVIN_MIN_INTERVAL=3600 CRITICAL_BRIGHTNESS=40"
. lib/common.sh
state_set filtered 0.7   # a dim room: 5 lux
bin/light kelvin 4500 >/dev/null
check "manual Kelvin writes your 4500K row 50/44/36" "grep -q 'set blue 36' $MOCK_DIR/calls.log"
bin/light critical on >/dev/null
check "critical ON → neutral gains immediately despite 1h gain interval" "tail -n 4 $MOCK_DIR/calls.log | grep -q 'set blue 50'"
check "critical ON → brightness frozen at 40" "grep -q 'set luminance 40' $MOCK_DIR/calls.log"
check "status shows the mode" "bin/light status | grep -q 'mode:      critical'"
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
check "never writes brightness while Lunar owns it" "! grep -q 'displays external brightness [0-9]' $MOCK_DIR/calls.log"
bin/light critical on >/dev/null
check "critical ON with Lunar → 'lunar mode manual' + brightness 40" \
    "grep -q 'lunar mode manual' $MOCK_DIR/calls.log && grep -q 'displays external brightness 40' $MOCK_DIR/calls.log"
bin/light critical off >/dev/null
check "critical OFF → Lunar back to sensor mode" "grep -q 'lunar mode sensor' $MOCK_DIR/calls.log"
kill -TERM $DPID; wait $DPID 2>/dev/null

echo "── 7. Hardware probes against a simulated AOC + sensor (plumbing, not the real monitor)"
FAKEBIN="$(mktemp -d)"; printf '#!/bin/sh\nexit 0\n' > "$FAKEBIN/open"; chmod +x "$FAKEBIN/open"
probe_env() {
    export MOCK_DIR; MOCK_DIR="$(mktemp -d)"; export LIGHT_HOME; LIGHT_HOME="$(mktemp -d)"
    mkdir -p "$LIGHT_HOME/tools"
    cp test/mocks/m1ddc "$LIGHT_HOME/tools/m1ddc"; cp test/mocks/m1ddc "$LIGHT_HOME/tools/m1ddc-1x"
    rm -rf probe/results
}
for model in "1.0 0 LINEAR-LIGHT 5403K" "2.2 1 GAMMA-ENCODED 4512K"; do
    set -- $model
    probe_env
    python3 test/fake_screen_sensor.py 18090 "$1" "$2" & SP=$!; PIDS="$PIDS $SP"; sleep 0.5
    res="$(yes "" | PATH="$FAKEBIN:$PATH" SENSOR_URL=http://127.0.0.1:18090/events SETTLE=0.2 WINDOW=0.6 bash probe/05-gain-domain.sh 2>&1)"
    kill $SP
    check "probe 05 identifies a simulated exponent-$1 monitor as $3" "echo \"\$res\" | grep -q 'RESULT Q3: $3'"
    check "probe 05 reports its 4500K row as ≈$4" "echo \"\$res\" | grep -q '4500K  50/44/36  → measured ≈  $4'"
    check "probe 05 restores 50/50/50 afterwards" "[ \$(cat \$MOCK_DIR/m1ddc_blue) = 50 ] && [ \$(cat \$MOCK_DIR/m1ddc_green) = 50 ]"
done
probe_env
res="$(yes "" | bash probe/04-single-write.sh 2>&1)"
check "probe 04: monitor that accepts single writes → 'takes single writes'" "echo \"\$res\" | grep -q 'RESULT Q1: NO'"
probe_env
res="$(yes "" | MOCK_DROP_SINGLE=1 bash probe/04-single-write.sh 2>&1)"
check "probe 04: monitor that drops single writes → 'keep double-send'" "echo \"\$res\" | grep -q 'RESULT Q1: YES'"
rm -rf probe/results

echo
echo "$PASS passed, $FAIL failed"
[ $FAIL = 0 ]
