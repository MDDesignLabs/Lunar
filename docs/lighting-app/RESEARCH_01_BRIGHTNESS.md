# Research 01: Adaptive brightness (learning curve, perception, algorithm)

Status: research, 2026-09-26. Every claim is tagged with where it comes from:

- **[code: path]**: source code I have read, either in this repo or in a clone I made this session
- **[src: …]**: a fetched document
- **[derived]**: my own calculation, shown
- **UNVERIFIED**: not checked. It says what would settle it.

---

## 1. What the sensor actually delivers

**Hardware:** Adafruit ESP32 Feather V2 + TSL2591, running ESPHome. It publishes Server-Sent Events at `http://lunarsensor.local/events` (from your setup description, confirmed working by probe 00 on your Mac).

- **The events carry three sensors:** `sensor-ambient_light`, `sensor-tsl2591_full_spectrum_light` and `sensor-tsl2591_infrared_light` (your `curl` output, reported in chat).
- **The firmware Lunar ships for this sensor** samples once a second, drops the saturation values `65535` and `NaN`, and applies `sliding_window_moving_average` with `window_size: 15`, `send_every: 2` and `send_first_at: 2`, but only to `calculated_lux` (the ambient channel). [code: `Lunar/ALS/tsl2591.yaml`]
  - UNVERIFIED: that your board runs this exact config. The sensor IDs match it, but you may have flashed your own. *Settles it:* read the YAML you flashed.
- **What that means for the app** [derived]: a lux value every ~2 s, already averaged over the last ~15 s. A step change in the room reaches ~100% of its size in about 15 s at the sensor.
- **Wi-Fi power saving:** ESPHome's schema default for `power_save_mode` on ESP32 is `"light"` [code: `esphome/components/wifi/__init__.py`, fetched from `esphome/esphome@dev`, the `cv.SplitDefault(CONF_POWER_SAVE_MODE, … esp32="light" …)` line]. Lunar's `lunar.yaml` doesn't override it [code: `Lunar/ALS/lunar.yaml`]. That fits the 33% ping loss and 160–270 ms round trips you measured.
  - UNVERIFIED: that power saving causes gaps in the *event stream*, not just in ping. *Settles it:* probe 02 (24 h log), then reflash with `power_save_mode: none` and compare.

---

## 2. Perception: why the curve works in log-lux

- **CIE 1976 lightness** is a cube-root function of relative luminance: `L* = 116·f(Y/Yn) − 16` [code: `colour/colorimetry/lightness.py`, `lightness_CIE1976`, fetched from colour-science/colour@develop]. Perceived lightness is strongly compressive in luminance, so equal perceptual steps need roughly multiplicative luminance steps.
- **Room illuminance spans decades.** The design range runs from 0 to 1000 lux (Lunar's `LUX_TO_NITS` table stops at 1000 [code: `Lunar/Data/Display.swift:1336`]). A linear-lux curve would crush everything below ~50 lx into a few percent of its x-axis.
- **Both reference implementations lean towards log spacing:**
  - Lunar's seed lux values are 0, 13, 23, 39, 71, 80, 100, 135, 160, 190, 224, 313, 565, 702, 800, 1000 [code: `Display.swift:1336`]. They're roughly log-spaced at the low end only (0→13→23→39→71); 71→80→100 is not multiplicative. Corrected 2026-09-26: this said "spaced multiplicatively".
  - Android limits how steep the curve can get using the ratio `((lux₂+0.25)/(lux₁+0.25))^1.0` between neighbouring points [code: AOSP `BrightnessMappingStrategy.java`, `permissibleRatio`, `LUX_GRAD_SMOOTHING = 0.25f`, `MAX_GRAD = 1.0f`].
- **Conclusion** [derived]: interpolate in `log10(lux)`, with a small floor (the prototype uses 0.1 lx). That's what `lighting-prototype/lib/engine.awk` does.
- UNVERIFIED: a *specific* psychophysical exponent for "preferred screen brightness vs ambient lux". I found no primary source this session (Wikipedia was blocked). No value in this plan depends on one: the curve is empirical and gets tuned by you.

---

## 3. How the three implementations map lux to brightness and learn

### 3.1 Lunar (readable parts only; the core is encrypted)

- **Curve storage:** per display and per mode, `[AutoLearnMapping]` of (lux → brightness %), `sensorBrightnessMapping` [code: `Display.swift:1706–1711`].
- **Seed:** on Apple Silicon, when the curve is empty, Lunar builds it as `nitsToPercentageMapping` from `LUX_TO_NITS`, using the display's min and max nits [code: `Display.swift:576–580`, `1866`]. The conversion `nitsToPercentage` is **not** in the readable code.
- **Correction:** `insertBrightnessUserDataPoint(lux, value)` is ignored when the curve is locked, adaptive brightness is paused, or the display connected less than 5 s ago [code: `Display.swift:6617–6631`]. Otherwise it calls an encrypted `insertDataPoint(_:in:cliffRatio:cliffSourceDiff:)` with `cliffRatio: 2, cliffSourceDiff: 30, stopCliffDetectionBelow: 35` for sensor mode [code: `Display.swift:6652`].
- **The older readable insert** removes every point that would break monotonicity, then adds the new one [code: `Display.swift:4400–4423`].
- **A drag counts once:** `previousBrightnessMapping.setOrRefresh(…, expireAfter: 1)` makes a whole slider drag one edit [code: `Display.swift:6650`].
- **Any brightness set through the CLI is also learned** unless `adaptivePaused` is set. The CLI's `.brightness` case calls `insertBrightnessUserDataPoint` [code: `Lunar/Data/CLI.swift`, `handleDisplays`, `case .brightness`]. That's why the prototype's override pauses Lunar first.
- **Your actual Lunar curve** (read by your local session from `defaults export fyi.lunar.Lunar`):
  - `0:21, 13:31, 23:34, 39:39, 71:41, 80:44, 100:45, 135:47, 160:49, 190:54, 224:58, 313:69, 565:91, 702:99, 800:100, 1000:100`
  - Its lux values are exactly the 16 seed values, with nothing added and nothing missing. **It's most likely the untouched default, not learned data.** A correction adds a point at the current lux, rounded to 4 decimals [code: `Display.swift:4410`, `featureValue.rounded(to: 4)`, in the readable insert].
  - UNVERIFIED: whether the encrypted insert also moves neighbouring y values. If it does, some learning could hide inside seed x values.

### 3.2 Android (AOSP `BrightnessMappingStrategy`)

[code: `services/core/java/com/android/server/display/BrightnessMappingStrategy.java`, fetched from `aosp-mirror/platform_frameworks_base@main`, 2026-09-26]

- **A base curve (a spline) plus one user point.** `addUserDataPoint(lux, brightness)` stores `mUserLux` and `mUserBrightness`, and infers a *global* adjustment in [−1, +1].
- **The adjustment is a gamma:** `gamma = log(desired)/log(current)` and `adjustment = −log(gamma)/log(maxGamma)`. Below 0.1 or above 0.9 it's a simple difference (`inferAutoBrightnessAdjustment`).
- **The curve is rebuilt** with the user point inserted as a control point. `smoothCurve` then walks outwards and clamps neighbours, so brightness never rises faster than `permissibleRatio` and never breaks monotonicity (minimum step `MIN_PERMISSABLE_INCREASE = 0.004`).
- **Short-term model:** the user point is discarded once ambient lux leaves `[anchor·(1−0.6), anchor·(1+0.6)]`, i.e. 0.4×–1.6× (`SHORT_TERM_MODEL_THRESHOLD_RATIO = 0.6f`, `shouldResetShortTermModel`). There's also a timeout (`config_autoBrightnessShortTermModelTimeout`).
  - UNVERIFIED: the default timeout value. It's a device resource I didn't fetch.

### 3.3 This project's prototype

[code: `lighting-prototype/lib/engine.awk`, `lib/apply.sh`, `bin/light`]

- **Curve:** piecewise-linear in log10(lux). Malformed entries are skipped and points are sorted.
- **Correction:** `light brighter|dimmer` sets an additive offset (±50 max). It's dropped when filtered log-lux moves more than `OFFSET_RESET_DECADES = 0.5` from where it was set, which is about 0.32×–3.2×.
- **Contradiction, kept visible:** the prototype's reset window (~0.32×–3.2×) is wider than Android's 0.4×–1.6×: about **2× wider on the upper side** (3.16 vs 1.6), and **1.66× wider in log terms** (1.0 decade vs 0.60 decades total) [derived: 10^±0.5; log10(1.6/0.4) = 0.60]. Corrected 2026-09-26: this said "roughly 5× wider", which was wrong. Neither has been tested against you. The wider window means one nudge persists across larger room changes, for better or worse.

### 3.4 Comparison

| | Lunar | Android | Prototype |
|---|---|---|---|
| Base curve | Seed from nits table | Device config spline | Config points, log-lux linear |
| Correction model | Local point insert + neighbour deletion ("cliff" logic encrypted) | Global gamma + local control point + smoothing | Global additive offset |
| Correction lifetime | Permanent | Short-term (0.4×–1.6× lux, or timeout) | Until lux moves ~3× |
| Monotonic guarantee | Yes (deletes violators) | Yes (clamps neighbours) | Only if you write a monotonic curve |

---

## 4. Filtering and transitions

- **Prototype filter:** EMA in log-lux with τ = 8 s when the room brightens and 45 s when it darkens, then a 0.04-decade dead-band before recomputing [code: `engine.awk` `cmd=filter`; `bin/lightd`].
  - UNVERIFIED: that these constants feel right. They're design guesses. *Settles it:* a week of use plus the probe 02 lux log.
- **Lunar's output smoothing writes many intermediate DDC values.** `smoothTransition` starts at one unit per write and grows the step (up to 100) when writes are slow, to keep each write near 90 ms. On a fast bus that's one write per unit; on a slow one, fewer, larger steps (corrected 2026-09-26: this said "one unit at a time" without the growth) [code: `Display.swift:5875–5950`, `MAX_SMOOTH_STEP_TIME_NS`]. That's the wear risk discussed in RESEARCH_02.
- **Prototype output:** jumps directly to the target, at most one adaptive write per 60 s and only when the change is ≥ 2 units [code: `config.example.sh`, `lib/ddc.sh`]. Expect a visible 2–3-unit step occasionally.

---

## 5. Recommendation for the Swift app

1. **Port the prototype's filter and log-lux curve unchanged** as a pure Swift module, with tests that compare its output to `engine.awk` point by point (parity tests, see TEST_PLAN).
2. **Replace the additive offset with Android's model:**
   - one user point;
   - a global gamma adjustment;
   - neighbour smoothing with a permissible ratio;
   - a short-term reset.
   Start with Android's 0.6 ratio, and make it configurable, because the prototype's wider window is the other candidate.
3. **Don't ship permanent learning in v1.** Your recovered Lunar curve shows that two weeks of Lunar Pro produced no stored learning. That's weak evidence that permanent learning matters less than expected. A short-term correction plus hand-editing the curve covers the same need.
4. **Seed the curve** from your Lunar default until a week of probe 02 logs and nudges suggests changes.

---

## What not to build

- A reimplementation of Lunar's encrypted "cliff detection". It can't be read, and Android's smoothing is documented and readable.
- Contrast adaptation. Changing contrast over DDC on a VA panel reduces native contrast, which is the panel's main strength (PLAN.md §5). UNVERIFIED on the AOC specifically.
- Spline interpolation. Piecewise-linear is monotonic by construction, whereas a cubic spline can overshoot between points [derived].
- Smooth DDC transitions (RESEARCH_02).
- A curve editor before there's a week of data.

---

## Assumptions

| Assumption | If wrong |
|---|---|
| Your ESP32 runs Lunar's `tsl2591.yaml` (15-sample average, 2 s publish) | Filter time constants and probe 05's settle time (17 s) are wrong. Probe 05 could be under-settled |
| Log-lux interpolation suits you | Curve points need different spacing. It's cheap to change |
| Your Lunar curve is the untouched seed | You'd be discarding a few real preferences. Small loss |
| Android's 0.4×–1.6× reset is a reasonable starting point for a desk | Nudges disappear too often or too rarely. It's configurable |
| The DDC brightness 0–100 maps roughly linearly to nits on the AOC | The bias-light maths (RESEARCH_05) and luminance compensation (RESEARCH_03) are off. UNVERIFIED: measure with the TSL2591 against the white patch at several brightness values |
