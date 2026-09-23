#!/bin/bash
# 02: Q6. Can a second SSE client stay connected to the ESP32 alongside Lunar?
# Also produces the lux dataset (plan step 0b): results/lux-<date>.csv
#
#   probe/02-sensor-log.sh [hours]      default 24. Leave it running; Ctrl-C ends early and summarises.
. "$(dirname "$0")/lib.sh"
HOURS="${1:-24}"
CSV="$RESULTS/lux-$(date +%Y%m%d-%H%M).csv"
OUT=02-sensor.txt

say "Logging $SENSOR_URL for ${HOURS} h → $CSV"
lunar_running && note "Lunar is running: this measures two clients at once (the real question)." \
             || note "Lunar is NOT running: this only measures one client. Start Lunar for Q6."

python3 - "$SENSOR_URL" "$HOURS" "$CSV" "$LUNAR" <<'PY' | tee -a "$RESULTS/$OUT"
import json, subprocess, sys, time, urllib.request
url, hours, csv, lunar = sys.argv[1], float(sys.argv[2]), sys.argv[3], sys.argv[4]
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
                    if now - last_lunar_check > 60:
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
verdict = "YES" if reconnects <= 2 and len(gaps) <= 5 and (lunar_checks == 0 or lunar_ok / lunar_checks > 0.95) else "NO/UNSTABLE"
print(f"RESULT Q6: {verdict} (two clients {'with' if lunar_checks else 'without'} Lunar verified)")
PY
