# My desk setup: what I have, what's suggested, what's decided

Status: 2026-10-17. One page for the whole desk. The details live in the linked docs; update this file when something is bought, measured or decided.

## Who and where
- **Work:** UI/UX product design, for sRGB/D65 screens (not print or video grading).
- **Place:** Berlin now; moving to Amman, Jordan later. Both are 230 V. Jordan uses C, D, F, G and J sockets, so bring C→G adaptors.
- **Room:** blackout blinds, so the room is often dark at any hour. Bedtime about 23:00.

## What I have now

| Item | Model / details | Role | State |
|---|---|---|---|
| Computer | Mac Studio (Apple Silicon), macOS 26.7 | Runs the app (`lightd`, the shell prototype) | ✅ In use |
| Monitor | **AOC CU34G4Z**: 34″ 3440 × 1440 VA, 1500R curve, 80.8 × 36.8 × 10.9 cm without stand, VESA 100 | Adaptive brightness and white point over DDC (m1ddc) | ✅ In use. Measured range ≈ 55–372 cd/m² (KitGuru; RESEARCH_07). OSD: User mode, R/G/B 50/50/50 |
| Light sensor | ESP32 + TSL2591 on ESPHome, `lunarsensor.local` (192.168.0.163) | Room light (lux) for the app | ✅ In use, on the top bezel facing me |
| Bias light | **Govee H6056 "Flow Plus" RGBICWW light bars** (2 bars + brackets; Amazon.de B0FWCWTMQD), arrived 2026-10-13 | Soft glow on the wall behind the screen, driven by the app over the LAN | 🔄 Not set up yet. EU label: CRI 80, R9 2, white slightly green of D65 (EPREL 857551). Probe 07 still to run |
| Desk light | **Xiaomi monitor light bar ("lite")**, model number unknown (Q20) | Lights the desk and keyboard, not the screen | ✅ Owned. Probably remote-only, so the app will only ever **ask** (FR-80) |
| Room light | Unknown: tell me what's there | — | ❓ Missing a side lamp |
| Software | `lightd` shell prototype (this repo); Lunar's Pro licence expired (not used) | Brightness curve, time-of-day white point, bias light | ✅ Running under launchd |

## How it's set up (target)
- **Monitor:** about 15 cm or more from a matte, neutral wall. The wall gap and colour still need measuring and telling me.
- **Sensor:** top bezel, facing me. When the Xiaomi bar goes on top, move the sensor just **left or right of it**.
- **Govee bars:** upright on their brackets behind the monitor, one each side of the stand, aimed at the wall and slightly up. No LED visible from the chair, and no reflection on the screen (RESEARCH_08 §1a).
- **Xiaomi bar:** top centre of the screen.
- **Room lamp (planned):** **to the side**, 70–120 cm left or right of my head, between level with my shoulders and 40 cm behind them. Never above or behind me, never behind the monitor. Its glow stays off the wall behind the monitor (RESEARCH_10 §3).

## What the system does through the day
- **Screen white (FR-23):** in a dark room, 6500 K by day, 5000 K from sunset, 4000 K from 20:00, back to 6500 K in the morning. A bright room stays 6500 K at any hour. Sunrise and sunset follow the Mac's time zone, so Amman works without edits.
- **Brightness:** follows the room light. In a dark room it's at its lowest, ≈ 55 cd/m² (≈ 41 at 4000 K).
- **Bias light:** about 5 cd/m² on the wall, matching the screen's white. Off in a bright room (above 60 lx), when the display sleeps, and when the app stops.
- **Colour-critical mode:** 6500 K, brightness 40 % ≈ 190 cd/m², bias at 6500 K.
- **Scene by scene:** SCENES.md, with Gemini prompts.

## Product choices suggested

| Need | Choice | Cost | Source |
|---|---|---|---|
| Bias light | **Keep the Govee H6056**, if probe 07 checks E, F and I pass | €0 (owned) | RESEARCH_09 |
| Bias fallback | CRI 95 CCT LED strip in an aluminium diffuser channel + **QuinLED An-Penta-Mini** (ESPHome) + 24 V supply; screw terminals, no soldering | ≈ €90–120 | RESEARCH_09 §3 |
| Bias, easier plug-in alternative | CCT strip + a ready-made WLED controller (Athom ESP32-C3 RGBCCT, or Gledopto) | ≈ €50–80 (UNVERIFIED) | RESEARCH_09 §3 (Athom listed as the alternative controller) |
| Desk light | **Keep the Xiaomi bar** | €0 (owned) | RESEARCH_08 §6 |
| Room lamp | **IKEA TÅGARP floor uplighter** (€9.99) | — | RESEARCH_10 |
| Room lamp bulb, cheapest | **Shelly Duo Bulb E27 Gen3**: no hub, best local API, CRI > 80 | ≈ €10 | RESEARCH_10 |
| Room lamp bulb, best colour | IKEA KAJPLATS 1521 lm white spectrum (CRI 90) + DIRIGERA hub | ≈ €10 + €80 | RESEARCH_10 |
| Room lamp bulb, measured | Philips Hue White Ambiance 1100 lm + Hue Bridge (lab-tested low flicker, CRI 80) | ≈ €32 + €34 | RESEARCH_10 |
| Don't buy | Another monitor bar, Hue Play, COB strip, Govee floor lamps, WiZ, Nanoleaf, LIFX | — | RESEARCH_09, RESEARCH_10 |

## Decisions

| Decision | Status | Date |
|---|---|---|
| Native DDC only; one app on the DDC bus; conservative EEPROM limits | ✅ Decided | 2026-09 |
| Brightness curve from RESEARCH_07; lowest brightness 0 %; no luminance compensation | ✅ Decided | 2026-10-11 |
| The screen's white follows the clock as well as the room (FR-23); bedtime 23:00 | ✅ Built | 2026-10-17 |
| The desk bar is never switched without a yes (FR-80) | ✅ Decided | 2026-10-11 |
| Keep the Govee as the bias light, pending probe 07 | ✅ Decided, waiting on probe 07 | 2026-10-17 |
| Room lamp to the side, uplighter style | ✅ Decided | 2026-10-17 |
| Room lamp bulb: Shelly (€20) vs Hue (€66) vs IKEA (€100) | ❓ Open: your choice | — |
| Should the app control the room lamp ("ask once, then follow")? Off at bedtime? | ❓ Open | — |
| Switch the bias light to an LED strip | 🔄 **Leaning yes** (2026-10-21): bars give two pools, not an even glow; CRI 80; probe 07 found no LAN reply. Buy list: BUY_BIAS_STRIP.md (≈ €92–103). Return the Govee within Amazon's window | 2026-10-21 |
| Dimming below the backlight's floor | ➖ Not now: revisit after a week with the bias light | 2026-10-17 |

## Still needed from me
1. Run `bin/light update`, set up the Govee bars (2.4 GHz Wi-Fi, LAN Control on), then run `probe/07-govee.sh` and send the RESULT lines.
2. The monitor-to-wall gap, the wall colour, and the ceiling height and colour.
3. Which side of the desk has space and a socket for the lamp; what room lights exist now.
4. The Xiaomi bar's model number, from the label (Q20).
5. The room-lamp budget.
6. Daily `light report` pastes for the review.
