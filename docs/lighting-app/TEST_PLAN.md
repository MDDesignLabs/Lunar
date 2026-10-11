# TEST PLAN

Status: draft, 2026-09-26. The requirements (FR-/NFR-/US-) are defined in SPEC.md, and the task IDs in BUILD_PLAN.md.

**What exists today:**
- `lighting-prototype/test/run_tests.sh`: **127 checks, all passing**, against simulators (2026-10-11, after `light update` and the config migration, §10: 110 before, 97 before the RESEARCH_07 defaults and probe 08, 63 before the 2026-09-26 review fixes). One check (discovery over real multicast) prints SKIP instead where the machine has no multicast route, so the total there is 126. The full run takes about 4 minutes. The checks added in the 2026-09-26 review rounds and the 2026-10-11 hardware fixes were confirmed by reintroducing the bug each targets and seeing the suite fail. The probe 08 checks weren't mutation-tested, except the Part B small-spill check, which fails under the old 20% rule. Only one run at a time: the suite refuses to start while another is running, because the fake devices use fixed ports. These are:
  - a fake ESPHome SSE sensor (`test/fake_sensor.py`);
  - a fake Govee strip on real UDP sockets (`test/fake_govee.py`);
  - a simulated AOC + TSL2591 that responds to gain writes (`test/fake_screen_sensor.py`);
  - mock `m1ddc` and `lunar` binaries (`test/mocks/`).
- Those tests prove logic, packet formats and probe plumbing. **They prove nothing about the real monitor.** The hardware tests in §3 do that.

---

## 1. Unit tests (pure functions)

Only some of these have a shell check today (marked "shell §N"). The rest are specified here for the Swift `Engine` and have **no shell check yet**: U-F01, F03, F04, F05, B01, B02, B04, B05, B06, G02, N01–N04. (Corrected 2026-09-26: this said the shell suite covered all of §1.) Parity fixtures are generated from `engine.awk` (P2-T06). Note U-F04: the dt = 0 → 1 s rule lives in `bin/lightd`, not `engine.awk`, so the fixtures must apply it before calling the engine.

### Filter (FR-03)

| ID | Case | Expected |
|---|---|---|
| U-F01 | First sample, no previous value | Returns log10(lux) |
| U-F02 | Brightening vs darkening, same Δ | Brightening moves more than 3× further per step (shell §1 check) |
| U-F03 | lux = 0 or negative | Clamped to log10(0.1) = −1 |
| U-F04 | dt = 0 | Treated as 1 s (as in the shell); never divides by zero |
| U-F05 | Parity vs awk on 200 random (lux, prev, dt) triples | abs error < 1e-4 |

### Curve (FR-10)

| ID | Case | Expected |
|---|---|---|
| U-B01 | Below the first point / above the last | Clamps to the end values |
| U-B02 | Exactly on a point | That point's value |
| U-B03 | Malformed entry (`134`, `a:b`, empty) | Skipped (shell §1: "malformed … ignored") |
| U-B04 | Unsorted points | Sorted before interpolation |
| U-B05 | All entries malformed | Returns the fallback (50) rather than crashing |
| U-B06 | Your recovered curve (`0:21,13:31,23:34,39:39,71:41,80:44,100:45,135:47,160:49,190:54,224:58,313:69,565:91,702:99,800:100,1000:100`, Lunar's seed) at 1, 50, 100, 134, 300 and 800 lux, compensation off | 26, 40, 45, 47, 68, 100 (recomputed from `engine.awk`). *Corrected 2026-09-26:* the earlier 29/43 came from the corrupted paste with points 13–80 missing |

### Kelvin and gains (FR-20/21)

| ID | Case | Expected |
|---|---|---|
| U-K01 | 300 lx → 6500 K; 10 lx → 5000 K | Shell §1 |
| U-K02 | Quantisation | Kelvin % 250 == 0 |
| U-K03 | Floor | Never below `KELVIN_FLOOR` (4000 K), whatever the config (shell §1) |
| U-G01 | Table interpolation 5250 K | 50/47/42 (shell §1) |
| U-G02 | K outside the table | Clamps to the end rows |
| U-G03 | No channel above neutral, for any K | `r ≤ nR, g ≤ nG, b ≤ nB`, even if the table has a higher value (shell §1) |
| U-C01 | `CCT_to_xy_CIE_D(6504.38938305)` | (0.3127077, 0.3291128) ± 1e-6 (colour-science doctest, R03 §1) |
| U-C02 | McCamy at xy (0.3127, 0.3290) | 6505.08 ± 0.01 (colour-science doctest) |

### Nudge (FR-11, Android-style)

| ID | Case | Expected |
|---|---|---|
| U-N01 | Nudge at anchor lux A, then lux 1.59·A | Kept |
| U-N02 | Then lux 1.61·A or 0.39·A | Cleared (Android `SHORT_TERM_MODEL_THRESHOLD_RATIO = 0.6`) |
| U-N03 | Smoothing after inserting a user point | Curve stays monotonic; neighbours respect `permissibleRatio` |
| U-N04 | Clamps | ±50 |

### Override and luminance

| ID | Case | Expected |
|---|---|---|
| U-O01 | Mode critical, any lux | Gains = `CRITICAL_GAINS`, K = 6500 (shell §1 checks one lux value only) |
| U-O02 | Override after the adaptive cap is used up | Neutral still written, from `OVERRIDE_RESERVE`; adaptive stays stopped (shell §2, §8) |
| U-L01 | Compensation on, 5000 K row | Brightness rises (shell §1: 20 → 22 with `GAIN_GAMMA` 1.0, the default until probe 05; 23 with 2.2) |
| U-L02 | Compensation with the gains actually on the monitor (a deferred set) | No boost for gains not yet written (shell §1, §9) |
| U-A01 | Probe 05 analysis on synthetic data with 3% noise | Right verdict for exponents 1.0 and 2.2; no false "headroom" (shell §1) |
| U-B07 | Brightness clamp | Curve values outside [`BRIGHTNESS_MIN`, `BRIGHTNESS_MAX`] are clamped (shell §1; sets `BRIGHTNESS_MIN=5` explicitly since the default is now 0) |
| U-B08 | Example config defaults (RESEARCH_07) | 0.5 lux → brightness 0; 300 lux → 22 (shell §1). Added 2026-10-11. The compensation checks (U-L01, U-L02) now set `LUMINANCE_COMPENSATION=1` and the old seed curve explicitly, because the defaults are now 0 and a curve that is 0 in a dim room |
| U-A02 | Probe 08 analysis (via the simulated runs I-P01–I-P05) | Match verdict, recommended curve, drift and self-illumination verdict, on simulated data only |

---

## 2. Integration tests

### DDC layer, with a mock transport (P4-T04)

| ID | Case | Expected |
|---|---|---|
| I-D01 | The same value twice | 1 transport call (shell §2) |
| I-D02 | Δ < dead-band, no interval in play | 0 calls (shell §2) |
| I-D03 | Second adaptive write inside the interval | Deferred |
| I-D04 | Forced (user) write inside the interval | Sent |
| I-D05 | Daily cap, brightness and gains; failed attempts count | Only `cap` attempts; the cap is logged once (shell §2) |
| I-D06 | Gain set with one channel changed | Only that channel is sent (shell §2) |
| I-D07 | 20 consecutive transport failures on one VCP | That VCP stops; UI state "fault" |
| I-D08 | Other DDC app running (the suite uses a fake app name, so a real Lunar on the host doesn't interfere) | 0 calls; "blocked" logged once (shell §8) |
| I-D09 | Live lightd PID file / stale PID file | Blocked / not blocked. Shell §7 checks both for the probes (nothing written while a live lightd runs); §9 checks that a second lightd refuses to start |
| I-D10 | Concurrent writes from two tasks | Serialised; never interleaved (actor) |
| I-D11 | Write while the display is asleep | Not sent; after wake, one reapply. Shell §8 checks "not sent" and "writes resume", not "exactly one" |
| I-D12 | Adaptive gain set deferred by the interval, then lux stops moving | Applied once the interval passes (shell §2, §9) |
| I-D12b | Adaptive brightness write deferred by the interval, then lux stops moving | Applied once the interval passes (shell §9). Added 2026-10-11, found while reading the code for the first live run |
| I-D12c | Restart in a dim room right after the exit's neutral write | Warm gains applied at once, not after the gain interval (shell §9). Added 2026-10-11 from the first live run |
| I-D13 | Lock left by a dead process | Broken at once; a live owner is waited for ≤ 60 s, then the write is skipped (shell §2 checks the dead case) |
| I-D14 | Override blocked (another DDC app, reserve used up, write failure) | Command exits non-zero with the reason; status and menu show "not neutral", never "ON" (shell §8) |
| I-D15 | Override turned on while an adaptive set waits for the lock | The adaptive set is dropped (shell §2) |
| I-D16 | User writes in quick succession | Spaced ≥ 250 ms per control; the last value lands (shell §2) |
| I-D17 | A lock held by a live process | The write waits until it's released (shell §2) |
| I-D18 | Override on at start, sensor offline | Neutral written before any lux sample (shell §9) |
| I-D19 | Previous run didn't exit cleanly | Neutral written first (shell §9) |
| I-D20 | `BACKEND=lunar` | Lunar running is expected; BetterDisplay or MonitorControl alongside it is refused (shell §9) |

### SSE client (P3)

| ID | Case | Expected |
|---|---|---|
| I-S01 | Stream with three sensor IDs | Only ambient values are delivered (shell §4) |
| I-S02 | Server stops sending | Stale within `STALE_SECS`; reconnect with backoff |
| I-S03 | Server restarts | Recovers without restarting the app |
| I-S04 | Malformed `data:` lines | Ignored |
| I-S05 | Bufferless delivery | Each sample arrives within 1 s of being sent (the awk buffering bug found earlier) |
| I-S06 | Negative or non-numeric samples (Lunar's −1 without Pro) | Discarded, not read as darkness (shell §9) |

### Probe 08 against simulators (shell §7, added 2026-10-11)

The fake sensor follows KitGuru's brightness table (opt-in: `FAKE_BRIGHTNESS=1`). `FAKE_BEZEL=1` plus `FAKE_SELF=<fraction>` model a sensor at the bezel that the screen lights.

| ID | Case | Expected |
|---|---|---|
| I-P01 | Part A against a monitor that follows KitGuru's table | `RESULT Q16a: MATCHES`; the printed `BRIGHTNESS_CURVE` equals RESEARCH_07's; drift check OK |
| I-P02 | Baseline after Part A | Gains 50/47/44 and brightness 60 restored, not 50 or the last step |
| I-P03 | Write count | Part A: 23 (19 + 4 restore). Both parts: 30 (19 + 7 + 4 restore), as in the probe's header |
| I-P04 | White screen closed during Part A | `ABORTED`, no `RESULT Q16a`, baseline restored (same as M-14 for probe 05) |
| I-P05 | Part B, no self-illumination / screen adds light to the sensor | `negligible` / `significant` with the advice; baseline restored |
| I-P06 | Part B, a small spill in a dark room (over 20% of a ~0.6 lux floor) that can't move brightness | `negligible`: the verdict asks whether lightd's brightness would change by ≥ the dead-band, not whether the reading changed |

### Config migration and `light update` (shell §10, added 2026-10-11)

Temp dirs, a temp bare repo and clone, a temp `HOME` (no git identity, no launchd agent) and a stub `launchctl`. Never the real `~/.lighting` or the real checkout. Not mutation-tested.

| ID | Case | Expected |
|---|---|---|
| I-C01 | Stale config: seed curve with the corrupt `134`, `GAIN_GAMMA=2.2`, old example `GAIN_TABLE`, old defaults (`BRIGHTNESS_MIN=5`, `LUMINANCE_COMPENSATION=1`, `MONITOR_NITS_MAX=350`) | All removed |
| I-C02 | Values equal to the current defaults (`LUNAR` written as the expanded `$HOME/…`, empty `M1DDC_DISPLAY=""`) | Removed |
| I-C03 | A custom value (`BRIGHTNESS_MAX=90`) and comments | Kept; the header is added once |
| I-C04 | A line it can't parse (`FOO=$(…)`) | Left as it is and reported |
| I-C05 | Backup and log | One `config.sh.bak-YYYYMMDD-HHMMSS` holding the original; one summary line in `lightd.log` |
| I-C06 | Second run | No change, no second backup, "nothing to change" |
| I-C07 | Effective config after migration (`common.sh`) | RESEARCH_07 curve, measured `GAIN_TABLE`, `GAIN_GAMMA=1.23`, `BRIGHTNESS_MAX=90` |
| I-C08 | `M1DDC=…m1ddc-1x`, `BACKEND`/`LUX_SOURCE=lunar`, `STALE_SECS=300` with Lunar lux, a curve with a learned point | All kept; lightd's check finds nothing stale |
| I-C09 | lightd starts on a config with the seed curve and `GAIN_GAMMA=2.2` | One "overrides <KEY> with an old value; run bin/light update" line per stale key; none for `BRIGHTNESS_MAX=90` |
| I-U01 | `light update`, fast-forward available, and the new commit changes `bin/light` | Clone at upstream; new commits listed; the new `bin/light` ran the second phase |
| I-U02 | A dirty tracked file and an untracked `probe/results` file | Stash `light update <date>` kept, with the edit; working tree clean; `probe/results` untouched |
| I-U03 | Config after the update | `GAIN_GAMMA=2.2` removed, `BRIGHTNESS_MAX=90` kept, backup made |
| I-U04 | No launchd agent installed | `launchctl` never called |
| I-U05 | Agent plist present | Reloaded through `install.sh` (`launchctl bootstrap`) |
| I-U06 | Local commit + new upstream commit (diverged) | Stops with "diverged"; HEAD, stash list, the dirty edit and config.sh unchanged |
| I-U07 | Remote unreachable | Fetch tried 3 times, then stops; HEAD unchanged |

### Govee (P8)

| ID | Case | Expected |
|---|---|---|
| I-G01 | Brightness / Kelvin packets | Exact JSON arrives on :4003 (shell §3) |
| I-G02 | Discovery | Scan reply parsed from :4002 (shell §3) |
| I-G03 | Two strips | Both addressed; sends don't block the loop (the `wait` bug found earlier) |

---

## 3. Hardware tests: the probe kit

| Probe | Settles | Requirements it validates |
|---|---|---|
| 00 setup | Tools, m1ddc build, helper build, display found, licence | Prerequisite for all |
| Q9 check: `system_profiler SPHardwareDataType`, the port, `m1ddc display list detailed`, one read of VCP 0x10 | Q9 | FR-43 (chip address) |
| 02 24 h log | Q6, Q12 | FR-01, FR-02, NFR-07 (sensor side) |
| 03 reads | Q2, Q14 (baseline) | No FR directly: decides whether the app may ever read back (R02) |
| 04 single write | Q1 | NFR-04 (double send halves the wear budget) |
| 05 gain domain | Q3, Q4, Q10 | FR-21 table, FR-12 `GAIN_GAMMA`, US-2 |
| 06 Part A | Q5 | FR-50/51 (is reapply-after-wake needed?) |
| 07 Govee | Q7 | FR-60/61 |
| 08 brightness (optional) | Q16 (a: does the unit follow KitGuru's table, b: does the screen light the sensor) | FR-10 curve (RESEARCH_07) |
| install + log | Q8 | NFR-07 |

---

## 4. Manual QA checklist

Run it before each phase gate. Record pass/fail and write counts.

| ID | Scenario | Pass if |
|---|---|---|
| M-01 | Mac sleep 30 min, then wake | Correct gains and brightness within 15 s; exactly one reapply in the write log |
| M-02 | Display sleeps while the Mac stays awake (energy settings), then wake | Same as M-01; no writes while asleep. **Passed 2026-10-11** on the real AOC: no writes while asleep for 18 min, then one reapply 8 s after wake |
| M-03 | Lock screen, then unlock | Correct state after unlock. Writes while locked are allowed (FR-53: not lock-gated in v1) |
| M-04 | Unplug the monitor cable, then replug | No crash; transport rediscovered; values reapplied once |
| M-05 | Power the monitor off with its button, then on | Values correct after (depends on Q5) |
| M-06 | Unplug the ESP32 for 5 min | "Sensor offline" within 60 s; outputs held; recovers within 30 s of replug |
| M-07 | Turn Mac Wi-Fi off/on (the sensor path) | Same as M-06 |
| M-08 | Override on during rapid light changes (switch lamps every 10 s for 2 min) | Gains stay neutral throughout; 0 adaptive gain writes |
| M-09 | Override on → Mac restart | Still neutral after login, before any adaptive write |
| M-10 | Rapid light changes, override off | ≤ 1 gain set per 10 min; no brightness write closer than 60 s |
| M-11 | Open BetterDisplay while the app runs | Writes stop; "Paused: BetterDisplay"; resume after quitting it |
| M-12 | `kill -9` the app while it's warm | After relaunch, neutral first (FR-45) |
| M-13 | Sensor facing a lamp (saturation) | Values filtered; no wild jumps (firmware drops 65535) |
| M-14 | Click the white screen during probe 05 or 08 | Probe stops with "ABORTED", restores the monitor, prints no verdict |
| M-15 | Switch the room from ~300 to ~30 lux and back, timing each | Brightening within 3 units of target in ≤ 90 s; darkening per the NFR-02 decision |
| M-16 | Evening, room < 5 lx for 10 min, light bar off | Exactly one prompt (notification and popover row); "Not tonight" suppresses it until 06:00; turning the room lights on withdraws it; nothing ever switches the bar without a yes (FR-80–87) |

---

## 5. Soak test: one week

**Daily (2 minutes):**
- Today's write counts per VCP, from `writes.log` or the UI.
- The number of manual nudges and "warm now" uses.
- The number of times you thought the screen was wrong. Note the time and lux.
- Any "sensor offline" periods, from the log.

**At week's end, pass if:**
- **Averages:** ≤ 60 brightness writes a day, ≤ 15 per gain channel a day (NFR-04).
- **Reliability:** 0 wake glitches that needed a manual fix; 0 caps hit.
- **Comfort:** fewer than 2 manual corrections a day on average.
- **Sensor:** gaps < 1% of the time (compare with Q6).
- **Resources:** CPU < 1% averaged (Activity Monitor snapshot, NFR-03).

---

## 6. Regression: must keep working as features land

1. **Every phase:** the override writes neutral within 2 s, from any state (NFR-01).
2. **Every phase:** exactly one writer (M-11, I-D08, I-D09).
3. **Every DDC change:** caps and intervals hold (I-D01–I-D05).
4. **Every engine change:** the parity fixtures still pass (U-F05, U-B06, U-C01/02).
5. **Every change:** the shell suite `lighting-prototype/test/run_tests.sh` still passes while the shell is in use.

---

## 7. Traceability

| Requirement | Unit | Integration | Hardware / manual |
|---|---|---|---|
| FR-01 | — | I-S01, I-S03, I-S04, I-S05 | probe 02 |
| FR-02 | — | I-S02 | M-06, M-07 |
| FR-03 | U-F01–F05 | — | soak, M-13 |
| FR-04 | — | I-S06 | — |
| FR-10 | U-B01–B08 | — | probe 08, soak |
| FR-11 | U-N01–N04 | — | soak |
| FR-12 | U-L01, U-L02 | — | probe 05 (`GAIN_GAMMA`) |
| FR-20 | U-K01–K03 | — | soak |
| FR-21 | U-G01–G03, U-C01–C02, U-A01 | — | probe 05 |
| FR-22 | — | — | manual: pick each preset, check gains and that it clears on the next room change (P4-T09) |
| FR-30 | U-O01, U-O02 | I-D14, I-D18 | M-08, M-09 |
| FR-31 | U-O01 | I-D15 | M-08, M-09; code review: no path sets the mode to adaptive except `light critical off` / the UI toggle |
| FR-40 | — | I-D08, I-D09, I-D20 | M-11 |
| FR-41 | — | I-D01–I-D06, I-D12, I-D16 | M-10, soak |
| FR-42 | — | I-D05 | soak (FR-42 now asks only for writes sent; refusals are summarised in `lightd.log`) |
| FR-43 | — | — | Q9 check, then P4-T02 on hardware |
| FR-44 | — | I-D10, I-D13, I-D17 | NFR-06 check |
| FR-45 | — | I-D19 | M-12 |
| FR-50 | — | I-D11 | M-01, M-05 |
| FR-51 | — | I-D11 | M-02 |
| FR-52 | — | — | M-04 |
| FR-53 | — | — | M-03 |
| FR-60/61 | — | I-G01–G03; planned: discovery joins the multicast group, unicast scan, sender-address fallback | probe 07 (checks A–I, RESEARCH_08) |
| FR-62 | planned: wall-nits → % inversion through `BIAS_CAL` | — | probe 07 check F (wall calibration) |
| FR-63 | planned: Kelvin clamped to 2200–6500 | planned: no out-of-range `colorTemInKelvin` sent | — |
| FR-64 | — | planned: `turn 0` above `BIAS_OFF_LUX`, on display sleep, on clean exit | M-01, M-02 (bias off while asleep) |
| FR-65/66 | — | planned: ≤ 1 update per 2 s, coalescing, refresh without `turn 1` | soak |
| FR-67 | — | planned: "not responding" after 3 missed `devStatus` | unplug the bars |
| FR-80 | — | planned: no light-bar command without a yes, in any code path | code review + M-16 |
| FR-81/82/85 | planned: ask/suppress/withdraw state machine (lux, time, evening window) | — | M-16: an evening at < 5 lx for 10 min gives exactly one prompt |
| FR-83/84/86 | — | planned: remote-only sends nothing; a controllable model sends exactly one command | — |
| FR-87 | — | — | the popover row is shown with notifications denied |
| FR-70/71 | — | — | P6-T03, P1-T07 reboot test |
| NFR-01 | — | — | M-08 timing, regression 1 |
| NFR-02 | — | — | M-15 |
| NFR-03 | — | — | soak |
| NFR-04 | — | I-D05 | soak |
| NFR-05 | — | I-D07 | M-06, M-12 |
| NFR-06 | — | I-D10 | manual (UI stays responsive during writes) |
| NFR-07 | — | — | probe 02, install + reboot |

### User stories → requirements → tests (added 2026-09-26: the review found stories weren't traced)

| Story | Requirements | Where it's checked |
|---|---|---|
| US-1 Adaptive brightness | FR-01–FR-04, FR-10, FR-12, NFR-02 | M-10, M-15, soak |
| US-2 Warm white point | FR-20, FR-21, FR-41 | U-K*, U-G*, probe 05, soak |
| US-3 Override | FR-30, FR-31, FR-45, NFR-01 | U-O*, I-D14, I-D18, M-08, M-09, M-12 |
| US-4 Nudge | FR-11 | U-N*, soak |
| US-5 Safe by default | FR-41, FR-42, NFR-04, NFR-05 | I-D01–D07, soak |
| US-6 No fights | FR-40 | I-D08, I-D09, I-D20, M-11 |
| US-7 Bias light (deferred) | FR-60, FR-61 | I-G*, probe 07 |

---

## What not to build (tests)

- **A UI snapshot test suite.** One user; manual QA covers it.
- **Performance benchmarks** beyond the NFR-03 snapshot.
- **Multi-display, Intel, or any other monitor.**
- **Govee** before a strip exists.

---

## Assumptions

| Assumption | If wrong |
|---|---|
| The simulators model the real devices well enough for logic tests | Real-hardware bugs surface only in §3–5. Two already did (the awk buffering and the `wait` freeze were caught by simulators; the Space switching in probe 05 wasn't) |
| You'll fill in the soak log daily | The week can't pass or fail objectively |
| A mock DDC transport captures the scheduler's behaviour | Transport timing issues show up only on hardware (P4-T03) |
