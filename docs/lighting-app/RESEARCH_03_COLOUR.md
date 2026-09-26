# Research 03: Colour (CCT maths, white point, calibration)

Status: research, 2026-09-26. Source tags:

- **[src: colour-science …]**: files fetched from `colour-science/colour@develop` on 2026-09-26
- **[code: …]**: this repo
- **[derived]**: my own calculation
- **UNVERIFIED**: not checked; each one says what would settle it

---

## 1. Formulas (all cited)

**CIE daylight locus, x from CCT** [src: `colour/temperature/cie_d.py`, `CCT_to_xy_CIE_D`, citing Wyszecki & Stiles 2000]. The domain is 4000–25000 K; the code warns outside it.

```
4000 ≤ T ≤ 7000:   x = −4.6070e9/T³ + 2.9678e6/T² + 0.09911e3/T + 0.244063
7000 < T ≤ 25000:  x = −2.0064e9/T³ + 1.9018e6/T² + 0.24748e3/T + 0.237040
```

**Daylight locus, y from x** [src: `colour/colorimetry/illuminants.py`, `daylight_locus_function`]:

```
y = −3.000·x² + 2.870·x − 0.275
```

**McCamy 1992, CCT from xy** [src: `colour/temperature/mccamy1992.py`]:

```
n = (x − 0.3320)/(y − 0.1858);  CCT = −449n³ + 3525n² − 6823.3n + 5520.33
```

`probe/analyze_gain.py` uses the sign-flipped but algebraically identical form, `n' = (x−0.3320)/(0.1858−y)` with `+449n'³ + 3525n'² + 6823.3n' + 5520.33` [derived: substitute `n' = −n`].

**sRGB primaries and white** [src: `colour/models/rgb/datasets/srgb.py`; `…/illuminants/chromaticity_coordinates.py`]:
- R (0.6400, 0.3300), G (0.3000, 0.6000), B (0.1500, 0.0600)
- D65 (CIE 1931 2°) = (0.31270, 0.32900)

**CIE 1976 lightness** [src: `colour/colorimetry/lightness.py`]: `L* = 116·f(Y/Yn) − 16`.

These are implemented in `lighting-prototype/probe/analyze_gain.py` (daylight locus, McCamy, the sRGB matrix). `lib/engine.awk` doesn't compute CCT; it interpolates the measured `GAIN_TABLE`.

**Checked this session:** `analyze_gain.py` reproduces both colour-science doctests.
- `daylight_xy(6504.38938305)` returns (0.3127078, 0.3291128); expected (0.3127077…, 0.3291128…).
- McCamy at (0.3127, 0.3290) returns 6505.0806; expected 6505.0805913…

The Swift port must pass the same two cases (TEST_PLAN U-C01, U-C02).

**Why the daylight locus rather than the Planckian one** [derived]: D65 lies on the daylight locus. If you compute "6500 K" on the Planckian locus and map it to sRGB, you don't get equal gains. The earlier calculation gave 50/47/50, visibly greenish.

---

## 2. How a DDC gain turns into a white point: the unresolved question

**Two models:**
- **Linear-light:** the gain scales linear light, so output = g/50.
- **Gamma-encoded:** the gain scales the encoded signal, so output = (g/50)^2.2.

**What each model predicts for your derived rows** [derived by `analyze_gain.py` on simulated monitors; code-tested in `test/run_tests.sh` §7]:

| Your row | Linear-light gives | Gamma-encoded gives |
|---|---|---|
| "5500K" 50/47/44 | ≈ 6020 K, 95% luminance | ≈ 5530 K, 89% |
| "5000K" 50/46/40 | ≈ 5710 K, 93% | ≈ 5000 K, 85% |
| "4500K" 50/44/36 | **≈ 5400 K, 89%** | **≈ 4510 K, 79%** |

Your table matches the gamma-encoded column almost exactly, so it was derived assuming encoded-domain gains.

**Measurement status: still open.**
- The first hardware run of probe 05 (2026-09-26) is **invalid**. Every channel stayed at the ambient floor (~2.6 lux), whatever the gain.
- Cause: the probe told you to make Safari full screen, then press Enter in Terminal, which moved the monitor off Safari's full-screen Space.
- Fixed in commit `ca02c06`:
  - an always-on-top white window (`helpers/whitepatch.swift`);
  - a preflight that needs white − black > 20 lux and white > 5× black;
  - `caffeinate -d` to keep the display awake;
  - brightness raised to 80 during the probe;
  - the floor re-measured before each channel.
- UNVERIFIED: that `whitepatch.swift` compiles. It never has: the cloud container has no `swiftc`.

**Why the TSL2591 method works in principle** [derived]:
- With two gains at 0 and a full-screen white patch, only one primary emits. Its spectrum is fixed, so any linear sensor's reading is proportional to that primary's output, whatever the sensor's spectral response.
- **Assumption this needs:** the AOC accepts gain 0 and treats gains as independent per-channel multipliers. If gain 0 is clamped to some minimum, the floor measurement absorbs it, as long as it's the same for all gains.
- **Assumption this needs:** ESPHome's `calculated_lux` stays proportional to irradiance when the TSL2591's automatic gain changes range. UNVERIFIED. The ESPHome TSL2591 docs weren't reachable. *Settles it:* check the reference-drift line in probe 05's output. If the gain-50 readings for a channel differ by more than ~3%, suspect a range switch.

---

## 3. Luminance and headroom

- **Warming lowers luminance.** Y = 0.2126 R + 0.7152 G + 0.0722 B, using sRGB luminance weights. This is the middle row of the sRGB→XYZ matrix derived from the primaries above [derived].
- **Don't raise gains above neutral to compensate.** If 50 is the ceiling, higher values clip. Whether there's headroom above 50 is UNVERIFIED; probe 05 measures output at gains 55 and 60.
- **Compensate with the backlight instead.** `engine.awk` multiplies brightness by 1/Y_rel(gains), using `GAIN_GAMMA` [code]. It only works as well as `GAIN_GAMMA` is measured.

---

## 4. Primaries: the AOC isn't sRGB

- `analyze_gain.py` assumes sRGB primaries. UNVERIFIED: the CU34G4Z's real primaries.
- The EDID holds them, and the IORegistry `DisplayAttributes` exposes EDID-derived data [code: MonitorControl `Arm64DDC.getIORegServiceAppleCDC2Properties` reads `DisplayAttributes`].
- **Effect:** absolute Kelvin values in the corrected table are approximate. The linear-vs-encoded verdict doesn't depend on primaries [derived: the verdict comes from ratios within one channel].

---

## 5. What "True Tone" would need

- The TSL2591 reports lux, full-spectrum and infrared counts [code: `Lunar/ALS/tsl2591.yaml`]. None of these is a chromaticity.
- The adaptive white point here is therefore a **rule of thumb (dimmer means warmer)**, not ambient colour matching.
- Lunar ships a TCS34725 (an RGB colour sensor) config [code: `Lunar/ALS/tcs34725.yaml`]. Using one would be a hardware change. UNVERIFIED: whether TCS34725 readings can be converted to a reliable CCT; that would need its datasheet.

---

## 6. Calibration paths, cheapest first

1. **Probe 05 with the TSL2591** (free, 16 min). Gives the gain response curve and a corrected `GAIN_TABLE`.
2. **By eye, against a known D50/D65 reference** (free). Coarse. UNVERIFIED how coarse.
3. **Borrow a colorimeter** (e.g. i1Display). Gives absolute white-point xy per row. This is the only way to verify absolute Kelvin. The UNVERIFIED part is software support: whether DisplayCAL/ArgyllCMS runs on macOS 26.

---

## What not to build

- **Automatic gamut detection from EDID in v1.** Fixed sRGB primaries plus measured response curves are enough.
- **Kelvin below 4000 K.** The daylight formula's valid domain ends there [src: `cie_d.py`], and gains shift fast in that range.
- **Gains above neutral** to preserve luminance (§3).
- **"True Tone" branding, or colour matching to ambient,** without a colour sensor.
- **An in-app colorimeter workflow.** Use DisplayCAL once, then paste the table.

---

## Assumptions

| Assumption | If wrong |
|---|---|
| Neutral (true D65) is at 50/50/50 on the AOC in User mode | The override returns to the wrong white. The OSD shows 50/50/50 today, but that's the factory default, not a measured D65. UNVERIFIED without a colorimeter |
| Gains act as independent per-channel multipliers (some power law) | The corrected table built by interpolation could be off. Probe 05's measured curve partly covers this |
| sRGB primaries are good enough for relative CCT | Absolute Kelvin is off by an unknown amount |
| `calculated_lux` stays linear across TSL2591 range switches | Probe 05's curve bends. Watch the reference-drift line |
