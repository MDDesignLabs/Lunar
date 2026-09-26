#!/bin/bash
# 02: Q6. Is the ESP32's event stream stable over 24 h? (With LUX_SOURCE=direct, lightd is
#     its only client, so this is the stability of the one link everything depends on.
#     With Lunar running it also measures two clients at once.)
# Also produces the lux dataset (plan step 0b): results/lux-<date>.csv
#
#   probe/02-sensor-log.sh [hours]      default 24. Leave it running; Ctrl-C ends early and summarises.
. "$(dirname "$0")/lib.sh"
# Keep the Mac from idle-sleeping for the duration (display sleep is fine). Re-exec once under caffeinate.
if [ -z "$UNDER_CAFFEINATE" ] && command -v caffeinate >/dev/null; then
    UNDER_CAFFEINATE=1 exec caffeinate -i bash "$0" "$@"
fi
HOURS="${1:-24}"
CSV="$RESULTS/lux-$(date +%Y%m%d-%H%M).csv"
OUT=02-sensor.txt

say "Logging $SENSOR_URL for ${HOURS} h → $CSV"
if lunar_running; then note "Lunar is running: measuring two clients at once, and checking \`lunar lux\` each minute."
else note "Lunar is not running: measuring the single-client link (your direct setup)."; fi
CHECK_LUNAR=0; lunar_running && [ -x "$LUNAR" ] && CHECK_LUNAR=1

python3 - "$SENSOR_URL" "$HOURS" "$CSV" "$LUNAR" "$CHECK_LUNAR" <<'PY' | tee -a "$RESULTS/$OUT"
import json, subprocess, sys, time, urllib.request
url, hours, csv, lunar = sys.argv[1], float(sys.argv[2]), sys.argv[3], sys.argv[4]
check_lunar = sys.argv[5] == "1"
end = time.time() + hours * 3600
samples = reconnects = 0
gaps = []           # gaps > 10 s between ambient samples
lunar_checks = lunar_ok = 0
last = None
last_lunar_check = 0
f = open(csv, "a")
f.write("epoch,lux,lunar_lux\n")
try:
    while time.time() < end:
        try:
            with urllib.request.urlopen(url, timeout=30) as r:
                while time.time() < end:
                    line = r.readline()
                    if not line:
                        raise ConnectionError("stream closed")
                    line = line.decode(errors="replace").strip()
                    if not line.startswith("data:"):
                        continue
                    try:
                        d = json.loads(line[5:])
                    except ValueError:
                        continue
                    if d.get("id") != "sensor-ambient_light":
                        continue
                    now = time.time()
                    if last and now - last > 10:
                        gaps.append(round(now - last))
                    last = now
                    samples += 1
                    ll = ""
                    if check_lunar and now - last_lunar_check > 60:
                        last_lunar_check = now
                        try:
                            ll = subprocess.run([lunar, "lux"], capture_output=True, text=True, timeout=10).stdout.strip()
                            lunar_checks += 1
                            if ll and float(ll) >= 0:
                                lunar_ok += 1
                        except Exception:
                            pass
                    f.write(f"{now:.0f},{d['value']},{ll}\n"); f.flush()
        except Exception as e:
            reconnects += 1
            print(f"{time.strftime('%H:%M:%S')} reconnect #{reconnects}: {e}", flush=True)
            time.sleep(min(30, 2 ** min(reconnects, 5)))
except KeyboardInterrupt:
    pass
print(f"samples={samples} reconnects={reconnects} gaps>10s={len(gaps)} longest_gap={max(gaps) if gaps else 0}s")
print(f"lunar lux checks={lunar_checks} ok={lunar_ok}")
verdict = "STABLE" if reconnects <= 2 and len(gaps) <= 5 and (lunar_checks == 0 or lunar_ok / lunar_checks > 0.95) else "UNSTABLE"
print(f"RESULT Q6: {verdict} ({'two clients, Lunar checked' if lunar_checks else 'single client'}). "
      f"Gaps > 10 s mean the white point holds its last value for that long.")
PY
