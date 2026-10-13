# Compute targets from a filtered lux value and push them to hardware.
# Sourced after common.sh, ddc.sh and govee.sh. Used by both lightd and `light`.

current_mode() { state_get mode adaptive; }

# Lunar's own (cached) brightness for the AOC. No DDC read happens here.
lunar_brightness() {
    lunar_get "$LUNAR_DISPLAY" brightness | awk '{ print int($0 + 0.5) }'
}

# apply_targets <filtered_log10_lux> [force]
# In critical mode returns the gain write's code (0 = neutral is on the monitor) and
# stores it as state "critical_rc", so `light`, lightd and the menu bar can tell.
apply_targets() {
    local lf="$1" force="${2:-0}" mode actual_b k v rc=0 on
    local kelvin=6500 brightness=0 red=50 green=50 blue=50 bias=0 bias_k=6500 bias_room="" bias_cal=1
    mode="$(current_mode)"

    # A "brighter/dimmer" nudge is a correction for THIS lighting. When the room moves
    # more than OFFSET_RESET_DECADES (0.5 = ~3× lux) from where it was set, drop it.
    if [ "$(state_get bright_offset 0)" != 0 ] && awk -v a="$lf" -v b="$(state_get bright_offset_lf "$lf")" \
        -v d="${OFFSET_RESET_DECADES:-0.5}" 'BEGIN { x = a - b; if (x < 0) x = -x; exit !(x > d) }'; then
        log "room light changed a lot since the brightness nudge; clearing offset $(state_get bright_offset 0)"
        state_set bright_offset 0
    fi

    actual_b=""
    if [ "$BACKEND" = lunar ] && [ "$mode" = adaptive ]; then
        actual_b="$(lunar_brightness)"
    fi

    # Computed first, not inside the here-doc: bash 5 printed a parse error ("trap: unexpected
    # EOF while looking for matching `)'") when lightd's TERM trap fired mid-here-doc.
    local tg; tg="$(engine_targets "$lf" "$mode" "$actual_b")"
    while IFS='=' read -r k v; do
        case "$k" in
            kelvin) kelvin="$v" ;; brightness) brightness="$v" ;;
            red) red="$v" ;; green) green="$v" ;; blue) blue="$v" ;; bias) bias="$v" ;;
            bias_k) bias_k="$v" ;; bias_room) bias_room="$v" ;; bias_cal) bias_cal="$v" ;;
        esac
    done <<EOF
$tg
EOF

    if [ "$mode" = critical ]; then
        # The override is never rate-limited, and may use the neutral reserve past the
        # daily cap. No-op skipping still applies.
        ddc_gains "$red" "$green" "$blue" 1 neutral || rc=$?
        state_set critical_rc "$rc"
        if [ -n "$CRITICAL_BRIGHTNESS" ]; then ddc_brightness "$brightness" 1; fi
    else
        ddc_gains "$red" "$green" "$blue" "$force" adaptive
        if [ "$BACKEND" = m1ddc ]; then
            on="$(state_get last_red "$red"):$(state_get last_green "$green"):$(state_get last_blue "$blue")"
            if [ "$LUMINANCE_COMPENSATION" = 1 ] && [ "$on" != "$red:$green:$blue" ]; then
                # Gains weren't (all) written: compensate for what the monitor really shows.
                brightness="$(engine_targets "$lf" "$mode" "" "$on" | sed -n 's/^brightness=//p')"
            fi
            ddc_brightness "$brightness" "$force"
        fi
    fi
    # Bias light (FR-61–FR-64). bias is the strip %, 0 = off (bright room, or the override with
    # BIAS_IN_CRITICAL=off); bias_k is the screen's target K clamped to 2200–6500, or 6500
    # in the override. Display sleep and exit are handled in lightd. GOVEE_IPS="" skips it all.
    if [ -n "$GOVEE_IPS" ]; then
        if [ -n "$bias_room" ] && [ "$bias_room" != "$(state_get bias_room '')" ]; then
            state_set bias_room "$bias_room"     # the hysteresis memory (engine reads it back)
            if [ "$bias_room" = 0 ]; then log "bias: room above ${BIAS_OFF_LUX} lx: off (the room already lights the wall)"
            else log "bias: room below ${BIAS_ON_LUX} lx (or first decision): on"; fi
        fi
        if [ "$bias_cal" = 0 ] && [ "$(state_get bias_uncal_logged 0)" != 1 ]; then
            state_set bias_uncal_logged 1
            log "bias: not calibrated yet (BIAS_CAL is empty): using ${BIAS_FALLBACK_PCT}% (UNVERIFIED). Run probe/07-govee.sh check F"
        fi
        govee_apply "$bias" "$bias_k" "$force"
    fi

    state_set target "kelvin=$kelvin brightness=$brightness gains=$red/$green/$blue bias=$bias mode=$mode"
    state_set kelvin "$kelvin"
    return $rc
}

# Why a gain write didn't land, for people.
gain_rc_reason() {
    case "$1" in
        4) echo "another app ($(other_ddc_app || echo 'Lunar, BetterDisplay or MonitorControl')) is controlling the monitor. Quit it and run this again" ;;
        3) echo "today's write allowance is used up, including the neutral reserve. Set the OSD to User 50/50/50 by hand" ;;
        *) echo "the monitor didn't accept the write (see ~/.lighting/lightd.log)" ;;
    esac
}
