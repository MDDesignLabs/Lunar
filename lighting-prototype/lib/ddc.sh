# DDC write scheduler. Sourced after common.sh.
#
# Every write to the monitor goes through ddc_write, which enforces:
#   - no-op skipping (never re-send the value last written)
#   - dead-band and minimum interval (unless forced, e.g. the override)
#   - a persistent daily cap per VCP, counted on every *attempt*
#   - a write log: $LIGHT_HOME/writes.log  (epoch vcp value result ms backend)
#
# Return codes: 0 written, 1 backend failed, 2 skipped (no-op/dead-band/interval), 3 daily cap hit.

vcp_name() {
    case "$1" in
        0x10) echo brightness ;; 0x16) echo red ;; 0x18) echo green ;; 0x1A) echo blue ;;
    esac
}

backend_write() {
    local vcp="$1" value="$2" name
    name="$(vcp_name "$vcp")"
    case "$BACKEND" in
        lunar)
            # Use Lunar's display properties, not `lunar ddc`, so Lunar's stored
            # values stay in sync and its wake-reapply restores OUR values.
            case "$name" in
                brightness) "$LUNAR" displays "$LUNAR_DISPLAY" brightness "$value" ;;
                red)        "$LUNAR" displays "$LUNAR_DISPLAY" redGain "$value" ;;
                green)      "$LUNAR" displays "$LUNAR_DISPLAY" greenGain "$value" ;;
                blue)       "$LUNAR" displays "$LUNAR_DISPLAY" blueGain "$value" ;;
            esac
            ;;
        m1ddc)
            case "$name" in
                brightness) name=luminance ;;
            esac
            # shellcheck disable=SC2086  # M1DDC_DISPLAY is intentionally word-split
            "$M1DDC" $M1DDC_DISPLAY set "$name" "$value"
            ;;
        *)
            echo "unknown BACKEND=$BACKEND" >&2; return 1 ;;
    esac
}

# ddc_write <vcp> <value> <min_interval_s> <deadband> <daily_cap> [force]
ddc_write() {
    local vcp="$1" value="$2" interval="$3" deadband="$4" cap="$5" force="${6:-0}"
    local last last_t count t0 t1 ok ms key
    key="$(vcp_name "$vcp")"
    last="$(state_get "last_$key" "")"
    last_t="$(state_get "last_t_$key" 0)"

    if [ "$last" = "$value" ]; then return 2; fi
    if [ "$force" != 1 ]; then
        if [ -n "$last" ] && [ "$(absdiff "$value" "$last")" -lt "$deadband" ]; then return 2; fi
        if [ $(( $(now) - last_t )) -lt "$interval" ]; then return 2; fi
    fi

    count="$(state_get "count_$(today)_$key" 0)"
    if [ "$count" -ge "$cap" ]; then
        if [ "$(state_get "capped_$(today)_$key" 0)" = 0 ]; then
            log "CAP: $key reached $cap writes today; adaptive writes stopped until midnight"
            state_set "capped_$(today)_$key" 1
        fi
        return 3
    fi
    state_set "count_$(today)_$key" $(( count + 1 ))

    t0="$(now_ms)"
    if backend_write "$vcp" "$value" >/dev/null 2>&1; then ok=ok; else ok=FAIL; fi
    t1="$(now_ms)"
    ms=$(( t1 - t0 ))
    printf '%s %s %s %s %s %s\n' "$(now)" "$vcp" "$value" "$ok" "$ms" "$BACKEND" >> "$LIGHT_HOME/writes.log"

    if [ "$ok" = ok ]; then
        state_set "last_$key" "$value"
        state_set "last_t_$key" "$(now)"
        return 0
    fi
    log "DDC write failed: $key=$value via $BACKEND"
    return 1
}

ddc_brightness() {  # <value> [force]
    local rc=0
    lock
    ddc_write 0x10 "$1" "$BRIGHTNESS_MIN_INTERVAL" "$BRIGHTNESS_DEADBAND" "$BRIGHTNESS_DAILY_CAP" "${2:-0}" || rc=$?
    unlock
    return $rc
}

# Write R, G, B as one set. Adaptive sets are rate-limited as a unit.
ddc_gains() {  # <r> <g> <b> [force]
    local r="$1" g="$2" b="$3" force="${4:-0}" last_set gap rc=0 wrote=0 c
    last_set="$(state_get last_t_gainset 0)"
    if [ "$force" != 1 ] && [ $(( $(now) - last_set )) -lt "$KELVIN_MIN_INTERVAL" ]; then return 2; fi
    gap="$(awk -v ms="$GAIN_GAP_MS" 'BEGIN { printf "%.3f", ms / 1000 }')"

    lock
    for c in "0x16 $r" "0x18 $g" "0x1A $b"; do
        # shellcheck disable=SC2086
        ddc_write $c 0 0 "$GAIN_DAILY_CAP" 1
        case $? in
            0) wrote=1; sleep "$gap" ;;
            2) ;;                     # unchanged channel
            *) rc=1 ;;
        esac
    done
    unlock

    [ $wrote = 1 ] && state_set last_t_gainset "$(now)"
    return $rc
}

# Forget last-written values so the next apply re-sends everything
# (after wake, or when the monitor may have been changed from its OSD).
ddc_invalidate() {
    rm -f "$STATE/last_brightness" "$STATE/last_red" "$STATE/last_green" "$STATE/last_blue"
    rm -f "$STATE/last_t_gainset" "$STATE/last_t_brightness"
}
