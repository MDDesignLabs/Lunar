# TEST PLAN

Status: draft, 2026-09-26. The requirements (FR-/NFR-/US-) are defined in SPEC.md, and the task IDs in BUILD_PLAN.md.

**What exists today:**
- `lighting-prototype/test/run_tests.sh`: **63 checks, all passing**, against simulators. These are:
  - a fake ESPHome SSE sensor (`test/fake_sensor.py`);
  - a fake Govee strip on real UDP sockets (`test/fake_govee.py`);
  - a simulated AOC + TSL2591 that responds to gain writes (`test/fake_screen_sensor.py`);
  - mock `m1ddc` and `lunar` binaries (`test/mocks/`).
- Those tests prove logic, packet formats and probe plumbing. **They prove nothing about the real monitor.** The hardware tests in §3 do that.

---

## 1. Unit tests (pure functions)

The shell engine is covered by `run_tests.sh` §1–2. The Swift `Engine` must pass the same cases, plus the new ones below. Parity fixtures are generated from `engine.awk` (P2-T06).

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
| U-B06 | Your recovered curve at 1, 50, 100, 134, 300 and 800 lux | 29, 43, 45, 47, 68, 100 (computed this session from `engine.awk`) |

### Kelvin and gains (FR-20/21)

| ID | Case | Expected |
|---|---|---|
| U-K01 | 300 lx → 6500 K; 10 lx → 5000 K | Shell §1 |
| U-K02 | Quantisation | Kelvin % 250 == 0 |
| U-K03 | Floor | Never below 4000 K, whatever the config |
| U-G01 | Table interpolation 5250 K | 50/47/42 (shell §1) |
| U-G02 | K outside the table | Clamps to the end rows |
| U-G03 | No channel above neutral, for any K | `r ≤ nR, g ≤ nG, b ≤ nB` |
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
| U-O01 | Mode critical, any lux | Gains = `CRITICAL_GAINS`, K = 6500 |
| U-L01 | Compensation on, 5000 K row | Brightness rises (shell §1: 20 → 23) |

---

## 2. Integration tests

### DDC layer, with a mock transport (P4-T04)

| ID | Case | Expected |
|---|---|---|
| I-D01 | The same value twice | 1 transport call (shell §2) |
| I-D02 | Δ < dead-band | 0 calls |
| I-D03 | Second adaptive write inside the interval | Deferred |
| I-D04 | Forced (user) write inside the interval | Sent |
| I-D05 | Daily cap | Only `cap` attempts; the cap is logged once (shell §2) |
| I-D06 | Gain set with one channel changed | Only that channel is sent (shell §2) |
| I-D07 | 20 consecutive transport failures on one VCP | That VCP stops; UI state "fault" |
| I-D08 | Other DDC app running (a process named Lunar) | 0 calls; "blocked" logged once (shell §8) |
| I-D09 | Live lightd PID file / stale PID file | Blocked / not blocked (shell §7) |
| I-D10 | Concurrent writes from two tasks | Serialised; never interleaved (actor) |
| I-D11 | Write while the display is asleep | Not sent; after wake, one reapply (shell §8) |

### SSE client (P3)

| ID | Case | Expected |
|---|---|---|
| I-S01 | Stream with three sensor IDs | Only ambient values are delivered (shell §4) |
| I-S02 | Server stops sending | Stale within `STALE_SECS`; reconnect with backoff |
| I-S03 | Server restarts | Recovers without restarting the app |
| I-S04 | Malformed `data:` lines | Ignored |
| I-S05 | Bufferless delivery | Each sample arrives within 1 s of being sent (the awk buffering bug found earlier) |

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
| 02 24 h log | Q6, Q12 | FR-01, FR-02, NFR-07 (sensor side) |
| 03 reads | Q2, Q14 (baseline) | FR-42 verification path, FR-45 |
| 04 single write | Q1 | FR-41/FR-43 write-cycle count, NFR-04 |
| 05 gain domain | Q3, Q4, Q10 | FR-21 table, FR-12 `GAIN_GAMMA`, US-2 |
| 06 Part A | Q5 | FR-50/51 (is reapply-after-wake needed?) |
| 07 Govee | Q7 | FR-60/61 |
| install + log | Q8 | NFR-07 |

---

## 4. Manual QA checklist

Run it before each phase gate. Record pass/fail and write counts.

| ID | Scenario | Pass if |
|---|---|---|
| M-01 | Mac sleep 30 min, then wake | Correct gains and brightness within 15 s; exactly one reapply in the write log |
| M-02 | Display sleeps while the Mac stays awake (energy settings), then wake | Same as M-01; no writes while asleep |
| M-03 | Lock screen, then unlock | No writes while locked (if gated) and correct state after |
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
| FR-01 | — | I-S01, I-S03 | probe 02 |
| FR-02 | — | I-S02 | M-06, M-07 |
| FR-03 | U-F01–F05 | — | soak |
| FR-10 | U-B01–B06 | — | soak |
| FR-11 | U-N01–N04 | — | soak |
| FR-12 | U-L01 | — | probe 05 (`GAIN_GAMMA`) |
| FR-20 | U-K01–K03 | — | soak |
| FR-21 | U-G01–G03, U-C01–C02 | — | probe 05 |
| FR-22 | — | — | manual |
| FR-30 | U-O01 | — | M-08, M-09 |
| FR-31 | U-O01 | — | M-08, M-09 |
| FR-40 | — | I-D08, I-D09 | M-11 |
| FR-41 | — | I-D01–I-D06 | M-10, soak |
| FR-42 | — | I-D05 | soak |
| FR-43 | — | — | P4-T02 on hardware (Q9) |
| FR-44 | — | I-D10 | NFR-06 check |
| FR-45 | — | — | M-12 |
| FR-50 | — | I-D11 | M-01, M-03 |
| FR-51 | — | I-D11 | M-02 |
| FR-52 | — | — | M-04 |
| FR-60/61 | — | I-G01–G03 | probe 07 |
| FR-70/71 | — | — | P6-T03, P1-T07 reboot test |
| NFR-01 | — | — | M-08 timing, regression 1 |
| NFR-02 | — | — | a timed lamp-switch test |
| NFR-03 | — | — | soak |
| NFR-04 | — | I-D05 | soak |
| NFR-05 | — | I-D07 | M-06, M-12 |
| NFR-06 | — | I-D10 | manual (UI stays responsive during writes) |
| NFR-07 | — | — | probe 02, install + reboot |

---

## What not to test

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
