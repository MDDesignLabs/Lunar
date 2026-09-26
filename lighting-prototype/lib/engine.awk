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

function kelvin_for(lf,    lo, hi, t, k) {
    lo = log10(kdim_lux); hi = log10(kbright_lux)
    t = smoothstep((lf - lo) / (hi - lo))
    k = kdim + t * (kbright - kdim)
    return round(k / kstep) * kstep
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

BEGIN {
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
            b = curve_eval(curve, lf) + boffset
            if (actual_b != "") {
                # Lunar owns brightness: report its value, only use it for the bias light.
                b = actual_b
            } else if (comp == 1) {
                y = rel_luminance(gr, gg, gb, cg[1], cg[2], cg[3])
                if (y > 0) b = b / y
            }
        }
        b = round(clamp(b, bmin, bmax))
        nits = nits_min + (nits_max - nits_min) * b / 100
        bias = round(clamp(bias_k * nits, bias_min, bias_max))
        printf "kelvin=%d\nbrightness=%d\nred=%d\ngreen=%d\nblue=%d\nbias=%d\n", k, b, gr, gg, gb, bias
        exit
    }

    print "unknown cmd: " cmd > "/dev/stderr"
    exit 2
}
