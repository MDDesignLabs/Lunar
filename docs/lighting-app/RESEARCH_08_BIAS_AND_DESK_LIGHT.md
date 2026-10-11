# Research 08: Bias light (Govee H6056) and desk light bar (Xiaomi)

Status: research, 2026-10-11. **Supersedes RESEARCH_05** for level, colour and behaviour. Two research agents gathered the sources; the orchestrator checked the load-bearing ones (marked ✓). **UNVERIFIED** marks anything not checked, with what settles it. **No hardware has been tested yet.**

Source tags: [G#] Govee/standards, [X#] Xiaomi/Apple (§8). [R05], [R07] are local research docs.

**What changed:** you **bought the Govee bars**, so the bias light is active, not deferred. You also own a Xiaomi monitor light bar ("xiaomi lite", model unknown); the app asks before it's used, and never switches it by itself.

---

## 1. Govee H6056 "Flow Plus" light bars

| Item | Finding | Source |
|---|---|---|
| Product | B0FWCWTMQD = Govee RGBICWW Light Bars **H6056**, two bars with monitor brackets. **UNVERIFIED** (agent's finding); the box or the Govee app settles it | [G1][G2] |
| LAN API | **Yes ✓**: openHAB's LAN binding lists "H6056 H6056 Flow Plus" from Govee's list; HA's `govee_light_local` drives it locally | [G10] ✓, [G24] ✓ |
| Setup | **2.4 GHz Wi-Fi only ✓**; LAN Control switched on per device in Govee Home, and **the switch can take minutes to appear ✓** | [G5] ✓, [R05] |
| Two IPs? | One source: the pair is discovered as **two lights, two IPs**. **UNVERIFIED**; probe 07 check A | [G24] |
| LEDs, output | RGBICWW (RGB + warm and cool white); **2200–6500 K**, 400 lm (earlier revision's manual); **CRI not stated** | [G1][G5] |
| Revision | 2026 Matter revision under the old SKU (FCC grant 2026-04-13); 5 V vs 12 V in different sources. Change **UNVERIFIED**; scan reply's `wifiVersionHard` | [G1][G4][G5] |

**LAN commands** (Govee's guide [G9]; the prototype's payloads match it and two libraries [G7][G12]; this closes R05 §1's payload question):

| Command | Data | Range / note |
|---|---|---|
| `scan` | to 239.255.255.250:4001; replies on :4002 | The guide says the client "needs to join" the group; the prototype doesn't |
| `turn` | `value` 0/1 | — |
| `brightness` | `value` | **1–100**; 0 is not valid, so "off" must be `turn 0` |
| `colorwc` | `color {r,g,b}` + `colorTemInKelvin` | Guide: **2000–9000**; product spec **2200–6500** → clamp to 2200–6500 |
| `devStatus` | — | Replies `onOff`, `brightness`, `color`, `colorTemInKelvin`; lags "several seconds" [R05] |

**Caveats:**
- **The white may be RGB-mixed.** The guide says a non-zero Kelvin is "converted into the color value of red, green and blue" [G9]. If so, LAN white skips the WW chips: spectral gaps, likely poor CRI. **UNVERIFIED**; probe 07 check E.
- **No per-segment LAN control** [G7]: the bars light evenly over LAN.
- **New revision:** earlier units under one SKU have lacked LAN (H6072 [G13]); confirmed only when the switch appears and a scan replies.
- **CRI unknown**; the TSL2591 can't measure chromaticity, so D65 accuracy needs a colorimeter.
- **Not used:** cloud (2 req/s, internet [G15]), BLE (writes dropped on other models [G14]), Matter (only via Apple Home/Shortcuts).

---

## 2. How bright, what colour

**Level: 5 cd/m² absolute. R05 §2's contradiction is resolved.**
- SMPTE ST 2080-3:2017 §6.4: "The reflected light from the surround or background in the field of view shall have a luminance of **5.0 ± 0.5 candelas per square meter**" ✓ [G16].
- An ITU-R WP6C document confirms ST 2080-3 replaced BT.2035's "10% of reference white" ✓ [G19].
- **For this desk:** the screen floor is ~55 cd/m², about 48 at 5000 K [R07, KitGuru]. So 5 cd/m² is ~10% of the screen at night: the two rules nearly coincide in the dark, not in daytime (derived).

**Colour.**
- Flanders Scientific: "SMPTE 2080-3 recommends matching the chromaticity of the bias light to the white point chromaticity of the reference display" ✓ [G20]; the surround is "neutral (achromatic) gray" ✓.
- **Adaptive mode:** follow the screen's current target Kelvin (the same matching principle). The research agent reports ST 2080-3 §6.3 says the white "in use" (**UNVERIFIED** by the orchestrator). *Contradiction kept:* the standard assumes a fixed reference white, so following a moving one is an extension.
- **Colour-critical mode:** 6500 K.
- Also from [G20] ✓: information displays ≤ 100 cd/m², reading lights ≤ 100 lx (per ST 2080-3). The Xiaomi bar is a reading light in these terms (§6).

**Target at the wall (derived).** For a matte (Lambertian) wall, L = ρ·E/π, so E = π·L/ρ:

| Wall reflectance ρ | Wall illuminance for 5 cd/m² |
|---|---|
| 0.8 (white paint) | **≈ 20 lx** (19.6) |
| 0.6 | ≈ 26 lx |

- **Assumptions** (§7): matte wall; ρ measured (sensor a few cm off the wall facing it, then facing white paper, ρ ≈ 0.85); TSL2591 lux ≈ photopic (**UNVERIFIED** for RGB light); no cosine correction.
- **Quantisation (derived):** 400 lm against ~20–30 lm on ~1 m² of wall puts the operating point near **3–8 %**, if output is linear (**UNVERIFIED**). Each 1 % step is then a 10–30 % luminance change, which makes ±0.5 cd/m² hard. Probe 07 check F measures it.
- **Sensor feedback:** the bars light the wall behind; the sensor faces you. Little should reach it, and an absolute target has no loop through screen brightness. **UNVERIFIED**; check F logs bezel lux, bias on vs off.

---

## 3. Recommended bias behaviour

| State | Bias | Level | Colour |
|---|---|---|---|
| Adaptive, dark or dim (filtered lux < `BIAS_OFF_LUX`) | On | 5 cd/m² on the wall (calibrated %) | Screen's target K, clamped 2200–6500 |
| Adaptive, bright day (> `BIAS_OFF_LUX`; start 60 lx, back on below 40, **UNVERIFIED**) | **Off** | — | — |
| Colour-critical | On (setting: off) | 5 cd/m² | **6500 K** |
| Display asleep, Mac awake | Off | — | — |
| Mac going to sleep | Off, sent **before** sleep | — | — |
| lightd/app stopped cleanly | Off | — | — |
| lightd/app crashed | Holds last state; corrected on next launch | — | — |

- In daylight the room already lights the wall far above 5 cd/m² (300 lx on ρ 0.7 ≈ 67 cd/m², derived), so the bias adds nothing.
- **Rate limits:** coalesce to the latest target; send only when brightness changes ≥ 1 step or K ≥ 100; ≤ 1 update per 2 s; ≥ 300 ms between datagrams to one device (today's 200 ms is **UNVERIFIED**); refresh every 60 s **without** resending `turn 1`; send on/off transitions twice, 300 ms apart; check `devStatus` ≥ 3 s later.

---

## 4. Planned prototype changes (not yet written)

| Change | Why |
|---|---|
| **Turn-off support:** on/off in `govee_apply`'s cache; `turn 0` for off states, `turn 1` before brightness when coming back | Today the bars can never go off: no `turn`, and bias is clamped ≥ `BIAS_MIN` |
| **Absolute level:** replace `BIAS_K` with `BIAS_TARGET_NITS=5`, `BIAS_WALL_RHO`, and a measured `BIAS_CAL="pct:lux,…"` table, inverted for E = πL/ρ; `BIAS_MAX` ≈ 15 % safety cap | §2 |
| **Kelvin clamp:** `GOVEE_K_MIN=2200`, `GOVEE_K_MAX=6500` | Unclamped K is sent today |
| **Discovery:** multicast join (`IP_ADD_MEMBERSHIP`) plus unicast scans to `GOVEE_IPS:4001` | Guide [G9]; multicast is fragile on Wi-Fi [R05] |
| **Source address** when the reply has no `ip` | Seen on other models [G13] |
| **Pre-sleep off hook** (sleepwatcher or the display-state helper), plus off in the display-asleep branch and `cleanup` | lightd sees Mac sleep only after waking, by a sample gap |
| `bin/govee status` and `off-all` | Probe and debugging |

---

## 5. Probe 07 checks

- **A.** Scan reply: `sku`, `ip` present, hardware versions; **how many devices** reply.
- **B.** `turn` and `brightness` work; does `brightness` power on bars that are off?
- **C.** Kelvin at 2200, 2700, 4000, 5000, 6000, 6500, 7000, 9000: does it saturate above 6500?
- **D.** `devStatus` after each command.
- **E.** White path: LAN 6500 K vs the app's White 6500 K at equal brightness, by eye and TSL2591 lux; does `devStatus` show non-zero RGB after a Kelvin command?
- **F.** Wall lux at brightness 1–30 in steps of 1, then 40–100: the %→lux table and the 5 cd/m² point. Also bezel lux, bias on vs off.
- **G.** Inter-packet gaps of 0, 50, 200 ms: are both commands applied?
- **H.** LAN still works with Matter paired.
- **I.** PWM flicker at low % (phone slow-motion video).

---

## 6. The Xiaomi monitor light bar

**Identification and controllability** (read the label under the bar or on its base) [X1]–[X17]:

| Candidate | Label | Tell-tale | Control from a Mac |
|---|---|---|---|
| Mi Computer Monitor Light Bar (gen 1) | **MJGJD01YL** (BHR4838GL) | Puck takes 2×AAA; no Mi Home QR | **Remote-only** (2.4 GHz proprietary; an ESP32 + nRF24 emulator exists [X18]) |
| Yeelight Pura Monitor Light Bar **Lite** | YLBGD-0111 / "YLXD014-LITE" (codes conflict) | 40 cm; touch keys; 3000/5000/6500 K steps | **Touch/remote-only** |
| Mi Smart … Light Bar **1S** | **MJGJD02YL** | "1S"/"Smart", Mi Home QR | miIO: UDP 54321, AES-128-CBC with the device token from the Mi cloud; MIoT siid/piid **UNVERIFIED**. Medium-hard |
| Mijia Monitor Light Bar 2 (CN, Jul 2026) | `xiaomi.light.bar2` | 50 cm | Probably MIoT; local access **UNVERIFIED** |
| Yeelight Screen Light Bar Pro | YLTD003 | RGB glow behind | Yeelight LAN JSON, TCP 55443, no token. Easy |

- No Xiaomi-branded "Lite" bar was found. Most likely the **Pura Lite** or the **gen-1 MJGJD01YL** ("light" heard as "lite"), both remote-only.

**Sensor interaction risk.**
- The bar shines down onto the desk; the sensor is in the screen plane just below it. Direct light is probably small (inference, UNVERIFIED).
- **Reflected light from the desk** is the real path: estimate **~5–15 lx at 30 %, ~20–50 lx at 100 %** at the sensor (estimate, not a measurement). In a 0.5 lx room that's +1–2 decades.
- Effect: brightness moves little on R07's curve, but **the Kelvin smoothstep (FR-20) shifts cooler**, and the bias may switch off if it crosses `BIAS_OFF_LUX`. Partly correct (you do see more light), wrong where the sensor sees more than your eyes.
- **Settled by:** room fixed, read lux with the bar off, at 30 % and at 100 %, three readings each.

**Asking flow** (the app never switches the bar by itself; "Turn on" applies one action, once):

| State | Enter when | Shows | Exits |
|---|---|---|---|
| Idle | Default; or asked tonight; or "Don't ask again" | — | → Candidate |
| Candidate | Evening window, **filtered lux < 5 for 10 min**, display awake, bar believed off | — | → Asking; → Idle if lux ≥ 5 |
| Asking | Candidate holds | Notification + popover row | "Turn on" → Bar on; "Not tonight" → Idle until 06:00; lux > 20 lx or window ends → **Withdrawn** |
| Bar on | Command acknowledged, or "It's on" (remote-only) | Popover: "Light bar on" | Next evening → Idle |
| Withdrawn | Room lights came on | Notification removed | Idle; no second ask tonight |

- **Remote-only models:** "Turn on" sends nothing; it shows "Use the bar's remote …" and an "It's on" button.
- At most one prompt per evening (HIG: avoid repeat notifications [X23]).
- *Contradiction kept:* if you switch the bar on with the remote while the prompt is up, the bar's own light may push lux past 20 lx and withdraw it. That's harmless (you've already acted), so it isn't treated as a bug.

---

## 7. Assumptions

| Assumption | If wrong |
|---|---|
| The product is the H6056 (B0FWCWTMQD → H6056 is the agent's finding) | Re-check the LAN list for the real SKU |
| Govee's generic LAN guide applies to H6056 | Commands silently ignored; probe 07 |
| Wall is matte, ρ 0.6–0.8 | L ≠ ρE/π; measure ρ |
| TSL2591 lux ≈ photopic for RGB-mixed light | Absolute level off by an unknown factor; check against the screen at a known cd/m² |
| You want evening prompts only | Widen the window in settings |
| Notifications are allowed and visible | The popover row covers it |

---

## What not to build

- **Screen-content colour sync** (ambilight) and the **Govee cloud API**. Also no BLE or Matter path for Govee.
- **Per-segment effects.** LAN has no segments, and the surround should be even and neutral.
- **A bias level tied to screen brightness** (`BIAS_K`). The standard is absolute.
- **Any automatic switching of the light bar.** Every change needs a tap.
- **Light-bar control code before the model is known**, and none at all for remote-only models.
- **An ESP32 remote emulator** for MJGJD01YL in v1.

---

## 8. Sources

Checked sources carry their URL. The rest are listed with URLs in the research agents' reports of 2026-10-11 (session scratchpad, not in the repo).
- **Govee:** [G1] Amazon.es B0FWCWTMQD; [G2] Govee EU/UK H6056; [G4] FCC 2A7VD-H6056; [G5] H6056 manual ✓ (2.4 GHz); [G7] govee-local-api; [G9] Govee WLAN guide, https://app-h5.govee.com/user-manual/wlan-guide; [G10] openHAB Govee binding ✓, https://www.openhab.org/addons/bindings/govee/; [G12][G13] govee2mqtt code and issues; [G14] lasswellt/govee-homeassistant; [G15] Govee API rate limits; [G24] smarthomeassistant.co.uk ✓ (local control; the two-IPs claim not verified).
- **Standards:** [G16] SMPTE ST 2080-3:2017 ✓, https://pub.smpte.org/pub/st2080-3/st2080-3-2017.pdf; [G19] ITU-R WP6C contribution C-0234 ✓, https://nabanet.com/wp-content/uploads/2024/04/R19-WP6C-C-0234MSW-E.pdf; [G20] Flanders Scientific, *Reference Viewing Environment* ✓, https://flandersscientific.com/uploads/tech-resources/ReferenceViewingEnvironment.pdf.
- **Xiaomi/Apple:** [X1]–[X17] Xiaomi and Yeelight specs, manuals, HA threads; [X18] https://github.com/ebinf/lightbar2mqtt; [X23] Apple HIG, Notifications, https://developer.apple.com/design/human-interface-guidelines/notifications. Apple APIs (`UNUserNotificationCenter`, `UNNotificationCategory`, `UNNotificationAction`, `removeDeliveredNotifications(withIdentifiers:)`, `.passive`) were read by the research agent, not re-checked.
