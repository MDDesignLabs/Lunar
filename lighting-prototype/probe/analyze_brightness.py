#!/usr/bin/env python3
"""Analyse probe 08's measurements: how does the AOC's brightness setting map to light?

Part A CSV (brightness,lux): one "floor" row (white patch up, all gains 0), then a row per
brightness step. Brightness 50 appears twice (start of the sweep, and again at the end).
Part B CSV (screen,lux): a "white" row and a "black" row, sensor at its everyday spot.

    analyze_brightness.py <part-a.csv> [--self <part-b.csv>]
    analyze_brightness.py --self <part-b.csv>

Method (Part A): rel(b) = (lux(b) − floor) / (lux(100) − floor), the screen's light at
setting b relative to full. Compared with KitGuru's colorimeter table for this model
(RESEARCH_07 §2). Absolute cd/m² cannot be measured with a lux sensor; the recommended
curve ASSUMES this unit's 100% is KitGuru's 371.6 cd/m².
"""
import argparse
import csv
import math
import statistics
import sys

# KitGuru, AOC CU34G4Z review p.4, X-Rite i1Display Pro + Calman: OSD brightness % → cd/m².
KITGURU = [(0, 55.2), (25, 139.5), (50, 221.5), (75, 297.9), (100, 371.6)]
KG_MAX = 371.6
TOLERANCE = 0.05          # "matches the review" = within ±0.05 of relative luminance at every step
DRIFT_WARN = 0.05         # 50% read twice; more than 5% of the signal apart = something moved
SELF_NEGLIGIBLE = 0.20    # white − black under 20% of the black reading

# RESEARCH_07 §3 targets (cd/m²) at the lux points of the recommended curve.
# 200 lux is log-interpolated between 100 lux (80) and 300 lux (130). 2000 lux = max.
TARGETS = [(0, 20.0), (10, 30.0), (50, 60.0), (100, 80.0)]
TARGETS += [(200, 80.0 + (130.0 - 80.0) * math.log(200 / 100) / math.log(300 / 100))]
TARGETS += [(300, 130.0), (500, 160.0), (1000, 300.0), (2000, None)]


def interp(points, x):
    """Piecewise-linear through sorted (x, y) points, clamped at both ends."""
    if x <= points[0][0]:
        return points[0][1]
    for (x0, y0), (x1, y1) in zip(points, points[1:]):
        if x <= x1:
            return y0 + (y1 - y0) * (x - x0) / (x1 - x0) if x1 != x0 else y1
    return points[-1][1]


def kitguru_rel(b):
    return interp([(p, v / KG_MAX) for p, v in KITGURU], b)


def read_rows(path):
    rows = []
    with open(path) as f:
        for r in csv.reader(f):
            if not r or r[0] in ("brightness", "screen"):
                continue
            try:
                lux = float(r[1])
            except (IndexError, ValueError):
                continue
            if math.isnan(lux):
                continue
            rows.append((r[0], lux))
    return rows


def part_a(path):
    rows = read_rows(path)
    floors = [v for k, v in rows if k == "floor"]
    if not floors:
        sys.exit("no floor measurement in " + path)
    floor = statistics.mean(floors)
    by = {}
    seq50 = []
    for k, v in rows:
        if k == "floor":
            continue
        b = int(float(k))
        by.setdefault(b, []).append(v)
        if b == 50:
            seq50.append(v)
    if 100 not in by or 0 not in by:
        sys.exit("need readings at brightness 0 and 100")
    full = statistics.mean(by[100]) - floor
    out = [f"floor (black screen, gains 0): {floor:.2f} lux;  100% reads {statistics.mean(by[100]):.2f} lux"]
    if full < 20:
        out.append(f"WARNING: only {full:.1f} lux of screen light above the floor at 100%. The sensor probably isn't "
                   "seeing the screen (sensor window facing the glass, flat, centred?). Rerun before trusting this.")
    if full <= 0:
        print("\n".join(out))
        sys.exit("no signal above the floor; cannot compute relative luminance")

    rel = {b: max(0.0, (statistics.mean(v) - floor) / full) for b, v in sorted(by.items())}
    out.append("")
    out.append("  setting   lux    measured rel   KitGuru rel   difference")
    worst = (0.0, 0)
    for b in sorted(rel):
        kg = kitguru_rel(b)
        d = rel[b] - kg
        if abs(d) > abs(worst[0]):
            worst = (d, b)
        out.append(f"  {b:4d}%   {statistics.mean(by[b]):7.2f}     {rel[b]:6.3f}        {kg:6.3f}       {d:+.3f}")

    if abs(worst[0]) <= TOLERANCE:
        out.append(f"\nRESULT Q16a: MATCHES the KitGuru review within ±{TOLERANCE:.2f} at every step "
                   f"(largest difference {worst[0]:+.3f} at {worst[1]}%).")
    else:
        sign = "brighter" if worst[0] > 0 else "dimmer"
        out.append(f"\nRESULT Q16a: DIFFERS from the KitGuru review: up to {worst[0]:+.3f} at {worst[1]}% "
                   f"(this unit is {sign} there than the review's). Use the curve below, not the research one.")

    # Recommended curve: absolute luminance L(b) = rel(b) · 371.6 (ASSUMPTION: this unit's 100% = KitGuru's).
    # Enforce a non-decreasing response so noise can't make the inversion jump backwards.
    pts, best = [], 0.0
    for b in sorted(rel):
        best = max(best, rel[b])
        pts.append((b, best * KG_MAX))
    entries = []
    for lux, target in TARGETS:
        if target is None:
            br = 100
        else:
            br = invert(pts, target)
        entries.append((lux, br))
    last = 0
    curve = []
    for lux, br in entries:
        last = max(last, br)                       # never decreasing as the room gets brighter
        curve.append(f"{lux}:{last}")
    out.append("\nRecommended curve (ASSUMES this unit's 100% = 371.6 cd/m², KitGuru's measurement; a lux sensor")
    out.append("can't measure absolute cd/m². Targets: RESEARCH_07 §3, inverted through YOUR measured response):")
    out.append(f'BRIGHTNESS_CURVE="{",".join(curve)}"')
    out.append("BRIGHTNESS_MIN=0")

    if len(seq50) >= 2:
        first, last50 = seq50[0], seq50[-1]
        sig = first - floor
        drift = (last50 - first) / sig if sig > 0 else float("nan")
        verdict = "OK" if abs(drift) <= DRIFT_WARN else (
            "TOO MUCH: room light or the panel moved during the sweep; treat the table as ±"
            f"{abs(drift) * 100:.0f}% and rerun if it matters")
        out.append(f"\nDrift check: 50% read {first:.2f} lux at the start and {last50:.2f} lux at the end "
                   f"({drift * 100:+.1f}% of the signal): {verdict}.")
    return "\n".join(out)


def invert(pts, target):
    """Brightness % at which the (non-decreasing) luminance curve reaches target cd/m², rounded, 0–100."""
    if target <= pts[0][1]:
        return int(pts[0][0])
    for (b0, l0), (b1, l1) in zip(pts, pts[1:]):
        if target <= l1:
            b = b0 + (b1 - b0) * (target - l0) / (l1 - l0) if l1 > l0 else b1
            return max(0, min(100, int(round(b))))
    return 100


def part_b(path):
    rows = dict(read_rows(path))
    if "white" not in rows or "black" not in rows:
        sys.exit("need a white and a black reading in " + path)
    white, black = rows["white"], rows["black"]
    diff = white - black
    ratio = f"{white / black:.2f}×" if black > 0 else "n/a (black reads 0)"
    out = [f"Sensor at its everyday spot, brightness 50: white screen {white:.2f} lux, black screen {black:.2f} lux.",
           f"Difference {diff:+.2f} lux, ratio {ratio}."]
    if diff < SELF_NEGLIGIBLE * black or diff <= 0:
        out.append("RESULT Q16b: negligible. The screen adds under 20% to what the sensor reads, "
                   "so its own light isn't steering the brightness.")
    else:
        out.append("RESULT Q16b: significant. The screen is lighting the sensor; consider moving it or tell Claude.")
    return "\n".join(out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("part_a", nargs="?", help="Part A CSV (brightness,lux)")
    ap.add_argument("--self", dest="part_b", help="Part B CSV (screen,lux)")
    a = ap.parse_args()
    if not a.part_a and not a.part_b:
        ap.error("give a Part A CSV, --self <Part B CSV>, or both")
    if a.part_a:
        print(part_a(a.part_a))
    if a.part_b:
        if a.part_a:
            print()
        print(part_b(a.part_b))


if __name__ == "__main__":
    main()
