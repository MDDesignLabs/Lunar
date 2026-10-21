# Buy list: CRI 95 bias strip (replaces the Govee bars)

Status: 2026-10-21. Prices were read from the shops' own pages today (✓) unless marked. They change, so check the basket. Background: RESEARCH_09 §3 and DESK_SETUP.md.

## Ready-made option, no assembly (2026-10-21; the user prefers this)
**Philips Hue Play Gradient Lightstrip for PC, 32–34″** + **Hue Bridge**
- **Price:** strip €109.68 on [Amazon.de](https://www.amazon.de/Philips-Hue-Lightstrip-steuerbar-kompatibel/dp/B0BB6NM186) (ASIN B0BB6NM186) ✓. Bridge from €33.99 (idealo, RESEARCH_10 [H7]). Total ≈ **€145**. Hue's own DE "Starter Set + Bridge" is listed at €109.99 (was €219.99) but marked "nicht mehr verfügbar" ✓.
- **Specs (philips-hue.com ✓):**
  - 116.5 cm, not cuttable, mounts with the included clips and bends round the monitor's corners;
  - 2000–6500 K, **CRI > 80**, 1000 lm at 4000 K, 19 W;
  - "gradient coloured and white light (RGBICW)".
- **App control:** the Hue Bridge has a documented local REST API (CLIP v2; R09 [H1]: about 10 commands/s to a light, 1/s to groups). No cloud is needed ("works without Wi-Fi"). It's the easiest backend for our app to add.
- **Low end:** 1 % of ~1000 lm ≈ 10 lm, below the ~20–30 lm the bias needs (R09), so it can dim low enough.
- **Trade-off:** the white is the same class as the Govee's (CRI 80, not 95). The gain over the Govee is an even glow, a reliable local API and monitor-specific mounting.

## The build-it option below
## Why this one
- **Even glow:** a continuous COB line around the back of the monitor, not two pools of light.
- **Real white:** separate warm (2700 K) and cool (6500 K) white LEDs, CRI 95. The Govee bars are CRI 80 on the EU label.
- **Fully automatic:** our app talks to the controller over the LAN by HTTP, and every command is acknowledged.
- **Flicker-free:** the controller dims at about 20 kHz PWM.

## The parts

| # | Part | Exact item | Qty | Price | Shop |
|---|---|---|---|---|---|
| 1 | **Strip** | led-konzept **CCT COB LED Streifen 24V dualweiß 15,4 W/m**: 2700–6500 K (± 100 K), **CRI 95**, 1520 lm/m, 608 LEDs/m, 10 mm wide, cut every 2.63 cm, bend radius 3 cm, common anode | **3 × 0.5 m = 1.5 m** (one piece) | €5.90 per 0.5 m → **€17.70** ✓ | [led-konzept.de](https://www.led-konzept.de/CCT-COB-LED-Streifen-24V-dualweiss-154W-m-warmweiss-kaltweiss) |
| 1a | Strip connection | Choose "Anschlusslitze **200 cm**" on the strip page (pre-soldered leads, no soldering), **or** a CCT strip-to-cable connector, 10 mm | 1 | Lead surcharge **UNVERIFIED**; connector **from €1.59** ✓ | [led-konzept connectors](https://www.led-konzept.de/Strom-Verbinder) |
| 2 | **Controller** | **QuinLED An-Penta-Mini**: ESP32-C3, 5 PWM channels (CCT = 2), ~20 kHz flicker-free PWM, aluminium case, colour-coded screw terminals, external antenna, fuses included; ESPHome or WLED | 1 | **€51.58** incl. VAT ✓ (datop.nl, in stock) · **€44.99** (QuinLED NL, from the reseller hub; **UNVERIFIED** on the shop page) + €7.95 shipping to DE ✓ | [datop.nl](https://www.datop.nl/Huis-en-kantoor/Quinled-LED-verlichting/An-Penta/QUINLED/QuinLED-AN-Penta-Mini-QLD-APMINI-p_41973.html) · [quinled.shop](https://quinled.shop/product/an-penta-mini/) |
| 3 | **Power supply** | **Mean Well GST36E24-P1J**: 24 V, 1.5 A, 36 W, EU plug, 5.5/2.1 mm barrel | 1 | **€13.10** ✓ (Conrad; check whether this is incl. VAT in the basket) | [conrad.de](https://www.conrad.de/de/p/mean-well-gst36e24-p1j-steckernetzteil-festspannung-24-v-dc-1500-ma-36-w-1439201.html) |
| 4 | Barrel → screw adapter | DC socket 5.5/2.1 mm with screw terminals (to feed the controller's input terminals) | 1 | ≈ €1–3 **UNVERIFIED** | Conrad or Amazon.de, "DC Buchse 5,5 x 2,1 Schraubklemme" |
| 5 | Double-sided tape (optional) | Extra 3M VHB strips, if the strip's own 3M tape doesn't hold on the monitor's plastic | — | ≈ €5 **UNVERIFIED** | Any |

**Not needed:**
- **Aluminium profile:** the CU34G4Z's 1500R back curves ~4 cm over a 70 cm run, so a rigid profile won't sit flat. COB has no dots to hide, and the strip faces the wall where you never see it. At bias levels it runs at ~1 % power, so heat isn't a concern either.
- **A separate dimmer or remote:** the controller does everything.

## Cost
| Item | € |
|---|---|
| Strip 1.5 m + leads/connector | ≈ 19–22 |
| led-konzept shipping (DHL, under 120 cm) | 5.99 ✓ |
| Controller (datop.nl, with shipping, or QuinLED NL €44.99 + €7.95) | ≈ 52–53 |
| Power supply + adapter | ≈ 15–16 |
| Conrad shipping | **UNVERIFIED** (≈ 0–6) |
| **Total** | **≈ €92–103** |

**Saving shipping:** led-konzept also sells 24 V supplies and adaptors (prices not checked). Ordering those with the strip drops the Conrad order.

## Budget alternative (not recommended)
- **Gledopto ESP32 WLED PWM controller** (GL-C-211WL family): 5 channels, CCT-capable, 12–24 V. About $17 (ledbe.com), or a PWM variant from gledopto.eu (the base model is €24.99 plus a €5 PWM surcharge, **UNVERIFIED** which product).
- It saves ≈ €20, but its **PWM frequency and low-end steps aren't documented**. Those are exactly the night-time qualities this strip is for.

## Fitting (≈ 1–2 h, screw terminals only)
1. **Cut:** about 1.2–1.5 m, at a printed cut mark.
2. **Place:** run it round the upper back of the monitor, 5–10 cm in from the edges, light facing the wall. Optionally run part of it down both sides. Don't put it behind the stand (RESEARCH_08 §1a).
3. **Wire** the strip to the controller:

   | Strip | Controller |
   |---|---|
   | Red (+, common anode) | + output |
   | Warm-white wire | Channel 1 |
   | Cool-white wire | Channel 2 |

   Power supply → barrel adapter → the controller's 24 V input. Check + and − before plugging in.
4. **Flash ESPHome:** the controller arrives with WLED, and I'll give you the ESPHome config (as with `lunarsensor`). Then the app gets a new bias backend, no Govee needed. Tested against a fake before the parts arrive.

## Then
- **Return the Govee bars** (Amazon.de, delivered 2026-10-13, about 30 days).
- **The light bar (Xiaomi) and the room lamp** (RESEARCH_10) are unchanged.
