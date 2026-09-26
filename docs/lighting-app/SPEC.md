# SPEC: adaptive display and lighting (personal macOS app)

Status: draft, 2026-09-26. Evidence tags point to the research files (R01–R06), the prototype (`lighting-prototype/`), or hardware results you reported. **UNVERIFIED** marks anything not yet shown to be true.

---

## 1. Problem and user

**The user is one person:** a product designer at a single desk.

- **Hardware:**
  - Mac Studio (Apple Silicon; generation UNVERIFIED, see Q9), macOS 26.7.
  - AOC CU34G4Z (34" VA, 3440×1440), connected over a port that's also UNVERIFIED (Q9).
  - ESP32 + TSL2591 ambient sensor at `lunarsensor.local`.
- **The problem:**
  1. The monitor's backlight and white point don't follow the room.
  2. Lunar Pro used to do the brightness part, but the licence was an expired demo.
  3. Nothing adapts the white point, and colour-critical work needs a guaranteed-neutral state at one click.

**What exists today:**
- A shell prototype that does all of this, tested against simulators (63 checks), with no hardware calibration yet.
- Probe results from your Mac:
  - probe 00: m1ddc builds and sees the CU34G4Z; the display-sleep helper works;
  - probes 03 and 04 ran, but their results haven't reached this document;
  - probe 05's first run was invalid (R03 §2).

## 2. Goals

- **G1:** backlight follows room light, with no visible hunting.
- **G2:** white point warms as the room dims, and stays neutral in bright light.
- **G3:** one click gives a guaranteed neutral 6500 K state that no automation can undo.
- **G4:** the monitor's settings storage is never worn out by this app.
- **G5:** no conflicts. Exactly one program writes to the monitor at any time.
- **G6 (deferred until hardware is bought):** a bias light that tracks screen brightness.

## 3. Non-goals

These are explicit and firm:

- Multiple monitors, Intel Macs, or the built-in display.
- The App Store, sandboxing, or distribution to anyone else.
- True Tone-style ambient colour matching (the sensor measures lux, not colour; R03 §5).
- Contrast adaptation, software dimming, gamma tables, HDR/XDR.
- Permanent machine learning of preferences in v1 (R01 §5).
- Screen-content colour sync for the bias light (R05).
- Auto-exiting the colour-critical mode, ever.

---

## 4. User stories

**US-1: Adaptive brightness**
As the user, when the room light changes, my screen brightness follows within about a minute and a half, without flicker or hunting.
- AC1: A room step of ×10 lux brings brightness within 3 units of the curve target within 90 s (NFR-02).
- AC2: With steady light (±10%), there are 0 brightness writes over 10 minutes.

**US-2: Warm white point in the evening**
As the user, as the room dims my white point warms, in steps I don't notice.
- AC1: At ≤ 10 lx the target is 5000 K; at ≥ 300 lx it's 6500 K (the configured endpoints).
- AC2: Gains change in 250 K steps, at most once per 10 minutes.

**US-3: Colour-critical override**
As the user, one click locks the monitor at neutral, and it stays there until I click again, through sleep and restarts.
- AC1: Gains equal `CRITICAL_GAINS` within 2 s of the click.
- AC2: The state survives Mac sleep/wake, monitor sleep/wake and app relaunch.
- AC3: The state is shown by text and icon, not colour alone.

**US-4: "A bit brighter, please"**
As the user, I can nudge brightness, and the nudge holds until the lighting changes substantially.
- AC1: A nudge applies within 2 s.
- AC2: It's cleared once lux leaves the configured band (FR-11).

**US-5: Safe by default**
As the user, I can see that the app isn't wearing out my monitor, and it stops itself if something goes wrong.
- AC1: Today's write counts are visible.
- AC2: Adaptive writes stop when a daily cap is hit, and I'm told.

**US-6: No fights**
As the user, if I open BetterDisplay or Lunar, this app stops writing and tells me why.
- AC1: No writes while those apps run (FR-40).
- AC2: A visible "Paused: <App>" state.

**US-7: Bias light** (deferred, G6)
As the user, the strip behind the monitor dims with the screen and turns neutral in colour-critical mode.

---

## 5. Functional requirements

Each requirement is individually testable. TEST_PLAN §7 traces them.

### Lux input

- **FR-01** Read `sensor-ambient_light` from the ESP32's event stream (`SENSOR_URL`). Reconnect with backoff of 1 s doubling to 30 s. [R01 §1; prototype `bin/lightd`]
- **FR-02** If no sample arrives for `STALE_SECS` (default 60), hold all outputs, show "sensor offline", and keep reconnecting.
- **FR-03** Filter in log10 lux with an asymmetric EMA (τ 8 s brightening, 45 s darkening). Recompute targets only when the filtered value moves ≥ 0.04 decades. [R01 §4]

### Brightness

- **FR-10** Map filtered lux to brightness % with piecewise-linear interpolation in log10(lux), over configured points. Skip malformed points; sort by lux; clamp to [min, max]. [R01 §3.3; prototype `engine.awk`]
- **FR-11** Nudge: ±5 per action, clamped to ±50, applied immediately. It's cleared when lux leaves [anchor × 0.4, anchor × 1.6] (Android's default [R01 §3.2]; configurable). *Contradiction kept:* the prototype currently clears at ~0.32–3.2×.
- **FR-12** Optional luminance compensation: brightness × 1/Y_rel(gains), using the measured `GAIN_GAMMA`. [R03 §3]

### White point

- **FR-20** Lux → Kelvin: smoothstep between (`KELVIN_DIM_LUX`, `KELVIN_DIM`) and (`KELVIN_BRIGHT_LUX`, `KELVIN_BRIGHT`), quantised to `KELVIN_STEP`, with a floor of 4000 K. [R03 §1]
- **FR-21** Kelvin → R/G/B by linear interpolation over the measured `GAIN_TABLE`. No channel may exceed its neutral value. [R03 §3]
- **FR-22** "Warm now" presets apply a temporary Kelvin until the next adaptive recompute.

### Override

- **FR-30** Turning the override on:
  - writes `CRITICAL_GAINS` immediately (bypassing minimum intervals, but never the daily caps or no-op skip);
  - optionally freezes brightness at `CRITICAL_BRIGHTNESS`;
  - persists to disk;
  - is restored first on every launch and wake.
- **FR-31** No code path turns the override off except an explicit user action.

### DDC safety

- **FR-40** Refuse every monitor write while Lunar, BetterDisplay or MonitorControl is running, or while the shell `lightd` is live (checked by PID file). [R02 §5]
- **FR-41** Scheduler rules:
  - skip writes equal to the last value;
  - brightness dead-band ≥ 2 units;
  - minimum intervals: brightness 60 s, gain set 600 s;
  - daily caps: 200 brightness writes, 30 per gain channel, counted on every attempt.
- **FR-42** Log every attempt: time, VCP, value, result, duration.
- **FR-43** Pick the DDC chip address per display: `0x37`, or `0xB7` for MCDP29xx ports. [R02 §1.3]
- **FR-44** All DDC transactions run serially and never on the main thread. [R02 §1.4]
- **FR-45** On quit, write neutral gains. If the previous run didn't exit cleanly, write neutral before anything else.

### System events

- **FR-50** Mac sleep: stop writing. Mac wake: wait `WAKE_DELAY` (8 s), rediscover the transport, reapply current targets **once**. [R02 §3]
- **FR-51** Display sleep with the Mac awake: pause writes. Display wake: same as FR-50.
- **FR-52** Display reconfiguration (connect, disconnect, mode change): rediscover the transport before the next write.

### Bias light (deferred)

- **FR-60** Send brightness % and Kelvin to configured strip IPs over UDP :4003, rate-limited, re-sent every 60 s. [R05]
- **FR-61** In the override, the strip goes to 6500 K.

### Configuration

- **FR-70** On first run, import the prototype's `~/.lighting/config.sh` values.
- **FR-71** Launch at login (`SMAppService.mainApp`). [R04]

---

## 6. Non-functional requirements

- **NFR-01 Override latency:** ≤ 2 s from click to all three gains written.
  - [derived: 3 writes × ~50 ms + 2 × 100 ms gaps ≈ 0.35 s; the 2 s budget allows for double-send and a retry]
- **NFR-02 Adaptive latency:** a ×10 lux step reaches within 3 units of target in ≤ 90 s.
  - [derived: ~15 s firmware average + ~3τ = 24 s EMA + up to a 60 s write interval ≈ 99 s worst case]
  - *Contradiction:* this worst case is slightly over 90 s. Either accept ≤ 100 s, or let the first write after a large change bypass the interval.
- **NFR-03 Resources:** idle CPU < 1% averaged over 10 minutes; memory < 150 MB. These are targets, not measurements (UNVERIFIED).
- **NFR-04 EEPROM budget:**
  - hard caps as FR-41;
  - design target ≤ 60 brightness writes and ≤ 15 per gain channel per typical day [R02 §4];
  - worst case assumes every write costs a cycle.
- **NFR-05 Failure behaviour:**
  - sensor loss holds outputs;
  - DDC failures are counted, and writes stop for that VCP after 20 faults (Lunar's threshold [R02 §2]);
  - a crash never leaves the monitor warm after the next launch (FR-45).
- **NFR-06 Responsiveness:** the UI never blocks on DDC or network.
- **NFR-07 Unattended operation:** after a reboot, the app runs, reads the sensor and writes the monitor without user action. This includes the Local Network permission being in place [R04 §2].

---

## 7. Open questions

Each question has the probe or decision that closes it.

| # | Question | Closed by | Status |
|---|---|---|---|
| Q1 | Does the AOC need every write sent twice? | probe 04 | Run; **result not reported here** |
| Q2 | Do DDC reads match the OSD? | probe 03 | Run; **result not reported here** |
| Q3 | Are gains linear-light or gamma-encoded? | probe 05 (rerun) | Open. First run invalid (R03 §2) |
| Q4 | Is there headroom above gain 50? | probe 05 | Open |
| Q5 | Do sleep, input switching or power-off reset the gains? | probe 06 Part A | Open |
| Q6 | Is the ESP32 stream stable for 24 h? | probe 02 | Open |
| Q7 | Govee model, Kelvin range, protocol match | probe 07 | Deferred (no hardware) |
| Q8 | Can a launchd agent reach `lunarsensor.local`? | `./install.sh`, then check `lightd.log` [R04 §2] | Open. **TN3179 says agents aren't exempt** |
| Q9 | Mac Studio generation and AOC port (HDMI vs USB-C) | `system_profiler SPHardwareDataType`; the physical port; `m1ddc display list detailed` | Open. **Decides the DDC transport** [R02 §1.3] |
| Q10 | Does `whitepatch.swift` compile and stay on top? | probe 05 rerun | Open |
| Q11 | Is 50/50/50 truly D65 on this panel? | colorimeter, or accept | Open. Default: accept |
| Q12 | Does `power_save_mode: none` fix the Wi-Fi loss? | probe 02 before and after reflashing | Open |
| Q13 | How bright should the bias light be? | decision: calibrate by eye (R05 §2) | Decided, pending hardware |
| Q14 | Current OSD brightness and baseline | probe 03's `baseline.txt` | Mentioned as "30%" in passing; UNVERIFIED |
| Q15 | How many hours a week can you spend? | you | **Unknown. It changes every estimate in BUILD_PLAN** |

---

## What not to build

- Everything in §3 Non-goals.
- **A permanent learning curve** (Lunar-style or ML). Use Android-style short-term corrections plus hand-edited points [R01].
- **Smooth DDC transitions, repeated wake re-applies, and read-modify-write** [R02].
- **Kelvin below 4000 K,** and gains above neutral [R03].
- **Govee code** before a strip exists, the Govee cloud API, and ambilight [R05].
- **Settings UI** before Phase 7, a curve chart before a week of data, and a global-hotkey system [R06].

---

## Assumptions

| Assumption | If wrong |
|---|---|
| The AOC can be driven by an open DDC transport (Q9) | The native app is blocked at the transport; only BetterDisplay-class tools work |
| The TSL2591 method can measure the gain response (Q3, Q10) | White-point calibration needs a colorimeter or stays approximate |
| One user, one monitor, one room | Scope grows by at least 2× |
| You accept a slightly visible 2–3-unit brightness step now and then | Smoothing would have to be in-app, not over DDC; that's a design change |
