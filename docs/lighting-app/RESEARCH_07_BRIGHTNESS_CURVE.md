# Research 07: How bright should the screen be for the room?

Status: research, 2026-10-11. A research agent gathered the sources; I checked the load-bearing ones myself (marked ✓ below). **UNVERIFIED** marks anything not checked, with what would settle it.

**Why:** the user felt the screen stays too bright in a dark room. The current curve is Lunar's untouched seed (`0:21,13:31,…`), and luminance compensation adds a few more points when the white point is warm.

---

## 1. What the sources say

| Room light | Recommended screen luminance | Source |
|---|---|---|
| 0 lx | **20.6–36.2 cd/m²** (low fatigue to "neither too dark nor too bright") for a desktop LCD in the evening, n=33 | Zhou et al. 2021, *Appl. Sci.* 11:4108 ✓ |
| 0 lx | 10–40 cd/m² (Na & Suk 2015, as cited by Zhou); 11 cd/m² (Li 2013, phone) | Zhou 2021 ✓ |
| 0–100 lx | "20.63–75.15 cd/m²" is the best range over 0–100 lx in the evening | Zhou 2021 ✓ |
| 0 / 10 / 20 / 40 / 100 / 200 / 400 / 1200 / 2000 lx | 2 / 24 / 44 / 87 / 136 / 164 / 206 / 312 / 435 nits, for a 435-nit laptop. "For devices with a different max nits, these values should be determined" | Microsoft, *Integrating Ambient Light Sensors with Computers Running Windows 10 Creators Update*, Table 4 ✓ |
| 500 lx | "100 cd/m² to 150 cd/m²" for an office | ISO 9241-303:2011 §5.2.3 (from the agent's reading of the preview; **UNVERIFIED** here, the preview was unreachable) |
| 64 / 200 lx | 80 cd/m² reference display (sRGB encoding / typical environment) | IEC 61966-2-1, via Wikipedia (**UNVERIFIED** against the standard) |

- **Phone and laptop curves run 2–4× higher than the desktop studies** at 50–500 lux. Handheld use is closer to the eye and often outdoors, and preferred luminance rises with a display's maximum (Kim et al. 2018, cited by Zhou ✓).
- **Zhou measured room light at eye level, with the screen off** ✓. Microsoft recommends a sensor in the screen plane, facing the user. Both measure light arriving from the room towards the viewer's side, so they're comparable, but not identical.

## 2. This monitor's real brightness range

KitGuru measured an AOC CU34G4Z at default settings with an X-Rite i1Display Pro and Calman ✓ (kitguru.net review, page 4):

| OSD brightness | 0% | 25% | 50% | 75% | 100% |
|---|---|---|---|---|---|
| White luminance (cd/m²) | **55.2** | 139.5 | 221.5 | 297.9 | 371.6 |

- The setting is **close to linear in luminance** (about 3.2 cd/m² per step), slightly bowed in the middle.
- **The backlight can't go below ~55 cd/m².** The research target for a dark room (20–36) is below the hardware floor.
- AOC specifies 450 cd/m² ✓ (aoc.com spec page). The review measured 372.
- Caveats: this is one unit, at default gains, not this user's. **`probe/08-brightness.sh` Part A settles this:** it measures this unit's response with the TSL2591 and says whether it matches the review within ±0.05 (RESULT Q16a). Lux gives the shape only; absolute cd/m² still assume KitGuru's 371.6 at 100%. The user's warm white point lowers luminance further. With the measured probe 05 response, 5000 K (50/43/35) gives ~0.87× and 4000 K (50/37/21) ~0.75× (derived from RESEARCH_03 §2's straight-line fit), so the floor at night is about 48 cd/m² at 5000 K.
- The agent's first figures (54–357, from a YouTube review) were replaced by these colorimeter numbers.

## 3. Recommendation

**Target luminance** (a compromise between the desktop studies and Microsoft; the 50–300 lux rows aren't from any single source):

| Room (lux) | 0–1 | 10 | 50 | 100 | 300 | 500 | 1000 | 2000+ |
|---|---|---|---|---|---|---|---|---|
| Target (cd/m²) | 20 | 30 | 60 | 80 | 130 | 160 | 300 | max |

**As a curve for this monitor**, inverted through the KitGuru table:

```
BRIGHTNESS_CURVE="0:0,10:0,50:1,100:7,200:17,300:22,500:31,1000:76,2000:100"
BRIGHTNESS_MIN=0
LUMINANCE_COMPENSATION=0
```

| Room (lux) | Now: % → cd/m² | Recommended: % → cd/m² |
|---|---|---|
| 0.5 | 24 → ~137 (+ compensation) | 0 → 55 |
| 10 | 30 → ~157 | 0 → 55 |
| 100 | 45 → ~205 | 7 → 79 |
| 300 | 68 → ~275 | 22 → 129 |
| 500 | 86 → ~332 | 31 → 159 |
| 1000 | 100 → 372 | 76 → 301 |

- **`BRIGHTNESS_MIN=0`**, because the example config's 5 would hold the floor at ~71 cd/m².
- **`LUMINANCE_COMPENSATION=0`:**
  - compensation only acts while the white point is warm, which means in dim light, where the goal is *less* light;
  - the f.lux FAQ makes the same point: in a dark room you'd want the display "to look dimmer";
  - evening-light guidance recommends lower light before bed (Brown et al. 2022, PLOS Biol; **UNVERIFIED** here).
- **The daytime change is large too:** 300 lux drops from ~275 to ~130 cd/m². That follows ISO 9241-303 and the desktop studies, but personal preference varies. Use `bin/light brighter` during the soak; if it's consistently too dim in daylight, raise the 300–1000 points rather than the dark end.

## 4. Going below the backlight floor (not built; a decision)

To actually reach 20–36 cd/m² in a dark room, the dimming must come from somewhere other than the backlight:
- **(a) Equal RGB gain cuts.** E.g. 0.4–0.6× at night. This uses the gain channels already written for the white point, but costs contrast and bit depth, and adds gain writes.
- **(b) Contrast (VCP 0x12).** Effect on this panel UNVERIFIED.
- **(c) macOS gamma-table dimming.** It's software dimming, which SPEC lists as a non-goal.
- **(d) A bias light.** It doesn't lower the screen, but makes 55 cd/m² feel less harsh against a dark wall. ISO 9241-303 §5.2.4 puts surrounds within 1:10 of the task, and ITU-R BT.2035 sets a background at 10% of white (both via the agent, **UNVERIFIED** here).
- **Recommendation:** live with the 55 floor (≈ 48 at 5000 K) for the soak first. If it's still too bright at night, (a) is the smallest change; it's a new requirement, so it goes through SPEC.

## 5. Where the sensor should be

- **Microsoft:** "Real-world optimum placement … is generally on the same plane as the display, facing the user," near the top of the screen, with a wide field of view (about 110° total). Keep point sources out of view. (Agent's quote; Microsoft's guidance page wasn't fetched here, **UNVERIFIED** word for word.)
- **For this desk:** top-centre of the bezel, flush with the screen, facing you. Not facing a lamp (the 3,000–13,000 lux readings on 2026-10-11 were the sensor seeing a light source), not the ceiling, and not behind the monitor (that's the right place for a bias-light sensor).
- **Check self-illumination:** at night with the lights off, compare the lux with a black screen and with a white screen. If white reads much higher, the screen is lighting the sensor (light reflected off you and the room), which can push brightness up. The slow darkening filter already damps this; a large difference would need correcting. `probe/08-brightness.sh` Part B does this check and prints the verdict. It estimates how far the screen's own light, reflected back to the sensor, would push lightd's brightness up at several room levels, using your curve, for a worst-case all-white screen. It's significant only if that reaches lightd's dead-band (2 steps). Changed 2026-10-11 in review: the first version flagged any spill over 20% of the black reading, which in a dark room (~0.5 lux) is almost always true, even when the spill can't move brightness at all.

## Assumptions

| Assumption | If wrong |
|---|---|
| KitGuru's unit behaves like this one | The % values shift; run `probe/08-brightness.sh` (Part A: relative brightness at 0, 10, … 100 against a white screen; it prints a corrected `BRIGHTNESS_CURVE`) |
| Research done mostly with young adults applies to you | Preference may differ; the soak and nudges will show it |
| Content is mostly light-mode | Dark-mode content needs less; the curve may feel bright less often |
| The sensor will sit in the screen plane facing you | Lux readings change with placement, so the curve's lux values won't mean the same light levels |

## Sources

- Zhou Y. et al., "Investigation of the Optimum Display Luminance of an LCD Screen under Different Ambient Illuminances in the Evening", *Appl. Sci.* 2021, 11(9), 4108. https://www.mdpi.com/2076-3417/11/9/4108 ✓
- Microsoft, *Integrating Ambient Light Sensors with Computers Running Windows 10 Creators Update*, Table 4 "Lux-to-Nits User Brightness Preference Data". https://learn.microsoft.com/en-us/windows-hardware/design/whitepapers/integrating-ambient-light-sensors-with-computers-running-windows-10-creators-update (table text via the docslib mirror) ✓
- Microsoft, "Adaptive brightness" (Windows 11 buckets; `AutobrightnessLuxToNitsCurve` example). https://learn.microsoft.com/en-us/windows-hardware/design/device-experiences/sensors-adaptive-brightness ✓ (bucket table seen in a search extract)
- KitGuru, "AOC CU34G4Z Review (Budget 240Hz Ultrawide)", p. 4, Brightness and Contrast table. https://www.kitguru.net/peripherals/monitors/dominic-moass/aoc-cu34g4z-review-budget-240hz-ultrawide/4/ ✓
- AOC CU34G4Z specification ("Brightness in nits 450 cd/m²"). https://sg.aoc.com/product/CU34G4Z ✓
- ISO 9241-303:2011 §5.2.3–5.2.4 (preview), via the agent. **UNVERIFIED** here.
- f.lux FAQ, https://justgetflux.com/faq.html, via the agent. **UNVERIFIED** here.
- Brown T.M. et al., PLOS Biol 2022, https://doi.org/10.1371/journal.pbio.3001571, via the agent. **UNVERIFIED** here.
