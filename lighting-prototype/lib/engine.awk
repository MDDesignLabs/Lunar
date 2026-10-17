# Pure maths for the lighting prototype. No I/O besides printing results.
# Portable to macOS's BWK awk and to mawk/gawk.
#
#   awk -f engine.awk -v cmd=filter  -v lux=48.2 -v prev=1.6 -v dt=2 -v tau_up=8 -v tau_down=45
#   awk -f engine.awk -v cmd=targets -v lf=1.68 -v mode=adaptive -v curve=... (see targets())
#
# lf = filtered log10(lux).

function log10(x) { return log(x) / log(10) }
function clamp(x, lo, hi) { return x < lo ? lo : (x > hi ? hi : x) }
function round(x) { return int(x + (x < 0 ? -0.5 : 0.5)) }

# Piecewise-linear interpolation over "x:y,x:y" pairs, x given in lux, evaluated in log10(lux).
# Malformed entries (no ":" or non-numeric) are skipped and the rest sorted by lux, so a
# pasting mistake can't create a bogus point or break the ordering.
function curve_eval(spec, lf,    raw, pts, kv, xs, ys, n, i, j, t, tx, ty) {
    raw = split(spec, pts, ",")
    n = 0
    for (i = 1; i <= raw; i++) {
        if (split(pts[i], kv, ":") != 2) continue
        if (kv[1] !~ /^[0-9.]+$/ || kv[2] !~ /^-?[0-9.]+$/) continue
        n++
        xs[n] = log10(kv[1] < 0.1 ? 0.1 : kv[1]); ys[n] = kv[2] + 0
    }
    if (n == 0) return 50
    for (i = 2; i <= n; i++)
        for (j = i; j > 1 && xs[j - 1] > xs[j]; j--) {
            tx = xs[j]; xs[j] = xs[j - 1]; xs[j - 1] = tx
            ty = ys[j]; ys[j] = ys[j - 1]; ys[j - 1] = ty
        }
    if (lf <= xs[1]) return ys[1]
    if (lf >= xs[n]) return ys[n]
    for (i = 1; i < n; i++) {
        if (lf <= xs[i + 1]) {
            t = (lf - xs[i]) / (xs[i + 1] - xs[i])
            return ys[i] + t * (ys[i + 1] - ys[i])
        }
    }
    return ys[n]
}

function smoothstep(t) { t = clamp(t, 0, 1); return t * t * (3 - 2 * t) }

function kelvin_for(lf,    lo, hi, t, k, kd) {
    lo = log10(kdim_lux); hi = log10(kbright_lux)
    t = (hi == lo) ? (lf >= hi) : smoothstep((lf - lo) / (hi - lo))
    kd = (tod == 1) ? tod_warm() : kdim             # the clock moves the dark-room end
    k = kd + t * (kbright - kd)
    k = round(k / kstep) * kstep
    return (kfloor != "" && k < kfloor + 0) ? kfloor + 0 : k
}

# Interpolate R:G:B from the calibration table "K:R:G:B,..." (any order).
function gains_for(k,    n, i, j, rows, f, K, R, G, B, tk, t) {
    n = split(table, rows, ",")
    for (i = 1; i <= n; i++) {
        split(rows[i], f, ":")
        K[i] = f[1] + 0; R[i] = f[2] + 0; G[i] = f[3] + 0; B[i] = f[4] + 0
    }
    # sort ascending by K (insertion sort, n is tiny)
    for (i = 2; i <= n; i++)
        for (j = i; j > 1 && K[j - 1] > K[j]; j--) {
            tk = K[j]; K[j] = K[j - 1]; K[j - 1] = tk
            tk = R[j]; R[j] = R[j - 1]; R[j - 1] = tk
            tk = G[j]; G[j] = G[j - 1]; G[j - 1] = tk
            tk = B[j]; B[j] = B[j - 1]; B[j - 1] = tk
        }
    if (k <= K[1]) { gr = R[1]; gg = G[1]; gb = B[1]; return }
    if (k >= K[n]) { gr = R[n]; gg = G[n]; gb = B[n]; return }
    for (i = 1; i < n; i++)
        if (k <= K[i + 1]) {
            t = (k - K[i]) / (K[i + 1] - K[i])
            gr = round(R[i] + t * (R[i + 1] - R[i]))
            gg = round(G[i] + t * (G[i + 1] - G[i]))
            gb = round(B[i] + t * (B[i + 1] - B[i]))
            return
        }
}

# Relative luminance of a gain set vs neutral, given the monitor's effective gain exponent.
function rel_luminance(r, g, b, nr, ng, nb) {
    return 0.2126 * (r / nr) ^ gamma + 0.7152 * (g / ng) ^ gamma + 0.0722 * (b / nb) ^ gamma
}

# ── Bias light (SPEC FR-61–FR-64, RESEARCH_08 §2–§3) ──
# Absolute level: wall luminance L = bias_nits (cd/m2) on a matte wall of reflectance rho needs
# wall illuminance E = pi * L / rho (lx). The strip % for E comes from inverting the measured
# table bias_cal = "pct:lux,..." (wall lux at each strip %, probe 07 check F), piecewise-linearly.
# Sets BIAS_E (target lx), BIAS_CAL_OK (1 if the table had ≥ 1 usable point) and returns the
# unrounded %. With no usable table: the fallback %, unrounded.
function bias_pct(nits, rho, cal, fallback,    raw, pts, kv, P, L, n, i, j, t, best, m, PP, LL) {
    if (rho + 0 <= 0) rho = 0.8
    BIAS_E = 3.14159265 * nits / rho
    raw = split(cal, pts, ",")
    n = 0
    for (i = 1; i <= raw; i++) {
        if (split(pts[i], kv, ":") != 2) continue
        if (kv[1] !~ /^ *[0-9.]+ *$/ || kv[2] !~ /^ *[0-9.]+ *$/) continue
        if (kv[1] + 0 <= 0 || kv[1] + 0 > 100) continue
        n++; P[n] = kv[1] + 0; L[n] = kv[2] + 0
    }
    BIAS_CAL_OK = (n > 0)
    if (n == 0) return fallback + 0
    for (i = 2; i <= n; i++)                       # sort by %
        for (j = i; j > 1 && P[j - 1] > P[j]; j--) {
            t = P[j]; P[j] = P[j - 1]; P[j - 1] = t
            t = L[j]; L[j] = L[j - 1]; L[j - 1] = t
        }
    # Monotonic: a reading below an earlier one (sensor noise) can't be inverted; drop it.
    m = 0; best = -1
    for (i = 1; i <= n; i++) if (L[i] > best) { m++; PP[m] = P[i]; LL[m] = L[i]; best = L[i] }
    if (BIAS_E <= LL[1]) return (LL[1] > 0) ? PP[1] * BIAS_E / LL[1] : PP[1]   # below the table: through the origin
    for (i = 1; i < m; i++)
        if (BIAS_E <= LL[i + 1])
            return PP[i] + (PP[i + 1] - PP[i]) * (BIAS_E - LL[i]) / (LL[i + 1] - LL[i])
    return PP[m]                                    # above the table: its brightest step
}

# The room decides on or off, with hysteresis: off above off_lux, back on below on_lux.
# prev = the last decision (1 on, 0 off, "" none yet: on unless above off_lux).
function bias_room_on(lf, prev, off_lux, on_lux,    lux) {
    lux = 10 ^ lf
    if (prev == "0") return (lux < on_lux) ? 1 : 0
    return (lux > off_lux) ? 0 : 1
}

# ── Time of day (SPEC FR-23) ────────────────────────────────────────────────
# Inputs: clock = "doy:minute:utcoffset" (e.g. "290:1215:+0200"), lat, lon (degrees, east +),
# bed = "HH:MM", knight (Kelvin), ramp (minutes), kdim, kbright.
function acos(x) { x = clamp(x, -1, 1); return atan2(sqrt(1 - x * x), x) }
function hhmm(s,    a) { return (split(s, a, ":") == 2) ? a[1] * 60 + a[2] : -1 }
function lerp(a, b, t) { t = clamp(t, 0, 1); return a + t * (b - a) }
# Sunrise and sunset in local minutes (NOAA's simple solar formulas, about ±2 min). Polar day or
# night clamps to "always up"/"never up". Sets SUNRISE and SUNSET.
function sun_times(doy, lat, lon, off,    pi, g, eqt, decl, rl, ha) {
    pi = atan2(0, -1); g = 2 * pi / 365 * (doy - 1)
    eqt = 229.18 * (0.000075 + 0.001868 * cos(g) - 0.032077 * sin(g) - 0.014615 * cos(2 * g) - 0.040849 * sin(2 * g))
    decl = 0.006918 - 0.399912 * cos(g) + 0.070257 * sin(g) - 0.006758 * cos(2 * g) + 0.000907 * sin(2 * g) \
         - 0.002697 * cos(3 * g) + 0.00148 * sin(3 * g)
    rl = lat * pi / 180
    ha = acos(cos(90.833 * pi / 180) / (cos(rl) * cos(decl)) - tan_(rl) * tan_(decl)) * 180 / pi
    SUNRISE = 720 - 4 * (lon + ha) - eqt + off
    SUNSET = 720 - 4 * (lon - ha) - eqt + off
}
function tan_(x) { return sin(x) / cos(x) }
# The warmest Kelvin the clock allows now: 6500 in the day; from sunset towards kdim, and from
# bedtime − 3 h towards knight (each over `ramp` minutes); held until the morning, then back to
# 6500 over `ramp` from sunrise, or from bedtime + 8 h if that's earlier (dark winter mornings).
function tod_warm(    c, m, off, sgn, bm, ls, ds, w, r) {
    if (split(clock, c, ":") != 3) return kdim
    m = c[2] + 0; sgn = (substr(c[3], 1, 1) == "-") ? -1 : 1
    off = sgn * (substr(c[3], 2, 2) * 60 + substr(c[3], 4, 2))
    sun_times(c[1] + 0, lat + 0, lon + 0, off)
    r = (ramp + 0 > 0) ? ramp + 0 : 60
    bm = hhmm(bed); if (bm < 0) bm = 23 * 60
    ls = (bm - 180 + 1440) % 1440; if (ls < 720) ls = 1440      # bedtime before 15:00: no late phase
    ds = (bm + 480) % 1440; if (SUNRISE < ds) ds = SUNRISE
    TOD_PHASE = "day"
    if (m < 720) {                                               # after midnight
        if (m < ds) { TOD_PHASE = "night"; return knight }
        if (m < ds + r) { TOD_PHASE = "morning"; return lerp(knight, kbright, (m - ds) / r) }
        return kbright
    }
    w = kbright
    if (m >= SUNSET) { w = lerp(kbright, kdim, (m - SUNSET) / r); TOD_PHASE = "evening" }
    if (m >= ls && lerp(kbright, knight, (m - ls) / r) < w) { w = lerp(kbright, knight, (m - ls) / r); TOD_PHASE = "night" }
    return w
}
function clock_str(m) { m = (m + 1440) % 1440; return sprintf("%02d:%02d", int(m / 60), int(m % 60)) }

BEGIN {
    if (cmd == "tod") {
        # awk -f engine.awk -v cmd=tod -v clock=... -v lat -v lon -v bed -v knight -v kdim -v kbright -v ramp
        w = tod_warm()
        printf "phase=%s\nwarm_end=%d\nsunrise=%s\nsunset=%s\n", TOD_PHASE, w, clock_str(SUNRISE), clock_str(SUNSET)
        exit
    }
    if (cmd == "biaspct") {
        # awk -f engine.awk -v cmd=biaspct -v bias_nits=5 -v bias_rho=0.8 -v bias_cal=... -v bias_fallback=5 -v bias_max=15
        p = bias_pct(bias_nits, bias_rho, bias_cal, bias_fallback)
        r = round(clamp(p, 1, (bias_max == "") ? 100 : bias_max))
        printf "bias=%d\ntarget_lux=%.1f\nexact_pct=%.2f\ncalibrated=%d\n", r, BIAS_E, p, BIAS_CAL_OK
        exit
    }

    if (cmd == "filter") {
        l = log10(lux < 0.1 ? 0.1 : lux)
        if (prev == "") { printf "%.4f\n", l; exit }
        tau = (l > prev) ? tau_up : tau_down
        a = 1 - exp(-dt / tau)
        printf "%.4f\n", prev + a * (l - prev)
        exit
    }

    if (cmd == "targets") {
        split(critical_gains, cg, ":")
        if (mode == "critical") {
            k = 6500; gr = cg[1]; gg = cg[2]; gb = cg[3]
            b = (critical_brightness == "") ? curve_eval(curve, lf) : critical_brightness
        } else {
            k = kelvin_for(lf)
            gains_for(k)
            # Never above neutral on any channel, whatever the table says.
            if (gr > cg[1] + 0) gr = cg[1] + 0
            if (gg > cg[2] + 0) gg = cg[2] + 0
            if (gb > cg[3] + 0) gb = cg[3] + 0
            b = curve_eval(curve, lf) + boffset
            if (actual_b != "") {
                # Lunar owns brightness: report its value (status and the sample log only).
                b = actual_b
            } else if (comp == 1) {
                # Compensate for the gains actually on the monitor (on_gains "r:g:b"), which
                # differ from the targets while a gain set is deferred or capped.
                if (split(on_gains, og, ":") == 3) y = rel_luminance(og[1], og[2], og[3], cg[1], cg[2], cg[3])
                else y = rel_luminance(gr, gg, gb, cg[1], cg[2], cg[3])
                if (y > 0) b = b / y
            }
        }
        b = round(clamp(b, bmin, bmax))
        # Bias: an absolute level, independent of screen brightness (FR-62). 0 = off.
        bias = round(clamp(bias_pct(bias_nits, bias_rho, bias_cal, bias_fallback), 1, (bias_max == "") ? 100 : bias_max))
        if (mode == "critical") {
            room = (bias_prev == "") ? 1 : bias_prev     # the override doesn't move the room decision
            bk = 6500                                     # FR-61
            if (bias_critical == "off") bias = 0
        } else {
            room = bias_room_on(lf, bias_prev, (off_lux == "") ? 60 : off_lux, (on_lux == "") ? 40 : on_lux)
            bk = k                                        # FR-63: the screen's target Kelvin
            if (!room) bias = 0
        }
        bk = clamp(bk, (gk_min == "") ? 2200 : gk_min, (gk_max == "") ? 6500 : gk_max)
        printf "kelvin=%d\nbrightness=%d\nred=%d\ngreen=%d\nblue=%d\nbias=%d\nbias_k=%d\nbias_room=%d\nbias_cal=%d\n", \
            k, b, gr, gg, gb, bias, bk, room, BIAS_CAL_OK
        exit
    }

    print "unknown cmd: " cmd > "/dev/stderr"
    exit 2
}
