# Research 06: Design (UI spec, competitive survey)

Status: research, 2026-09-26. Source tags:

- **[code: …]**: code or README I read
- **[tokens]**: `docs/lighting-app/DESIGN_TOKENS.md`, extracted from Lunar's source earlier
- **UNVERIFIED**: not checked; each one says what would settle it

---

## 1. Competitive survey (only what I've read)

| Product | What it does that matters here | Model | Source |
|---|---|---|---|
| **Lunar** | Menu bar panel with per-display pill sliders; adaptive modes (sensor, sync, location, clock); learning curve. Sensor Mode needs Pro (inferred, see note below) | Free + Pro | [code: `Lunar/SwiftUIViews/QuickActionsMenuView.swift`; `Modes/AdaptiveMode.swift:50–51`] |
| **MonitorControl** | Brightness, volume and contrast via DDC; menu bar sliders; native OSD; keyboard keys. **No ambient sensor of its own, but it follows ambient light indirectly:** it can "Synchronize brightness from built-in and Apple screens - replicate Ambient light sensor … induced changes to a non-Apple external display". README doesn't mention colour gains (UNVERIFIED whether the UI has them). Doesn't support DDC on M1 built-in HDMI | Free, MIT | [code: `MonitorControl/README.md:34–49` (sync: line 41), `94`] |
| **BetterDisplay** | "Brightness, volume, and color control … through software controls, DDC"; DDC capability detection, including built-in HDMI | Free for non-business use + Pro ($21.99 / €19.99, perpetual, 14-day trial) | [code: `BetterDisplay/README.md:57, 66, 78–86`] |
| **m1ddc** | CLI: set/get luminance, contrast, R/G/B gain, input | Free, MIT | [code: `m1ddc/README.md`] |
| **Home Assistant Adaptive Lighting** | Sun-position brightness and Kelvin for room lights; "sleep mode" | Free | [code: `adaptive-lighting/README.md:11–19`] |
| **macOS Night Shift / True Tone** | Built-in white-point shifting | Built in | UNVERIFIED. Not researched this session. Don't rely on claims about them |

Corrected 2026-09-26: the MonitorControl row said "No ambient sensor, no colour gains in its UI". It has no sensor, but it does follow the Mac's own ambient-light changes; the colour-gains claim was unsupported.

**Lunar "Sensor Mode needs Pro":** `AdaptiveMode.swift:50–51` is `var enabled: Bool { proactive || self == .manual || self == .auto }`, but `proactive` isn't defined in any readable file. "`proactive` = Pro licence" is an inference. Your own experience supports it: with an expired demo, Sensor Mode was disabled (VERDICT.md).

**The gap no tool fills** (from the rows above): an **external lux sensor driving the hardware white point** (DDC gains), tied to backlight and bias light, with a hard neutral override. MonitorControl follows ambient light only for brightness, and only via an Apple display's built-in sensor. BetterDisplay has colour controls, but its README says nothing about lux-driven white point. UNVERIFIED whether it can do this through its Pro scripting features.

---

## 2. What to take from Lunar's design

[tokens §3.1–3.3]

- **Take:** a 320 pt `.hudWindow` blur panel; 22 pt pill sliders with the value inside; continuous corners (18 pt panel, 8 pt controls); two springs (`interactiveSpring(dampingFraction: 0.7)` and `spring(response: 0.4, dampingFraction: 0.45)`).
- **Leave:**
  - three drifting colour sources;
  - page × hover state dictionaries;
  - ~40 font combinations;
  - hover-only controls;
  - hierarchy that relies on opacity over blur.

---

## 3. UI spec: the menu bar item

**Icon**
- A sun glyph, tinted with the current target white point, rendered from Kelvin via the RESEARCH_03 maths into sRGB.
- **Colour-critical mode:** a neutral grey half-filled circle. The icon and its accessibility label must change as well as the colour.
- UNVERIFIED: whether `MenuBarExtra` labels can take a tint. *Settles it:* a prototype in Xcode. Fallback: SF Symbols variants with no tint.

**Popover** (`MenuBarExtra(.window)` [RESEARCH_04]), about 320 pt wide, top to bottom:

```
┌────────────────────────────────────────────┐
│  ● ADAPTIVE            5 250 K   ▢ swatch   │  status: mode chip, target K, swatch
│  38 lx · sensor live                        │
├────────────────────────────────────────────┤
│  [   Colour-critical  (6500 K lock)   ◯ ]   │  primary action: one click, full width
├────────────────────────────────────────────┤
│  Brightness         44 %      [ − ] [ + ]   │  nudge ±5, shows offset when non-zero
│  White point        auto      [Warm ▾]      │  temporary 6000/5500/5000/4500 until the room changes
├────────────────────────────────────────────┤
│  Bias light   ◑ following · 5 250 K   [◯]   │  status row + on/off switch (added 2026-10-11, §3.1)
│  Desk light   Room is dark. Turn it on?     │  only while a prompt is active (§3.2)
│               [Turn on]  [Not tonight]      │
├────────────────────────────────────────────┤
│  DDC ok · writes today  B 12/200  G 3/30    │  health row, only in "details"
│  Settings…                          Quit    │
└────────────────────────────────────────────┘
```

**States.** Each state must be distinguishable **without colour**: text, plus icon or shape.

| State | Trigger | Status line | Controls |
|---|---|---|---|
| Adaptive | Default | "● ADAPTIVE · 5 250 K" | All |
| Colour-critical | Override on | "◐ COLOUR-CRITICAL · 6500 K locked" + neutral swatch | Brightness nudges disabled if brightness is frozen |
| Sensor stale | No lux for ≥ `STALE_SECS` | "Sensor offline · holding last values" | Override still works |
| DDC blocked | Lunar, BetterDisplay or MonitorControl running [code: `lib/ddc.sh`] | "Paused: <App> is controlling the monitor" | "Show me" (brings that app forward). UNVERIFIED how |
| Display asleep | `CGDisplayIsAsleep` [RESEARCH_02] | "Monitor asleep" | Read-only |
| Cap reached | Daily cap hit | "Adaptive writes paused until tomorrow (safety cap)" | Override still works: it has a reserved allowance beyond the adaptive cap (FR-30). Corrected 2026-09-26: this said "it respects the cap too", which contradicted "still works" |

The bias-light and desk-light states (2026-10-11) live in their own rows (§3.1, §3.2), not in the status line, so they never hide a monitor state.

### 3.1 Bias light row (added 2026-10-11; SPEC US-7, FR-60–FR-67)

One row under the white-point row; hidden when no Govee IP is configured. Each state has its own glyph **and** words; no colour-only cues.

| State | Trigger | Row text | Control |
|---|---|---|---|
| Following | Adaptive, room below `BIAS_OFF_LUX` | "◑ Bias light · following · 5 250 K" | Switch on |
| Colour-critical | Override on (FR-61) | "◐ Bias light · 6500 K (colour-critical)" | Switch on |
| Off: room bright | Lux > `BIAS_OFF_LUX` (FR-64) | "○ Bias light · off, room is bright" | Switch on (it's automatic, not disabled) |
| Off: monitor asleep | Display asleep | "○ Bias light · off, monitor asleep" | Read-only |
| Off: by you | Switch turned off | "○ Bias light · off" | Switch off |
| Not responding | 3 refreshes without a `devStatus` reply (FR-67) | "⚠ Bias light · not responding" | "Details" shows the IPs and last reply time |

- The switch is "Bias light on/off", not the lamp itself: off means the app sends `turn 0` and stops driving the bars until you switch it on. Persisted.
- With two lights (two IPs, SPEC Q17), the row shows one state; "Details" lists each. If only one replies, the row says "⚠ Bias light · 1 of 2 responding".
- The level (5 cd/m²) is not shown; it's a calibration, not a control. Shown in "details" as "wall target 5 cd/m² · 6 %".

### 3.2 Desk light bar prompt (added 2026-10-11; SPEC US-8, FR-80–FR-87)

**The app never switches the bar by itself.** The prompt appears at most once per evening, after lux < 5 for 10 min (FR-81).

**Notification** (`UNUserNotificationCenter`; a `UNNotificationCategory` with two `UNNotificationAction`s; interruption level `.passive`):
- Title: **"Room is dark"**
- Body (controllable model): **"Turn on the light bar? A little desk light can make the screen easier on your eyes."**
- Body (remote-only model): **"Turn on the light bar with its remote? A little desk light can make the screen easier on your eyes."**
- Actions: **"Turn on"**, **"Not tonight"**.
- UNVERIFIED: macOS banners may show action buttons only on hover, and Focus can hide the notification. *Settles it:* a test notification. The popover row is the always-present fallback (FR-87).
- Withdrawn with `removeDeliveredNotifications(withIdentifiers:)` when lux rises above 20 lx or the evening window ends (FR-85).

**Popover row states:**

| State | Row text | Buttons |
|---|---|---|
| Asking | "◇ Desk light · Room is dark. Turn on the light bar?" | "Turn on", "Not tonight" |
| Remote-only, after "Turn on" | "Desk light · Use the bar's remote: press to switch on, turn for warmer." | "It's on", "Not tonight" |
| Controllable, sent | "✓ Desk light · on, 2700 K, 30 %" | — |
| Controllable, failed | "⚠ Desk light · couldn't reach the light bar" | "Try again" (one more command, still your tap) |
| You said on | "✓ Desk light · on (you turned it on)" | — |
| Not tonight | "Desk light · not tonight. Asks again tomorrow evening." | "Don't ask again" |
| Withdrawn / idle | row hidden | — |

- The ◇ glyph stands in for an SF Symbol (e.g. `lightbulb`, name UNVERIFIED); the text carries the meaning.
- **"Not tonight" suppression:** until 06:00 (FR-82). "Don't ask again" is also a toggle in Settings ("Ask about the desk light in the evening").
- No snooze, no repeat, no badge: HIG says avoid repeat notifications for the same thing.

**Interaction rules:**
- **The override is the first control, not in a submenu, and doesn't auto-exit.**
- **Brightness uses −/+ nudges, not a free slider.** A slider drag produces many target values. The scheduler would coalesce them, but it invites fiddling. If there's a slider, it commits on release only.
- **"Warm now" presets are labelled temporary** ("until the room changes"). This matches the prototype's behaviour [code: `swiftbar/lighting.10s.sh`].
- **Health numbers stay out of the default view.** They matter for the first weeks only.

**Settings** (`Settings` scene [RESEARCH_04]):
- a curve table (lux → %);
- Kelvin mapping endpoints;
- the gain table (pasted from probe 05), with the "measured on" date;
- write limits, read-only with an "advanced" unlock;
- launch at login (`SMAppService.mainApp`).

**No global hotkey in v1.** Use a Shortcut that calls the app's URL scheme or CLI, the way the prototype does today. UNVERIFIED which global-hotkey API needs no Accessibility permission; not researched.

---

## 4. Tokens

Use the deduplicated JSON in [tokens §9] as the starting point. Additions from this spec:

- `color.whitepoint.live`: computed at runtime.
- `color.critical = #8E8E93`: neutral grey, shown only in colour-critical mode. A new addition for this app, not taken from Lunar (corrected 2026-09-26: this was tagged [tokens §9], implying a Lunar source).

Accessibility:
- Every state carries a text label (§3).
- Text contrast over the `.hudWindow` blur must be checked in both light and dark mode. UNVERIFIED: the contrast ratio. *Settles it:* Accessibility Inspector.

---

## What not to build

- **A full settings window before the popover is right.** Settings can stay a text file for Phases 1–4 of BUILD_PLAN.
- **A curve chart** before a week of data exists.
- **Per-display UI.** One monitor.
- **Hover-reveal controls, or onboarding carousels.**
- **Custom-drawn sliders.** Use system controls, then style them with tokens.
- **Animated transitions of the tint.** The monitor itself changes slowly, so the icon can just update.
- **A bias brightness slider.** The level is a calibration to 5 cd/m² (R08), not a preference.
- **Repeat or escalating light-bar prompts,** and any light-bar action without a tap (R08 §6).

---

## Assumptions

| Assumption | If wrong |
|---|---|
| You'll use the popover more than Settings | Invest in Settings instead. Easy to shift |
| Nudges beat a slider for you | Add a commit-on-release slider |
| A tinted menu bar icon is possible and readable | Use shape-only icons |
| Actionable notifications work for an `LSUIElement` menu bar app (UNVERIFIED) | The popover row alone carries the prompt; FR-87 already requires it |
