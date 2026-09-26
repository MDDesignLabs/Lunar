#!/usr/bin/env python3
"""Analyse probe 05's measurements: how does the AOC's DDC gain map to light output?

Input CSV (from 05-gain-domain.sh):  channel,gain,lux     channel ∈ floor|red|green|blue

Method: with the other two gains at 0 and a full-screen white patch, the sensor sees one
primary only, so its spectrum is fixed and the sensor reading is proportional to that
channel's light output, whatever the sensor's spectral response. The ratio
    r(g) = (L(g) − floor) / (L(50) − floor)
is the channel's relative output at gain g. A monitor that scales linear light gives
r = g/50 (exponent ≈ 1). One that scales the gamma-encoded signal gives r = (g/50)^2.2.

    analyze_gain.py <csv> [--table "K:R:G:B,..."] [--primaries srgb|x,y,x,y,x,y]
"""
import argparse
import csv
import math
import statistics
import sys
from collections import defaultdict

SRGB = (0.64, 0.33, 0.30, 0.60, 0.15, 0.06)
D65 = (0.31271, 0.32902)


def rgb_to_xyz_matrix(prim, white=D65):
    xr, yr, xg, yg, xb, yb = prim
    cols = [(x / y, 1.0, (1 - x - y) / y) for x, y in ((xr, yr), (xg, yg), (xb, yb))]
    W = (white[0] / white[1], 1.0, (1 - white[0] - white[1]) / white[1])
    # Solve cols · S = W for the per-primary scales S (3×3, Cramer's rule).
    M = [[cols[j][i] for j in range(3)] for i in range(3)]

    def det(m):
        return (m[0][0] * (m[1][1] * m[2][2] - m[1][2] * m[2][1])
                - m[0][1] * (m[1][0] * m[2][2] - m[1][2] * m[2][0])
                + m[0][2] * (m[1][0] * m[2][1] - m[1][1] * m[2][0]))

    d = det(M)
    S = []
    for k in range(3):
        mk = [row[:] for row in M]
        for i in range(3):
            mk[i][k] = W[i]
        S.append(det(mk) / d)
    return [[M[i][j] * S[j] for j in range(3)] for i in range(3)]


def inv3(m):
    a, b, c = m[0]; d, e, f = m[1]; g, h, i = m[2]
    A, B, C = e * i - f * h, -(d * i - f * g), d * h - e * g
    D, E, F = -(b * i - c * h), a * i - c * g, -(a * h - b * g)
    G, H, I = b * f - c * e, -(a * f - c * d), a * e - b * d
    det = a * A + b * B + c * C
    return [[A / det, D / det, G / det], [B / det, E / det, H / det], [C / det, F / det, I / det]]


def mul(m, v):
    return [sum(m[i][j] * v[j] for j in range(3)) for i in range(3)]


def cct_mccamy(X, Y, Z):
    x, y = X / (X + Y + Z), Y / (X + Y + Z)
    n = (x - 0.3320) / (0.1858 - y)
    return 449 * n ** 3 + 3525 * n ** 2 + 6823.3 * n + 5520.33


def daylight_xy(T):
    if T <= 7000:
        x = -4.6070e9 / T ** 3 + 2.9678e6 / T ** 2 + 0.09911e3 / T + 0.244063
    else:
        x = -2.0064e9 / T ** 3 + 1.9018e6 / T ** 2 + 0.24748e3 / T + 0.237040
    return x, -3.0 * x * x + 2.870 * x - 0.275


class Response:
    """Measured relative output vs gain for one channel, piecewise-linear, anchored at (0, 0)."""

    def __init__(self, points):
        pts = sorted(set(points) | {(0, 0.0)})
        # enforce monotonic non-decreasing output
        out, best = [], 0.0
        for g, r in pts:
            best = max(best, r)
            out.append((g, best))
        self.pts = out

    def __call__(self, g):
        p = self.pts
        if g <= p[0][0]:
            return p[0][1]
        for (g0, r0), (g1, r1) in zip(p, p[1:]):
            if g <= g1:
                return r0 + (r1 - r0) * (g - g0) / (g1 - g0) if g1 != g0 else r1
        return p[-1][1]

    def inverse(self, r):
        p = self.pts
        for (g0, r0), (g1, r1) in zip(p, p[1:]):
            if r0 <= r <= r1 and r1 > r0:
                return g0 + (g1 - g0) * (r - r0) / (r1 - r0)
        return p[-1][0] if r > p[-1][1] else 0


def analyse(rows, table, prim):
    # Rows are in measurement order. Each channel uses the floor (all gains 0) measured
    # most recently before it, so slow room-light drift between channels is tracked.
    by = defaultdict(lambda: defaultdict(list))
    floors, cur, white = {}, None, None
    for ch, g, lux in rows:
        if ch == "floor":
            cur = lux
        elif ch == "white":
            white = lux
        else:
            floors.setdefault(ch, cur)
        by[ch][g].append(lux)
    if cur is None:
        sys.exit("no floor measurement")
    report, resp, gammas = [], {}, {}
    if white and floors.get("red") is not None and white > 0 and floors["red"] / white > 0.05:
        report.append(f"WARNING: black screen reads {floors['red'] / white * 100:.0f}% of white. Above ~5% the "
                      "floor subtraction is approximate (lux isn't additive); darken the room and rerun if you can.")
    for ch in ("red", "green", "blue"):
        if 50 not in by[ch]:
            sys.exit(f"no gain-50 reference for {ch}")
        floor = floors.get(ch)
        if floor is None:
            floor = cur
        ref = statistics.mean(by[ch][50]) - floor
        if ref <= 0:
            sys.exit(f"{ch}: no signal above floor; is the sensor facing the screen?")
        drift = (max(by[ch][50]) - min(by[ch][50])) / ref if len(by[ch][50]) > 1 else 0
        pts = [(g, (statistics.mean(v) - floor) / ref) for g, v in by[ch].items()]
        resp[ch] = Response(pts)
        exps = [math.log(r) / math.log(g / 50) for g, r in pts if 0 < g < 45 and r > 0]
        gammas[ch] = statistics.median(exps) if exps else float("nan")
        head = dict((g, r) for g, r in pts if g > 50)
        report.append(f"{ch:5s}: effective exponent {gammas[ch]:.2f}   "
                      f"(r at 40 = {resp[ch](40):.3f}; linear predicts 0.800, encoded 0.612)   "
                      f"reference drift {drift * 100:.1f}%")
        if head:
            # Real headroom gives at least 1.1× at 55 and 1.2× at 60 (linear light; more if
            # encoded). Demand clearly more than sensor noise: a few % isn't headroom.
            r55, r60 = head.get(55, 0), head.get(60, 0)
            has = r60 >= 1.10 and r55 >= 1.05
            report.append(f"       above 50: {r55:.3f}× at 55, {r60:.3f}× at 60 → "
                          + ("HEADROOM exists above 50" if has else "no headroom: 50 is the ceiling (values above clip)"))

    g_mean = 0.2126 * gammas["red"] + 0.7152 * gammas["green"] + 0.0722 * gammas["blue"]
    verdict = ("INCOMPLETE (a channel has no usable readings below gain 45; rerun)" if math.isnan(g_mean) else
               "LINEAR-LIGHT gain (≈1.0)" if g_mean < 1.4 else
               "GAMMA-ENCODED gain (≈2.2)" if g_mean > 1.8 else "IN BETWEEN (neither model; use the measured table)")
    report.append(f"\nRESULT Q3: {verdict}. Luminance-weighted exponent = {g_mean:.2f}")

    M = rgb_to_xyz_matrix(prim)
    Minv = inv3(M)
    report.append("\nWhat your gain table actually produces (assumes 50/50/50 = D65):")
    for K, R, G, B in table:
        s = [resp["red"](R), resp["green"](G), resp["blue"](B)]
        X, Y, Z = mul(M, s)
        report.append(f"  labelled {K:5d}K  {R}/{G}/{B}  → measured ≈ {cct_mccamy(X, Y, Z):5.0f}K, "
                      f"luminance {Y * 100:3.0f}%")

    corrected = []
    for K in (6500, 6000, 5500, 5000, 4500, 4000):
        x, y = daylight_xy(K)
        lin = mul(Minv, [x / y, 1.0, (1 - x - y) / y])
        ref = mul(Minv, [D65[0] / D65[1], 1.0, (1 - D65[0] - D65[1]) / D65[1]])
        lin = [a / b for a, b in zip(lin, ref)]
        m = max(lin)
        lin = [a / m for a in lin]
        gains = [round(resp[c].inverse(v)) for c, v in zip(("red", "green", "blue"), lin)]
        corrected.append(f"{K}:{gains[0]}:{gains[1]}:{gains[2]}")
    report.append("\nCorrected table for ~/.lighting/config.sh (daylight locus, measured response):")
    report.append(f'GAIN_TABLE="{",".join(corrected)}"')
    report.append(f"GAIN_GAMMA={g_mean:.2f}")
    return "\n".join(report), g_mean


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("csv")
    ap.add_argument("--table", default="6500:50:50:50,5500:50:47:44,5000:50:46:40,4500:50:44:36")
    ap.add_argument("--primaries", default="srgb")
    a = ap.parse_args()
    rows = []
    with open(a.csv) as f:
        for r in csv.DictReader(f):
            if r["lux"] not in ("", "nan"):
                rows.append((r["channel"], int(r["gain"]), float(r["lux"])))
    table = [tuple(int(v) for v in row.split(":")) for row in a.table.split(",")]
    prim = SRGB if a.primaries == "srgb" else tuple(float(v) for v in a.primaries.split(","))
    text, _ = analyse(rows, table, prim)
    print(text)


if __name__ == "__main__":
    main()
