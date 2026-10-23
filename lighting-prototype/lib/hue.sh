# Philips Hue bias light over the Hue Bridge's local CLIP v2 API (SPEC FR-68; RESEARCH_09).
# Sourced after common.sh. bash 3.2 / BSD tools / curl. HUE_BRIDGE="" disables all of this.
#
# The bridge answers HTTPS with its own certificate (signed by Signify's root, issued to the
# bridge id, not its IP), so curl runs with -k on the LAN. The application key comes from
# `bin/hue pair` (press the bridge's link button). It's stored in ~/.lighting/hue_key (mode 600),
# never in config.sh.
#
#   hue_apply <pct> <K> [force]   pct 0 = off; 1–100 = on at that brightness. K → mirek (153–500)
#   hue_tick                      send a target held back by the rate limit
#   hue_invalidate                forget what the strip shows (the next apply sends everything)
#
# Rules mirror the Govee ones (FR-64–FR-66), minus what HTTP makes unnecessary:
#   - each PUT is answered, so there's no blind 60 s refresh and nothing is sent twice;
#   - send only on a change of ≥ 1 % or ≥ 100 K, at most one update per HUE_MIN_INTERVAL (1 s);
#   - "on" is sent only on our own off→on transition, so a strip you switched off in the Hue
#     app stays off until the next transition (Hue doesn't power a light on for dimming alone);
#   - every change fades over HUE_FADE_MS (the bridge does it), so steps are never visible;
#   - 3 failed PUTs in a row log "bias light not responding" once (FR-67), and it keeps trying.
# State: hue_on (1/0/empty), hue_pct, hue_k, hue_ms, hue_want, hue_pending, hue_fails.

# Resolved on each use, not once at load: LIGHT_HOME can change after this file is sourced.
hue_key_file() { printf '%s' "${HUE_KEY_FILE:-$LIGHT_HOME/hue_key}"; }

hue_url() { echo "${HUE_SCHEME:-https}://$HUE_BRIDGE$1"; }
hue_key() { cat "$(hue_key_file)" 2>/dev/null; }

# hue_req <METHOD> <path> [json]: prints the body; returns 0 on HTTP 200 with no errors.
hue_req() {
    local out code body
    out="$(curl -sk -m "${HUE_TIMEOUT:-3}" -X "$1" -H "hue-application-key: $(hue_key)" \
        -H 'Content-Type: application/json' ${3:+-d "$3"} -w '\n%{http_code}' "$(hue_url "$2")" 2>/dev/null)"
    code="${out##*
}"; body="${out%
*}"
    printf '%s\n' "$body"
    [ "$code" = 200 ] || return 1
    case "$body" in *'"errors":[]'*|*'"errors": []'*) return 0 ;; *'"errors"'*) return 1 ;; esac
    return 0
}

hue_mirek() {  # <K> → mirek, clamped to the bridge's 153 (6500 K) … 500 (2000 K)
    awk -v k="$1" 'BEGIN { m = int(1000000 / k + 0.5); print (m < 153) ? 153 : (m > 500 ? 500 : m) }'
}

hue_put() {  # <json>: one PUT to the bias light, with the failure counter
    if hue_req PUT "/clip/v2/resource/light/$HUE_LIGHT" "$1" >/dev/null; then
        [ "$(state_get hue_fails 0)" -ge 3 ] && log "hue: bias light responding again"
        state_set hue_fails 0; return 0
    fi
    local n=$(( $(state_get hue_fails 0) + 1 )); state_set hue_fails "$n"
    [ "$n" = 3 ] && log "hue: bias light not responding (3 failed updates to $HUE_BRIDGE); still trying"
    return 1
}

hue_apply() {
    local pct="$1" k="$2" force="${3:-0}" on cur_on cur_pct cur_k body="" kind="" ms d
    [ -z "$HUE_BRIDGE" ] && return 0
    case "$pct" in ''|*[!0-9.]*|*.*.*) log "hue: ignoring a bad level '$pct'"; return 1 ;; esac
    case "$k" in ''|*[!0-9.]*|*.*.*) k=6500 ;; esac
    pct="$(awk -v p="$pct" 'BEGIN { if (p + 0 <= 0) print 0; else { r = int(p + 0.5); print (r < 1) ? 1 : (r > 100 ? 100 : r) } }')"
    k="$(awk -v k="$k" -v lo="${GOVEE_K_MIN:-2200}" -v hi="${GOVEE_K_MAX:-6500}" \
        'BEGIN { k = int(k + 0.5); print (k < lo) ? lo : (k > hi ? hi : k) }')"
    on=1; [ "$pct" = 0 ] && on=0
    state_set hue_want "$pct $k"
    cur_on="$(state_get hue_on "")"; cur_pct="$(state_get hue_pct "")"; cur_k="$(state_get hue_k "")"
    d="${HUE_FADE_MS:-2000}"

    if [ $on = 0 ]; then
        if [ "$cur_on" != 0 ] || [ "$force" = 1 ]; then kind=off; body='{"on":{"on":false},"dynamics":{"duration":'"$d"'}}'; fi
    elif [ "$cur_on" != 1 ]; then
        kind=on
        body='{"on":{"on":true},"dimming":{"brightness":'"$pct"'},"color_temperature":{"mirek":'"$(hue_mirek "$k")"'},"dynamics":{"duration":'"$d"'}}'
    else
        local parts=""
        if [ "$force" = 1 ] || [ "$pct" != "$cur_pct" ]; then parts='"dimming":{"brightness":'"$pct"'}'; fi
        if [ "$force" = 1 ] || [ -z "$cur_k" ] || [ "$(absdiff "$k" "$cur_k")" -ge 100 ]; then
            parts="${parts:+$parts,}"'"color_temperature":{"mirek":'"$(hue_mirek "$k")"'}'
        else
            k="$cur_k"                     # under 100 K: keep what the strip has
        fi
        [ -n "$parts" ] && { kind=update; body="{$parts,\"dynamics\":{\"duration\":$d}}"; }
    fi
    if [ -z "$body" ]; then state_set hue_pending 0; return 0; fi

    ms="$(now_ms)"
    if [ "$force" != 1 ] && [ $(( ms - $(state_get hue_ms 0) )) -lt $(( ${HUE_MIN_INTERVAL:-1} * 1000 )) ]; then
        state_set hue_pending 1           # coalesced: hue_tick sends the latest target later
        return 0
    fi
    state_set hue_ms "$ms"
    if ! hue_put "$body"; then state_set hue_pending 1; return 1; fi
    state_set hue_pending 0
    if [ $on = 1 ]; then state_set hue_on 1; state_set hue_pct "$pct"; state_set hue_k "$k"
    else state_set hue_on 0; fi
    case "$kind" in
        on)     log "hue: on ${pct}% ${k}K" ;;
        off)    log "hue: off" ;;
        update) log "hue: ${pct}% ${k}K" ;;
    esac
    return 0
}

hue_tick() {
    [ -z "$HUE_BRIDGE" ] && return 0
    [ "$(state_get hue_pending 0)" = 1 ] || return 0
    local want; want="$(state_get hue_want "")"
    [ -z "$want" ] && return 0
    # shellcheck disable=SC2086
    hue_apply $want
}

hue_invalidate() { rm -f "$STATE/hue_on"; }

# ── Backend choice: lightd and `light` call these, never govee_*/hue_* directly ──
# HUE_BRIDGE set → Hue; else GOVEE_IPS set → Govee; else none (nothing is ever sent).
# No command substitution in these: lightd calls them every sample, and each fork widens the
# window in which bash can lose a TERM (seen in the test suite, 2026-10-23).
bias_backend() {
    if [ -n "$HUE_BRIDGE" ]; then echo hue; elif [ -n "$GOVEE_IPS" ]; then echo govee; else echo none; fi
}
bias_set()        { [ -n "$HUE_BRIDGE$GOVEE_IPS" ]; }
bias_apply()      { if [ -n "$HUE_BRIDGE" ]; then hue_apply "$@"; elif [ -n "$GOVEE_IPS" ]; then govee_apply "$@"; fi; }
bias_tick()       { if [ -n "$HUE_BRIDGE" ]; then hue_tick; elif [ -n "$GOVEE_IPS" ]; then govee_tick; fi; }
bias_invalidate() { if [ -n "$HUE_BRIDGE" ]; then hue_invalidate; elif [ -n "$GOVEE_IPS" ]; then govee_invalidate; fi; }
bias_last_k()     { if [ -n "$HUE_BRIDGE" ]; then state_get hue_k 6500; else state_get govee_k 6500; fi; }
bias_where()      { case "$(bias_backend)" in hue) echo "Hue bridge $HUE_BRIDGE, light ${HUE_LIGHT:-?}" ;; govee) echo "$GOVEE_IPS" ;; *) echo "<none set>" ;; esac; }
bias_state() {    # "on 5% 4000K" / "off" / "unknown"
    local p; p="$(bias_backend)"; [ "$p" = hue ] || p=govee
    case "$(state_get ${p}_on '')" in
        1) echo "on $(state_get ${p}_pct '?')% $(state_get ${p}_k '?')K" ;; 0) echo off ;; *) echo unknown ;;
    esac
}
