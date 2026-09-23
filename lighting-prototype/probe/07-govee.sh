#!/bin/bash
# 07: Q7 Govee: discovery, model, command port 4003, supported Kelvin range.
# Before: Govee Home app → each light → Settings → "LAN Control" ON.
. "$(dirname "$0")/lib.sh"
. "$PROBE_DIR/../lib/common.sh"
. "$PROBE_DIR/../lib/govee.sh"
OUT=07-govee.txt; : > "$RESULTS/$OUT"

say "Discovery (scan → 239.255.255.250:4001, replies on :4002)"
replies="$(govee_discover 4)"
if [ -z "$replies" ]; then
    record $OUT "RESULT Q7: no replies. Check: LAN Control on per device; Mac and strips on the same subnet;"
    record $OUT "  router passes multicast on Wi-Fi; nothing else on this Mac owns UDP 4002; allow Terminal"
    record $OUT "  under System Settings → Privacy & Security → Local Network."
    ip="$(ask 'Enter a strip IP manually (from your router) to test commands anyway, or blank to stop:')"
    [ -z "$ip" ] && exit 1
    ips="$ip"
else
    echo "$replies" | tee -a "$RESULTS/$OUT"
    ips="$(echo "$replies" | python3 -c 'import json,sys
for l in sys.stdin:
    try: print(json.loads(l)["msg"]["data"]["ip"])
    except Exception: pass' | sort -u | tr '\n' ' ')"
    record $OUT "found: $ips"
fi

for ip in $ips; do
    say "Commands to $ip:4003"
    govee_turn "$ip" 1; sleep 1
    govee_brightness "$ip" 100; sleep 1
    govee_brightness "$ip" 10; sleep 1
    ask_yn "Did $ip turn on, go bright, then dim to ~10%?" \
        && record $OUT "$ip: turn + brightness on :4003 WORK" \
        || record $OUT "$ip: turn/brightness did NOT work"
    govee_brightness "$ip" 60; sleep 1
    lo="" hi=""
    for k in 2000 2700 4000 6500 9000; do
        govee_kelvin "$ip" $k; sleep 1.5
        ask_yn "  ${k}K: does it look different from the previous step?" && { [ -z "$lo" ] && lo=$k; hi=$k; }
    done
    record $OUT "$ip: colorwc Kelvin visibly responds from ~${lo:-?}K to ~${hi:-?}K"
done
record $OUT "RESULT Q7: see above. Put the IPs in GOVEE_IPS in ~/.lighting/config.sh (DHCP-reserve them on your router)."
