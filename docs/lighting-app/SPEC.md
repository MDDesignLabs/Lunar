# SPEC: adaptive display and lighting (personal macOS app)

Status: draft, 2026-09-26; bias light and desk light bar updated 2026-10-11 (R08). Evidence tags point to the research files (R01–R08), the prototype (`lighting-prototype/`), or hardware results you reported. **UNVERIFIED** marks anything not yet shown to be true.

---

## 1. Problem and user

**The user is one person:** a product designer at a single desk.

- **Hardware:**
  - Mac Studio (Apple Silicon; generation UNVERIFIED, see Q9), macOS 26.7.
  - AOC CU34G4Z (34" VA, 3440×1440), connected over a port that's also UNVERIFIED (Q9).
  - ESP32 + TSL2591 ambient sensor at `lunarsensor.local`.
  - **Govee H6056 "Flow Plus" RGBICWW light bars** behind the monitor, as the bias light (bought; added 2026-10-11). On Govee's LAN API list ✓ [R08 §1]. Product identity from the ASIN is UNVERIFIED (Q17).
  - **A Xiaomi monitor light bar** ("xiaomi lite") on top of the monitor; model unknown (Q20) [R08 §6].
- **The problem:**
  1. The monitor's backlight and white point don't follow the room.
  2. Lunar Pro used to do the brightness part, but the licence was an expired demo.
  3. Nothing adapts the white point, and colour-critical work needs a guaranteed-neutral state at one click.

**What exists today:**
- A shell prototype that does all of this, tested against simulators (97 checks after the review fixes), with no hardware calibration yet.
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
- **G6 (active; changed 2026-10-11 from "deferred until hardware is bought"):** the best bias light this hardware allows: the wall behind the monitor at the standard surround level (5 cd/m², SMPTE ST 2080-3 §6.4 ✓), following the screen's white point, 6500 K in the override, and off whenever it adds nothing (bright day, display or Mac asleep, app stopped) [R08 §2–3].
- **G7 (added 2026-10-11):** in a dark room, offer to turn on the desk light bar. **It's your decision every time:** the app asks, and never switches the bar by itself [R08 §6].

## 3. Non-goals

These are explicit and firm:

- Multiple monitors, Intel Macs, or the built-in display.
- The App Store, sandboxing, or distribution to anyone else.
- True Tone-style ambient colour matching (the sensor measures lux, not colour; R03 §5).
- Contrast adaptation, software dimming, gamma tables, HDR/XDR.
- Permanent machine learning of preferences in v1 (R01 §5).
- Screen-content colour sync for the bias light (ambilight) (R05, R08).
- The Govee cloud API; also BLE and Matter control of the Govee bars (R08 §1).
- Switching the desk light bar on or off without your explicit tap (G7, FR-80).
- Auto-exiting the colour-critical mode, ever.

**User constraints** (added 2026-09-26; firm):
- Never decrypt or circumvent Lunar's Pro code.
- Native DDC only. Never assume BetterDisplay is installed.
- Probe 06 Part B (power-cord pulls) is skipped.

---

## 4. User stories

**US-1: Adaptive brightness**
As the user, when the room light changes, my screen brightness follows within about a minute and a half, without flicker or hunting.
- AC1: A room step of ×10 lux brings brightness within 3 units of the curve target within 90 s (NFR-02). *Covers brightening only;* darkening needs its own target, see the NFR-02 decision.
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

**US-7: Bias light** (G6; rewritten 2026-10-11 from R08 §3; was "dims with the screen", deferred)
As the user, the wall behind my monitor is lit at the standard surround level, matches my screen's white point, turns neutral in colour-critical mode, and is off when it isn't needed.
- AC1: At night (filtered lux < `BIAS_OFF_LUX`), the wall at the centre of the lit area measures **5.0 ± 0.5 cd/m²**: ≈ 19.6 lx ± 10% by the TSL2591 flat on a ρ 0.8 wall (derived, E = πL/ρ; uses the measured ρ, Q19) (FR-62).
- AC2: The bars go to **6500 K within 5 s** of the override turning on (FR-61).
- AC3: The bars are **off within 5 s of display sleep** (FR-64).
- AC4: In adaptive mode, the bars' Kelvin equals the screen's target Kelvin clamped to 2200–6500, and commands are ≤ 1 update per 2 s (FR-63, FR-65).
- AC5: The bars are off before the Mac sleeps, after lightd/the app stops cleanly, and when the room is above `BIAS_OFF_LUX` (FR-64).
- *Contradiction kept:* `devStatus` lags "several seconds" [R05 §1], so AC2/AC3 are checked by eye or by a `devStatus` read at 5 s, not by an immediate read-back.

**US-8: Desk light bar prompt** (G7; added 2026-10-11)
As the user, when I'm working in a dark room, the app asks once whether I'd like the light bar on, and does nothing to it unless I say yes.
- AC1: **Never on without a yes.** Over a soak week the bar changes state only after a tap on "Turn on" (FR-80).
- AC2: **At most one prompt per evening**, including after "Not tonight" and after a withdrawn prompt (FR-81, FR-82).
- AC3: **Withdrawn when the room is lit:** the notification and the popover prompt are gone within 1 min of filtered lux rising above 20 lx (FR-85).
- AC4: **Works whether or not the bar can be controlled:** remote-only models get instructions and an "It's on" button; controllable models get one command (FR-83, FR-84).

---

## 5. Functional requirements

Each requirement is individually testable. TEST_PLAN §7 traces them.

### Lux input

- **FR-01** Read `sensor-ambient_light` from the ESP32's event stream (`SENSOR_URL`). Reconnect with backoff of 1 s doubling to 30 s. [R01 §1; prototype `bin/lightd`]
- **FR-02** If no sample arrives for `STALE_SECS` (default 60), hold all outputs, show "sensor offline", and keep reconnecting.
- **FR-03** Filter in log10 lux with an asymmetric EMA (τ 8 s brightening, 45 s darkening). Recompute targets only when the filtered value moves ≥ 0.04 decades. [R01 §4]
- **FR-04** Discard negative or non-numeric lux samples. They are never treated as darkness (0 lx). The shell prototype now does this. (Added 2026-09-26.)

### Brightness

- **FR-10** Map filtered lux to brightness % with piecewise-linear interpolation in log10(lux), over configured points. Skip malformed points; sort by lux; clamp to [min, max]. [R01 §3.3; prototype `engine.awk`]
- **FR-11** Nudge: ±5 per action, clamped to ±50, applied immediately. It's cleared when lux leaves [anchor × 0.4, anchor × 1.6] (Android's default [R01 §3.2]; configurable). *Contradiction kept:* the prototype currently clears at ~0.32–3.2×.
- **FR-12** Optional luminance compensation: brightness × 1/Y_rel(gains), using the measured `GAIN_GAMMA`, computed from the gains **actually on the monitor**. While a gain set is deferred or capped these differ from the targets. [R03 §3]
  - Until probe 05 measures it, `GAIN_GAMMA` defaults to 1.0. If the truth is 2.2, this under-compensates (the screen is slightly dim when warm). A guessed 2.2 would over-brighten by ~9% at 5000 K if the truth is 1.0 (derived: Y_rel of 50/46/40 is 0.928 at γ 1.0 vs 0.852 at γ 2.2). Changed 2026-09-26: the prototype defaulted to a guessed 2.2.

### White point

- **FR-20** Lux → Kelvin: smoothstep between (`KELVIN_DIM_LUX`, `KELVIN_DIM`) and (`KELVIN_BRIGHT_LUX`, `KELVIN_BRIGHT`), quantised to `KELVIN_STEP`, with a floor of `KELVIN_FLOOR` (default 4000 K). The floor is implemented in the prototype's `engine.awk` and `light kelvin`. [R03 §1]
- **FR-21** Kelvin → R/G/B by linear interpolation over the measured `GAIN_TABLE`. No channel may exceed its neutral value; the prototype's engine now clamps gains to ≤ neutral (`CRITICAL_GAINS`). [R03 §3]
- **FR-22** "Warm now" presets apply a temporary Kelvin until the next adaptive recompute.
- **FR-23** Time of day (added 2026-10-17; the user works in a blackout room, so a dark room is not evening). The clock sets the warm end of FR-20's curve. Bright rooms stay 6500 K at every hour.
  - **Day** (sunrise to sunset): 6500 K whatever the lux, so colours are true for UI/UX design work.
  - **Evening**: from sunset, ramp to `KELVIN_DIM` (5000 K).
  - **Night**: from `BEDTIME` − 3 h (default 23:00 → 20:00), ramp to `KELVIN_NIGHT` (4000 K) and hold until morning.
  - **Morning**: back to 6500 K from sunrise, or from `BEDTIME` + 8 h if that's earlier.
  - Each ramp takes `TOD_RAMP_MIN` (60). `KELVIN_FLOOR` still applies, and colour-critical mode ignores the clock.
  - **Location**: sunrise and sunset come from the Mac's time zone (a table of cities: Berlin now, Amman after the planned move), with a `LATITUDE`/`LONGITUDE` override. An unknown zone falls back to its UTC offset at 45° N. A move needs no config edit.
  - `TIME_OF_DAY=0` restores room-light-only behaviour.
  - Write budget: a day adds about 20 gain sets from the ramps (6 + 4 + 10, paced by `KELVIN_MIN_INTERVAL`), against `GAIN_DAILY_CAP` 30. Daytime lux changes no longer move the Kelvin, which saves writes. Watch the count in the daily report. [shell §13]

### Override

- **FR-30** Turning the override on:
  - writes `CRITICAL_GAINS` immediately. It bypasses minimum intervals and the adaptive daily cap, using a separate reserved allowance (`OVERRIDE_RESERVE`, default 10 writes per channel per day, counted on top of the adaptive cap). No-op skip still applies;
  - if a write can't be made (another DDC app running, reserve exhausted, or a transport failure), the command reports failure and the UI shows "override incomplete", never "ON";
  - *rationale:* the user's non-negotiable override (G3) vs the EEPROM rule (G4). Writes back to neutral are bounded by the writes away from it, so the reserve adds little wear;
  - corrected 2026-09-26: this said "bypassing minimum intervals, but never the daily caps or no-op skip";
  - optionally freezes brightness at `CRITICAL_BRIGHTNESS`;
  - persists to disk;
  - is restored first on every launch and wake, before the first lux sample (the sensor may be offline). The prototype does this since 2026-09-26.
- **FR-31** No code path turns the override off except an explicit user action.

### DDC safety

- **FR-40** Refuse every monitor write while Lunar, BetterDisplay or MonitorControl is running, or while the shell `lightd` is live (checked by PID file). [R02 §5] (Prototype with `BACKEND=lunar`: Lunar is the intended bus owner there, so only the other two are refused.)
- **FR-41** Scheduler rules:
  - skip writes equal to the last value;
  - brightness dead-band ≥ 2 units;
  - minimum intervals: brightness 60 s, gain set 600 s;
  - daily caps: 200 brightness writes, 30 per gain channel, counted on every attempt;
  - user actions (nudges, presets, the override) skip the intervals but are spaced ≥ 250 ms per control (≤ 4 writes/s), delayed rather than dropped so the last value lands. Added 2026-09-26: PLAN §2.2 had this throttle and SPEC had dropped it.
  - *Contradiction flagged 2026-09-26:* PLAN.md §2.2 set brightness ≥ 20 s and caps of 300/50. SPEC's stricter 60 s and 200/30 follow the user's rule of conservative EEPROM limits, and supersede PLAN. They're also the reason NFR-02's darkening case is slow.
- **FR-42** Log every write sent to the monitor: time, VCP, value, result, duration. Refusals (another DDC app, a cap) never reach the monitor and cost no wear, so they're summarised in the app log (once per episode), not in the write log. Changed 2026-09-26: this said "every attempt"; the review found the shell logs refusals only in `lightd.log`, and logging each retry would flood the write log.
- **FR-43** Pick the DDC chip address per display: `0x37`, or `0xB7` for MCDP29xx ports. [R02 §1.3]
- **FR-44** All DDC transactions run serially and never on the main thread. [R02 §1.4]
- **FR-45** On quit, write neutral gains. If the previous run didn't exit cleanly, write neutral before anything else.

### System events

- **FR-50** Mac sleep: stop writing. Mac wake: wait `WAKE_DELAY` (8 s), rediscover the transport, reapply current targets **once**. [R02 §3]
  - Read back after the reapply only if probe 03 shows reads are trustworthy (Q2). *Contradiction flagged 2026-09-26:* PLAN.md said "reapply plus a read-back" unconditionally.
  - The shell prototype approximates this. It has no sleep notifications, so it treats a gap of `WAKE_GAP` (90 s) between samples as a possible wake, and checks `sysctl kern.waketime` to tell a real wake from a sensor dropout. The `kern.waketime` output format is UNVERIFIED on your Mac; if it can't be read, every gap is treated as a wake.
- **FR-51** Display sleep with the Mac awake: pause writes. Display wake: same as FR-50.
- **FR-52** Display reconfiguration (connect, disconnect, mode change): rediscover the transport before the next write.
- **FR-53** Screen lock is **not** a gate in v1: writes are allowed while the screen is locked (the display-sleep rules in FR-51 still apply). Added 2026-09-26 because TEST_PLAN M-03 says "no writes while locked (if gated)"; with this decision, M-03 checks only the correct state after unlock.

### Bias light (active; rewritten 2026-10-11 from R08)

- **FR-60** Transport: Govee LAN UDP. Commands to each configured IP on :4003. Discovery: scan to 239.255.255.250:4001 **after joining the group**, plus a unicast scan to each configured IP; replies on :4002. If a reply has no `ip`, use its source address. Manual IPs always work without discovery. Each IP is a separate light (the pair may be two, Q17). [R08 §1, §4]
- **FR-61** In the override, the bars go to 6500 K within 5 s. A setting (`BIAS_IN_CRITICAL=on|off`, default on) may turn them off instead. [R08 §3]
- **FR-62** Level is an **absolute wall luminance**, `BIAS_TARGET_NITS` (default 5.0), converted to wall lux E = π·L/ρ with the measured `BIAS_WALL_RHO`, then to brightness % by inverting the measured `BIAS_CAL` table (pct:lux pairs). Result clamped to [1, `BIAS_MAX`] (default 15). It doesn't depend on screen brightness. Replaces `BIAS_K`. [R08 §2]
- **FR-63** Colour in adaptive mode: the screen's current target Kelvin (FR-20), clamped to [`GOVEE_K_MIN` 2200, `GOVEE_K_MAX` 6500]. No Kelvin outside that range is ever sent. [R08 §1]
- **FR-64** Off (`turn 0`) when: filtered lux > `BIAS_OFF_LUX` (default 60, back on below `BIAS_ON_LUX` 40; UNVERIFIED, Q22); display asleep (within 5 s); before Mac sleep (from a sleep notification, not after wake); on a clean stop. Coming back on sends `turn 1` before brightness. A crash leaves the last state; the next launch corrects it. [R08 §3]
- **FR-65** Rate limits: coalesce to the latest target; send only on a change of ≥ 1 brightness step or ≥ 100 K; ≤ 1 update per 2 s; ≥ 300 ms between datagrams to one device; on/off transitions sent twice, 300 ms apart. [R08 §3]
- **FR-66** Refresh the current state every 60 s (UDP has no ack), **without** resending `turn 1`, so bars you switched off in the Govee app stay off.
- **FR-67** Reachability: poll `devStatus` with each refresh; after 3 consecutive refreshes without a reply, show "Bias light not responding" and keep trying. (The threshold of 3 is a design choice, not a measured value.)
- **FR-68** Hue backend (added 2026-10-23; the user chose the Hue Play Gradient Lightstrip for PC 32–34″ over the Govee bars, which spread unevenly on the wide 1500R screen).
  - **Transport:** the Hue Bridge's local CLIP v2 REST API: `PUT /clip/v2/resource/light/<id>` with the `hue-application-key` header, HTTPS with `-k` on the LAN.
  - **Pairing and backend choice:** the key comes from `bin/hue pair` (link button) and is stored in `~/.lighting/hue_key` (mode 600), never in config.sh. `HUE_BRIDGE` set → Hue is the bias light and `GOVEE_IPS` is ignored.
  - **Level and colour:** the same level, Kelvin and off rules as FR-61–FR-64. Kelvin → mirek, clamped 153–500.
  - **Sending:** only on a change of ≥ 1 % or ≥ 100 K; ≤ 1 update/s (`HUE_MIN_INTERVAL`); fades of `HUE_FADE_MS` done by the bridge; "on" only on our own off→on transition. Each PUT is acknowledged, so there's no blind refresh.
  - **Reachability (FR-67):** 3 failed PUTs → "bias light not responding" once, then keep trying.
  - **Calibration:** `BIAS_CAL` for Hue isn't measured yet; the fallback % applies until a Hue variant of probe 07 check F exists. [shell §14]

### Desk light bar (added 2026-10-11 from R08 §6)

- **FR-80** The app never changes the light bar's power, brightness or colour temperature without your explicit action for that one change.
- **FR-81** Ask at most once per evening: when filtered lux has been < `LIGHTBAR_ASK_LUX` (5) for `LIGHTBAR_ASK_MIN` (10 min) inside the evening window (default sunset to bedtime − 3 h, configurable), with the display awake and the bar believed off. Asked-today state persists across restarts.
- **FR-82** The prompt offers "Turn on" and "Not tonight". "Not tonight" suppresses prompts until 06:00. A setting, "Don't ask again", turns prompting off until you turn it back on.
- **FR-83** Remote-only model: "Turn on" sends nothing. It shows remote instructions and an "It's on" button, which records "you said on".
- **FR-84** Controllable model: "Turn on" sends one command (on, `LIGHTBAR_K` 2700 K, `LIGHTBAR_PCT` 30 %) over the LAN, under the existing Local Network grant. Failure is shown, not retried silently.
- **FR-85** Withdraw the prompt (notification and popover row) when filtered lux rises above 20 lx or the evening window ends; it doesn't come back that evening. Lux added by the bar after a "Turn on" doesn't trigger or cancel anything.
- **FR-86** Light-bar model setting: `none` / `remote-only` / `miio(ip, token)` / `yeelight-lan(ip)`. Default `remote-only` until the model is known (Q20). A miIO token is stored in the Keychain.
- **FR-87** The popover always shows the prompt row while a prompt is active, so it works when notifications are denied or hidden by Focus.

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
  - *Contradiction (added 2026-09-26): the 99 s covers brightening only.* Darkening uses τ 45 s: ~15 s firmware + 3 × 45 = 135 s EMA + 60 s write interval ≈ **210 s** [derived, same arithmetic]. **Decision needed:** either a separate darkening target (e.g. ≤ 240 s) in NFR-02 and US-1 AC1, or a faster darkening τ (about 5 s would be needed to fit 90 s, which removes the asymmetry).
- **NFR-03 Resources:** idle CPU < 1% averaged over 10 minutes; memory < 150 MB. These are targets, not measurements (UNVERIFIED).
- **NFR-04 EEPROM budget:**
  - hard caps as FR-41;
  - design target ≤ 60 brightness writes and ≤ 15 per gain channel per typical day [R02 §4];
  - worst case assumes every write costs a cycle.
- **NFR-05 Failure behaviour:**
  - sensor loss holds outputs;
  - DDC failures are counted, and writes stop for that VCP after 20 consecutive faults (matches I-D07; Lunar's threshold [R02 §2]);
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
| Q3 | Are gains linear-light or gamma-encoded? | probe 05 (rerun) | **Answered 2026-10-11: linear light, with a small offset** (zero output at gain ~4–5; fitted exponent 1.23). The room wasn't dark (white ≈ 2.2× black); the verdict was checked to hold anyway (R03 §2) |
| Q4 | Is there headroom above gain 50? | probe 05 | **Answered 2026-10-11: no.** 55 and 60 equal 50 on every channel |
| Q5 | Do sleep, input switching or power-off reset the gains? | probe 06 Part A | Open |
| Q6 | Is the ESP32 stream stable for 24 h? | probe 02 | Open |
| Q7 | Govee model, Kelvin range, protocol match | probe 07 (checks A–D) | **Active 2026-10-11:** bars bought. H6056 is on the LAN list ✓; the range and protocol wait for probe 07 [R08 §5] |
| Q8 | Can a launchd agent reach `lunarsensor.local`? | `./install.sh`, then check lux updates under launchd [R04 §2] | **Answered 2026-10-11: yes, on your Mac.** The launchd agent (`state = running`, pid matching the lightd process) received live lux, which changed when the sensor was covered. This contradicts the expectation from TN3179 (agents aren't exempt); why it's allowed is UNVERIFIED. **Confirmed after a reboot** with nothing started by hand: live lux, and `last sent` matching the target |
| Q9 | Mac Studio generation and AOC port (HDMI vs USB-C) | `system_profiler SPHardwareDataType`; the physical port; `m1ddc display list detailed` | Open. **Decides the DDC transport** [R02 §1.3] |
| Q10 | Does `whitepatch.swift` compile and stay on top? | probe 05 rerun | Probably yes: the rerun completed with stable per-channel readings, which needs the white patch to stay up. Not confirmed |
| Q11 | Is 50/50/50 truly D65 on this panel? | colorimeter, or accept | Open. Default: accept |
| Q12 | Does `power_save_mode: none` fix the Wi-Fi loss? | probe 02 before and after reflashing | Open |
| Q13 | How bright should the bias light be? | ST 2080-3 §6.4 ✓ | **Resolved 2026-10-11: 5.0 ± 0.5 cd/m² absolute** (R05 §2's 5-vs-10% contradiction closed; ST 2080-3 replaced BT.2035's 10% ✓) [R08 §2]. Was "calibrate by eye" |
| Q14 | Current OSD brightness and baseline | probe 03's `baseline.txt` | Mentioned as "30%" in passing; UNVERIFIED |
| Q16 | Is the research-based brightness curve right for you (RESEARCH_07), and is the ~55 cd/m² backlight floor dim enough at night? | the soak (nudge counts, notes at night) | Open. Curve recommended 2026-10-11 |
| Q15 | How many hours a week can you spend? | you | **Unknown. It changes every estimate in BUILD_PLAN** |
| Q17 | Is the Govee product exactly the H6056, and how many IPs does the pair have? | the box or the Govee app; probe 07 check A | Open (added 2026-10-11) |
| Q18 | Does the LAN Control switch appear for this revision, and do LAN whites use the WW chips or RGB? | Govee app; probe 07 checks A and E | Open |
| Q19 | Wall reflectance ρ and the brightness→wall-lux table | probe 07 check F, plus the white-paper ρ check [R08 §2] | Open |
| Q20 | Which Xiaomi light bar model is it? | read the label under the bar or on its base (P0b-T10) | Open. Decides remote-only vs controllable |
| Q21 | How much does the light bar raise the sensor's lux? | lux with the bar off, at 30 % and at 100 %, room fixed, three readings each (P0b-T11) | Open. Estimate 5–15 lx at 30 % (not measured) |
| Q22 | `BIAS_OFF_LUX`: the room lux above which the wall is already brighter than 5 cd/m² | spot readings of wall lux (bias off) against bezel lux at several times of day (P0b-T07) | Open. Starting value 60/40 lx is UNVERIFIED |

---

## What not to build

- Everything in §3 Non-goals.
- **A permanent learning curve** (Lunar-style or ML). Use Android-style short-term corrections plus hand-edited points [R01].
- **Smooth DDC transitions, repeated wake re-applies, and read-modify-write** [R02].
- **Kelvin below 4000 K,** and gains above neutral [R03].
- **The Govee cloud API, BLE or Matter control, per-segment effects, and ambilight** [R05, R08]. *Changed 2026-10-11:* "no Govee code before a strip exists" is removed; the bars are bought.
- **Automatic light-bar switching**, and any light-bar control code before the model is known (Q20) [R08].
- **Settings UI** before Phase 7, a curve chart before a week of data, and a global-hotkey system [R06].

---

## Assumptions

| Assumption | If wrong |
|---|---|
| The AOC can be driven by an open DDC transport (Q9) | The native app is blocked at the transport; only BetterDisplay-class tools work |
| The TSL2591 method can measure the gain response (Q3, Q10) | White-point calibration needs a colorimeter or stays approximate |
| One user, one monitor, one room | Scope grows by at least 2× |
| You accept a slightly visible 2–3-unit brightness step now and then. **A guess about you, not something you've said** | Smoothing would have to be in-app, not over DDC; that's a design change |
| The wall behind the monitor is matte and roughly neutral (R08 §2) | 5 cd/m² can't be set from lux alone; it needs a luminance meter |
| Govee's 1 % steps are fine enough near 3–8 % to hold ±0.5 cd/m² (R08 §2) | US-7 AC1 relaxes to the nearest step; record the achieved value |
