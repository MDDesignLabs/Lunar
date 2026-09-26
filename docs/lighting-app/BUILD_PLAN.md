# BUILD PLAN

Status: draft, 2026-09-26. The requirements (FR-/NFR-) and open questions (Q-) are defined in SPEC.md.

## How to read the estimates

- **Hours are ranges for someone learning Swift, using AI pair-programming.**
  - The low end assumes things work the first time.
  - The high end assumes one real snag per task: a signing issue, an unfamiliar concurrency error, or a hardware surprise.
- **Guess about you:** I don't know your weekly hours (Q15), or how quickly Swift will click for a designer who reads code but hasn't shipped it.
  - Phases 1–2 carry the learning curve.
  - If Swift comes easily, those phases land near the low end; otherwise the high end or beyond.
  - Later phases get cheaper once the patterns are familiar.
- **Difficulty levels:**
  - **routine:** well-trodden, documented.
  - **needs research:** the approach is known, but details need checking against docs or hardware.
  - **genuinely hard:** hardware- or OS-dependent, with failure modes nobody documents.

Every phase ends with something you can use, and a decision point.

### Basis for the ranges (added 2026-09-26: the review found most tasks gave no reasoning)

The numbers are judgement, not measurements. This is what each phase's range rests on:

| Phase | What the range is based on |
|---|---|
| P0 | Hands-on time per probe, from the probes' own timings (README table), plus config and install work already done once in this project |
| P1 | First Xcode project and signing for someone new to it (the high end), then small SwiftUI views over files that already exist |
| P2 | The code to port is small and fully specified: `engine.awk` is 127 lines, with fixtures to test against. The Android nudge (P2-T05) is the unknown |
| P3 | One async stream client. The format and a fake server already exist (`test/fake_sensor.py`); Local Network behaviour is the risk |
| P4 | m1ddc's transport is ~350 lines of Objective-C (`ioregistry.m` 266, `i2c.m` 86) calling private IOKit APIs. Porting unfamiliar low-level code, with hardware-only failures, is why the high end is 2–3× the low end |
| P5 | Three system-notification hooks; the C reconfiguration callback is the unfamiliar part |
| P6–P8 | Mostly wiring existing pieces together; ranges are small because the hard parts land earlier |

---

## Phase 0: Finish and live with the shell system (no Swift)

**Goal:** a calibrated shell system running your desk, and answers to Q1–Q6, Q8–Q10, Q12 and Q14.

| ID | Task | Deps | Acceptance criteria | Hours | Difficulty |
|---|---|---|---|---|---|
| P0-T01 | Report probe 03 and 04 results to the planning docs | — | Q1, Q2 and Q14 marked answered in SPEC §7, with values | 0.25–0.5 | routine |
| P0-T02 | Establish the Mac Studio chip and the AOC port (Q9) | — | Chip, port, and m1ddc's chip address (0x37/0xB7) recorded | 0.25–0.5 | routine |
| P0-T03 | Rerun probe 05 with the new white window | P0-T01 | Preflight passes; `RESULT Q3` line present; reference drift < 3% per channel. **If the preflight fails twice, stop and decide on a colorimeter** | 1–3 (the sensor setup is fiddly; 3 h if the helper fails to build) | needs research |
| P0-T04 | Probe 06, Part A only | P0-T01 | KEPT/RESET recorded for sleep, input switch and power | 0.5 | routine |
| P0-T05 | Write `~/.lighting/config.sh` from the results | P0-T01, P0-T02, P0-T03, P0-T04 | Values set: `M1DDC`, `GAIN_TABLE`, `GAIN_GAMMA`, `CRITICAL_GAINS` and curve, with a comment on where each came from | 1–2 | routine |
| P0-T06 | Install `lightd` and test Local Network as an agent (Q8) | P0-T05, P0-T09 | Either the log shows lux arriving under launchd for 1 h, **or** Q8 is marked "blocked" with log evidence | 0.5–2 | needs research |
| P0-T07 | If T06 is blocked: switch to a workaround | P0-T06 | `lightd` runs unattended after logout and login. Options: a Terminal-launched session, or a launchd *daemon* (R04 §2) | 2–6 (the daemon route has root/DDC unknowns) | genuinely hard |
| P0-T08 | SwiftBar item plus the override Shortcut with a hotkey | P0-T06 (or P0-T07, if T06 is blocked) | The override toggles from the menu bar and the hotkey in < 2 s (NFR-01) | 1–2 | routine |
| P0-T09 | Probe 02, 24 h, **before** T06 (single client) | — | `RESULT Q6` recorded; lux CSV saved | 0.5 hands-on | routine |
| P0-T10 | Optional: reflash the ESP32 with `power_save_mode: none` (Q12) | P0-T09 | A second probe 02 run is compared with the first | 1–4 (the ESPHome toolchain is new to you) | needs research |
| P0-T11 | One-week soak (TEST_PLAN §5) | P0-T05, P0-T06, P0-T08 | The daily soak checklist is filled for 7 days | 0.25/day | routine |

**Usable at the end:** adaptive brightness and white point, the override, EEPROM-safe writes, a menu bar item and a hotkey. This is the "~75%" configuration from VERDICT.md.

**Phase total:** about 7–13 h of hands-on time without the conditional P0-T07 and the optional P0-T10; 10–23 h with both. Plus at least two weeks of use (see D0). Corrected 2026-09-26: this said 8–22 h, which counted T07 and T10 in the low end.

**Contradiction flagged 2026-09-26:** PLAN.md §5 #11 says no hotkeys or Shortcuts for the first month. P0-T08 schedules one now. P0-T08 stands: the brief makes a one-click override non-negotiable, and a Shortcut or the menu bar is the only one-click path the shell has. PLAN.md's rule is superseded for the override only; other shortcuts still wait.

**Decision point D0**, after **at least two weeks** of use. Corrected 2026-09-26: this said one week, which contradicted VERDICT.md (2–4 weeks) and RESEARCH_05 (a Govee decision after two weeks). The one-week soak (P0-T11) is part of it.
- Stop here if the soak shows fewer than 2 manual fixes a day, no wake glitches, and T06 passed.
- Continue if T06 needed an awkward workaround, wake behaviour is poor, or you want to learn Swift.
- **Also decide here:** colorimeter or not (if T03 failed), and whether to buy Govee (R05 §3).
- **Buying Lunar Pro is not an option here any more**, though VERDICT.md and HANDOFF.md listed it. The recovered curve was Lunar's untouched seed, so there's no learned curve to keep, and the Android-style nudge replaces learning (R01). Reconsider only if the shell's brightness proves worse than Lunar's was, over the two weeks.

---

## Phase 1: Native menu bar companion (read-only, Swift)

**Goal:** a Swift app that *shows* the shell's state and calls `bin/light`. The shell still does all the hardware work.

| ID | Task | Deps | Acceptance criteria | Hours | Difficulty |
|---|---|---|---|---|---|
| P1-T01 | Xcode project: SwiftUI app, `LSUIElement`, macOS 14 target | D0 (a decision, not a task) | Builds and runs with no Dock icon | 2–6 (first Xcode setup and signing) | needs research |
| P1-T02 | `MenuBarExtra(.window)` with a placeholder layout (R06 §3) | P1-T01 | Popover opens from the menu bar | 2–5 | routine |
| P1-T03 | Read `~/.lighting/state/*` every 2–5 s into an `@Observable` model | P1-T02 | Mode, Kelvin, lux and today's counts match `bin/light status` | 3–8 | routine |
| P1-T04 | Override button runs `bin/light critical toggle` | P1-T03 | The toggle works; the UI reflects the new mode within 5 s | 2–5 (Process/sandbox surprises) | needs research |
| P1-T05 | Nudge buttons run `bin/light brighter/dimmer` | P1-T04 | ±5 applied; offset shown | 1–3 | routine |
| P1-T06 | Status states and icon per R06 §3 (stale, blocked, asleep, cap) | P1-T03 | Each state is shown when its state file says so; no colour-only cues | 3–8 | routine |
| P1-T07 | Launch at login (`SMAppService.mainApp`) | P1-T01 | Survives a reboot | 1–3 | needs research |
| P1-T08 | Stable code-signing identity: a free Apple ID personal team at minimum, not "Sign to Run Locally" (R04 §4, TN3179) | P1-T01 | After one local network call is allowed, the Local Network grant persists across two rebuilds | 0.5–2 | needs research |

**Usable at the end:** a native menu bar UI in place of SwiftBar.

**Phase total:** 14.5–40 h (P1-T08 added 2026-09-26; was 14–38). **Decision D1:** is Swift workable for you? If P1 went past about 40 h, reconsider continuing.

---

## Phase 2: The engine in Swift (pure, tested)

| ID | Task | Deps | Acceptance criteria | Hours | Difficulty |
|---|---|---|---|---|---|
| P2-T01 | Swift package `Engine`, with a test target | P1-T01 | `swift test` runs | 1–3 | routine |
| P2-T02 | Port the filter (FR-03) | P2-T06 | Parity vectors from `engine.awk cmd=filter` within 1e-4 (TEST_PLAN U-F*) | 2–4 | routine |
| P2-T03 | Port the curve (FR-10), including skipping malformed points and sorting | P2-T06 | U-B* pass, including the `134` malformed case | 2–4 | routine |
| P2-T04 | Port Kelvin + gains (FR-20/21) | P2-T01 | U-K*, U-G* pass; doctest vectors U-C01/C02 pass | 3–6 | routine |
| P2-T05 | Android-style nudge (FR-11), replacing the additive offset | P2-T03 | U-N* pass (reset at 0.4×/1.6×, smoothing stays monotonic) | 4–10 (porting `smoothCurve` and `inferAutoBrightnessAdjustment`) | needs research |

Clarified 2026-09-26: "no spline curves" (What not to build) still holds. Android's `smoothCurve` adjusts the neighbours of the user's point by a permissible ratio; it isn't a spline, and it's applied here to the piecewise-linear curve. Android's own base curve is a spline, and that part is not ported.
| P2-T06 | Parity-vector generator script (awk → JSON fixtures), **done first after T01** | P2-T01 | Fixtures generated from `engine.awk` for filter, curve, Kelvin and gains; committed; a test target can load them | 2–4 | routine |

Corrected 2026-09-26: P2-T06 depended on P2-T02, while T02/T03's parity ACs needed its fixtures: a hidden cycle. T06 now depends only on T01, and T02/T03 depend on T06. The ID is kept so TEST_PLAN references still resolve.

**Usable at the end:** nothing new on screen. P1 is still the working system. **Phase total:** 14–31 h. **D2:** proceed if the parity tests pass.

---

## Phase 3: Native sensor client

| ID | Task | Deps | Acceptance criteria | Hours | Difficulty |
|---|---|---|---|---|---|
| P3-T01 | `LuxClient`: `URLSession.bytes(from:)`, parse `data:` lines, filter by ID (FR-01) | P2-T02 | Against `test/fake_sensor.py`: correct values, and other sensor IDs ignored | 3–8 (async sequences are new) | needs research |
| P3-T02 | Reconnect/backoff + stale state (FR-02) | P3-T01 | Killing the fake sensor shows "offline" within `STALE_SECS`, then recovers | 2–5 | routine |
| P3-T03 | `NSLocalNetworkUsageDescription` + `waitsForConnectivity` (R04 §2) | P3-T01 | First run on your Mac shows the prompt; allowed after reboot (NFR-07) | 1–4 | needs research |
| P3-T04 | The app shows its own lux next to `lightd`'s | P3-T02 | The two agree within the sensor's noise over 1 h | 1–2 | routine |

**Usable at the end:** the app reads the sensor itself, which resolves Q8 natively. **Phase total:** 7–19 h. **D3:** if Local Network behaves, the app can own the sensor.

---

## Phase 4: DDC in Swift, gains and override only (the hard one)

| ID | Task | Deps | Acceptance criteria | Hours | Difficulty |
|---|---|---|---|---|---|
| P4-T01 | Bridging header for the IOAVService declarations (R02 §1.1) | P1-T01 | Compiles; the symbols link | 1–3 | needs research |
| P4-T02 | IORegistry walk to find the AOC's `DCPAVServiceProxy`, and pick 0x37/0xB7 (FR-43) | P4-T01, P0-T02 (answers Q9) | Finds exactly one external service; the chip address matches m1ddc's | 6–16 (the IORegistry API is unfamiliar; port from `m1ddc/sources/ioregistry.m`) | genuinely hard |
| P4-T03 | Write and read packets with checksum; write-cycle count from Q1 | P4-T02 | `set blue 40` visibly lands; reading it back matches (if Q2 says reads work) | 4–10 | genuinely hard |
| P4-T04 | `DDCWriter` actor: scheduler rules FR-41, caps, write log FR-42, off-main FR-44 | P4-T03 | Integration tests I-D* pass against a mock transport | 5–12 | needs research |
| P4-T05 | Single-writer handover: refuse while lightd/Lunar/BetterDisplay run (FR-40); add the app to the shell's `OTHER_DDC_APPS` | P4-T04 | TEST_PLAN M-11 passes: never two writers | 2–4 | routine |
| P4-T06 | Override + white point driven by the app; lightd stopped | P4-T05, P3-T02, P3-T03 | US-2, US-3 acceptance criteria met on hardware | 3–8 | needs research |
| P4-T07 | Neutral on quit and on crash recovery (FR-45) | P4-T04 | Killing the app with `kill -9` leaves neutral gains after the next launch | 1–3 | routine |
| P4-T08 | Adaptive brightness via `DDCWriter`, using the ported filter and curve (FR-10; FR-12 optional). Moved here from P6-T01 | P4-T06, P2-T02, P2-T03 | Brightness follows lux with lightd stopped; US-1 AC1–AC2 met on hardware | 2–5 | routine |
| P4-T09 | "Warm now" presets (FR-22): temporary Kelvin until the next adaptive recompute | P4-T06 | Preset applies within 2 s; the next adaptive recompute replaces it | 1–2 | routine |

**Brightness gap, flagged 2026-09-26.** Once P4-T06 stops lightd (one writer), the shell no longer does brightness either, so adaptive brightness would be lost until Phase 6. Options:
- (a) Give the shell a `GAINS_ENABLED=0` mode, so lightd keeps brightness while the app owns gains. **Rejected:** two processes then write the same bus, which breaks the single-writer rule (G5, FR-40).
- (b) **Recommended:** move brightness into the app in Phase 4 (P4-T08), with the curve and filter ported in P2. The Android-style nudge (P2-T05) and native nudge UI stay in Phase 6; until then the shell-style additive offset or no nudge is acceptable.
- Also note: the override's `CRITICAL_BRIGHTNESS` freeze (FR-30) is already a brightness write from the app in P4-T06, before Phase 6. So "no brightness in the app before Phase 6" was never true as written.

**Usable at the end:** the app owns the white point, the override **and adaptive brightness** (P4-T08). lightd is stopped. Corrected 2026-09-26: this said "Brightness is still shell or manual", which was impossible once lightd stops.

**Phase total:** 25–63 h (was 22–56; P4-T08 and P4-T09 added). **This is where schedules slip.** **D4:** if P4-T02 or T03 fails after about 20 h, stop. Keep the shell for DDC and treat the app as UI only.

---

## Phase 5: System events

| ID | Task | Deps | Acceptance criteria | Hours | Difficulty |
|---|---|---|---|---|---|
| P5-T01 | `NSWorkspace` sleep/wake + screens sleep/wake → gate and reapply once (FR-50/51) | P4-T04 | M-01 to M-03 pass | 3–6 | needs research |
| P5-T02 | `CGDisplayRegisterReconfigurationCallback` → rediscover (FR-52) | P4-T02 | M-04 (unplug/replug) passes | 3–8 (C callback into Swift) | genuinely hard |
| P5-T03 | Fault counters: stop a VCP after 20 consecutive faults (NFR-05) | P4-T04 | I-D07 passes | 1–3 | routine |

**Usable at the end:** the app survives sleep, wake and replugging without manual fixes, and stops writing to a VCP that keeps failing.

**Phase total:** 7–17 h. **D5:** continue to Phase 6 if M-01 to M-04 pass across a week of normal use. If wake behaviour is still unreliable after about 17 h, don't retire the shell (skip P6-T03) until it's fixed, so you can fall back to lightd.

---

## Phase 6: Brightness takeover, shell retired

| ID | Task | Deps | Acceptance criteria | Hours | Difficulty |
|---|---|---|---|---|---|
| P6-T01 | *Moved to P4-T08 (2026-09-26).* | — | — | — | — |
| P6-T02 | Native nudges (FR-11, Android-style) + UI | P4-T08, P2-T05, P5-T01, P5-T02 | US-4 acceptance criteria met | 2–4 | routine |
| P6-T03 | Import `config.sh` (FR-70); `launchctl bootout` of lightd | P4-T08 | Fresh install reproduces the shell's behaviour; one-week soak passes | 2–5 | routine |

**Usable at the end:** the full native app, with the shell retired: brightness, white point, override, nudges, and system events.

**Phase total:** 4–9 h (was 6–14; P6-T01 moved to Phase 4). **D6:** done. Phases 7–8 are optional.

---

## Phase 7 (optional): Settings and polish

| ID | Task | Deps | AC | Hours | Difficulty |
|---|---|---|---|---|---|
| P7-T01 | `Settings` scene: curve table, gain table, limits (R06 §3) | P6-T03 | Edits persist and apply | 6–14 | routine |
| P7-T02 | Curve chart (Swift Charts) | P7-T01 | Shows the curve and today's lux trace | 4–10 | routine |

**Usable at the end:** curve, gain table and limits editable in the app instead of the config file; a curve chart.

**Phase total:** 10–24 h (no totals row: out of v1 scope). **D7:** build P7-T02 only if a week of data exists and you're still editing the curve.

## Phase 8 (optional; only after buying a strip): Govee

| ID | Task | Deps | AC | Hours | Difficulty |
|---|---|---|---|---|---|
| P8-T01 | Probe 07 on real hardware (Q7) | — (a strip has been bought) | Kelvin range and protocol confirmed | 0.5–1 | routine |
| P8-T02 | `NWConnection` UDP sender + manual IP (FR-60/61) | P8-T01 | I-G* pass; the strip tracks brightness; US-7 AC1–AC2 met | 4–10 | needs research |

**Usable at the end:** a bias light that follows screen brightness and goes to 6500 K in the override.

**Phase total:** 4.5–11 h (no totals row: out of v1 scope). **D8:** if probe 07 shows the protocol doesn't match, stop and use a fixed D65 strip (R05 §3).

---

## Totals

| Scope | Hours | At 5 h/week | At 10 h/week |
|---|---|---|---|
| Phase 0 only | 7–23 + two weeks of use | 2–5 weeks of hands-on time, overlapping the two weeks of use | 1–3 weeks, likewise |
| Phases 1–6 (native app replacing the shell) | 72–179 | 14–36 weeks | 7–18 weeks |

**The weekly-hours columns are guesses about you (Q15).** The range is wide because Phase 4 is genuinely uncertain, not padded. Totals updated 2026-09-26 (were 70–175 h) for P1-T08, P4-T09 and the brightness move.

**Comparison with earlier documents** (corrected 2026-09-26; the earlier version compared PLAN.md's weeks with this plan's Phases 1–4 at 10 h/week, which mixed up both scope and weekly hours):
- **PLAN.md §1.6:** "6–8 weeks part-time" for an MVP of brightness + white point + override, assuming 12–15 h/week. That's about **72–120 h**. Because it includes brightness, the like-for-like scope here is **Phases 1–6 (72–179 h)**. PLAN.md's estimate sits inside this range, in its low half. The two agree if things mostly work first time; this plan's high end adds learning time and Phase 4's hardware risk explicitly.
- **VERDICT.md:** a 3–4-week white-point v1. This plan's Phases 1–4 (white point + override, now also brightness) come to about 60–153 h: 6–15 weeks at 10 h/week. **Contradiction kept:** that exceeds VERDICT.md's 3–4 weeks. Fitting 4 weeks would need at least 15 h/week even at the low end.

---

## What not to build

These are also in SPEC.md, and they're enforced by the phase gates:

- **No app code before D0.** The shell weeks decide whether the app is needed. The two small probe helpers (`displaystate`, `whitepatch`) are measurement tools, not app code; they're the only Swift before D0.
- **No brightness in the app before Phase 4.** Corrected 2026-09-26: this said Phase 6, but stopping lightd in P4-T06 would drop adaptive brightness (see the Phase 4 note). Gains and brightness now move to the app together, keeping one writer.
- **No Settings UI before Phase 7.** Edit the config file.
- **No Govee before a strip is bought.**
- **No multi-display support, Intel support, permanent learning, spline curves, smooth DDC transitions, or contrast adaptation, ever.**

---

## Assumptions

| Assumption | If wrong |
|---|---|
| You can spend at least 5 h a week in focused blocks | Estimates stretch; the learning curve suffers from gaps |
| Q9 allows an open transport | Phase 4 is impossible; stop at Phase 3 (app = UI + sensor, shell = DDC) |
| AI pair-programming is available for every task | The hours at least double for Phases 1–4 |
| The shell's behaviour is the spec for the app | If the week of use changes requirements, re-plan Phases 2 and 6 |
