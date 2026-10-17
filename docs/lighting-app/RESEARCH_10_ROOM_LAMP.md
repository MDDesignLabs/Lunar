# Research 10: Which room lamp to buy, where to put it, and how the app should drive it

Status: research, 2026-10-17. One research agent, web sources plus local calculations. **No hardware tested.** ✓ = I read the primary page's text in this session (fetched, or as a search extract of that page). **UNVERIFIED** = not confirmed, with what would settle it. "Derived" = my own calculation from cited numbers (the script is in §7). WebFetch failed DNS for ikea.com and eprel.ec.europa.eu, so those pages were read through Exa's fetcher or search extracts; where only an extract was read, the source line says so.

**The ask:** "Which lamp should I get?" This is the **room light**, the third layer after the bias light (behind the monitor) and the Xiaomi desk bar (on top of it). It stands **beside you**, roughly level with or a little behind your shoulder. Its job is to lift the room in the evening so the screen isn't the only bright thing in a blackout room, without reflecting in the screen or shining in your eyes.

---

## Summary

1. **Primary pick (≈ €100): an IKEA TÅGARP floor uplighter + IKEA KAJPLATS 1521 lm smart white-spectrum bulb + the IKEA DIRIGERA hub.**
   - **Lamp:** TÅGARP is an opaque bowl at 180 cm. Light goes only to the ceiling, so you never see the bulb from the chair. **€9.99** [K5] ✓.
   - **Bulb:** KAJPLATS 1521 lm (LED2408G10). IKEA rates it **CRI 90**; it is Matter over Thread. **€9.99** [K1] ✓.
   - **Hub:** DIRIGERA is the Thread border router, and it has a **local HTTPS REST API** (port 8443, a token you get by pressing the hub's button, a websocket for events). IKEA doesn't document the API, but a maintained client library (v1.4.1, 12 Oct 2026) lists KAJPLATS as working [K7][K8] ✓. **€79.99** [K4] ✓.
   - **Why it wins:** it's the only CRI ≥ 90 tunable-white E27 bulb I found that is sold in Germany *and* reachable from our app without Apple Home or the cloud. Everything is IKEA, which also sells KAJPLATS in Jordan [K3] ✓, and IKEA's 365-day return covers the flicker risk below.
   - **Its one real gap:** **nobody has measured KAJPLATS flicker.** The only report is a blog's 240 fps video, "no visible flicker" [K10] (weak). Probe check RL-F (§4.5) decides whether it stays.
2. **Budget pick (≈ €20): the same TÅGARP + a Shelly Duo Bulb E27 Gen3 (€9.90)** [S2] ✓. No hub, and **Shelly documents its local API** (`/cct/0?turn=on&brightness=…&temp=…&transition=…`, or RPC `CCT.Set`) [S3] ✓. It covers 2700–6500 K at 806 lm, but **CRI is only "> 80"** [S1] ✓, and its flicker is unmeasured.
3. **Fallback: the same lamp + Philips Hue White Ambiance E27 1100 lm (≈ €32) + Hue Bridge (≈ €34).** Use it if KAJPLATS flickers or DIRIGERA's API misbehaves.
   - Hue has the **best-documented local API** of any option (R09 [H1] ✓), and it is **the one candidate with independent measurements**: it dims to **≈ 1–2 lm**, its tint is close to neutral, and it is graded **"low risk"** for flicker (PWM ≈ 1.2 kHz) [P1][P2] ✓.
   - **The price is CRI 80, R9 0**, on Signify's own EU sheet [E1] ✓.
4. **Don't buy a Govee floor lamp for this job.** It would run on the Govee LAN code you already have (H607C, H60B0 and H6076 are on Govee's LAN list [G1][G2] ✓). But no CRI is published, LAN white may be mixed from RGB (R09 [G9]), and the two Govee bulbs that were measured never dim below **≈ 100 lm** [P1] ✓. That is far too bright for a night room. The LEDs are also built in, so the lamp can't take a better bulb.
5. **How the app should drive it** (§4):
   - **Ask once, then follow.** The app asks once per evening; after your yes, it follows the clock: brightness by time of day, Kelvin = the screen's target Kelvin.
   - **Never on by itself.** The app never switches the lamp on without your yes, and never re-lights it after you turned it off.
   - **The bezel sensor will see the lamp.** The screen's backlight hardly moves (the curve is ≈ 0 % below ~20 lx). But the lamp's light **would push the evening Kelvin back up** (≈ 4250 K at 20 lx, ≈ 5250 K at 50 lx, derived), and it could also switch the bias light off or withdraw the desk-bar prompt.
   - **Fix:** measure the lamp's contribution at the bezel once (probe), then subtract it ("room lux without our lights") for Kelvin, bias on/off and the desk-bar prompt. Brightness keeps the measured lux. **The lamp's level never depends on lux**, so no feedback loop is possible.

---

## 0. What "best" means here (scorecard)

| # | Constraint | Pass means |
|---|---|---|
| L1 | Side form factor, indirect | Bulb never visible from the chair; no mirror image on the 1500R screen (§3) |
| L2 | Smooth, low, flicker-free | Reaches ~5 lx at the desk with fine steps; measured or rated flicker in IEEE 1789's low-risk zone or better (R09 §2.2) |
| L3 | Tunable white from white emitters, CRI ≥ 90 preferred | Rated or measured; 2200 (or 2700) – 6500 K |
| L4 | Local API, no cloud | Works with the internet unplugged, from shell and Swift; Matter counts only if we can drive it without Apple Home |
| L5 | Buyable in DE, € price; travels to Amman | 230 V; E27 preferred; plug/adaptor noted |

**A note on CRI for this lamp:** its light doesn't reach the screen, and your colour judgements are made on the screen (HANDOFF: UI/UX for sRGB screens). So CRI here affects paper, skin, the desk and the room, not your design work. CRI ≥ 90 stays "preferred" (your rule), but flicker and low-end dimming matter more for evening comfort, and I weight them that way.

**A note on EU flicker labels:** every mains bulb sold in the EU since 09/2021 must meet Pst_LM ≤ 1.0, and since 09/2024 SVM ≤ 0.4 [F1] ✓. **These limits apply at full load only;** dimmed states aren't covered [F1] ✓. So an EPREL sheet saying "Pst 1.0 / SVM 0.4" tells you nothing about the 5–30 % levels this lamp will live at. Only independent measurements do [P1][P3].

---

## 1. Recommendation

### 1.1 Primary: TÅGARP uplighter + KAJPLATS 1521 lm + DIRIGERA

| Part | What | Price (DE, incl. VAT) | Source |
|---|---|---|---|
| Lamp | **IKEA TÅGARP Deckenfluter**, black/white, 180 cm, shade Ø 24 cm, E27, max 13 W, cord 80 cm | **€9.99** | [K5] ✓ (ikea.com/de extract, 2026-10-17) |
| (alt.) | TÅGARP Deckenfluter/Leseleuchte (uplighter + E14 reading arm), 178 cm, max 21.6 W, cord 100 cm | €14.99 | [K5] ✓ |
| Bulb | **KAJPLATS E27 1521 lm, smart white spectrum, opal globe** (LED2408G10, 9.5 W, class C) | **€9.99** | [K1] ✓ (ikea.com/de extract) |
| (alt.) | KAJPLATS E27 1055 lm white spectrum (LED2407G8, 7.8 W, class D) | €8.99 | [K2] ✓ (fetched via Exa, 2026-10-17) |
| Hub | **DIRIGERA** (Thread border router + Zigbee; local API) | **€79.99** | [K4] ✓ (fetched via Exa, 2026-10-17) |
| **Total** | | **≈ €100** | |

**Why each part:**
- **TÅGARP:** the cheapest pure uplighter with an opaque bowl. From a seated eye height (~120 cm), a 180 cm rim hides the bulb completely. The light reaches you only after bouncing off the ceiling, so nothing bright sits near your eye line, and the reflection check passes with margin (§3). The 13 W cap fits the 9.5 W bulb.
- **Why 1521 lm and not 1055:** an uplighter loses light into the ceiling and walls. Derived (§7): 1521 lm at 100 % gives ≈ 65 lx at the desk with a white ceiling; 1055 lm gives ≈ 45 lx. Your evening target is 20–50 lx, so 1521 lm leaves headroom for a darker ceiling or a bigger room, and night levels sit at 10–30 %, where the steps are finer.
- **KAJPLATS:** IKEA lists **"Colour rendering 90"** for both the 1055 and 1521 lm white-spectrum bulbs [K1][K2] ✓. The 1055 lm page lists the **2200 / 2700 / 4000 / 6500 K** range [K2] ✓; the same range on the 1521 lm bulb is **UNVERIFIED** (its page shows only the 2700 K default).
  - The R9 value and spectrum aren't published. I didn't find the EPREL sheet for LED2407G8 or LED2408G10 (**UNVERIFIED**; the QR code on the box opens it).
  - The older Zigbee TRÅDFRI white-spectrum bulbs measured **CRI 87–94** but were often rated **"high flicker risk"** [P1] ✓. KAJPLATS is a new design, so that history is a warning, not a verdict.
- **DIRIGERA API** [K7][K8] ✓ (GitHub README and source, PyPI page):
  - `https://<hub>:8443/v1/devices`, with `Authorization: Bearer <token>`. You get the token once, by pressing the hub's action button during `generate-token`.
  - `PATCH /v1/devices/<id>` with `[{"attributes":{"lightLevel":30}}]` (1–100) and `colorTemperature` (Kelvin). A websocket at `wss://<hub>:8443/v1` pushes state changes.
  - The hub uses a **self-signed certificate** (the library sets `verify=False`).
  - **Rate limits aren't documented.** The library doesn't throttle; keep ≤ 1 command per 2 s as for the Govee.
  - It is **undocumented by IKEA, and firmware can change it** [K7] ✓. That is the price of CRI 90 here.
- **Matter without Apple Home?** KAJPLATS is a Matter device, but Thread needs a border router (DIRIGERA, HomePod, Apple TV…). Driving Matter from our own app means running our own Matter controller (python-matter-server or chip-tool, R09 §2.1). Going through DIRIGERA's REST is far simpler. **Matter doesn't count as the app's path here.**
- **Portability to Amman:**
  - IKEA Jordan lists KAJPLATS bulbs [K3] ✓, so replacements are local. DIRIGERA in Jordan is **UNVERIFIED**.
  - Jordan is 230 V / 50 Hz with sockets of **types C, D, F, G and J** (some sources add B) [J1] ✓.
  - A German lamp's Euro (C) or Schuko (F) plug fits C, F and J sockets; G (UK-style) and D sockets need an adaptor. Bring two cheap C→G adaptors (one for the lamp, one for the hub's power supply). Which plug the TÅGARP and the DIRIGERA PSU have is **UNVERIFIED**; check the box.

### 1.2 Budget: TÅGARP + Shelly Duo Bulb E27 Gen3 (≈ €20)

- **Bulb** [S1][S2] ✓: Shelly Duo Bulb E27 Gen3 (ESP32-C3, Wi-Fi + BLE), **€9.90** at shelly.com. 806 lm, 2700–6500 K, **CRI > 80**, 15,000 h.
- **API** [S3] ✓: **officially documented, local, no hub.**
  - HTTP: `GET /cct/0?turn=on&brightness=0..100&temp=2700..6500&transition=500..10800000` (ms). It returns `ison`, `brightness` and `temp`, so commands are acknowledged.
  - RPC: `CCT.Set {id, on, brightness, ct, transition_duration}`, plus MQTT and webhooks. That's the same shape as our ESPHome sensor: easy `curl`, easy `URLSession`.
- **Gaps:**
  - CRI only > 80.
  - 806 lm in an uplighter gives ≈ 34 lx at the desk at 100 % (derived). That's enough for evenings, with little headroom.
  - Flicker, low end and Duv are unmeasured for Gen3. The Hook Up found Shelly bulbs (an earlier generation) "dim impressively low to less than 1 lumen", but slightly **green-shifted (positive Duv)** [P3] ✓.
- **When to choose it:** you want the cheapest working setup now and accept CRI 80. It's also a no-regret first step, since the TÅGARP stays whichever bulb wins.

### 1.3 Fallback: TÅGARP + Hue White Ambiance E27 1100 lm + Hue Bridge (≈ €66)

- **Price:** bulb from **€31.70** (billiger.de, October 2026) [E3] ✓; idealo shows €22.90 for an unboxed unit (data 2026-10) [E4] ✓. Bridge from **€33.99** (idealo, 27.03.2026; R09 [H7]) ✓.
- **API:** Hue CLIP v2. Local HTTPS, app key from the link button, ≈ 10 commands/s to lights, colour temperature in mirek 153–500, acknowledged (R09 [H1][H2]) ✓. It also takes any Zigbee 3.0 bulb, e.g. innr.
- **White quality:**
  - **Official:** EPREL 406179 (Hue White Ambiance E27 806 lm, 9290024684, 2021–2023) lists **CRI 80, R9 0, Pst_LM 1.0, SVM 0.4** [E1] ✓. The current White and Colour 1100 lm sheet (9290038535H) also lists **CRI 80, R9 0** [E2] ✓.
  - **Measured** (US Hue White Ambiance A19, LTA025):
    - CRI Re **81** averaged (Ra 86–88 at warm settings);
    - dims to **1.1–2.0 lm**;
    - tint −0.0014 to +0.0031 Duv (near neutral);
    - percent flicker **32 % at full, 97 % at half**, graded "low risk" [P2] ✓.
  - **Flicker frequency:** The Hook Up measured Hue Zigbee bulbs' PWM at **1.2 kHz** [P3] ✓. That's just under IEEE 1789's 1250 Hz line, where the low-risk limit is 0.08 × 1200 ≈ 96 %. So 97 % sits **on the border** (derived), consistent with R09's caution about Hue.
- **When to choose it:** KAJPLATS fails check RL-F (visible shimmer or a phone-camera band at night levels), or DIRIGERA's API breaks.

---

## 2. Comparison

Prices in € incl. VAT, with the date the price was seen.

### 2.1 Bulbs for an E27 lamp

| Bulb | L4 local API | L3 CRI (rated / measured) | L2 low end, flicker | DE price | Verdict |
|---|---|---|---|---|---|
| **IKEA KAJPLATS 1521 / 1055 lm WS** (Matter/Thread) | **✓ via DIRIGERA** REST :8443, token, websocket; **undocumented** (maintained library) [K7][K8] ✓; no published rate limit | **90** rated [K1][K2] ✓; R9 and measurements **not found** | "No visible flicker" in a 240 fps video [K10] (weak); a lux-meter user reports a steep curve (50 % ≈ 1/10 output) [K11] (weak); **UNVERIFIED** | €9.99 / €8.99 bulb + €79.99 hub (ikea.com/de, 2026-10-17) [K1][K2][K4] ✓ | **Primary**, pending check RL-F |
| **Shelly Duo Bulb E27 Gen3** (Wi-Fi) | **✓✓ documented** HTTP `/cct/0` + RPC `CCT.Set`, transitions, acknowledged [S3] ✓ | **> 80** [S1] ✓ | Earlier Shelly: < 1 lm, positive Duv [P3] ✓; Gen3 **UNVERIFIED** | €9.90 (shelly.com) [S2] ✓ | **Budget** |
| **Philips Hue White Ambiance E27 1100** (Zigbee, + Bridge) | **✓✓ documented** CLIP v2, ≈ 10/s (R09 [H1]) ✓ | **80**, R9 0 (EPREL) [E1] ✓; measured Re 81 [P2] ✓ | **≈ 1–2 lm**, low risk, 1.2 kHz PWM [P2][P3] ✓ | from €31.70 (billiger.de, 10/2026) [E3] ✓ + Bridge €33.99 | **Fallback** (the only one with measurements) |
| Hue White and Colour E27 1100 (2025, "dims to 0.2 %") | ✓ same | 80, R9 0 (EPREL 9290038535H) [E2] ✓; UK page "≥ 80" [E5] ✓ | 0.2 % claimed [E5] ✓ | from €51.50 (idealo, 14.10.2026) [E6] ✓ | Pays for RGB you don't need |
| WiZ tunable white (Signify, Wi-Fi) | ✓ UDP :38899, well established, unofficial; **"values < 10 % not supported"** (R09 [W1]) ✓ | **Depends on the generation**: EPREL 584520 (2021) **CRI 90**, R9 0 [W2] ✓; current "Modern bulb" EPREL 1877823 (2024) **CRI 80** [W3] ✓ | 10 % floor ≈ 3–5 lx in an uplighter (derived): acceptable here, unlike for the bias | CRI-90 SKU availability **UNVERIFIED** | Possible if you find the old CRI 90 SKU; the 10 % floor limits the night level |
| LIFX Colour E27 1000 | ✓✓ LAN protocol, 16-bit brightness (R09 [F1]) ✓ | **80**, R9 0 (EU sheet) [L1] ✓; measured 66–79 on US models [P1] ✓ | 6–8 lm, low risk [P1] ✓ | €44.99 (MediaMarkt, offer 12–19.10.2026) [L2] ✓ | ✗ CRI; great API |
| Nanoleaf Essentials Matter E27 (Thread or Wi-Fi) | ✗ no local API except Matter (own controller needed) | **≥ 90** rated [N1] ✓; old NL67E100 measured **93** [P4] ✓ | **Contradiction:** [P4] grades NL67E100 **high flicker risk** (42 % / 82 %, SVM 0.46 / 0.61) ✓; The Hook Up's 2024 Matter bulb had "very low flicker" [P3] ✓ (different generation) | **UNVERIFIED** | ✗ API; flicker unclear |
| Govee bulbs with LAN (H6008, H6006…) | ✓ same LAN code as the bars | H6008 measured **85**, H6006 **93** [P1] ✓ | **Dimmest 102–129 lm** [P1] ✓ → ≈ 4–6 lx minimum in an uplighter (derived), too bright for late night | ~€9–18 (Amazon.de listing) [L3] ✓ | ✗ low end |
| innr Comfort E27 1100 (Zigbee, Hue-compatible) | ✓ through the Hue Bridge | **> 83** [I1] ✓ (the US AE 270 T measured 92, no flicker, dimmest 29 lm [P1] ✓; the EU model isn't measured) | **UNVERIFIED** (EU) | €29.99 / 2-pack (innr.com) [I1] ✓ | Hue-bridge alternative to the Hue bulb; low end unknown |
| Aqara LED Bulb T1 (Zigbee) | Aqara hub; Hue-bridge pairing **UNVERIFIED** | **Ra 90** [A1] ✓ | **UNVERIFIED** | **UNVERIFIED** | ✗ hub lock-in |
| Yeelight W3 (Wi-Fi) | ✓ documented LAN JSON (R08 §6) | not published | **UNVERIFIED** | €19.99 (out of stock) / €26 [Y1] ✓ | ✗ unknown white |
| Athom "Made for ESPHome" E27 15 W | ✓ ESPHome REST + SSE (same as the sensor) | not published; CT 3000–6000 K [T1] ✓ | Old version: ESP8266 PWM (≈ 1 kHz default, **UNVERIFIED** for this build); the newer ESP32-C3 version is **UNVERIFIED** | ~$15 (Athom/Tindie, ships from CN) [T1] ✓ | Tinkerer's option; CRI unknown |

### 2.2 Integrated smart floor lamps

| Lamp | API | White | Price | Verdict |
|---|---|---|---|---|
| **Govee Floor Lamp 2 (H607C)**, corner lamp, 152 cm | ✓ **Govee LAN**, on the official and Home Assistant lists [G1][G2] ✓, so **the same `lib/govee.sh` code** would drive it | RGBICWW, 2200–6500 K, 1725 lm [G3] ✓; **CRI not published** ("Färgåtergivningsindex: ingen uppgift" [G4] ✓); LAN Kelvin → RGB caveat (R09 [G9]) | €119.99 (eu.govee.com, seen 2026-10-17) [G3] ✓ | ✗ for this job: unknown CRI, likely high minimum, bare LED bar faces the room unless turned to the wall |
| **Govee Uplighter Floor Lamp (H60B0)**, 170 cm, three zones | ✓ Govee LAN [G2] ✓ | 2700–6500 K, 1000 lm, RGBWW + RGBIC + WW [G5] ✓; CRI not published | from €134.99 (idealo, 29.03.2026) [G6] ✓; €135.01 (geizhals, 02.07.2026) [G7] ✓; €189.99 list | ✗ same reasons; the ripple effect is decorative, not ambient |
| Govee Floor Lamp Basic (H6076) | ✓ Govee LAN [G2] ✓ | **RGBICW**, white only **3400–4300 K** [G4] ✓ | — | ✗ can't reach 6500 K or 2700 K |
| Hue Signe / Gradient floor lamps | ✓ Hue | RGB-based gradients; CRI not checked | — | Not checked: more expensive than bulb + uplighter for the same job |

**Could our Govee code drive them?** Yes, unchanged: same multicast discovery, UDP :4003, `turn` / `brightness` / `colorwc`. The H607C and H60B0 also have more than one zone, and LAN control addresses the whole device (**UNVERIFIED** per zone). The reason not to buy one is the light, not the code.

### 2.3 Lamps for the bulb

| Lamp | Light path | Price | Notes |
|---|---|---|---|
| **IKEA TÅGARP Deckenfluter** | Up only (opaque bowl) | **€9.99** [K5] ✓ | **Pick.** Max 13 W; cord 80 cm (you may need an extension) |
| TÅGARP uplighter + reading arm | Up + a directable E14 arm | €14.99 [K5] ✓ | The arm stays off (or holds a plain bulb); extra cord length (100 cm) |
| IKEA HEKTAR floor lamp | Directional metal shade (Ø 31.5 cm), aim at the ceiling or side wall | €59.99 [K6] ✓ | Use if the ceiling is dark, sloped or very high: aim at the side wall (§3) |
| Any shaded drum floor lamp | Up + down + glowing shade | — | Works, but the glowing shade is the brightest thing near you: keep it out of the reflection corridor (§3) |

---

## 3. Placement guide for this desk

**Geometry (derived, §7):** the CU34G4Z is 1500R. From 65 cm, the curved screen's mirror rays leave its edges almost parallel, so the screen reflects only a **corridor straight behind you**, about as wide as the screen (≈ ±45–60 cm either side of your head's centre line). It reflects almost nothing beside you. A flat 34″ would reflect a ±31° fan.

| Lamp part, relative to your eyes | Mirror margin (screen tilt 5°) | Result |
|---|---|---|
| Uplighter bowl, 80 cm to the side, level with you | 36° | Safe |
| Uplighter bowl, 80 cm to the side, 40 cm behind | 22° | Safe |
| Lit ceiling patch above a lamp 120 cm to the side | 45° | Safe |
| Shaded lamp, shade at 150 cm, 70 cm to the side, 50 cm behind | 12° | Borderline: the matte coating may show a faint glow at the screen's edge |
| Shade 60 cm to the side, 100–200 cm behind | 2–5° | **Reflects** (right or left edge of the screen) |
| Anything directly behind you | ≈ 0° | **Reflects** (centre) |
| Wall patch lit by a lamp aimed at the side wall, 150 cm to the side | 57° | Safe |

The matte (anti-glare) surface spreads a reflection; treating "< 10°" as visible is my judgement, not a measured value.

**Where to put it:**
1. **Side:** whichever side has the socket and floor space (Q2). If both do, pick the side away from the door or walkway, so a 180 cm lamp isn't knocked over.
2. **Distance:** the uplighter column **70–120 cm to the side of your head**, and **between level with your shoulders and 40 cm behind them**. Don't put it further back than that unless it's at least ~90 cm to the side: further back, the column enters the reflection corridor.
3. **Height:** TÅGARP's 180 cm rim is above both seated (~120 cm) and standing (~165 cm) eye level, so the bulb is never visible. A shorter (≤ 150 cm) open-top lamp would show its bulb when you stand up next to it.
4. **Wall clearance:** keep the bowl ≥ 40–50 cm from the side wall. Closer, the wall gets a hot stripe instead of the ceiling getting a soft pool (judgement).
5. **Keep it off the bias zone:** the lit ceiling pool shouldn't spill onto the wall behind the monitor. That wall is the bias light's calibrated 5 cd/m² surround (R08 §2). With the lamp at the side or slightly behind you, the pool lands above and beside you, which is right.
6. **Low, dark or sloped ceiling?** Use a HEKTAR-type directional head aimed at the **side wall** (57° margin) instead of an uplighter.

**Checks after setting it up** (room dark, you in your normal position):
- (a) **Reflection:** screen showing a black full-screen image, lamp at 100 %. You see no glow or bright patch anywhere on the screen, including the edges. Repeat with the lamp at 10 %.
- (b) **Glare:** no bulb or bright rim visible, seated or standing at the desk.
- (c) **Bias wall:** with the bias bars off and the lamp at your night level, the wall behind the monitor shouldn't be visibly lit by the lamp. If the TSL2591 can be laid flat on that wall, a reading under ~2 lx is negligible next to the bias target of ≈ 20 lx (judgement).
- (d) **Bezel sensor:** probe check RL-C (§4.5) measures what the lamp adds at the sensor.

---

## 4. How the app should drive it

### 4.1 What the lamp adds at the sensor, and what that would do (derived)

- **What the sensor sees:** the TSL2591 on the top bezel faces you, so it sees your face, the walls and the ceiling behind and beside you, which is exactly what an uplighter lights. Expect a few lx to ~20 lx at the bezel at evening levels (rough, derived; check RL-C measures it).
- **What the prototype would do with that extra lux:**

| Lamp adds at the bezel | Brightness (curve `0:0,10:0,50:1,…`) | Night Kelvin (warm end 4000 K, smoothstep 10 → 300 lx, `engine.awk`) | Bias light (`BIAS_OFF_LUX` 60) | Desk-bar prompt (FR-81 < 5 lx; FR-85 withdraws > 20 lx) |
|---|---|---|---|---|
| 5 lx | 0 % (no change) | 4000 K | on | prompt may not fire |
| 20 lx | ≈ 0.25 % → 0 (no write) | **≈ 4250 K** | on | **withdrawn** |
| 50 lx | ≈ 1 % | **≈ 5250 K** | on (below 60) | withdrawn |

- **Brightness: harmless.** The curve is flat at the floor, and a little more backlight in a brighter room is the physically right answer anyway.
- **Kelvin: unwanted.** FR-20's rule "more lux → cooler" assumes the extra light is daylight. Here it's the app's own warm lamp, so it would undo the evening warming that FR-23 just added.
- **Bias and desk-bar prompt:** the lamp would withdraw the desk-bar prompt, and a bright lamp near the 60 lx line could switch the bias light off.

### 4.2 Fix: "room lux without our lights"

- **Calibrate once.** A probe records `ROOM_CAL="pct:lux,…"`: the bezel lux the lamp adds at each level, screen black, room otherwise dark. It's the same shape as `BIAS_CAL`.
- **Correct the lux.** While the app drives the lamp at p %, `lux_room = max(0, lux_filtered − ROOM_CAL(p))`.
- **Use the corrected lux for:**
  - Kelvin (FR-20/23);
  - bias on/off (FR-64);
  - the desk-bar prompt and its withdrawal (FR-81/85). FR-85 already says light the bar adds "doesn't trigger or cancel anything"; this extends that rule to the room lamp.
- **Keep the measured lux for brightness** (FR-10).
- **No feedback loop is possible.** The lamp's level is a function of the clock and your nudges only, never of lux. The lamp's Kelvin follows the screen's target Kelvin, which now depends on `lux_room`, which excludes the lamp. A wrong `ROOM_CAL` biases Kelvin a little; it can't oscillate. `KELVIN_MIN_INTERVAL` (600 s) damps it further.
- **If it isn't calibrated yet:** while `ROOM_CAL` is empty and the lamp is on under app control, hold Kelvin at the clock's warm end, i.e. treat the room as dark.

### 4.3 Behaviour: ask once, then follow (proposal; needs a SPEC change)

FR-80's rule ("never without your yes") was written for the desk bar. A room lamp changes the whole room, so the same consent applies to **switching it on**. Once on, though, having to approve every 5 % step would be noise. Proposal:

| | Rule |
|---|---|
| On | **Only after your yes.** Ask at most once per evening when `lux_room` < 5 lx for 10 min, display awake, between sunset and bedtime − 1 h (same machinery as FR-81/82/87: "Turn on room light" / "Not tonight"). An opt-in setting `ROOM_AUTO_ON=1` skips the question. |
| While on | **Follows by itself.** Kelvin = the screen's target Kelvin (FR-63 analogue), clamped to the bulb's range; an optional `ROOM_K_OFFSET` (e.g. −500 K) runs the room slightly warmer than the screen. Level comes from the clock (below), sent as small steps or with on-device transitions. |
| Your changes win | If the hub or bulb reports a state the app didn't send (you used the IKEA app, a remote or a switch), the app **stops driving the lamp until the next evening**. It never re-lights a lamp you turned off (FR-66 analogue). |
| Off | **Never automatic by default:** not on display sleep (it's room light, and you may still be in the room) and not at bedtime. Optional `ROOM_OFF_AT_BEDTIME=1` fades it out over 10 min at `BEDTIME`. Off on a clean app stop only if `ROOM_OFF_ON_QUIT=1` (default 0). |
| Colour-critical override | `ROOM_IN_CRITICAL=neutral` (default): 6500 K at the current level, like `BIAS_IN_CRITICAL`. Or `leave` / `off`. |

**Level by time of day** (Berlin; bedtime 23:00; desk targets; % from `ROOM_DESK_CAL`, or estimated from §7 until measured):

| Window | Screen (FR-23) | Room lamp target at the desk | ≈ % of the 1521 lm bulb's full output (derived; the app's % will differ, because the bulb's dimming curve isn't linear) |
|---|---|---|---|
| Day, blackout shut (only if you ask; `ROOM_ASK_DAY=1`) | 6500 K | 50–100 lx | 75–100 % |
| Sunset → 20:00 | 6500 → 5000 K | **≈ 40 lx** | ≈ 60 % |
| 20:00 → 22:00 | → 4000 K | **≈ 20 lx** | ≈ 30 % |
| 22:00 → 23:00 (wind-down) | 4000 K | **≈ 8 lx** | ≈ 12 % |
| After 23:00 | 4000 K | hold the wind-down level (or fade out if `ROOM_OFF_AT_BEDTIME=1`) | — |

**Why these levels:** at 20–40 lx a desk of reflectance ~0.4 is ≈ 2.5–5 cd/m² (derived, L = ρE/π). With the screen at ≈ 41–48 cd/m² at night (SCENES), surfaces in view sit at ≈ 1/10 of the screen. That's the same ratio R09 §4.2 used for the bias light, so the three layers agree. The numbers are starting values; the soak and your `brighter`/`dimmer` nudges decide.

### 4.4 Code changes (mirroring the bias backend; nothing changed yet)

| Area | Change |
|---|---|
| Backend | `lib/room.sh` with `room_apply <pct> <K> <transition>`, reusing the backend-neutral rules R09 §3.1 proposed for `bias_apply` (coalesce to the latest target; send only on a change of ≥ 1 % or ≥ 100 K; ≤ 1 update per 2 s). Backends: `dirigera` (`curl --cacert <pinned> -X PATCH https://$ROOM_HUB:8443/v1/devices/$ROOM_ID -H "Authorization: Bearer $TOKEN" -d '[{"attributes":{"lightLevel":N,"colorTemperature":K}}]'`), `shelly` (`/cct/0?turn=on&brightness=N&temp=K&transition=2000`), `hue` (CLIP v2 `PUT /clip/v2/resource/light/<id>` with `dimming.brightness` and `color_temperature.mirek`), `govee` (reuse `lib/govee.sh`), `esphome` |
| Engine | `engine.awk` gets the time-of-day level table and outputs `room=`, `room_k=`; it takes `lux_room` (lux minus `ROOM_CAL`) for `kelvin_for` and the bias/light-bar gates; brightness keeps `lf` |
| Config | `ROOM_BACKEND=none\|dirigera\|shelly\|hue\|govee\|esphome`, `ROOM_HUB`, `ROOM_ID`, `ROOM_K_MIN/MAX` (2200/6500 KAJPLATS; 2700/6500 Shelly), `ROOM_LEVELS="sunset:40,20:00:20,22:00:8"` (lx), `ROOM_CAL`, `ROOM_DESK_CAL`, `ROOM_ASK_LUX=5`, `ROOM_AUTO_ON=0`, `ROOM_K_OFFSET=0`, `ROOM_IN_CRITICAL=neutral`, `ROOM_OFF_AT_BEDTIME=0` |
| Secrets | DIRIGERA token and Hue app key in the Keychain (as FR-86 does for the miIO token); pin DIRIGERA's self-signed certificate on first pairing (trust-on-first-use), never disable TLS checks globally |
| State | `room_asked_date`, `room_user_override_until`, last sent pct/K; refresh every 60 s by **reading** state (all backends except Govee acknowledge), resend only if it differs and the user hasn't overridden |
| Probe | `probe/10-room-lamp.sh` (§4.5) |
| Tests | `test/fake_room_hub.py` (an HTTPS fake with a self-signed cert: devices list, PATCH, state file) plus a Shelly fake; cases: no-loop (lux rising from the lamp doesn't change Kelvin), manual override stops driving, never-on-without-yes, the bias and desk-bar gates use `lux_room` |
| Swift app | `URLSession` with a delegate that pins DIRIGERA's certificate; Local Network permission as already needed |
| SPEC | New goal G8 ("room light: on only with your yes, then follows the screen"), US-9, FR-90–FR-99 (above), and an FR-85 amendment ("light from the room lamp doesn't trigger or cancel anything") |

### 4.5 Probe 10 (when the lamp arrives)

| Check | What | Pass |
|---|---|---|
| RL-A | Pair; `GET /v1/devices` lists the lamp; on/off/level/K round-trip; note the reported `colorTemperatureMin/Max` | Commands acknowledged; K range covers 4000–6500 |
| RL-C | Bezel lux, screen black, room dark: lamp off, then 1, 2, 5, 10, 20, 30, 50, 75, 100 % → `ROOM_CAL` | Monotonic; saved on "y" |
| RL-D | The same sweep with the TSL2591 flat on the desk → `ROOM_DESK_CAL` | Gives the % for the 8 / 20 / 40 lx targets |
| RL-F | **Flicker at 5, 10, 20 and 30 %:** phone slow-motion video of a white wall and the phone's camera at the bowl rim (rolling-shutter bands mean PWM below a few kHz), plus a pencil swept quickly in front of the lit wall (phantom-array or stroboscopic edges) | No bands, no stroboscopic edges. If it fails, return the bulb (IKEA: 365 days [K2] ✓) and move to the Hue fallback |
| RL-R | §3 checks (a)–(c) | No reflection, no glare, bias wall unaffected |
| RL-S | 10 minutes with the lamp following the clock while you watch `light status`: Kelvin must not rise when the lamp brightens | The no-loop rule works |

The TSL2591 integrates over ≥ 100 ms, so it **can't** see kHz PWM. RL-F is a camera-and-eye check, not a measurement. A real number needs a photodiode and an oscilloscope (DOE method [F2] ✓); that's optional.

---

## 5. Open questions for you

| # | Question | Why it matters |
|---|---|---|
| 1 | **What lights are in the room now?** (ceiling lamp, other lamps, bulbs: brand, socket type, smart or not) | An existing E27 floor lamp may just need the bulb (−€10); an existing Hue Bridge or Apple TV/HomePod changes the cheapest route |
| 2 | **Which side of the desk has floor space and a socket**, and how far to the socket? | Placement (§3) and cord length (TÅGARP's is 80 cm) |
| 3 | **Ceiling:** height, colour (white?), flat or sloped? | Uplighter vs a lamp aimed at the side wall; the lux estimates assume white, ~2.6 m |
| 4 | **Budget:** ~€20 (Shelly, CRI 80), ~€100 (IKEA CRI 90, hub), or ~€66 (Hue, best API)? | Picks the row in §1 |
| 5 | OK with **"ask once per evening, then it follows"**? Or should it come on by itself (`ROOM_AUTO_ON`), or should every change be asked? | §4.3; it becomes a SPEC FR |
| 6 | Should the lamp **turn off at bedtime** by itself, or stay at the wind-down level until you switch it off? | `ROOM_OFF_AT_BEDTIME` |
| 7 | Do you want the lamp **slightly warmer than the screen** at night (e.g. 3500 K room with a 4000 K screen), or matched? | `ROOM_K_OFFSET`; matched is the default |
| 8 | Do you sometimes want the lamp **during the day** with the blackout shut? | `ROOM_ASK_DAY` |
| 9 | Is your Wi-Fi 2.4 GHz reliable where the lamp stands (Shelly), or is there an Ethernet port near the router for a hub (DIRIGERA/Hue)? | Backend choice |
| 10 | Will you take the hub to Amman? IKEA Jordan sells KAJPLATS; whether it sells DIRIGERA is unknown | Portability (§1.1) |

---

## 6. Assumptions

| Assumption | If wrong |
|---|---|
| KAJPLATS 1521 lm has the same 2200–6500 K range as the 1055 lm | It may be 2700–6500 K; still covers the screen's 4000–6500 K |
| DIRIGERA's local API keeps working across firmware updates | It's undocumented [K7]; the fallback is the Hue Bridge (documented) or Shelly |
| Hue measurements on US A19 models carry over to the EU E27 bulb | EU drivers may differ; the EU EPREL sheet agrees on CRI 80 |
| Room ~4 × 4 × 2.6 m, white ceiling (ρ 0.8), average room reflectance 0.45 | Lux at a given % changes; `ROOM_DESK_CAL` measures it |
| Eye 65 cm from the screen centre, 12 cm above it, tilt 5–10°, 1500R | The reflection corridor shifts slightly; check (a) settles it |
| A matte-coated reflection < 10° from the mirror direction is visible | A judgement; check (a) settles it |

---

## 7. Calculations

[`calc/lamp_geom.py`](calc/lamp_geom.py) (run from `calc/`):
- **Reflections:** the CU34G4Z modelled as a 79.7 × 33.4 cm cylinder of radius 150 cm, eye at 65 cm, with tilt. For each lamp position it finds the screen point whose mirror ray passes closest to the lamp and prints that angle.
  - Result: the reflected field is only **±3° in azimuth** (±8° at 55 cm), i.e. a screen-wide corridor straight behind you.
  - Elevation is −14…+14° at 5° tilt and −5…+24° at 10° tilt.
- **Desk lux from an uplighter:** the lit ceiling patch is treated as a Lambertian disc of 3 m² (ρ 0.8, 80 % of the flux going up), plus one inter-reflection term (ρ 0.45 over 75 m²).
  - At 100 %: 806 lm → ≈ 34 lx, 1055 → ≈ 45, 1100 → ≈ 47, **1521 → ≈ 65 lx**.
  - At 1 % (1521 lm): ≈ 0.65 lx.
  - Accurate to perhaps ± 50 %: it's for choosing a bulb size, not for calibration.
- **Kelvin vs lux** (§4.1): from `engine.awk`'s `kelvin_for` with `KELVIN_DIM_LUX` 10, `KELVIN_BRIGHT_LUX` 300, warm end 4000 K, smoothstep in log₁₀ lux, 250 K steps.

---

## 8. Sources

**IKEA**
- [K1] ✓ IKEA DE, KAJPLATS E27 1521 lm white spectrum (LED2408G10, CRI 90, €9.99), https://www.ikea.com/de/en/p/kajplats-led-bulb-e27-1521-lumen-smart-white-spectrum-globe-opal-white-10611302/ (search extract; ikea.com failed DNS for WebFetch).
- [K2] ✓ IKEA DE, KAJPLATS E27 1055 lm white spectrum (€8.99, 365-day return), fetched via Exa, https://www.ikea.com/de/en/p/kajplats-led-bulb-e27-1055-lumen-smart-white-spectrum-globe-opal-white-20608592/; specs (LED2407G8, CRI 90, 2200–6500 K, Matter over Thread) from the AT/GB pages, https://www.ikea.com/at/en/p/kajplats-led-bulb-e27-1055-lumen-smart-white-spectrum-globe-opal-white-20608592/ (search extract).
- [K3] ✓ IKEA Jordan, KAJPLATS E27 470 lm listing, https://www.ikea.com/jo/en/p/kajplats-led-bulb-e27-470-lumen-smart-white-spectrum-clear-globe-80611488/ (search result only).
- [K4] ✓ IKEA DE, DIRIGERA hub €79.99, fetched via Exa, https://www.ikea.com/de/de/p/dirigera-steuergeraet-fuer-smarte-produkte-weiss-smart-10503406/.
- [K5] ✓ IKEA DE, TÅGARP Deckenfluter €9.99 (180 cm, max 13 W), https://www.ikea.com/de/de/p/tagarp-deckenfluter-schwarz-weiss-20404095/; TÅGARP Deckenfluter/Leseleuchte €14.99, https://www.ikea.com/de/en/p/tagarp-floor-uplighter-reading-lamp-black-white-40486387/ (search extracts).
- [K6] ✓ IKEA DE, HEKTAR Standleuchte €59.99, https://www.ikea.com/de/de/p/hektar-standleuchte-dunkelgrau-00215307/ (search extract).
- [K7] ✓ Leggin/dirigera README (unofficial, local API, token, KAJPLATS listed), https://github.com/Leggin/dirigera, and source `hub.py` (port 8443, `/v1`, Bearer token, `verify=False`, websocket), https://github.com/Leggin/dirigera/blob/main/src/dirigera/hub/hub.py.
- [K8] ✓ PyPI dirigera 1.4.1 (2026-10-12), https://pypi.org/project/dirigera/.
- [K9] ✓ IKEA KAJPLATS manual (Matter certified; DIRIGERA or other Matter hub), https://www.ikea.com/gb/en/manuals/kajplats-led-bulb-e27-1055-lumen-smart-white-spectrum-globe-opal-white__AA-2672138-1-100.pdf (search extract).
- [K10] smarthomeguide.blog, KAJPLATS E26 review ("240 fps … no visible flicker"), https://smarthomeguide.blog/product/ikea/kajplats-e26-smart-bulb-color-and-white-spectrum/ (search extract; source quality uncertain).
- [K11] Rhythm Lighting tutorial (user lux-meter dimming curve for KAJPLATS E26 1100 lm), https://rhythm.lighting/tutorials/fix-ikea-kajplats-uneven-dimming-rhythm-brightness-curve (search extract; vendor content).

**Philips Hue**
- [E1] ✓ EPREL 406179, Hue White Ambiance E27 806 lm (9290024684): CRI 80, R9 0, Pst_LM 1.0, SVM 0.4, on the market 01/09/2021–26/05/2023, https://eprel.ec.europa.eu/fiches/lightsources/Fiche_406179_EN.pdf (fetched via Exa).
- [E2] ✓ Hue White and Colour E27 1100 (9290038535H) EU data sheet: CRI 80, R9 0, Pst 1.0, SVM 0.4, https://d.otto.de/files/15b083f2-c1d3-5787-8d0d-d9b422c78a16.pdf (search extract).
- [E3] ✓ billiger.de, Hue White Ambiance E27 1100 lm from €31.70 (October 2026), https://www.billiger.de/baseproducts/119194-philips-hue-white-ambiance-e27-1100-lm (search extract).
- [E4] ✓ idealo.de, White Ambiance E27 1100 lm (929002468401), 2200–6500 K, from €22.90, https://www.idealo.de/preisvergleich/OffersOfProduct/201612959_-white-ambiance-e27-8w-1100lm-929002468401-philips.html (search extract).
- [E5] ✓ Philips Hue UK, White and Colour A60 1100 ("dimmable to 0.2 %", CRI ≥ 80, EPREL 2476110), https://www.philips-hue.com/en-gb/p/hue-white-and-colour-ambiance-a60-e27-smart-bulb-1100/8720169364066 (search extract).
- [E6] ✓ idealo.de, White & Color Ambiance E27 1100 from €51.50 (data 14.10.2026), https://www.idealo.de/preisvergleich/OffersOfProduct/201601961_-hue-white-color-ambiance-e27-a60-1100l-philips.html (search extract).
- Hue API and Bridge price: R09 [H1], [H2], [H7].

**Independent measurements**
- [P1] ✓ Optimize Your Biology, Smart Light Database (119 bulbs; CRI Re, dimmest lm, flicker risk per IEEE 1789; updated 2026-04-12), https://optimizeyourbiology.com/smart-light-database (fetched via Exa; CC BY 4.0).
- [P2] ✓ Optimize Your Biology, Philips Hue LTA025 (CRI 81, 1.1–2.0 lm, 32 % / 97 % flicker, low risk), https://optimizeyourbiology.com/smart-light/philips-hue-lwa025-2.
- [P3] ✓ The Hook Up, "Top 4 smart tunable white bulbs" (2024-10-24; Hue/ERIA PWM 1.2/1.8 kHz; Shelly < 1 lm and positive Duv; Nanoleaf low flicker), https://www.thesmarthomehookup.com/top-4-smart-tunable-white-light-bulbs-matter-thread-and-zigbee-local-control-cct-only/.
- [P4] ✓ Optimize Your Biology, Nanoleaf NL67E100 (CRI 93; 42 % / 82 % flicker; SVM 0.46 / 0.61; high risk), https://optimizeyourbiology.com/smart-light/nanoleaf-nl67e100.

**Flicker rules**
- [F1] ✓ LEDVANCE FAQ on EU 2019/2020 (Pst_LM ≤ 1, SVM ≤ 0.9 → 0.4 from 09/2024, full load only), https://www.ledvance.com/professional/services/eu-legislations/eu-regulations/faq, and the XAL catalogue page (full load only), https://viva-interiors.com/en/catalogs/xal/collection-2022/15616/page-986 (search extracts; regulation text not read).
- [F2] ✓ US DOE, "Characterizing Photometric Flicker" (percent flicker, flicker index, meters), https://www.energy.gov/sites/prod/files/2016/03/f30/characterizing-photometric-flicker.pdf (search extract). IEEE 1789 limits: R09 [I1].

**WiZ, LIFX, Shelly, Nanoleaf, innr, Aqara, Yeelight, Athom**
- [W2] ✓ EPREL 584520, WiZ-connected tunable white 806 lm (9290023835A), CRI 90, R9 0, Pst 1.0, SVM 0.4, from 01/09/2021, https://eprel.ec.europa.eu/fiches/lightsources/Fiche_584520_EN.pdf (fetched via Exa); retail sheet https://www.assets.signify.com/is/content/Signify/GB.en_GB.8719514372429.
- [W3] ✓ EPREL 1877823, WiZ tunable white 806 lm (9290037819W), CRI 80, from 18/06/2024, https://eprel.ec.europa.eu/fiches/lightsources/Fiche_1877823_EN.pdf (fetched via Exa); https://www.wizconnected.com/en-gb/p/modern-bulb-bulb-60w-a60-e27/8720169076945. WiZ 10 % floor: R09 [W1].
- [L1] ✓ Telekom product sheet, LIFX Colour A60 1000 lm E27 (CRI 80, R9 0), https://www.telekom.de/pdf/produktdatenblatt-lifx-colour-a60-1000-lumen-e27.pdf (search extract).
- [L2] ✓ MediaMarkt DE, LIFX Colour 1000 lm €44.99 (offer 12–19.10.2026), https://www.mediamarkt.de/de/product/_lifx-colour-1000lm-led-bulb-1er-pack-2734593.html (search extract). LIFX LAN: R09 [F1].
- [L3] ✓ Amazon.de search listing (Govee E27 bulbs ~€9–18), https://www.amazon.de/LIFX/s?k=LIFX (search extract).
- [S1] ✓ Shelly KB, Duo Bulb E27 Gen3 (806 lm, 2700–6500 K, CRI > 80, ESP32-C3), https://kb.shelly.cloud/knowledge-base/shelly-duo-bulb-e27-gen3.
- [S2] ✓ Shelly EU shop, Duo Bulb E27 Gen3 €9.90, https://www.shelly.com/products/shelly-duo-bulb-e27-gen3 (search extract).
- [S3] ✓ Shelly API docs, CCT component (`CCT.Set`, HTTP `/cct/id`, transition 500–10,800,000 ms), https://shelly-api-docs.shelly.cloud/gen2/ComponentsAndServices/CCT (fetched via Exa).
- [N1] ✓ Nanoleaf EU shop, Matter Thread E27 (CRI ≥ 90, RGBCW, Thread border router required), https://eu-shop.nanoleaf.me/products/matter-thread-e27-smart-bulb-each (search extract).
- [I1] ✓ innr, Smart Bulb Comfort 1100 lm E27 (RB 272 T, 2000–6500 K, CRI > 83, €29.99 / 2-pack, works with the Hue Bridge), https://innr.com/products/innr-smart-bulb-comfort-1100lm-e27 (search extract).
- [A1] ✓ Aqara LED Bulb T1 (Ra 90+, Zigbee, hub required), https://aqara.com/en/product/led-bulb-t1, and manual https://www.manualslib.com/guide/3277474/aqara-led-bulb-t1-turnable-white-manual.html (search extracts).
- [Y1] ✓ control-your-home.de, Yeelight W3 €19.99 (out of stock), https://control-your-home.de/YEELIGHT-LED-Smart-Bulb-W3-Mehrfarbig-E27-Wifi/YEELYLDP005; hipicon €26, https://www.hipicon.com/de/P/yeelight-w3-led-e27-smart-bulb/364807 (search extracts).
- [T1] ✓ ESPHome devices, Athom E27 15 W bulb (ESP8266 PWM config, 1400 lm, 3000–6000 K), https://devices.esphome.io/devices/athom-e27-15w-bulb/; Athom "Made for ESPHome" page (discontinued → ESP32-C3 12 W), https://www.athom.tech/blank-1/15w-color-bulb-for-esphome (search extracts).

**Govee**
- [G1] ✓ Govee WLAN guide (LAN protocol; H6076 listed), https://app-h5.govee.com/user-manual/wlan-guide (search extract); Govee developer model list (H6076, H6078, H6079, H607C), https://developer.govee.com/docs/support-product-model.
- [G2] ✓ Home Assistant "Govee lights local" supported devices (H6076, H607C, H60B0, H60B1…), https://www.home-assistant.io/integrations/govee_light_local/; openHAB Govee binding list, https://www.openhab.org/addons/bindings/govee/.
- [G3] ✓ Govee EU, Floor Lamp 2 (H607C), €119.99, 1725 lm, 2200–6500 K, EU 2-pin plug, https://eu.govee.com/products/govee-floor-lamp-2 (search extract).
- [G4] ✓ Ljud & Bild, Govee Floor Lamp 2 review (CRI "ingen uppgift"), https://www.ljudochbild.se/test/smart-hem/govee-floor-lamp-2-h607c/; Bonmario review (H6076 RGBICW 3400–4300 K), https://bonmario.com/blog/recenzja-govee-floor-lamp-2-h607c.html (search extracts).
- [G5] ✓ Basic Tutorials, Govee Uplighter Floor Lamp test (H60B0 specs), https://basic-tutorials.de/tests/technik-gadgets/govee-uplighter-floor-lamp/; Amazon.de listing €189.99, https://www.amazon.de/dp/B0F1CS4VC2 (search extracts).
- [G6] ✓ idealo.de, H60B0 from €134.99 (data 29.03.2026), https://www.idealo.de/preisvergleich/OffersOfProduct/208050707_-uplighter-floor-lamp-h60b0-govee.html (search extract).
- [G7] ✓ geizhals.de, H60B0 €135.01 (02.07.2026), https://geizhals.de/govee-uplighter-stehleuchte-schwarz-h60b0-a3554006.html (search extract).
- Govee LAN Kelvin → RGB note: R09 [G9].

**Travel**
- [J1] ✓ WorldStandards, Jordan (230 V, 50 Hz; plug types), https://www.worldstandards.eu/electricity/plug-voltage-by-country/jordan/, and NETIO type J page, https://www.netio-products.com/en/glossary/type-j-electrical-socketelectrical-plug (search extracts).

**Local docs:** SPEC (FR-20/23, FR-60–67, FR-80–87), R08 §1a, §2 and §6, R09 §2–4, SCENES, HANDOFF, `lighting-prototype/lib/engine.awk` (`kelvin_for`), `config.example.sh`.
