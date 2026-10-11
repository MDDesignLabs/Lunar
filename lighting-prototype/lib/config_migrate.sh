#!/bin/bash
# Config migration: turn ~/.lighting/config.sh into personal overrides only.
#
#   bash lib/config_migrate.sh [config]     migrate (default: $LIGHT_CONFIG or ~/.lighting/config.sh)
#   . lib/config_migrate.sh                 sourced (lightd): defines config_stale_keys only
#
# A KEY=value line is removed when its value is the current default in config.example.sh
# (redundant), an old default from an earlier config.example.sh, or a known superseded
# value (Lunar's seed curve). Everything else is kept: comments, blank lines, any value
# not recognised (that's your choice), and any line too complex to read safely
# ($(…), multi-line strings, several assignments on one line), which is reported.
# A backup (config.sh.bak-YYYYMMDD-HHMMSS) is made before any rewrite. Running it again
# changes nothing and makes no second backup. Written for macOS's bash 3.2 and BSD tools.

CM_PROTO="${CM_PROTO:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

# Old defaults, from every earlier config.example.sh (git log -- lighting-prototype/config.example.sh,
# 5840d63 … 12fff9a), and other superseded values. key<TAB>value<TAB>why.
# Deliberately NOT here, although they were defaults once, because they're a real choice:
# BACKEND=lunar and LUX_SOURCE=lunar (Lunar Pro). STALE_SECS=300 and M1DDC=/usr/local/bin/m1ddc
# are handled in the awk below: old only when LUX_SOURCE isn't lunar / the probe-00 m1ddc exists.
cm_old_values() {
    local t='	'
    cat <<EOF
BRIGHTNESS_CURVE${t}0:10,10:20,40:35,100:50,300:70,1000:100${t}the old example curve (RESEARCH_07 replaced it)
BRIGHTNESS_MIN${t}5${t}an old default (RESEARCH_07: 5 holds the floor at ~71 cd/m2)
LUMINANCE_COMPENSATION${t}1${t}an old default (RESEARCH_07 section 3 turned it off)
BRIGHTNESS_DAILY_CAP${t}300${t}an old default
BRIGHTNESS_MIN_INTERVAL${t}20${t}an old default
GAIN_DAILY_CAP${t}50${t}an old default
GAIN_TABLE${t}6500:50:50:50,5500:50:47:44,5000:50:46:40,4500:50:44:36${t}the old example table (probe 05 measured the AOC: now the default)
GAIN_GAMMA${t}2.2${t}the old guessed gamma (probe 05 measured 1.23: now the default)
GAIN_GAMMA${t}1.0${t}the placeholder used until probe 05 ran (now the measured default)
MONITOR_NITS_MIN${t}40${t}an old default (KitGuru measured 55)
MONITOR_NITS_MAX${t}350${t}an old default (KitGuru measured 372)
RESTORE_LUNAR_MODE${t}sensor${t}a setting no longer used
EOF
}

# The parser, the classifier and the rewriter, in one awk program (POSIX awk: macOS and Linux).
# Files: 1 = known values (TSV), 2 and 3 = the config (read twice: pass 1 finds each key's last
# assignment, pass 2 writes). mode=defaults reads config.example.sh (file 1) and prints key<TAB>value.
CM_AWK='
function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
# Parse one line as a simple assignment. Sets P_KEY and P_VAL; returns 1, 0 (not an
# assignment: comment or blank) or -1 (looks like code we will not rewrite).
function parse(line,    rest, q, i, v, after) {
    P_KEY = ""; P_VAL = ""
    if (line ~ /^[ \t]*(#.*)?$/) return 0
    if (line !~ /^[ \t]*[A-Za-z_][A-Za-z0-9_]*=/) return -1
    rest = line; sub(/^[ \t]+/, "", rest)
    i = index(rest, "="); P_KEY = substr(rest, 1, i - 1); rest = substr(rest, i + 1)
    q = substr(rest, 1, 1)
    if (q == "\"" || q == "'\''") {
        rest = substr(rest, 2); i = index(rest, q)
        if (i == 0) return -1                                  # multi-line or unterminated
        v = substr(rest, 1, i - 1); after = substr(rest, i + 1)
        if (q == "\"") { v = home_tilde(v); if (v ~ /[$`\\]/) return -1 }
    } else {
        i = match(rest, /[ \t]/)
        if (i) { v = substr(rest, 1, i - 1); after = substr(rest, i) } else { v = rest; after = "" }
        v = home_tilde(v)
        if (v ~ /[$`\\"'\''();&|<>]/) return -1
    }
    if (after !~ /^([ \t]+#.*|[ \t]*)$/) return -1            # A=1 B=2, A=1;cmd, "a"b …
    P_VAL = trim(v); return 1
}
# $HOME/…, ${HOME}/… and the real home path all compare equal to ~/….
function home_tilde(v) {
    if (v ~ /^\$\{HOME\}(\/|$)/) v = "~" substr(v, 8)
    else if (v ~ /^\$HOME(\/|$)/) v = "~" substr(v, 6)
    if (home != "" && (v == home || index(v, home "/") == 1)) v = "~" substr(v, length(home) + 1)
    return v
}
function odd_quotes(s, q,    n, t) { t = s; n = gsub(q, "", t); return n % 2 }
# Lunar seed curve, with or without corrupt entries: every well-formed lux:pct point is a
# seed point (Display.swift nitsToPercentageMapping), and there are at least three of them.
function is_seed(v,    n, a, i, good) {
    n = split(v, a, ","); good = 0
    for (i = 1; i <= n; i++) {
        a[i] = trim(a[i])
        if (a[i] !~ /^[0-9.]+:[0-9.]+$/) continue           # malformed (e.g. "134"): ignore
        if (!(a[i] in SEED)) return 0                          # a learned point: keep the curve
        good++
    }
    return good >= 3
}
# Why a value would be removed, or "" to keep it.
function why(k, v) {
    if ((k SUBSEP v) in DEF) return "same as the repo default"
    if ((k SUBSEP v) in OLD) return "old: " OLD[k, v]
    if (k == "BRIGHTNESS_CURVE" && is_seed(v)) return "old: Lunar'\''s seed curve (RESEARCH_07 replaced it)"
    if (k == "STALE_SECS" && v == "300" && LASTVAL["LUX_SOURCE"] != "lunar") return "old: an old default (300 is for LUX_SOURCE=lunar)"
    if (k == "M1DDC" && v == "/usr/local/bin/m1ddc" && have_tools_m1ddc) return "old: an old default (probe 00 builds ~/.lighting/tools/m1ddc)"
    return ""
}
function show(s) { return length(s) > 64 ? substr(s, 1, 61) "..." : s }
BEGIN {
    FS = "\t"
    split("0:21,13:31,23:34,39:39,71:41,80:44,100:45,135:47,160:49,190:54,224:58,313:69,565:91,702:99,800:100,1000:100", s, ",")
    for (i in s) SEED[s[i]] = 1
    HEADER1 = "# Personal overrides only. Defaults come from lighting-prototype/config.example.sh and update with git pull."
    HEADER2 = "# Run `bin/light update` to update."
}
FNR == 1 { file++ }
mode == "defaults" { if (parse($0) == 1) print P_KEY "\t" P_VAL; next }
file == 1 { if ($3 == "default") DEF[$1, $2] = 1; else OLD[$1, $2] = $3; next }
file == 2 {
    if (inq != "") { UNPARSED = UNPARSED "\n" $0; if (odd_quotes($0, inq)) inq = ""; next }
    if (index($0, "Personal overrides only.")) has_header = 1
    r = parse($0)
    if (r == 1) { LAST[P_KEY] = FNR; LASTVAL[P_KEY] = P_VAL }
    if (r == -1) {
        UNPARSED = UNPARSED "\n" $0
        if (odd_quotes($0, "\"")) inq = "\""; else if (odd_quotes($0, "'\''")) inq = "'\''"
    }
    next
}
file == 3 && FNR == 1 {
    for (k in LAST) {
        w = why(k, LASTVAL[k])
        # A key that a line we cannot read may also set: removing ours could change which wins.
        if (w != "" && index(UNPARSED, k "=")) w = ""
        DROP[k] = w
    }
    if (mode == "check") { for (k in DROP) if (DROP[k] ~ /^old: /) print k; exit }
    if (!has_header) { print HEADER1; print HEADER2; print ""; header_added = 1 }
    inq = ""
}
file == 3 {
    if (inq != "") {
        print; if (odd_quotes($0, inq)) inq = ""; next
    }
    r = parse($0)
    if (r == 1) {
        if (DROP[P_KEY] != "") {
            w = (FNR == LAST[P_KEY]) ? DROP[P_KEY] : "set again later in the file, and that line is removed"
            sub(/^old: /, "", w)
            printf "  removed  %-50s %s\n", show(P_KEY "=" P_VAL), w > report
            next
        }
        if (FNR == LAST[P_KEY])
            printf "  kept     %-50s %s\n", show(P_KEY "=" P_VAL), "your setting" > report
    } else if (r == -1) {
        printf "  left     line %d: %-40s not a simple KEY=value; left as it is\n", FNR, show($0) > report
        if (odd_quotes($0, "\"")) inq = "\""; else if (odd_quotes($0, "'\''")) inq = "'\''"
    }
    print
}
END { if (header_added && mode == "migrate") print "  added    the header (personal overrides only)" > report }
'

cm_config_path() { printf '%s' "${1:-${LIGHT_CONFIG:-${LIGHT_HOME:-$HOME/.lighting}/config.sh}}"; }

# key<TAB>value<TAB>class lines for the awk: the current defaults, then the old values.
cm_known() {
    awk -v mode=defaults -v home="$HOME" "$CM_AWK" "$CM_PROTO/config.example.sh" | sed 's/$/	default/'
    cm_old_values
}

cm_awk() {  # <mode> <config> [report]
    local known; known="$(mktemp "${TMPDIR:-/tmp}/light-known.XXXXXX")" || return 1
    cm_known > "$known"
    local tools=0; [ -x "${LIGHT_HOME:-$HOME/.lighting}/tools/m1ddc" ] && tools=1
    awk -v mode="$1" -v home="$HOME" -v have_tools_m1ddc=$tools -v report="${3:-/dev/null}" \
        "$CM_AWK" "$known" "$2" "$2"
    local rc=$?; rm -f "$known"; return $rc
}

# Keys the config sets to an old or superseded value (lightd warns about these at start).
config_stale_keys() {  # [config]
    local cfg; cfg="$(cm_config_path "$1")"
    [ -s "$cfg" ] || return 0
    cm_awk check "$cfg"
}

cm_log() {
    local home="${LIGHT_HOME:-$HOME/.lighting}"
    mkdir -p "$home" && printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$home/lightd.log"
}

config_migrate() {  # [config]
    local cfg tmp report backup removed kept left
    cfg="$(cm_config_path "$1")"
    if [ ! -s "$cfg" ]; then          # missing or empty: nothing to lose, no backup needed
        mkdir -p "$(dirname "$cfg")"
        printf '%s\n%s\n\n' \
            "# Personal overrides only. Defaults come from lighting-prototype/config.example.sh and update with git pull." \
            "# Run \`bin/light update\` to update." > "$cfg"
        echo "Config: $cfg holds only the header for now (no overrides)."
        cm_log "config migrate: wrote a header-only $cfg (no overrides)"
        return 0
    fi
    report="$(mktemp "${TMPDIR:-/tmp}/light-report.XXXXXX")" || return 1
    tmp="$cfg.migrate.$$"
    # Copy first so the rewritten file keeps the original's permissions.
    cp -p "$cfg" "$tmp" || { rm -f "$report"; return 1; }
    cm_awk migrate "$cfg" "$report" > "$tmp" || { echo "config migrate: failed; $cfg left as it is" >&2; rm -f "$tmp" "$report"; return 1; }
    removed="$(grep -c '^  removed' "$report")"; kept="$(grep -c '^  kept' "$report")"; left="$(grep -c '^  left' "$report")"
    echo "Config: $cfg"
    if cmp -s "$cfg" "$tmp"; then
        rm -f "$tmp"
        [ "$kept$left" != 00 ] && cat "$report"
        echo "  nothing to change: it already holds only your overrides."
        cm_log "config migrate: nothing to change ($kept kept, $left left as they are)"
        rm -f "$report"; return 0
    fi
    backup="$cfg.bak-$(date +%Y%m%d-%H%M%S)"
    [ -e "$backup" ] && backup="$backup-$$"
    if ! cp -p "$cfg" "$backup"; then
        echo "config migrate: could not back up $cfg; left as it is" >&2; rm -f "$tmp" "$report"; return 1
    fi
    mv "$tmp" "$cfg"
    cat "$report"
    echo "  backup: $backup"
    cm_log "config migrate: removed $removed ($(sed -n 's/^  removed  \([A-Za-z0-9_]*\)=.*/\1/p' "$report" | tr '\n' ' ' | sed 's/ $//')), kept $kept, left $left; backup $backup"
    rm -f "$report"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    config_migrate "$@"
fi
