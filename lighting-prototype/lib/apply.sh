# Compute targets from a filtered lux value and push them to hardware.
# Sourced after common.sh, ddc.sh and govee.sh. Used by both lightd and `light`.

current_mode() { state_get mode adaptive; }

# Lunar's own (cached) brightness for the AOC. No DDC read happens here.
lunar_brightness() {
    lunar_get "$LUNAR_DISPLAY" brightness | awk '{ print int($0 + 0.5) }'
}

# apply_targets <filtered_log10_lux> [force]
apply_targets() {
    local lf="$1" force="${2:-0}" mode actual_b k v
    local kelvin=6500 brightness=0 red=50 green=50 blue=50 bias=0
    mode="$(current_mode)"

    actual_b=""
    if [ "$BACKEND" = lunar ] && [ "$mode" = adaptive ]; then
        actual_b="$(lunar_brightness)"
    fi

    while IFS='=' read -r k v; do
        case "$k" in
            kelvin) kelvin="$v" ;; brightness) brightness="$v" ;;
            red) red="$v" ;; green) green="$v" ;; blue) blue="$v" ;; bias) bias="$v" ;;
        esac
    done <<EOF
$(engine_targets "$lf" "$mode" "$actual_b")
EOF

    if [ "$mode" = critical ]; then
        # The override is never rate-limited. No-op skipping still applies.
        ddc_gains "$red" "$green" "$blue" 1
        if [ -n "$CRITICAL_BRIGHTNESS" ]; then ddc_brightness "$brightness" 1; fi
    else
        ddc_gains "$red" "$green" "$blue" "$force"
        if [ "$BACKEND" = m1ddc ]; then ddc_brightness "$brightness" "$force"; fi
    fi
    govee_apply "$bias" "$kelvin" "$force"

    state_set target "kelvin=$kelvin brightness=$brightness gains=$red/$green/$blue bias=$bias mode=$mode"
    state_set kelvin "$kelvin"
}
