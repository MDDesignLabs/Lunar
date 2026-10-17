# Research 09: Which bias light suits this desk best, and a check of the whole brightness system

Status: research, 2026-10-17. One research agent, web sources plus local calculations. **No hardware tested.** ✓ = I read the primary page's text in this session (fetched, or as a search extract of that page). **UNVERIFIED** = not confirmed, with what would settle it. "Derived" = my own calculation from cited numbers (the scripts are in §7).

**The ask:** check the bias setup and the whole brightness system, and name the product that fits this desk best, controlled automatically by our app.

---

## Summary

1. **The Govee H6056 fails your own white-quality rule, on the EU's official data.** Govee's EU energy-label sheet (EPREL 857551, on sale from 09/06/2026) lists **CRI 80, R9 = 2, 430 lm** and a white point of x 0.313, y 0.337. That point is about 6440 K and visibly **greener than D65** ✓ [E1]. Two questions are still open: whether LAN white uses the white LEDs at all, and how coarse its low-end steps are.
2. **No ready-made smart light passes all six constraints.** The ones with good local APIs (Hue, Elgato, LIFX, WiZ, Nanoleaf, Yeelight, other Govee models) either have CRI ≈ 80 or unpublished, can't dim low enough, or mix white from RGB. The one with excellent white (MediaLight, CRI ≥ 98, D65) is fixed at 6500 K and controlled by an IR remote.
3. **Primary recommendation: build a small kit, not a smart bulb.** It's a high-CRI (≥ 95) **tunable-white (CCT) COB strip**, in an aluminium channel on the back of the monitor, driven by a **QuinLED An-Penta-Mini** (ESP32, pre-flashed WLED, ESPHome-capable) running **ESPHome**. You already run ESPHome for the sensor. The parts total about **€90–120**; assembly is screw terminals only, no soldering. Control is a documented local HTTP API (`/light/<name>/turn_on?brightness=…&color_temp=…`). Dimming is flicker-free (PWM at ≥ 4.9 kHz, above IEEE 1789's 3 kHz no-effect limit), with 4,096–16,384 steps.
4. **Fallback: keep the Govee H6056** (already bought and integrated). Run probe 07 as planned. It's acceptable as a dim surround light if checks E, F and I pass, but not for judging colour. **Don't buy Hue Play or another off-the-shelf bar instead:** they have the same CRI 80 class of white and only a better API.
5. **Brightness system:** keep the current curve, the 55 cd/m² floor, `LUMINANCE_COMPENSATION=0` and `KELVIN_FLOOR=4000`. With the bias light at 5 cd/m² and the screen at ~48 cd/m², the ratio is ≈ 10:1, which matches the guidance. Don't build gain dimming below the floor yet. If you ever do, fold one fixed factor into the evening white-point gain write, so it costs no extra writes (§4.3).

---

## 0. What "best" means here (scorecard)

Your six hard constraints, scored for every candidate in §2:

| # | Constraint | Pass means |
|---|---|---|
| C1 | Local, documented or well-established API; no cloud | Works with the internet unplugged, from shell and Swift |
| C2 | Very low, stable, flicker-free levels | Reaches ~20 lx on a near wall (5 cd/m² at ρ 0.8) with steps ≤ 10 %, and PWM ≥ 3 kHz or DC |
| C3 | True tunable white from dedicated white emitters, CRI ≥ 90 (R9), accurate 6500 K; CT settable over the API | API drives the white chips, not an RGB mix |
| C4 | Gentle updates OK | ≤ 1 update per 2 s is safe |
| C5 | Fits a 34″ 1500R ultrawide near a wall; sold in DE; reasonable € | — |
| C6 | Matter only if drivable locally without Apple Home | — |

---

## 1. Keep the Govee H6056? (A)

### 1.1 What's now known

| Item | Finding | Source |
|---|---|---|
| Official EU data | EPREL 857551, supplier GOVEE MOMENTS (DE) HANDEL GmbH, model **H6056**, on the EU market **from 09/06/2026**: the 2026 revision R08 §1 suspected | [E1] ✓ |
| CRI / R9 | **CRI 80, R9 = 2** (a search extract of another language version read R9 as 8, but the fetched sheet shows 2; either is very poor) | [E1] ✓ |
| Light output | **430 lm** useful flux (360°), **11 W**; colour-tunable, 2200–6500 K | [E1] ✓ |
| White point | **x 0.313, y 0.337** → **CCT ≈ 6440 K, Duv ≈ +0.007** (derived). D65 is Duv +0.003, so the label white is **≈ 0.004 greener than D65** | [E1] ✓ + derived §7 |
| Size | 250 × 44 × 41 mm per bar | [E1] ✓ |
| LAN white path | Govee's guide: a non-zero Kelvin is "converted into the color value of red, green and blue". No source found either way for the H6056. **UNVERIFIED**; probe 07 check E | [G9] ✓ |
| One device or two? | The govee2mqtt test data lists each H6056 as one entry with one BLE name, which suggests **the pair is one LAN device**. Two IPs (R08 §1) is therefore less likely. **UNVERIFIED**; check A | [G26] ✓ (local clone) |
| Minimum level, flicker | **No data found** (no review measures it) | — |
| Rate limit | One developer note says "~7 req/min"; that's almost certainly the **cloud** API, not LAN. LAN has no documented limit; the prototype's 2 s / 300 ms is conservative | [G27] (search extract; **UNVERIFIED**) |

### 1.2 Will it reach 5 cd/m² finely enough? (derived)

- Target: 20 lx on a ρ 0.8 wall.
- If output is linear in %, 430 lm puts that near **3–8 %**, as R08 §2 estimated with 400 lm.
- In that range, **one 1 % step changes the light by 12–33 %**. SPEC US-7 AC1 asks for ± 10 % (5.0 ± 0.5 cd/m²), so **AC1 may be unreachable** unless Govee's dimming curve is finer at the low end. Check F answers this directly.

### 1.3 Verdict on the Govee

| Constraint | Govee H6056 |
|---|---|
| C1 local API | ✓ (openHAB and HA list it [G10]); this unit **UNVERIFIED** until check A |
| C2 low and flicker-free | **Unknown** (checks F, I) |
| C3 white quality | **✗ by spec: CRI 80, R9 2**, greenish label white; LAN white possibly RGB-mixed |
| C4 rate | ✓ |
| C5 fit and price | ✓ (already owned) |
| C6 Matter | not needed (LAN) |

It's **good enough as a dim, roughly neutral surround light** if E, F and I pass. **It isn't good enough for your stated white-quality rule, or for colour-critical work.** CRI 80 and R9 2 are fixed hardware facts; no probe result changes them.

---

## 2. Alternatives (B)

Prices in € incl. VAT unless marked, with the date of the price data.

| Product | C1 local API | C3 white emitters, CRI | C2 low end, flicker | DE price | Verdict |
|---|---|---|---|---|---|
| **Philips Hue Play light bar** (+ Hue Bridge) | ✓ **Best-documented API**: Bridge CLIP v2 local HTTPS, app key from the link button; ≈ 10 commands/s to lights, 1/s to groups [H1] ✓; colour temp in mirek 153–500 [H2] ✓; Bridge is the hub, no Apple Home needed | "RGBW" (Signify page [H3] ✓), **CRI 80 Ra** (idealo listing [H4] ✓); 500 lm at 4000 K per bar | 254 levels; minimum 1 % ≈ 5 lm per bar. One hobbyist claims Hue uses **~1 kHz PWM** [H5] (**UNVERIFIED**): above IEEE's low-risk line, below its no-effect line (§2.2) | Double pack **from €91.90** (idealo, 10.05.2026) [H4] ✓; RRP €149.99 [H6] ✓. Bridge **from €33.99** (idealo, 27.03.2026) [H7] ✓ | **Same white class as the Govee**, better API. Not worth buying over the bars you have |
| **Elgato Light Strip** | ✓ Local HTTP on :9123, no auth (Key Light API; HA's integration covers the Light Strip [L1] ✓). Firmware quirks: resets on HTTP/1.1 GETs, lock-ups on rapid connections [L2] | RGBWW: 6 RGB + 6 WW + 6 CW per section; 3500–6500 K [L3] ✓; CRI **not published** | **2000 lm** per 2 m; brightness range 3–100 on Key Lights [L2]. 3 % ≈ 60 lm, likely **too bright** for 20 lx on a near wall (derived). "Without visible on-camera flicker" [L4] ✓ | €59.99 in 2021 [L5]; current DE price **UNVERIFIED** | ✗ floor too high, CRI unknown |
| **LIFX** (strips, bulbs) | ✓ Best binary protocol: UDP, HSBK with **16-bit brightness**, Kelvin, acks [F1] ✓ | Model-dependent; strip CRI not found | 16-bit steps are excellent; flicker **UNVERIFIED** | **DE availability poor/UNVERIFIED** | Protocol great, product hard to get here |
| **WiZ** (Signify) | ✓ UDP :38899 `setPilot`, well established (pywizlight, HA) [W1] ✓ | Bulbs have WW/CW; strips' CRI not found | **✗ "values less than 10 % are not supported"** (hardware limit, per pywizlight) [W1] ✓ | — | ✗ can't dim low enough |
| **Nanoleaf** (Lines, Shapes, Canvas) | ✓ OpenAPI on :16021, token from holding the power button [N1] ✓ | `ct` 1200–6500 K [N2] ✓, but these panels are **RGB light**; no white emitters found (**UNVERIFIED**) | Unknown | — | ✗ white from RGB |
| **Yeelight** | ✓ Documented LAN JSON, TCP 55443 (R08 §6) | Lightstrips are RGB; Screen Light Bar Pro is a desk lamp | — | Sparse in DE | ✗ |
| **Other Govee LAN models** | ✓ same API | Same Kelvin→RGB note in the guide; CRI not published | Unknown | — | No gain over the H6056 |
| **MediaLight Mk2 v2 Flex** | ✗ as sold: **IR remote**. Option: a **MagicHome Wi-Fi controller** (+$20) [M2] ✓; MagicHome's local TCP protocol is well reverse-engineered (flux_led); that unit's PWM is **UNVERIFIED** | ✓✓ **CRI ≥ 98, TLCI 99, 6500 K ± 50 K "simulated D65"**, single white channel [M1][M3] ✓ | ✓ **25 kHz** "flicker-free" dimmer, **150 levels**, 30 of them in 0–20 % [M3] ✓. The maker notes 5 V voltage drop is visible "at very low brightness levels, like those recommended by SMPTE" [M4] ✓ | 4 m: **€99.95 excl. 21 % VAT** (FSI Europe) [M5] ✓; 2 m: **€109** (son-video.com, FR) [M6] ✓. LX1 (CRI 95, no dimmer) from **$21.95** [M7] ✓ | ✗ for adaptive: **fixed 6500 K**, can't follow the screen to 5000 K. Ideal for the colour-critical override only |
| **DIY: CCT strip + ESP32 PWM (ESPHome/WLED)** | ✓ ESPHome web server REST + SSE (what the sensor already uses) [S1] ✓, or the native API; WLED JSON API | ✓ **dedicated warm + cool white chips**; DE stock at **CRI 95** (led-konzept, 2700–6500 K COB) [D2] ✓ or CRI > 90 (LedKing) [D3] ✓; CRI 97 single-colour strips exist (§2.3) | ✓ ESP32 LEDC: **19.5 kHz at 12 bit, 4.9 kHz at 14 bit, 1.2 kHz at 16 bit** [S2] ✓. Both ≥ 3 kHz options are flicker-safe by IEEE 1789 (§2.2) | Strip **€11.80/m** [D2] ✓; QuinLED An-Penta-Mini **€51.58** (datop.nl, NL) [Q1] ✓ / official $29.99 [Q2] ✓; PSU and profile **UNVERIFIED** (~€25–40). **≈ €90–120** total | **✓ passes all six** (§3) |

### 2.1 Matter (C6)

- Driving Matter lights from a Mac **without Apple Home** is possible, but heavy. You commission the device as a second admin (multi-admin) into your own fabric, using `chip-tool` or the Open Home Foundation's python-matter-server (macOS 14+ on Apple Silicon is a supported dev environment) [T1][T2] ✓.
- That means a Matter SDK and a server process on the Mac, for a light that needs four commands.
- **Not recommended** for any candidate here; LAN or HTTP is simpler and already proven in the prototype.

### 2.2 Flicker yardstick

IEEE 1789-2015, as summarised by the US DOE [I1] ✓:
- **No observable effect:** above **3000 Hz**, with no limit on modulation depth.
- **Low risk:** above **1250 Hz**; between 90 and 1250 Hz, percent flicker ≤ 0.08 × f.

| Driver | PWM | Verdict |
|---|---|---|
| ESP32 at 4.9 or 19.5 kHz | full modulation | ✓ no observable effect |
| MediaLight's 25 kHz dimmer | — | ✓ |
| 1.2 kHz 16-bit LEDC mode | 100 % PWM | Only low-risk; **avoid** |
| Hue (~1 kHz, if the claim holds) | 100 % PWM | Only low-risk |

### 2.3 Colour match: why the strip's two white endpoints matter (derived, §7)

- Our screen white follows the **daylight locus** (RESEARCH_03 §1), which sits **Duv ≈ +0.003** above the Planckian line from 4000 to 6500 K.
- A two-white CCT strip mixes along a straight chord between its two chips. The chord **sags below** the Planckian line.

| Strip | Duv at 4000 K | at 5000 K | at 6000 K | Gap to the screen white at 5000 K |
|---|---|---|---|---|
| 2700 K + 6500 K (common) | −0.0063 | −0.0045 | −0.0015 | **≈ 0.008** (slightly pink next to the screen) |
| 3000 K + 6500 K | −0.0045 | −0.0036 | −0.0014 | ≈ 0.007 |
| 4000 K + 6500 K | 0.000 | −0.0014 | −0.0007 | ≈ 0.005 |
| 4000 K + D65-calibrated 6500 K (MediaLight-type) | — | +0.0002 | +0.0021 | **≈ 0.003** |
| Govee label white (one point) | — | — | +0.0072 at 6440 K | ≈ 0.004 at 6500 K (greenish) |

- **Practical meaning:** adaptive mode sits at 5000–6500 K (KELVIN_DIM 5000; never below KELVIN_FLOOR 4000).
- **Good:** a 2700/6500 CCT strip ("ok, slightly pink at 5000 K").
- **Better:** two single-colour high-CRI strips, **4000 K + 6500 K**, side by side in one channel, on the two PWM outputs. led-konzept notes two single-colour strips on a CCT controller behave like one CCT strip [D4] ✓. CRI 97 single-colour 4000/6500 K strips exist [D5][D6]; **DE retail availability UNVERIFIED**.
- **Best D65 at 6500 K:** MediaLight or LX1 as the cool half (5 V; needs its own 5 V channel, **UNVERIFIED** wiring effort).
- **Caveat:** our screen's white point is itself unmeasured (no colorimeter, sRGB primaries assumed; R03 §4). Gaps under ~0.005 are below what this setup can verify.

---

## 3. Ranking and recommendation (C)

| Rank | Option | C1 | C2 | C3 | C4 | C5 | Cost | Effort |
|---|---|---|---|---|---|---|---|---|
| **1** | **CRI ≥ 95 CCT strip + QuinLED An-Penta-Mini on ESPHome** | ✓ | ✓ | ✓ | ✓ | ✓ | ≈ €90–120 | ~2–3 h build + 4–8 h code |
| 2 | Keep Govee H6056 | ✓? | ? | ✗ | ✓ | ✓ | €0 | probe 07 only |
| 3 | Hue Play ×2 + Bridge | ✓ | ✓? | ✗ (CRI 80) | ✓ | ✓ | ≈ €125–150 | 4–6 h code |
| 4 | MediaLight + MagicHome Wi-Fi | ✓? | ✓ | ✓ but fixed 6500 K | ✓ | ✓ | ≈ €110–130 | — |
| ✗ | Elgato, WiZ, Nanoleaf, Yeelight, LIFX | — | — | — | — | — | — | — |

### 3.1 Primary: ESPHome-driven high-CRI CCT strip

**Parts** (EU 230 V; prices as found 2026-10-17):

| Part | Suggestion | Price |
|---|---|---|
| Strip | 24 V COB CCT, 2700–6500 K, **CRI 95**, 1520 lm/m, cut every 2.63 cm, min. bend radius 3 cm (follows the 1500R back) [D2] ✓. Need ≈ 1.0–1.5 m. *Upgrade:* 4000 K + 6500 K CRI 97 single-colour pair (§2.3) | €5.90 per 0.5 m [D2] ✓ |
| Controller | **QuinLED An-Penta-Mini**: ESP32, 5 PWM channels ("2x CCT strips"), "high PWM frequencies capable", **I²C port**, USB-C, WLED pre-installed, "also great for ESPhome" [Q2] ✓ | €51.58 incl. VAT (datop.nl) [Q1] ✓ |
| Alt. controller | Athom ESP32-C3 RGBCCT controller (WLED pre-flashed, 5–24 V; CW on GPIO4, WW on GPIO7) [Q3] ✓ | **UNVERIFIED** |
| Power | 24 V DC, ~1 A (the strip runs far below rating at bias levels) | **UNVERIFIED** (~€15–25) |
| Mounting | Aluminium profile with opal diffuser, or angled profile, VHB tape | **UNVERIFIED** (~€10–20) |
| Optional | A second TSL2591 on the controller's I²C, facing the wall (closed loop, below) | ~€10 **UNVERIFIED** |

**Why it fits:**
- **Fine low end:** at bias level the strip runs at ~1 % of full output (≈ 2000 lm for 1.3 m against ~20–30 lm needed; derived).
  - At 14-bit / 4.9 kHz, 1 % = 164 PWM counts, so steps are < 1 %.
  - ESPHome's REST `brightness` is 0–255, but with ESPHome's default perceptual gamma the operating point lands near 49/255. **One step there is ≈ 6 % luminance**, inside AC1's ± 10 % (derived).
- **White from white chips;** `color_temp` sets the warm/cool ratio. With `constant_brightness: true`, total output stays constant across Kelvin [S3] ✓.
- **Acknowledged writes:** HTTP over TCP replies, unlike the Govee's UDP. `GET /light/<name>` returns state, and the SSE stream `/events` pushes changes [S1] ✓. FR-67 reachability becomes trivial.
- **On-device transitions** (`transition=2`) make every change a smooth fade, gentler than any rate limit.
- **Same stack** as `lunarsensor.local`. You already flash ESPHome.

**Physical placement** (same rules as R08 §1a):
- Run the strip in the profile around the upper back of the cabinet, about 5–10 cm in from the edges, light facing the wall.
- Top and sides, not the bottom: the stand neck and desk would block it.
- Keep it hidden from your eye position and out of the bezel sensor's view (R08 §1a checks a–c still apply).

**Integration in the prototype** (no code changed; what it would take):

| Area | Change |
|---|---|
| Backend split | Move the rules out of `govee_apply` (coalescing, ≥ 1 step / ≥ 100 K thresholds, ≤ 1 per 2 s, off states) into a backend-neutral `bias_apply`. Add `lib/esphome_light.sh` with `bias_send <pct> <K> <transition>` via `curl -X POST "$BIAS_URL/light/$BIAS_ENTITY/turn_on?brightness=…&color_temp=<mired>&transition=…"` and `…/turn_off`. Keep `lib/govee.sh` as the second backend |
| Config keys | `BIAS_BACKEND=govee\|esphome`; `BIAS_URL=http://biaslight.local`; `BIAS_ENTITY="Bias"`; `BIAS_K_MIN/BIAS_K_MAX` (rename of `GOVEE_K_MIN/MAX`; 2700/6500 or 4000/6500); `BIAS_TRANSITION=2`. `GOVEE_GAP_MS` and the double-send of on/off are Govee-only. `BIAS_CAL` stays `pct:lux`, with pct as % of ESPHome brightness (×2.55) |
| Refresh | FR-66's 60 s blind resend becomes a 60 s `GET` and resend only if the state differs. "Don't resend `turn 1`" still holds: never switch on a light you turned off by hand |
| Probe | Generalise probe 07, or add `probe/09-bias-esphome.sh`. Keep checks A (reachable, state), B (on/off), C (K range; ends at chip CCTs), F (wall lux sweep at 1, 2, … 40 of 255, then coarser: the `BIAS_CAL` table), R (ρ) and I (flicker; expect none). Drop E (white path), G (packet gaps) and H (Matter) |
| Tests | `test/fake_esphome_light.py`: an HTTP fake with the same state file as `fake_wall_sensor.py` |
| Swift app (P8) | `URLSession` instead of `NWConnection` UDP plus multicast. P8-T02's multicast-entitlement risk goes away. Local Network permission is still needed |
| Optional closed loop | A TSL2591 on the controller, facing the wall, publishes "wall lux" over the same SSE. lightd (or an ESPHome lambda) trims brightness to π·5/ρ. Calibration then can't drift with strip ageing or ρ guesses. This is a SPEC change (new FR), so it's optional |

### 3.2 Fallback: keep the Govee H6056

- Use it now. Run probe 07 (P0b-T04) as planned, then apply D0b, with one addition: **CRI 80 / R9 2 is already known**, so D0b's "fixed D65 strip for colour-critical work" branch applies whatever check E shows, **if colour-critical work matters to you**.
- If check F shows 1 % steps > 10 % at the operating point, either accept the nearest step (relax AC1 to ± 20 % for the Govee) or move to the primary.
- **If Govee LAN doesn't work at all** (check A fails) and you don't want the DIY kit, Hue Play + Bridge is the off-the-shelf fallback. It has the same white quality and a reliable, acknowledged API.
- **Return window:** the bars arrived 2026-10-13 (HANDOFF). If you'd rather return them, Amazon.de's usual window is 30 days from delivery; check your order. The exact deadline is **UNVERIFIED**.

---

## 4. Whole brightness system check (D)

### 4.1 Current settings: keep or change

| Setting | Now | Verdict |
|---|---|---|
| `BRIGHTNESS_CURVE` `0:0,10:0,50:1,100:7,200:17,300:22,500:31,1000:76,2000:100` | R07 targets inverted through KitGuru | **Keep.** Probe 08 Part A corrects it for your unit |
| `BRIGHTNESS_MIN=0` | floor ~55 cd/m² (≈ 48 at 5000 K) | **Keep** |
| `LUMINANCE_COMPENSATION=0` | — | **Keep** (R07 §3 reasoning stands) |
| `KELVIN_DIM=5000` at ≤ 10 lx, `KELVIN_FLOOR=4000` | — | **Keep.** Pick the strip's warm endpoint for this range (§2.3): 4000 K is enough, 2700 K isn't needed |
| `GOVEE_K_MIN=2200` | — | Harmless. The screen never asks below 4000 K, so the bias light never goes below either |
| `BIAS_TARGET_NITS=5`, `BIAS_MAX=15`, `BIAS_OFF_LUX=60/40` | — | **Keep.** With blackout blinds the bias light will be on most of the time, which is intended |
| US-7 AC1 ± 10 % | — | **Keep for the DIY strip.** For the Govee it may need relaxing after check F (§1.2) |

### 4.2 Does a 5 cd/m² surround justify the 55 floor?

**Mostly yes.** Reasons and limits:
- **Ratio:** night screen ~48 cd/m² against a 5 cd/m² surround is **≈ 10:1**. That matches ST 2080-3's 10 %-of-white heritage (BT.2035) and the ISO 9241-303 1:10 guidance (R07 §4, UNVERIFIED there). With no bias light, the ratio is effectively unbounded.
- **It won't make the screen *look* dimmer.** Baek et al. 2013 found perceived monitor brightness "little changes" while the surround stays below the monitor's luminance (surround ratio < 1) ✓ [P1]. The gain is comfort (less contrast between screen and surroundings), not perceived brightness.
- **The 20–36 cd/m² range is a dark-room result.** Zhou 2021 measured it with the room at 0 lx (R07 §1).
  - Na & Suk 2014: in dark environments, the preferred object luminance *rises* with viewing time ✓ [P2].
  - Rempel 2009: older viewers prefer about 0.3 log₁₀ (≈ 2×) higher brightness ✓ [P3].
  - So ~48 cd/m² for long evening sessions is plausibly fine. **The soak decides**, with `bin/light dimmer` nudges as the evidence.

### 4.3 Go below the backlight floor? (R07 §4)

**Not now.** If the soak with the bias light **on** still says "too bright at night", do this:
- **Smallest change: no extra writes.** Fold one fixed night factor (e.g. ×0.7) into the gain set that already happens when the white point warms at dusk.
  - Example (5000 K row 50/43/35, gains linear with an offset of ~5, R03 §2): × 0.7 in linear light → about **37/32/26** (derived).
  - The screen goes to ≈ 34 cd/m², inside Zhou's range.
- **Costs:**
  - **Contrast ratio drops ≈ 30 %**, because black stays where the backlight puts it (derived).
  - **About 0.5 bit of tonal resolution is lost**, a banding risk in dark gradients (derived).
  - Colour-critical mode must still restore 50/50/50 (it does today).
- **Process:** it's a new requirement, so it goes through SPEC. It isn't "software dimming", which is a non-goal, but it's close in effect.
- **Don't** make it continuous with lux: that would multiply gain writes against `GAIN_DAILY_CAP`.

### 4.4 Other system notes

- **Bias light vs the bezel sensor:**
  - The strip or bars light the wall behind; the TSL2591 faces you. Check F, bias on vs off, still applies to any bias hardware.
  - A strip on the cabinet's upper back edge is closer to the bezel than the Govee bars. Keep its profile pointed backwards, and repeat the check.
- **Bias Kelvin source:** keep "screen's target K". With the DIY strip, also send the colour-critical 6500 K. A 4000 K + 6500 K pair at full cool is just the 6500 K chips.

---

## 5. Open questions for you (E)

| # | Question | Why it matters |
|---|---|---|
| 1 | **Gap from the monitor's back to the wall** (cm)? | Under ~10 cm, use an angled profile or aim sideways (R08 §1a) |
| 2 | **Wall colour and finish** (white/grey/coloured; matte/glossy)? Anything on it (shelves, posters, a window)? | Tint and ρ; ST 2080-3 wants a neutral grey/white matte surround |
| 3 | **Budget ceiling** for replacing the bias light: €0 (keep Govee), ~€100 (DIY), more? | Picks primary vs fallback |
| 4 | **OK with screw-terminal assembly** (no soldering) and a 24 V wall-wart behind the desk? | The DIY kit needs it |
| 5 | **Do you do colour-critical work** (photo/video grading, print proofing)? | If yes, a D65-accurate 6500 K (MediaLight or 4000 K + D65 pair) matters; if not, CRI 95 CCT is plenty |
| 6 | Do you want **RGB effects** ever? | If not, CCT-only is simpler and better; if yes, keep the Govee for effects (by hand, in the Govee app) |
| 7 | **Return the Govee, or keep it** (effects, a second room, the fallback)? When was it delivered? | Return deadline (§3.2) |
| 8 | Has **probe 07** run? Results for checks A, E, F, I? | Settles the Govee's floor, steps and white path |
| 9 | Is 2.4 GHz Wi-Fi good **behind the monitor**? (The An-Penta-Mini has an external antenna) | Reliability of either option |
| 10 | Is the CU34G4Z's back flat enough above the VESA plate for a 1–1.5 m profile run, or is it ribbed/curved there? (photo helps) | Mounting choice |
| 11 | Want the **optional wall sensor** (closed loop)? | One more SPEC FR; removes `BIAS_CAL` drift |

---

## 6. Assumptions

| Assumption | If wrong |
|---|---|
| EPREL 857551 describes your unit (2026 revision) | Older units may differ; the label on the box or the Govee app's model page settles it |
| EPREL's 430 lm is for the pair | If it's per bar, the operating point halves to 1.5–4 % and steps get coarser |
| ESPHome's perceptual gamma ≈ 2.8 applies through the REST `brightness` | Step size at the operating point differs; check F (generalised) measures it |
| The screen white follows the daylight locus | If the panel's 50/50/50 isn't D65 (R03 Q11), the §2.3 gaps shift by an unknown amount |
| ~1.3 m of strip at ~1500 lm/m | Shorter runs mean a higher duty cycle, which is still fine |

---

## 7. Calculations

- [`calc/duv.py`](calc/duv.py): Krystek 1985 Planckian uv approximation, CIE daylight-locus formula, linear XYZ mixing of two whites, CCT/Duv by nearest point on the locus (5 K grid). Sign convention: + = above the locus (greenish).
- [`calc/mix2.py`](calc/mix2.py) (run from `calc/`; it imports `duv.py`): the 4000 K Planckian + D65 mix. Results are in §1.1 and §2.3. Duv values are accurate to about ± 0.0005, which is enough for the comparisons made here.

---

## 8. Sources

**Govee**
- [E1] ✓ EPREL product information sheet 857551 (H6056), https://eprel.ec.europa.eu/fiches/lightsources/Fiche_857551_SL.pdf (fetched via Exa; the eprel host failed DNS for WebFetch).
- [G9] ✓ Govee WLAN guide, https://app-h5.govee.com/user-manual/wlan-guide.
- [G10] ✓ openHAB Govee LAN binding (lists "H6056 Flow Plus"), https://www.openhab.org/addons/bindings/govee/.
- [G26] ✓ govee2mqtt `test-data/undoc-device-list-issue-21.json` (local clone from an earlier session), https://github.com/wez/govee2mqtt.
- [G27] govee-h6056 "gotchas" note, https://tessl.io/registry/jbaruch/govee-h6056/files/rules/govee-h6056-gotchas.md (search extract only; host failed DNS).

**Hue**
- [H1] ✓ Hue Developer Program support FAQ (≈ 10 commands/s to lights, 1/s to groups), https://developers.meethue.com/support/.
- [H2] ✓ Microsoft connector docs for the Hue v2 `mirek` field (153–500), https://learn.microsoft.com/uk-ua/connectors/philipshueip.
- [H3] ✓ Philips Hue RO product page (RGBW, 500 lm at 4000 K, 253 × 44 mm), https://www.philips-hue.com/ro-ro/p/hue-white-and-color-ambiance-pachet-individual-cu-bara-cu-joc-de-lumini/7820130P7.
- [H4] ✓ idealo.de, Hue Play single pack (Farbwiedergabe 80 Ra), https://www.idealo.de/preisvergleich/OffersOfProduct/6292030_-hue-white-and-color-play-lightbar-einzelpack-philips.html; double pack from €91.90 (data 10.05.2026), https://www.idealo.de/preisvergleich/OffersOfProduct/6291943_-hue-play-lightbar-doppelpack-philips.html.
- [H5] Hobbyist flicker measurement claiming 1 kHz PWM on Hue, https://github.com/WolfgangFranke/LightFlickerMeasure (search extract; **UNVERIFIED**).
- [H6] ✓ Philips Hue DE, Play double pack €149.99, https://www.philips-hue.com/de-de/p/hue-white-color-ambiance-play-lightbar-doppelpack/7820231P7.
- [H7] ✓ idealo.de, Hue Bridge from €33.99 (data 27.03.2026), https://www.idealo.de/preisvergleich/OffersOfProduct/4899382_-hue-bridge-philips.html; Bridge Pro from €82.94 (data 14.10.2026), https://www.idealo.de/preisvergleich/OffersOfProduct/207731432_-hue-bridge-pro-philips.html.

**Elgato**
- [L1] ✓ Home Assistant Elgato integration (includes Light Strip, local), https://www.home-assistant.io/integrations/elgato.
- [L2] Elgato local API notes (port 9123, brightness 3–100, firmware quirks), https://git.sub-net.at/tina.schellander/elgato-cli and https://www.powershellgallery.com/packages/elgato/0.3.4/Content/elgato.psm1 (search extracts).
- [L3] ✓ Elgato Light Strip technical specifications, https://help.elgato.com/hc/en-us/articles/360057812551.
- [L4] ✓ Elgato Control Center 1.1.4 release notes, https://help.elgato.com/hc/en-us/articles/4583255663117.
- [L5] Xataka review (€59.99, 2021), https://www.xataka.com/analisis/elgato-light-strip-analisis-caracteristicas-precio-especificaciones.

**LIFX, WiZ, Nanoleaf**
- [F1] ✓ LIFX LAN protocol, https://lan.developer.lifx.com/docs/changing-a-device and https://lan.developer.lifx.com/docs/representing-color-with-hsbk.
- [W1] ✓ pywizlight `bulb.py` (UDP 38899; "values less than 10% are not supported"), https://github.com/sbidy/pywizlight/blob/master/pywizlight/bulb.py.
- [N1] ✓ Nanoleaf API Quick Start (port 16021, token), https://support.nanoleaf.me/hc/en-us/articles/41105798500628-API-Quick-Start-Guide.
- [N2] ✓ Nanoleaf OpenAPI docs (ct 1200–6500), https://nanoleaf.atlassian.net/wiki/spaces/nlapid/pages/2789310530.

**MediaLight**
- [M1] ✓ MediaLight Mk2 v2 Flex product page, https://www.biaslighting.com/products/medialight-mk2-flex-6500k-cri-98-bias-lighting.
- [M2] ✓ MediaLight DE page (MagicHome Wi-Fi controller option), https://de.biaslighting.com/products/medialight-mk2-flex-6500k-cri-98-bias-lighting.
- [M3] ✓ "What's new in Mk2 v2" (25 kHz, 150 levels), https://www.biaslighting.com/blogs/news/medialight-mk2-v2-whats-new-with-the-latest-update-to-our-flagship-product.
- [M4] ✓ AV Nirvana thread, maker's reply on voltage drop at SMPTE levels, https://www.avnirvana.com/threads/medialight-unveils-the-ultimate-mk2-v2-bias-light-new-features-and-first-impressions.14231/.
- [M5] ✓ FSI Europe, Mk2 v2 Flex 4 m, https://www.shopfsi.eu/mvc/article?id=601.
- [M6] ✓ Son-Vidéo, Mk2 Flex 2 m €109, https://www.son-video.com/article/accessoires-extras-accessoires-tv/bias-lighting/medialight-mk2-flex-2-m.
- [M7] ✓ LX1 product page, https://www.biaslighting.com/products/lx1-bias-lighting-cri-95-6500k-simulated-d65-white-bias-lights.

**DIY parts and firmware**
- [D2] ✓ led-konzept.de CCT COB 24 V CRI 95, https://www.led-konzept.de/CCT-COB-LED-Streifen-24V-dualweiss-154W-m-warmweiss-kaltweiss.
- [D3] ✓ LedKing.de 24 V COB CCT CRI > 90, €59.90 / 5 m, https://www.ledking.de/24V-COB-CCT-LED-Strip-5m-608-LEDs-m-2700-6500K-CRI-90.
- [D4] ✓ led-konzept.de CCT category (two single-colour strips on a CCT controller), https://www.led-konzept.de/CCT-LED-streifen-dualweiss.
- [D5] ZBL Lighting CRI 97 COB 4000/6500 K, https://www.zbllight.com/cob-320led-strip-light-custom.html (manufacturer; EU retail **UNVERIFIED**).
- [D6] Super Bright LEDs 97 CRI single white, https://www.superbrightleds.com/5m-ultra-high-97-cri-led-strip-light-lux-tape-light-24v-up-to-768-lm-ft-single-white-2700k-3000k-3500k-4000k-5000k-6500k (US).
- [Q1] ✓ datop.nl, QuinLED An-Penta-Mini €51.58 incl. VAT, https://www.datop.nl/Huis-en-kantoor/Quinled-LED-verlichting/An-Penta/QUINLED/QuinLED-AN-Penta-Mini-QLD-APMINI-p_41973.html.
- [Q2] ✓ QuinLED An-Penta-Mini, https://quinled.info/quinled-an-penta-mini/ and buying page https://quinled.info/an-penta-mini-buying-page/.
- [Q3] ✓ Athom ESP32-C3 RGBCCT controller, https://www.athom.tech/blank-1/wled-rgbcct-analog-and-digital-light-strip-controller.
- [S1] ✓ ESPHome Web Server API, https://esphome.io/web-api/.
- [S2] ✓ ESPHome LEDC output (frequency vs bit depth table), https://esphome.io/components/output/ledc/.
- [S3] ✓ ESPHome light component (colour modes, `color_temperature`), https://esphome.io/components/light/; colour-temperature platform, https://esphome.io/components/light/color_temperature/.
- WLED: default PWM 19,531 Hz on ESP32 and analog CCT support ✓, https://kno.wled.ge/basics/compatible-led-strips/; PWM dithering and CIE curve ✓, https://github.com/wled/WLED/blob/02f14baa/wled00/bus_manager.cpp.

**Flicker**
- [I1] ✓ US DOE SSL Postings, 11 June 2015 (summary of IEEE 1789-2015 limits), https://www.energy.gov/sites/prod/files/2015/06/f22/postings_06-11-15.pdf.

**Matter**
- [T1] ✓ python-matter-server (macOS 14+ Apple Silicon dev support), https://github.com/home-assistant-libs/python-matter-server/blob/main/docs/os_requirements.md.
- [T2] ✓ Nordic, CHIP Tool multi-admin guide, https://docs.nordicsemi.com/bundle/ncs-3.3.0/page/matter/chip_tool_guide.html.

**Perception**
- [P1] ✓ Baek Y.S. et al., "Monitor Brightness Perception Changes under Various Surround Condition", CIC 2013, https://doi.org/10.2352/cic.2013.21.1.art00008.
- [P2] ✓ Na N., Suk H.-J., "Adaptive and Affective Luminance Contrast on Optimal Brightness of Displays", CIC 2014, https://doi.org/10.2352/cic.2014.22.1.art00013.
- [P3] ✓ Rempel A. et al., preferred HDR display brightness vs ambient (UBC, 2009), https://www.cs.ubc.ca/labs/imager/tr/2009/Rempel_Pref_Ambient/Rempel_Pref_Ambient.pdf.

**Local docs:** R03 (white point, gains), R05, R07 (curve, floor), R08 (Govee, physical setup), SPEC FR-60–FR-67, BUILD_PLAN Phase 0b / D0b.
