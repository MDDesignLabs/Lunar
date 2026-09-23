#!/usr/bin/env python3
"""Synthetic probe-05 data for a monitor with a known gain exponent. Used to test analyze_gain.py.
    synth_gain.py <exponent> <headroom:0|1> [noise]"""
import random, sys
gam, headroom = float(sys.argv[1]), sys.argv[2] == "1"
noise = float(sys.argv[3]) if len(sys.argv) > 3 else 0.01
random.seed(7)
ref = {"red": 60.0, "green": 200.0, "blue": 25.0}
floor = 0.6
print("channel,gain,lux")
for _ in range(3):
    print(f"floor,0,{floor * (1 + random.gauss(0, noise)):.3f}")
for ch in ("red", "green", "blue"):
    for g in (50, 40, 30, 20, 45, 36, 25, 55, 60, 50):
        rel = (g / 50) ** gam
        if g > 50 and not headroom:
            rel = 1.0
        print(f"{ch},{g},{(floor + ref[ch] * rel) * (1 + random.gauss(0, noise)):.3f}")
