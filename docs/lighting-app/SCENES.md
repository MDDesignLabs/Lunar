# Scenes: what the desk looks like through the day (for Gemini)

Status: 2026-10-17. Each scene's numbers come from the prototype's engine with the repo defaults (`engine_targets`, Berlin time zone, bedtime 23:00). The screen luminance in cd/m² is derived from KitGuru's colorimeter table (RESEARCH_07 §2) and the warm-gain factors (≈ 0.87× at 5000 K, 0.75× at 4000 K). The bias light is uncalibrated until probe 07 runs, so its % is the 5 % fallback aiming at 5 cd/m² on the wall.

## The decision

| | What | Why |
|---|---|---|
| **Bias light** | **Keep the Govee H6056 bars** you already own, if probe 07 checks E, F and I pass | Your work is UI/UX design for screens. What matters is the screen's own white, and the app sets that. The bias light only has to be dim and roughly neutral. Its CRI 80 is fine for that (RESEARCH_09) |
| Bias fallback | The DIY CRI 95 strip on a QuinLED An-Penta-Mini with ESPHome (≈ €100) | Only if a probe check fails: LAN white mixed from RGB, coarse low steps, or flicker |
| **Desk light** | **The Xiaomi monitor light bar you already own**, on top of the screen | It lights the desk and keyboard without lighting the screen, which is what an asymmetric monitor bar is for. The app only **asks** in the evening, and never switches it by itself (FR-80) |
| Don't buy | Another monitor bar, a Hue Play, a COB strip | None of them improves on the pair you have |

**Placement:**
- **Govee bars:** upright on their brackets behind the monitor, one each side of the stand, aimed at the wall and slightly up (RESEARCH_08 §1a).
- **Xiaomi bar:** clamped on the top centre of the screen.
- **Sensor:** move the ESP32 to the top bezel just **left or right of** the Xiaomi bar, still facing you, so the bar doesn't shade it or shine into it.

## What the system does in each scene

| # | Scene (Berlin) | Room at the sensor | Screen white | Screen brightness | Bias light | Desk bar |
|---|---|---|---|---|---|---|
| 1 | Autumn noon, blackout shut | 0.5 lx | **6500 K** (neutral) | 0 % ≈ 55 cd/m² | On, 5 %, 6500 K (wall ≈ 5 cd/m²) | Off |
| 2 | Noon, blinds open, overcast | 300 lx | 6500 K | 22 % ≈ 130 cd/m² | **Off** (room above 60 lx) | Off |
| 3 | Sunny afternoon 15:00 | 1000 lx | 6500 K | 76 % ≈ 300 cd/m² | Off | Off |
| 4 | Dusk 18:40, warm ceiling lamp | 40 lx | 6000 K | 1 % ≈ 58 cd/m² | On, 6000 K | Off |
| 5 | Evening 19:30, lights off | 1 lx | **5000 K** (slightly warm) | 0 % ≈ 48 cd/m² | On, 5000 K | The app asks "Turn on the desk light?" If yes: 2700 K, 30 % (planned; not in the prototype yet) |
| 6 | Night 21:30, lights off | 0.5 lx | **4000 K** (warm) | 0 % ≈ 41 cd/m² | On, 4000 K | Whatever you chose |
| 7 | Night 21:30, colour-critical review | 0.5 lx | 6500 K | **40 % ≈ 190 cd/m²** | On, 6500 K | Off for an accurate review (your choice) |
| 8 | Winter morning 07:30, blackout shut | 0.5 lx | 5250 K, warming up to 6500 K by 08:00 | 0 % ≈ 50 cd/m² | On, 5250 K | Off |
| 9 | Amman, summer noon, sunlit room | 1500 lx | 6500 K | 90 % ≈ 345 cd/m² | Off | Off |

## Gemini prompts

Each prompt stands alone: paste one into Gemini's image generation. They describe the same desk every time, so the series stays consistent. If Gemini drifts, add: "Keep the exact same desk, monitor, wall and camera angle as the previous image."

### 1. Autumn noon, blackout blinds shut
```
Photorealistic interior photo of a minimalist home office desk at midday with blackout blinds fully closed, so the room is almost dark. A 34-inch black curved ultrawide monitor (AOC CU34G4Z, thin bezels, matte black, slim V-shaped stand) sits on a light oak desk, about 15 cm in front of a matte white wall. A small silver Mac Studio sits to the left of the monitor. On the screen: a Figma UI design workspace with a clean light-grey canvas, white app cards and blue buttons, shown in neutral daylight white (6500 K), very dim: the screen is the main light source but not glaring. Behind the monitor, two slim upright light bars on brackets wash the wall with a soft, even, neutral white glow, faint (about 5 nits), extending a little above and to the sides of the screen like a gentle halo; the LEDs themselves are not visible. A small matte-white sensor box sits on the top bezel, slightly off centre, facing the viewer. A slim monitor light bar on top of the screen is switched off. A thin line of daylight leaks at the blind's edge. Camera: eye level from the chair, 35 mm, slight angle from the left. Calm, focused, low-contrast mood, true neutral colours, no colour cast, no RGB effects, no gaming lights.
```

### 2. Noon, blinds open, overcast
```
Photorealistic interior photo of the same minimalist home office at midday with the window blinds fully open on an overcast autumn day in Berlin: soft, diffuse, cool-grey daylight fills the room from a window on the left. A 34-inch black curved ultrawide monitor (AOC CU34G4Z, matte black, slim stand) on a light oak desk about 15 cm in front of a matte white wall; a silver Mac Studio to its left. The screen shows a Figma UI design workspace (light-grey canvas, white cards, blue buttons) in neutral daylight white, at moderate brightness that matches the room: comfortable, not glowing. The light bars behind the monitor are off; the wall is lit only by daylight. A small matte-white sensor on the top bezel, slightly off centre, faces the viewer. The light bar on top of the monitor is off. Camera: eye level from the chair, 35 mm, slight angle from the left. Natural, airy, realistic exposure, no lens flare, no RGB lighting.
```

### 3. Sunny afternoon
```
Photorealistic interior photo of the same minimalist home office at 3 pm on a bright sunny day: strong sunlight streams through a window on the left, warm patches of sun on the floor and a bright, evenly lit room, without direct sun falling on the screen. A 34-inch black curved ultrawide monitor (AOC CU34G4Z, matte black) on a light oak desk in front of a matte white wall; a silver Mac Studio beside it. The screen shows a Figma UI design workspace in neutral daylight white at high brightness, clearly readable and punchy against the bright room, with no washed-out look. The bias light bars behind the monitor are off. A small matte-white sensor sits on the top bezel facing the viewer; the monitor light bar on top is off. Camera: eye level, 35 mm, slight angle from the left. Crisp, high-key, realistic, true colours, no RGB lighting.
```

### 4. Dusk, warm ceiling lamp on
```
Photorealistic interior photo of the same minimalist home office at dusk (18:40) in autumn: the window shows a deep blue twilight sky, and a warm 2700 K ceiling lamp gives the room a soft amber tone. A 34-inch black curved ultrawide monitor (AOC CU34G4Z) on a light oak desk about 15 cm from a matte white wall; a silver Mac Studio beside it. The screen shows a Figma UI design in a very slightly warm white (6000 K) at low brightness, gentle on the eyes. Behind the monitor, two slim upright light bars give a faint, even, near-neutral white halo on the wall around the screen (LEDs hidden). A small matte-white sensor on the top bezel faces the viewer; the monitor light bar on top is off. Camera: eye level from the chair, 35 mm, slight angle from the left. Cosy transitional mood, balanced exposure, no RGB colours.
```

### 5. Evening, room lights off
```
Photorealistic interior photo of the same minimalist home office at 19:30, all room lights off and the blackout blinds shut: dark room. A 34-inch black curved ultrawide monitor (AOC CU34G4Z) on a light oak desk about 15 cm in front of a matte white wall; a silver Mac Studio beside it. The screen is at its lowest brightness with a slightly warm white (5000 K), showing a Figma UI design. Behind the monitor, two slim upright light bars cast a soft, faint, slightly warm white glow on the wall, evenly surrounding the screen like a quiet halo (about 5 nits, LEDs not visible), so the screen doesn't feel like a bright rectangle in the dark. A slim asymmetric light bar on top of the monitor is on at a low warm 2700 K, lighting only the keyboard, a notebook and a coffee mug on the desk in a soft pool of warm light, with no glare on the screen. A small macOS notification in the top-right corner reads "Turn on the desk light?". A small matte-white sensor sits on the top bezel, off centre. Camera: eye level, 35 mm, slight angle from the left. Calm evening mood, low contrast, realistic, no RGB effects.
```

### 6. Night, lights off, before bed
```
Photorealistic interior photo of the same minimalist home office at 21:30 at night, room dark, blackout blinds shut. A 34-inch black curved ultrawide monitor (AOC CU34G4Z) on a light oak desk about 15 cm in front of a matte white wall; a silver Mac Studio beside it. The screen is at its lowest brightness with a clearly warm white (4000 K, like soft candlelit paper, not orange), showing a document or a Figma file. Behind the monitor, two slim upright light bars give a very faint warm-white halo on the wall around the screen (LEDs hidden), matching the screen's warm tone. Optionally, the slim light bar on top of the monitor glows warm and low, lighting only the keyboard. The rest of the room falls into soft darkness. A small matte-white sensor on the top bezel faces the viewer. Camera: eye level, 35 mm, slight angle from the left. Restful, wind-down mood, gentle and warm, realistic exposure, no blue light, no RGB effects.
```

### 7. Night, colour-critical design review
```
Photorealistic interior photo of the same minimalist home office at night, room dark, blackout blinds shut, during a colour-accurate design review. A 34-inch black curved ultrawide monitor (AOC CU34G4Z) on a light oak desk about 15 cm in front of a matte white wall; a silver Mac Studio beside it. The screen is noticeably brighter (moderate, about 190 nits) and in true neutral daylight white (6500 K), showing a colourful UI design system: brand colour swatches, buttons and illustrations rendered with accurate colours. Behind the monitor, two slim upright light bars cast a faint, perfectly neutral white halo on the wall around the screen (LEDs hidden), so the eye stays adapted to neutral white. The light bar on top of the monitor is off. A small menu-bar indicator reads "Colour-critical". A small matte-white sensor on the top bezel faces the viewer. Camera: eye level, 35 mm, slight angle from the left. Professional, precise, neutral, no colour cast, no RGB effects.
```

### 8. Dark winter morning
```
Photorealistic interior photo of the same minimalist home office at 07:30 on a December morning in Berlin, still dark outside, blackout blinds shut. A 34-inch black curved ultrawide monitor (AOC CU34G4Z) on a light oak desk about 15 cm in front of a matte white wall; a silver Mac Studio beside it. The screen is dim, in a soft white that is just warming up towards daylight (about 5250 K), showing a calendar and an email inbox. Behind the monitor, two slim upright light bars give a faint, soft white halo on the wall (LEDs hidden). A mug of coffee steams on the desk. The light bar on top of the monitor is off. A small matte-white sensor on the top bezel faces the viewer. Camera: eye level, 35 mm, slight angle from the left. Quiet early-morning mood, gentle, realistic, no RGB effects.
```

### 9. Amman, summer noon
```
Photorealistic interior photo of a minimalist home office in Amman, Jordan, at noon in summer: bright, warm Mediterranean sunlight through a window with sheer curtains, a sandy-beige plastered wall, a bright and airy room. A 34-inch black curved ultrawide monitor (AOC CU34G4Z) on a light oak desk about 15 cm in front of the wall; a silver Mac Studio beside it. The screen is at high brightness in neutral daylight white (6500 K), showing a Figma UI design, clearly readable against the bright room. The bias light bars behind the monitor are off; the wall is lit by daylight. A small matte-white sensor on the top bezel faces the viewer; the monitor light bar is off. Camera: eye level, 35 mm, slight angle from the left. Bright, clean, realistic, true colours, no lens flare, no RGB lighting.
```

## Notes
- **The images are illustrations, not measurements.** Real cd/m² and Kelvin come from the table above, and from probe 07 once it has run.
- **The light-bar prompt** in scene 5 is a planned feature (FR-81–FR-87); the shell prototype doesn't ask yet.
- **If your wall isn't white,** change "matte white wall" to its colour in every prompt.
