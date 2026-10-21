# `light report [YYYY-MM-DD]`: one day's summary to paste for review. Sourced by bin/light
# after common.sh. Reads only lightd's own files; changes nothing. macOS bash 3.2 / BSD tools.

# Epoch seconds of local midnight for YYYY-MM-DD (BSD date, then GNU date).
day_start() {
    date -j -f '%Y-%m-%d %H:%M:%S' "$1 00:00:00" +%s 2>/dev/null || date -d "$1 00:00:00" +%s 2>/dev/null
}

# "doy:720:offset" for noon on YYYY-MM-DD, for that day's sunset (BSD date, then GNU date).
day_clock() {
    local j z tz; tz="$(tz_name)"
    j="$(TZ="$tz" date -j -f '%Y-%m-%d %H:%M' "$1 12:00" +%j 2>/dev/null || TZ="$tz" date -d "$1 12:00" +%j 2>/dev/null)"
    z="$(TZ="$tz" date -j -f '%Y-%m-%d %H:%M' "$1 12:00" +%z 2>/dev/null || TZ="$tz" date -d "$1 12:00" +%z 2>/dev/null)"
    echo "$((10#$j)):720:$z"
}

light_report() {
    local day="${1:-$(today)}" start samples="$LIGHT_HOME/samples-${1:-$(today)}.csv"
    case "$day" in [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;; *) echo "usage: light report [YYYY-MM-DD]" >&2; return 64 ;; esac
    start="$(day_start "$day")"
    [ -n "$start" ] || { echo "can't read the date $day" >&2; return 64; }

    echo "== Lighting report for $day =="
    echo "config: curve=$BRIGHTNESS_CURVE"
    echo "        min=$BRIGHTNESS_MIN comp=$LUMINANCE_COMPENSATION kelvin ${KELVIN_DIM}K@${KELVIN_DIM_LUX}lx..${KELVIN_BRIGHT}K@${KELVIN_BRIGHT_LUX}lx critical_brightness=${CRITICAL_BRIGHTNESS:-adaptive}"
    if [ "${TIME_OF_DAY:-0}" = 1 ]; then
        local ti; ti="$(LIGHT_CLOCK="$(day_clock "$day")" tod_info)"
        echo "clock:  time of day ON: dark room 6500K by day, ${KELVIN_DIM}K from sunset $(echo "$ti" | sed -n 's/^sunset=//p'), ${KELVIN_NIGHT}K from bedtime $BEDTIME − 3 h ($(tz_name))"
    else
        echo "clock:  time of day OFF (old version, or TIME_OF_DAY=0): the room light alone sets the white point"
    fi
    local pid; pid="$(cat "$STATE/lightd.pid" 2>/dev/null)"
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then echo "lightd: running (pid $pid)"
    else echo "lightd: NOT RUNNING: the 'now' line below is the last state it saved"; fi
    echo "now:    mode=$(current_mode) lux=$(state_get lux '?') target: $(state_get target '?')"
    echo

    echo "-- Hourly (from lightd's 5-minute samples)"
    if [ -f "$samples" ]; then
        awk -F, 'NR > 1 {
            h = substr($1, 1, 2); n[h]++; lux = $2 + 0
            if (!(h in lo) || lux < lo[h]) lo[h] = lux
            if (!(h in hi) || lux > hi[h]) hi[h] = lux
            if ($3 == "asleep") asleep[h]++
            sb[h] = sb[h] (sb[h] == "" ? "" : " ") $7; kb[h] = $6; off[h] = $9; md[h] = $4
          }
          END {
            printf "  %-5s %-17s %-14s %-7s %-6s %s\n", "hour", "lux min–max", "sent bright %", "kelvin", "nudge", "note"
            for (i = 0; i < 24; i++) {
                h = sprintf("%02d", i); if (!(h in n)) continue
                split(sb[h], v, " "); first = v[1]; last = v[length(v)]
                note = (h in asleep) ? sprintf("display asleep %d of %d samples", asleep[h], n[h]) : ""
                if (md[h] == "critical") note = note (note == "" ? "" : "; ") "colour-critical"
                printf "  %-5s %6.1f – %-8.1f %-14s %-7s %-6s %s\n", h ":00", lo[h], hi[h], (first == last ? first : first "→" last), kb[h], off[h], note
            }
          }' "$samples"
    else
        echo "  (no samples for $day: lightd records them from 2026-10-13 on, every SAMPLE_LOG_SECS)"
    fi
    echo

    echo "-- Monitor writes (writes.log)"
    if [ -f "$LIGHT_HOME/writes.log" ]; then
        awk -v s="$start" '$1 >= s && $1 < s + 86400 {
            n[$2]++; if ($4 != "ok") fail[$2]++
            if ($2 == "0x10") { t = int(($1 - s) / 60); b = b sprintf(" %02d:%02d→%s", int(t / 60), t % 60, $3) }
          }
          END {
            printf "  brightness %d, red %d, green %d, blue %d writes", n["0x10"], n["0x16"], n["0x18"], n["0x1A"]
            nf = fail["0x10"] + fail["0x16"] + fail["0x18"] + fail["0x1A"]; if (nf) printf " (%d failed)", nf
            print ""
            if (b != "") print "  brightness:" b
          }' "$LIGHT_HOME/writes.log"
    else
        echo "  (no writes.log yet)"
    fi
    echo

    echo "-- Events (lightd.log)"
    if [ -f "$LIGHT_HOME/lightd.log" ]; then
        grep "^$day " "$LIGHT_HOME/lightd.log" | cut -c12- | tail -n 40
        echo "  ($(grep -c "^$day .*user:" "$LIGHT_HOME/lightd.log") nudges or manual changes by you)"
    else
        echo "  (no lightd.log yet)"
    fi
}
