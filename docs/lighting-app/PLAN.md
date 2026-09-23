# Adaptive display and lighting app: analysis and plan

Written for: a product designer moving into design engineering, building a personal macOS menu bar app.
Hardware: Mac Studio (Apple Silicon), AOC CU34G4Z, ESP32 Feather V2 + TSL2591 (ESPHome), Govee light bars.
Status: analysis only. No code has been written.

Sources read:

- `alin23/Lunar` @ 6.11.0. This repo; every file reference below is a path in it.
- `MonitorControl/MonitorControl` (main branch, Sep 2026)
- `waydabber/m1ddc` (main branch, Aug 2026)
- `wez/govee-lan-hass`, plus the library that actually implements the protocol, `wez/govee-py` (`govee_led_wez/govee.py`)
- `lunar.fyi/sensor` and `app-h5.govee.com/user-manual/wlan-guide` were **blocked by this environment's network proxy**. I took the sensor protocol from the ESPHome configs in `Lunar/ALS/` and from your own sample output. I took the Govee protocol from wez's implementation. Check both against the official pages before building.

---

## TL;DR (read this if nothing else)

1. **You can't build Lunar, and you can't lift its most useful parts.** Four things are encrypted: the sensor mode, the curve-fitting/learning maths, the Pro gate, and the whole Apple Silicon DDC transport (`DDC2.c`). Lunar is a design and architecture reference only.
2. **Build the DDC layer on MonitorControl's `Arm64DDC.swift` (MIT, about 150 useful lines).** Use `m1ddc` as a known-good command-line tool to test against. Don't fork either app.
3. **Your gain table has a hidden assumption.** Your 5000K and 4500K rows match the maths exactly if the AOC applies gain to *gamma-encoded* values. If it applies gain in *linear light*, your "4500K" row actually lands at about 5400K. You have to measure which it is. See §2.4.
4. **"Scale all three up to preserve luminance" is a bad idea.** Above neutral you clip highlights. Keep the largest channel at neutral and let the backlight make up the lost luminance. You control the backlight anyway.
5. **Your sensor measures lux, not colour, so this isn't True Tone.** Warmer-when-dimmer is a reasonable rule of thumb, but True Tone matches the *colour* of the room light. For that you'd add an RGB/spectral sensor (TCS34725 or AS7341) to the ESP32 later.
6. **Govee control commands go to UDP 4003, not 4001.** 4001 is only for discovery (multicast scan), and 4002 is where replies arrive.
7. **Brightness writes are a bigger EEPROM risk than gain writes.** Lunar-style smooth transitions send every intermediate step over DDC, and both reference DDC implementations send every packet twice. Put the smoothing in software and write to the monitor rarely.
8. **Before writing any Swift, spend 2–3 days on a shell-script prototype** (`curl` + `m1ddc` + `nc`). It proves all three outputs and the override work on your hardware. §2.8, step 0.
9. **Scope:** about 6–8 weeks part-time for a solid MVP (brightness + white point + override), and 10–14 weeks for everything including Govee and learning. §1.6.

---

# 1. Architecture lead

## 1.1 What's present vs missing in the Lunar repo

`.gitsecret/paths/mapping.cfg` lists what's encrypted. Each has a `.secret` twin and no plaintext:

| Encrypted file | What it holds | What losing it rules out |
|---|---|---|
| `Lunar/Modes/SensorMode.swift` | The external sensor client (SSE), lux window averaging, `DEFAULT_BRIGHTNESS_MAPPING`, `adapt()` for sensor mode | Copying the lux→brightness pipeline you use today |
| `Lunar/Modes/SyncMode.swift`, `LocationMode.swift`, `ClockMode.swift` | The other adaptive modes and `interpolate(...)` | Copying any mode's adapt logic |
| `Lunar/Data/Pro.swift` | Licensing, and most likely the shared curve maths: `insertDataPoint(_:in:cliffRatio:cliffSourceDiff:)`, `computeBrightnessSpline` and `AutoLearnMapping` are called from plaintext but defined nowhere in plaintext | Copying the learning curve |
| `Lunar/DDC/DDC2.c/.h` | **The Apple Silicon DDC transport** (`DDCWrite(avService:…)`, `DDCRead`) | Using Lunar's DDC code on your Mac Studio at all. The plaintext `DDC.c` is Intel-only (IOFramebuffer I2C) |
| `Lunar/required.swift` | Build glue | Compiling the project |
| `Lunar/Resources/*_priv*` | Update-signing keys | Not relevant |

**What's still readable and useful:**

- `Lunar/Modes/AdaptiveMode.swift`: the mode protocol.
- `Lunar/Data/Display.swift`: data model, curve *call sites* and their parameters, the old readable `insertDataPoint(values:featureValue:targetValue:)`, `smoothTransition`, `LUX_TO_NITS`, and colour-gain properties.
- `Lunar/DDC/DDC.swift`: fault counting, wake gating, VCP enum.
- `Lunar/Utils/DisplayController.swift`: DCP/AVService discovery and matching.
- `Lunar/Control/*`: the control abstraction.
- `Lunar/ALS/*.yaml`: ESPHome sensor firmware.
- `LunarShortcuts/`: App Intents.
- All UI code, the storyboard and the asset catalog.

That's enough to understand *what* Lunar does and *how it's structured*. It isn't enough to reproduce the adaptive curve exactly, and I haven't tried to recover it. You'll write your own, and it'll be simpler (§2.4).

## 1.2 Lunar's architecture

```
AppDelegate ── StatusItemButtonController (custom NSWindow, not NSPopover)
    │             └── QuickActionsMenuView (SwiftUI)
    │
DisplayController (DC, singleton)  Utils/DisplayController.swift
    ├── adaptiveModeKey ─► AdaptiveMode.shared  (Sensor | Sync | Location | Clock | Manual | Auto)
    ├── activeDisplays: [CGDirectDisplayID: Display]
    └── adaptBrightness(for:) → mode.adapt(display)
         │
Display (6.7k lines, ObservableObject + Codable)  Data/Display.swift
    ├── per-mode curves: sensorBrightnessMapping, syncBrightnessMapping[source], locationBrightnessMapping, … (+ contrast twins)
    ├── brightness/contrast/redGain/greenGain/blueGain (@Published, didSet → control.setX)
    └── control: Control  ← chosen per display
         ├── DDCControl        → DDC (static) → DDC.c (Intel) | DDC2.c (arm64, encrypted)
         ├── AppleNativeControl (DisplayServices private framework: Apple displays)
         ├── GammaControl      (software dimming via gamma tables)
         ├── NetworkControl    (DDC over a Raspberry Pi on the LAN)
         └── DDCCTLControl     (external ddcctl binary)
```

**Display discovery (Apple Silicon)**, `DisplayController.swift:162` `DCP`:

1. Walk the IORegistry for the `dispext*`/DCP services.
2. For each one, find the `DCPAVServiceProxy` child whose `Location` is `External`, and create an `IOAVService` from it.
3. Read `AppleCLCD2`'s properties: EDID UUID, `ProductAttributes` (name, serial, vendor), and `Transport`.
4. Score each display against each service (`AVServiceMatch`: `byEDIDUUID`, `byProductAttributes`, `byExclusion`) to decide which `CGDirectDisplayID` owns which AVService.

`DDC.setup()` registers IOKit notifications on `AppleCLCD2`, `IOMobileFramebufferShim` and `DCPAVServiceProxy`, and rebuilds the map on a 1-second debounce when the tree changes.

**The adaptive mode structure** is a simple protocol (`AdaptiveMode.swift:180`): `watch()`, `stopWatching()`, `adapt(display)`, `available`, and `DataPoint` min/max/last values for the chart. Every mode is a singleton. `Auto` picks the best available mode. It's a clean seam, and the one idea worth copying structurally.

**Where DDC sits:** three layers down, behind `Control`. The key design choice is that **`Display` properties have side effects**. Setting `display.redGain` immediately writes DDC in `didSet` (`Display.swift:3782`) with no rate limiting. Brightness has a 50 ms `throttle` in `DDCControl.brightnessPublisher`, and that's all. Also, **`DDC.sync` runs on the main thread** (`DDC.swift:857`: `mainThread(action)`), so C-level `usleep`s inside I2C transactions block the UI thread. Don't copy either choice.

**Safety machinery worth copying** (`DDC.swift`):

- Per-display, per-VCP **fault counters**. A write that fails counts +1, one that takes more than 2 s counts +4, and a success counts −1. After 20 faults the property is put on a "skip writing" list; for reads it's 10.
- A **wake gate**. `DDC.write` returns early while screens sleep, while the Mac is locked, or within `waitAfterWakeSeconds` of wake.
- **Slow-write detection** in `smoothTransition`. If a step takes more than 2×90 ms, the step size grows.

## 1.3 Lunar's adaptive algorithm (what the plaintext shows)

**The data model.** A curve is `[AutoLearnMapping]`, a list of `(source, target)` points:

- `source` is lux (sensor mode), the source display's brightness (sync mode) or sun elevation (location mode).
- `target` is brightness 0–100, normalised to the display's min/max.

Curves are stored **per display, per mode**, and there's a separate contrast curve. The default sensor curve comes from the encrypted `SensorMode`. On Apple Silicon, when the display's nits are known, Lunar instead builds it from a readable table (`Display.swift:1336`):

```
LUX_TO_NITS = [0:40, 13:54, 23:61, 39:76, 71:87, 80:100, 100:105, 135:120,
               160:134, 190:147, 224:160, 313:193, 565:289, 702:340, 800:400, 1000:500]
```

It converts nits to percent using the display's min and max nits. **This is a sensible seed curve for you too.** Fill in your AOC's real min and max nits (see the spec sheet or measure).

**How lux maps to brightness.** `mode.interpolate(lux, display:)` evaluates a spline fitted through the curve points (`computeBrightnessSpline`; the file imports `Surge`/`Accelerate`). The implementation is encrypted. The result is mapped to the display's `[minBrightness, maxBrightness]`.

**How manual corrections teach the curve** (`Display.swift:6617–6666`). When you move the slider while an adaptive mode is on, Lunar calls `insertBrightnessUserDataPoint(currentLux, newValue)`. That function:

1. Returns early if the curve is locked (`lockedBrightnessCurve`), adaptive is paused, or the display connected less than 5 s ago.
2. Normalises the value to 0–100 within the user's min/max, and subtracts any sub-zero (gamma) dimming.
3. Inserts the point with **"cliff detection"** parameters that differ by mode. Sensor uses `cliffRatio 2`, `cliffSourceDiff 30`, `stopCliffDetectionBelow 35`; sync uses `1.5, 10`; location uses `3, 5`. The function body is encrypted. The names suggest it stops a new point from creating a slope more than *N*× steeper than its neighbours within a source distance, and smooths or removes neighbours when it would.
4. **Coalesces a whole drag into one edit.** `previousBrightnessMapping.setOrRefresh(curve, expireAfter: 1)` snapshots the curve before the drag. Each slider tick re-inserts into *that snapshot*, so a 2-second drag leaves one point, not a trail. This is a good detail. Copy the idea.

The older plaintext version, `Display.insertDataPoint(values:featureValue:targetValue:)` (`Display.swift:4400`), shows the core principle. **When a point is added, delete every existing point that would break monotonicity**: any point to the left that is ≥ the new value, and any point to the right that is ≤ it. Then add the point. A curve that only ever goes up is the invariant. That's all the "learning" you need for v1.

**How transitions are smoothed.** There are three layers:

1. **Firmware.** `Lunar/ALS/tsl2591.yaml` samples every 1 s, applies `sliding_window_moving_average` (window 15, `send_every: 2`), and drops the `65535`/`NaN` saturation values. Lux arrives every 2 s as a 15-second average.
2. **App.** Lunar keeps a window of the last 15 readings (`GetSensorLuxIntent` exposes "average of the last 15 readings").
3. **Output.** `Display.smoothTransition` (`Display.swift:5875`) **steps the DDC value one unit at a time** from current to target on a serial queue. It measures each write's latency and raises the step size so each step stays near 90 ms. Clock mode uses `slowBrightnessTransition` over minutes in 0.005 steps. **Every intermediate step is a DDC write.** That's why this is the thing *not* to copy for EEPROM reasons (§2.2).

## 1.4 MonitorControl vs m1ddc as a foundation

| | MonitorControl | m1ddc |
|---|---|---|
| Language | Swift | Objective-C / C |
| Licence | MIT | MIT |
| Apple Silicon DDC | `Support/Arm64DDC.swift`, 275 lines | `sources/i2c.m`, 86 lines + `ioregistry.m`, 266 |
| Display ↔ service matching | Scored matching (EDID UUID fragments, IO location, name, serial) | Several identification methods (uuid, edid, serial…) |
| Retries / timing | Configurable write cycles, retries, sleep times | Fixed `DDC_WAIT 10ms`, `DDC_ITERATIONS 2` |
| Sleep/wake handling | Yes (`sleepID` gating in `AppDelegate`) | No (CLI) |
| Built as | Full app (AppKit prefs, keyboard taps, OSD) | CLI |

**Recommendation: port MonitorControl's `Arm64DDC.swift` into your own DDC module**, not the app around it. It's already Swift, so you won't have to bridge Objective-C. Its `performDDCCommunication` (packet build, checksum, write, optional read, retries) is exactly the transport you need. `getIoregServicesForMatching` handles discovery. You only need these private declarations in a bridging header, the same ones MonitorControl uses:

```c
typedef CFTypeRef IOAVService;
extern IOAVService IOAVServiceCreateWithService(CFAllocatorRef, io_service_t);
extern IOReturn IOAVServiceReadI2C(IOAVService, uint32_t chip, uint32_t offset, void*, uint32_t);
extern IOReturn IOAVServiceWriteI2C(IOAVService, uint32_t chip, uint32_t dataAddr, void*, uint32_t);
```

**Use m1ddc as a test oracle.** Build it with `make` on the Mac. When your app's write "doesn't work", `m1ddc set red 47` tells you in 5 seconds whether the problem is your code or the monitor. It's also the core of the step-0 prototype.

Two things to change when you port:

- **Set write cycles to 1.** Both MonitorControl (`numOfWriteCycles ?? 2`) and m1ddc (`DDC_ITERATIONS 2`) **send every write twice** as a reliability hack. For gains, test whether your AOC takes a single write. If it does, you've halved the writes.
- **Simplify matching.** You have exactly one external display, so the matching can be "the only `DCPAVServiceProxy` with `Location == External`", checked against the product name `CU34G4Z`. Keep MonitorControl's scoring code around in case you ever add a second monitor.

## 1.5 What you must write from scratch vs adapt

| Piece | Source | Effort |
|---|---|---|
| I2C transport + checksum | **Adapt** `Arm64DDC.performDDCCommunication` | Small |
| AVService discovery | **Adapt** `Arm64DDC.getIoregServicesForMatching`, simplified | Small |
| **Write scheduler** (rate limits, coalescing, budget, sleep gating) | **Write from scratch.** Neither reference has one. Lunar's fault counters are the model | Medium. **This is the most important code in the app** |
| SSE lux client | **Write** (URLSession `bytes(for:)` + `.lines`, about 60 lines) | Small |
| Lux filtering | **Write** (pure function, unit-testable) | Small |
| Brightness curve + corrections | **Write**, inspired by Lunar's monotonic insertion | Medium |
| CCT → gains + calibration LUT | **Write** (§2.4) | Medium (the maths is small; calibrating it takes the time) |
| Govee LAN client | **Write**, porting the packet shapes from `govee_led_wez/govee.py` | Small–medium |
| Sleep/wake/reconfigure handling | **Write**, modelled on MonitorControl's `sleepID` and Lunar's `waitAfterWakeSeconds` | Small |
| Menu bar UI + settings | **Write** in SwiftUI, with Lunar as visual reference (see DESIGN_TOKENS.md) | Medium |
| Curve editor (chart) | **Write** with Swift Charts | Medium. Defer it |

## 1.6 An honest scope estimate

Assumptions: about 12–15 focused hours a week, heavy AI pair-programming, no prior Swift. The first 2 weeks will feel slow because you're learning Xcode, Swift concurrency, code signing and the menu bar app lifecycle, not the problem itself. That's normal.

| Milestone | Calendar time | Cumulative |
|---|---|---|
| Step 0: shell prototype proving DDC gains, lux and Govee on your hardware | 2–3 days | ~0.5 wk |
| Menu bar app skeleton + live lux display | 1.5 wk | 2 wk |
| DDC module + write scheduler, manual brightness/gain sliders | 2 wk | 4 wk |
| Adaptive brightness (fixed curve) + colour-critical override | 1.5 wk | 5.5 wk |
| Adaptive white point + calibration table | 1.5 wk | **7 wk = MVP** |
| Sleep/wake hardening, Lunar coexistence, persistence | 1 wk | 8 wk |
| Manual-correction learning | 1.5 wk | 9.5 wk |
| Govee bias light | 1.5 wk | 11 wk |
| Polish: login item, settings window, curve chart | 2 wk | ~13 wk |

What makes this run over: getting white-point calibration right (budget time with a colorimeter if you can borrow one), sleep/wake edge cases (they only show up overnight), and redesigning the UI before the engine works. Design the UI last. You're a designer, so this is the one you'll find hardest to hold to.

## 1.7 Does this already exist?

- **#1 Adaptive brightness from your ESP32: yes, solved.** Lunar Pro, which you already own, does it. Building it again is for unification and learning, and those are fine reasons. Know that that's the trade you're making.
- **Lunar Pro can already do a crude #2.** It has a hardware colour-gain Shortcut (`AdjustHardwareColorsIntent`, which writes 0x16/0x18/0x1A), a "Get Ambient Light (lux)" Shortcut, and a CLI (`lunar lux`, `lunar displays <name> redGain 47`, `lunar ddc`, in `Data/CLI.swift`). A script that polls lux and calls the CLI gives you a zero-Swift adaptive white point *today*, using Lunar's DDC stack. It's a good way to live with the feature for a week before building it.
- **MonitorControl** does keyboard and slider brightness/contrast/volume. It has no ambient sensor, no gain UI and no adaptive modes. A contribution to it would be a large feature outside its current scope, so check their issues and discussions before investing.
- **Night Shift / f.lux** shift white point *in software* (display colour transform) on a schedule, not by lux. They work on your external monitor today. They're a fallback if the AOC's gain behaviour turns out to be bad.
- **Home Assistant**, if you run it, already integrates both ESPHome and Govee LAN. Bias light as a function of lux could live entirely there, with no Mac involved. The catch is that the colour-critical override and manual brightness offsets then have to reach HA.
- **Nobody** does hardware white point from lux, unified with backlight and bias, with a hard neutral override. **That combination is the real reason to build this.**

---

# 2. Systems

## 2.1 Module structure

One Xcode project, one app target, with the logic in **local Swift packages**. Packages can be unit-tested with `swift test` without launching the app. That's how you make "every step testable".

```
LightingApp (app target: SwiftUI, LSUIElement = YES)
│
├── Packages/
│   ├── LuxKit        SSE client → AsyncStream<LuxSample>; staleness detection
│   ├── Engine        PURE. No I/O. Filter, curves, CCT maths, policy state machine
│   │     ├── LuxFilter.swift        log-domain EMA, asymmetric, dead-band
│   │     ├── BrightnessCurve.swift  points + monotonic insert + interpolate
│   │     ├── WhitePoint.swift       lux→K, K→xy→RGB→gains, calibration LUT
│   │     ├── BiasPolicy.swift       screen nits → strip %
│   │     └── Policy.swift           Mode: .adaptive | .manualHold | .colourCritical
│   ├── DDCKit        IOAVService transport, discovery, WriteScheduler (actor), VCP enum
│   └── GoveeKit      UDP scan/listen/command, device cache
│
└── App/
    ├── Coordinator.swift     wires streams → Engine → outputs; owns persistence
    ├── SystemEvents.swift    sleep/wake, display reconfig, "is Lunar running?"
    ├── MenuBarView.swift     MenuBarExtra(.window) content
    └── SettingsView.swift    Settings scene
```

**Principle: `Engine` never touches hardware.** It takes `(filteredLux, mode, userOffsets, calibration)` and returns `Targets(brightness, gains, biasPct, biasKelvin)`. The Coordinator hands targets to `DDCKit.WriteScheduler` and `GoveeKit`. Those decide *whether and when* anything is actually sent. Almost all bugs will be in one of those two boundaries, and both can be tested on their own.

**Apple frameworks:**

| Framework | Why |
|---|---|
| SwiftUI | All UI. `MenuBarExtra` with `.menuBarExtraStyle(.window)` + `Settings` scene (macOS 13+) |
| AppKit | `NSWorkspace` sleep/wake notifications, `NSRunningApplication` (Lunar detection), `NSApp` activation |
| IOKit | IORegistry walk + `IOAVService*` (private symbols, declared in a bridging header) |
| CoreGraphics | `CGDirectDisplayID`, `CGDisplayRegisterReconfigurationCallback` |
| Foundation / URLSession | SSE via `URLSession.bytes(for:)` |
| Network | `NWConnection` (UDP to 4003/4001), `NWListener` on 4002 |
| OSLog | `Logger`. You'll live in Console.app |
| ServiceManagement | `SMAppService.mainApp` for launch at login |
| Charts | Curve visualisation (later) |

**Not needed** (Lunar uses them, you don't): SkyLight, DisplayServices, CoreBrightness, MonitorPanel, OSD, BezelServices, CoreDisplay (optional), Sparkle, Paddle.

**Distribution constraint:** private `IOAVService` calls mean **no App Store and no sandbox**. Sign with your personal Apple Developer identity (even a free one) so macOS privacy prompts behave. On macOS 15+, both `.local` resolution and UDP multicast trigger the **Local Network** permission prompt. Add `NSLocalNetworkUsageDescription` to Info.plist, as Lunar does (`Lunar/Info.plist:83`).

## 2.2 DDC pitfalls

**1. Calls are synchronous and slow.** A write costs about 10 ms pre-sleep × write cycles + I2C time. A read adds about 50 ms and often needs retries, so budget 30–300 ms per transaction. Never make one on the main thread (Lunar does; don't). Wrap the transport in a Swift **`actor DDCWriter`** so calls are serialised, off-main, and impossible to interleave. Two concurrent transactions on one AVService corrupt each other.

**2. EEPROM wear (~100k cycles, worst case).** You can't know whether the AOC commits every DDC write to EEPROM or buffers in RAM and commits on OSD timeout or power-off. **Design for the worst case.** The maths:

| Pattern | Writes/day to one VCP | Life at 100k |
|---|---|---|
| Lunar-style smooth transitions (≈30 steps per change) × 50 changes/day × 2 (double-send) | ~3,000 | **~33 days** |
| Direct writes, 1 per change, 50 changes/day, single-send | 50 | ~5.5 years |
| Gains quantised to 250K steps, dwell ≥ 10 min, ≈12 changes/day | 12 per channel | ~23 years |

Rules for the `WriteScheduler`:

- **Do smoothing in software, not over the wire.** Filter the lux, not the DDC output. The backlight simply jumps to the new value. A 2–3-unit jump on a VA panel's backlight is imperceptible when it happens slowly and rarely.
- **Latest-wins coalescing per VCP.** Only the most recent target is pending. Old targets are dropped, not queued.
- **Minimum interval per VCP.** Brightness ≥ 20 s between adaptive writes, and manual slider writes throttled to ≤ 4/s *while dragging*. Gains ≥ 10 min between adaptive changes.
- **Dead-bands.** Brightness writes only when |Δ| ≥ 2. Gains write only when the quantised Kelvin step changes.
- **Skip no-ops.** Never write the value you last wrote successfully.
- **A persistent daily write counter per VCP,** with a hard cap (say 300 brightness, 50 per gain channel). Past the cap, adaptive writes stop and the menu shows why. This is the fuse that stops a bug from burning out your monitor.
- **Write log.** Keep a ring buffer of `(time, vcp, value, ok, ms)` and show it in a debug view. It's how you'll prove the rate limits work.
- **The three gains go out as one ordered "set" with 50–100 ms gaps.** Lunar's Shortcut has a "small delay between each colour" option (`LunarShortcuts.swift:2383`), which suggests some monitors drop back-to-back gain writes. Test whether the AOC does.

**3. Sleep/wake.** DDC to a sleeping or waking monitor fails, hangs, or, on some monitors, lands and is then overwritten by the monitor's own restore.

- On `NSWorkspace.willSleepNotification` / `screensDidSleepNotification`: close the scheduler gate and drop pending writes.
- On `didWakeNotification` / `screensDidWakeNotification`: wait **5–10 s** (Lunar calls this `waitAfterWakeSeconds`; MonitorControl uses a `sleepID` gate), rediscover the AVService (the handle can go stale), then **reapply current targets once**. Lunar reapplies *N* times every 2 s (`AppDelegate.swift:2491`). That's a wear multiplier. Once plus one read-back check is enough.
- `CGDisplayRegisterReconfigurationCallback`: rediscover on resolution, arrangement or cable changes.
- Also gate on the screen being locked, as Lunar does.

**4. Monitors that accept writes but not reads.** Many do. Some return stale or garbage values, or fail the checksum. So:

- **Never do read-modify-write** (no `chg +10`). Always write absolute values computed from your own state.
- **Your app is the source of truth.** Persist the last written value per VCP and assume it's still what the monitor has, unless the user touched the OSD.
- Treat reads as **diagnostics only**. There's an optional "verify" button that reads back and shows a mismatch.
- Copy Lunar's **fault counter**. After *N* failures on a VCP, stop writing it and surface a warning instead of hammering the bus.

**5. The OSD colour mode must stay on "User".** In other presets, the AOC ignores or resets 0x16/0x18/0x1A. You can't reliably detect this over DDC. Put it in onboarding copy and add a "white point isn't changing?" hint.

**6. Leaving the monitor warm.** If the app quits or crashes at 4500K, the monitor stays at 4500K, because the gains are stored in the monitor. On quit, write neutral. On launch, if the last session didn't exit cleanly, write neutral before anything else.

## 2.3 Not conflicting with Lunar during migration

Lunar will fight you in three ways, all visible in its source:

1. **Brightness.** Lunar's sensor mode re-adapts on every lux change and after wake (`DC.adaptBrightness(force: true)`), so it will overwrite your brightness writes.
2. **Gains.** If the per-display `reapplyColorGain` is on, Lunar **rewrites its stored gains after wake**, repeatedly (`AppDelegate.swift:1719` and `:2493`). That silently resets your white point.
3. **Bus contention.** Two apps sending I2C to one AVService at once can interleave packets. Rare with low-rate writes, but real.

Migrate by handing over one responsibility at a time:

| Stage | Lunar | Your app |
|---|---|---|
| A (build steps 1–7) | Keeps adaptive brightness. **Turn off "re-apply color gain"** for the AOC | White point + override only. Writes gains only |
| B (build step 8+) | Set the AOC to **Manual** mode and disable its DDC control for that display (or "unmanage" it), or just quit Lunar | Brightness + white point |
| C | Uninstall, or keep for other tools | Everything |

Two more steps:

- **Detect Lunar.** `NSRunningApplication.runningApplications(withBundleIdentifier: "fyi.lunar.Lunar")` (bundle ID from `Lunar.xcodeproj`). Show a persistent banner: "Lunar is running and may overwrite brightness/white point."
- **The sensor.** Both apps can hold an SSE connection to `lunarsensor.local/events`. ESPHome's web server supports several event-stream clients, but the ESP32 has limited sockets. Test it with both connected for a day. If it's flaky, either lower the rate or give the sensor a second endpoint.

## 2.4 Lux → three outputs

### Filtering (shared by all three)

The firmware already gives you a 15 s moving average every 2 s. On top of that:

```
L      = log10(max(lux, 0.1))                        // perception is ~logarithmic
τ      = (L > Lf) ? 8 s : 45 s                       // brighten fast, dim slow
Lf    += (1 − exp(−Δt/τ)) · (L − Lf)                 // exponential moving average
act    only if |Lf − L_lastActed| ≥ 0.04             // ≈ 10% lux dead-band (hysteresis)
stale  if no sample for 60 s → HOLD all outputs (never snap to a default)
```

Why asymmetric: when a lamp turns on, you want the screen to catch up in seconds. When a cloud passes, you don't want it to dip.

### Output 1: backlight (VCP 0x10)

```
b = interpolate(curve, Lf)                     // piecewise-linear in log-lux, clamped
b = clamp(b + userOffset, bMin, bMax)
b = b × luminanceCompensation(K)               // see white point below
```

- **Curve:** 5–8 points `(log10 lux, brightness%)`. Seed it from Lunar's `LUX_TO_NITS` table, converted with your monitor's min/max nits. Use **piecewise-linear interpolation in log-lux**, not a spline. It's predictable, monotonic by construction, and easy to draw in a UI. A spline can overshoot between points.
- **Manual correction (v1):** a slider move while adaptive becomes a global `userOffset` that decays back to 0 over ~2 h, or clears when lux moves a lot. That handles 80% of "it's a bit too bright right now" with no curve surgery.
- **Learning (v2):** on a confirmed correction (slider released, value held ≥ 5 s), insert `(Lf, b)` into the curve using Lunar's monotonic rule. Delete points that break ordering and coalesce the whole drag (the 1-second snapshot trick). Cap the number of points. Merge points closer than 0.1 decades.

### Output 2: white point (VCP 0x16/0x18/0x1A)

**Step 1: lux → target Kelvin.** A clamped linear ramp in log-lux, quantised:

```
K = lerp(K_dim, 6500, smoothstep((Lf − log10(L_dim)) / (log10(L_bright) − log10(L_dim))))
defaults: L_dim = 10 lx → K_dim = 5000 K;  L_bright = 300 lx → 6500 K
K = round(K / 250) × 250
```

Stop at 5000K by default, and don't allow below 4000K. Below that, gain-based shifts get ugly (the blue channel falls under 60% even in the gentle domain).

**Step 2: Kelvin → chromaticity.** Use the **CIE daylight locus**, which is valid for 4000–25000K. It's correct here because D65, your neutral, sits *on* the daylight locus and *off* the Planckian locus. If you use Planckian maths, "6500K" won't come out neutral: you get 50/47/50, which is visibly green-ish. In the formula below, `T` is the target Kelvin:

```
x = −4.6070e9/T³ + 2.9678e6/T² + 0.09911e3/T + 0.244063        (4000 ≤ T ≤ 7000)
x = −2.0064e9/T³ + 1.9018e6/T² + 0.24748e3/T + 0.237040        (7000 < T ≤ 25000)
y = −3.000x² + 2.870x − 0.275
```

**Step 3: chromaticity → linear RGB relative to D65.**

```
XYZ = (x/y, 1, (1 − x − y)/y)
rgb = M_sRGB⁻¹ · XYZ           // [[3.2406,−1.5372,−0.4986],[−0.9689,1.8758,0.0415],[0.0557,−0.2040,1.0570]]
rgb = rgb / rgb(D65)            // channel-wise, so 6500 K → (1,1,1)
rgb = rgb / max(rgb)            // largest channel = 1 → never exceed neutral
```

For better accuracy, replace the sRGB matrix with one built from **your monitor's primaries from its EDID**. They're in the IORegistry `DisplayAttributes` (`ColorElements`) that Lunar and MonitorControl already read.

**Step 4: RGB → DDC gain.** This is where the unknown is:

```
linear-domain monitor:   gain_c = neutral_c × rgb_c
encoded-domain monitor:  gain_c = neutral_c × rgb_c^(1/2.2)
```

| K | Linear-domain gains | Encoded-domain gains | **Your table** |
|---|---|---|---|
| 6500 | 50/50/50 | 50/50/50 | 50/50/50 |
| 6000 | 50/47/44 | 50/49/47 | — |
| 5500 | 50/45/37 | 50/48/44 | 50/47/44 |
| 5000 | 50/41/31 | 50/46/40 | **50/46/40** |
| 4500 | 50/38/24 | 50/44/36 | **50/44/36** |
| 4000 | 50/34/18 | 50/42/31 | — |

(Computed with the daylight-locus and sRGB formulas above, with neutral at 50.)

**Your numbers match the encoded-domain column almost exactly.** Whatever method you used, it assumed the AOC applies gain to gamma-encoded signal values. Many monitor scalers apply RGB gain in *linear* light, the way the old "video gain (drive)" definition implies. If the AOC does, your "4500K" row actually gives about 5400K: warmer, but half the shift you think you're getting.

**How to find out:** measure. With a colorimeter (i1Display, Spyder or similar; borrow one), write each row and read the white point's CCT. Without one, compare side by side against a known-D50 reference: a D50 viewing booth, or a MacBook set to a D50 profile. Measure once and store a **calibration LUT** of `K → (r, g, b)` measured points. Interpolate between them at runtime. The maths above only picks the starting points to measure.

**Luminance: don't scale up.** Warming lowers luminance (Y ≈ 0.2126R + 0.7152G + 0.0722B). At 5000K in the encoded domain you lose about 15%. Scaling all three gains *above* neutral to recover that will clip: the red channel hits panel maximum before white does, and you compress highlights and shift near-white hues, which is exactly where colour judgement happens. **Keep the largest channel at neutral and compensate with the backlight:** `luminanceCompensation(K) = 1 / Y_rel(K)`, capped so brightness stays ≤ `bMax`. You already control the backlight, so the coupled model is free.

### Output 3: bias light

The standard advice is that bias lighting should be about **10% of the screen's white luminance**, and **D65 neutral** for colour-critical viewing.

```
screenNits  ≈ nitsMin + (nitsMax − nitsMin) × (b / 100)        // backlight PWM is ~linear in nits
biasPct     = clamp(round(k × screenNits), 1, 100)             // k calibrated once
biasKelvin  = K (follow white point) — except colourCritical → 6500
```

`k` depends on the strip, its distance from the wall and the wall colour, so it can't be calculated. **Calibrate it by eye once.** At a normal screen brightness, adjust the strip until it "just frames" the screen, and store `k = pct / nits`. Govee brightness % isn't linear in luminance either. If it looks wrong at the extremes, add a 3-point curve later.

## 2.5 Colour-critical override (non-negotiable, so it's designed first)

A policy state. It isn't a "mode" the adaptive loop can argue with.

- **One click** in the menu bar, plus an optional global hotkey later. It writes neutral gains **immediately**. That's the one write allowed to skip the dwell timer, though it still goes through the scheduler's serialisation. It freezes white point, sets bias to 6500K, and **optionally freezes brightness** at a reference value (say 120 nits). Luminance affects colour judgement too, so I'd default to freezing it.
- **Persisted.** It survives sleep, restart and app relaunch. On wake, neutral is reapplied first.
- **Unmistakable.** A distinct menu bar icon state, and a banner in the popover saying "Colour-critical — 6500K locked".
- **No auto-exit.** Leaving is always a deliberate click. Auto-enabling when Figma or Photoshop is frontmost is a nice v2 feature. Auto-*exit* never.
- **Neutral means calibrated neutral.** Store the measured D65 gains from calibration. They may not be exactly 50/50/50.

## 2.6 Govee LAN protocol

Taken from `govee_led_wez/govee.py` (the library `govee-lan-hass` uses). Check it against the official doc before building.

| Port | Direction | Purpose |
|---|---|---|
| **4001** | You → multicast `239.255.255.250` | Discovery scan |
| **4002** | Devices → you (unicast) | Scan replies + `devStatus` replies. **You must bind this port**; only one app per IP can |
| **4003** | You → device IP (unicast) | **All control commands** |

Discovery request (sent to `239.255.255.250:4001`):

```json
{"msg":{"cmd":"scan","data":{"account_topic":"reserve"}}}
```

A scan reply arrives on your port 4002. Fields used: `ip`, `device`, `sku`, `bleVersionHard`, `bleVersionSoft`, `wifiVersionHard`, `wifiVersionSoft`.

Commands (to `<device ip>:4003`):

```json
{"msg":{"cmd":"turn","data":{"value":1}}}
{"msg":{"cmd":"brightness","data":{"value":10}}}
{"msg":{"cmd":"colorwc","data":{"color":{"r":255,"g":180,"b":120}}}}
{"msg":{"cmd":"colorwc","data":{"colorTemInKelvin":5000}}}
{"msg":{"cmd":"devStatus","data":{}}}
```

`turn` is 1 for on and 0 for off. `brightness` is 1–100. For `colorwc`, the supported Kelvin range is device-specific; typically about 2000–9000K.

Practical notes:

- **Sending** to a multicast address doesn't need a group join. Replies come back unicast. So the Swift side is one UDP send plus an `NWListener` on 4002. Simpler than it sounds.
- **UDP has no acknowledgement,** and wez notes devices "don't reliably return the updated state for several seconds". So send absolute values, don't read-after-write, and re-send the current target about every 60 s as self-healing.
- Rate-limit to about 1 command per second per device, and coalesce like DDC. No EEPROM worry here, but these devices drop packets when flooded.
- Cache discovered IPs, and allow a **manual IP** (set a DHCP reservation on your router). Multicast over Wi-Fi is the flakiest part of the whole system.
- If Home Assistant or Homebridge Govee runs on *this Mac*, port 4002 conflicts. On another machine it's fine.

## 2.7 Sensor protocol (as observed)

- `GET http://lunarsensor.local/events` returns `text/event-stream`. Each event looks like this:

  ```
  event: state
  data: {"id":"sensor-ambient_light","name":"Ambient Light","value":48.2,"state":"48.2 lx"}
  ```

  (The `event: state` line is ESPHome's usual convention. Confirm it on your device.)
- Filter on `id == "sensor-ambient_light"`. Ignore the TSL2591 infrared and full-spectrum channels.
- Expect an update every ~2 s. Saturated readings are already filtered on-device.
- Parse with `URLSession.shared.bytes(from:)` → `.lines`, taking lines that start with `data:`. Reconnect with exponential backoff (1, 2, 4… 30 s) and resolve mDNS every reconnect.

## 2.8 Build order: every step testable on its own

| # | Build | How you know it works |
|---|---|---|
| **0** | **Shell prototype, no Swift.** `curl -N http://lunarsensor.local/events`; `m1ddc set luminance 40`; `m1ddc set red 50` / `green 46` / `blue 40`; test whether one write lands or two are needed; `m1ddc get red` (do reads work?); Govee `echo '{"msg":{"cmd":"brightness","data":{"value":10}}}' \| nc -u -w1 <ip> 4003` | Each output changes on command. You know read support, whether one write is enough, and whether gains are linear- or encoded-domain (colorimeter) |
| **0b** | Log a week of lux to CSV (a `curl` loop is fine) | The dataset you'll tune every filter and curve against, offline |
| 1 | Xcode project: `MenuBarExtra` with a label and Quit | It appears in the menu bar and has no Dock icon |
| 2 | `LuxKit`: live lux in the menu, plus a "stale" state | Unplugging the ESP32 shows stale within 60 s; plugging it back in reconnects |
| 3 | `Engine.LuxFilter` + unit tests fed with the 0b CSV | `swift test` passes; the filtered curve plotted from a test looks calm |
| 4 | `DDCKit` transport: two buttons set brightness 30 / 70 | Monitor changes; Console shows timing |
| 5 | `WriteScheduler` + write log view + daily counters | Dragging a slider wildly produces ≤ 4 writes/s; the log proves the dead-band and no-op skipping work |
| 6 | **Colour-critical override** + manual Kelvin slider → gains | One click returns to neutral from any state, including after sleep |
| 7 | Adaptive white point (lux → K, quantised, dwell) | In a 24 h log, gain sets ≤ ~20/day; room dimming visibly warms within the dwell time |
| 8 | Adaptive brightness, fixed curve. **Hand brightness over from Lunar here (stage B)** | Matches Lunar's behaviour closely enough; write count ≤ budget |
| 9 | `SystemEvents`: sleep/wake/reconfigure/lock + Lunar detection | Overnight sleep → correct values within 10 s of wake, one reapply in the log |
| 10 | User offset (v1 corrections), then curve learning (v2) | A correction survives a restart; the curve stays monotonic in tests |
| 11 | `GoveeKit`: manual IP first, then discovery; bias follows brightness | The strip tracks the screen; the override sets it to 6500K |
| 12 | Settings, launch at login, curve chart, calibration UI | You stop opening Xcode to change a number |

---

# 3. Design system extraction

The full token inventory is in **[DESIGN_TOKENS.md](DESIGN_TOKENS.md)**: colours, type, spacing, radii, shadows, components, the SwiftUI/AppKit split, theming and motion, with a JSON block you can rebuild from. The critique is below.

## 3.1 What's well designed

- **A distinctive, calm identity.** Warm yellow/peach accent on deep mauve/indigo ink, in place of system blue. It reads as "light" without being cartoonish, and it's the right emotional register for a lighting app.
- **The menu bar surface.** A 320 pt panel on HUD-material blur, 18 pt continuous corners, per-display rows with big, thick (22 pt), pill-shaped sliders that show an icon and value inside the track. Direct manipulation, glanceable, very little chrome.
- **Progressive disclosure through hover.** Header and footer fade in on hover (`handleHeaderTransition`, 50 ms in / 500 ms out). The resting state is almost just sliders.
- **Honest system feedback.** The fault counters feed a "responsive DDC" state, `possibleDDCBlockers()` gives vendor-specific OSD advice (Dell, LG, Samsung…), and the curve chart shows what the learning did. Copy that tone: tell the user *why* hardware isn't responding.
- **Motion is restrained and consistent.** Two springs (`fastSpring`: interactive, damping 0.7; `jumpySpring`: response 0.4, damping 0.45) and ease-out-expo (0.19, 1, 0.22, 1) for AppKit transitions. Nothing lingers.
- **The drag-coalescing trick** in the learning model is a UX decision disguised as engineering: one gesture is one intent.

## 3.2 What isn't

- **Three parallel colour systems that have drifted apart.** Asset catalog colorsets, `Theme.swift` NSColor literals and `Colors.swift` SwiftUI HSB values each define "the same" colours differently:

  | Colour | `Theme.swift` | `Colors.swift` |
  |---|---|---|
  | `mauve` | `#3D304C` | `#2D2A3B` |
  | `blackMauve` | `#171518` | `#1D1C1F` |
  | `sunYellow` | `#FDB53A` | `#FFC56E` |

  The asset catalog's text colour is a third ink, indigo `#100333`. **Lesson: one token source, generated into both SwiftUI and AppKit.**
- **State colour as page × hover × on/off dictionaries** (`onStateButtonColor[.hover][.settings]`…). That's a combinatorial explosion instead of semantic tokens (`accent`, `accent-hover`, `danger`…). Unmaintainable.
- **No type scale.** There are ~40 distinct size/weight/design combinations in Swift, plus ~25 in the storyboard. They mix SF, SF Rounded, SF Mono *and* Menlo, and weights run from light to black. Hierarchy comes from weight abuse and opacity, not scale.
- **A hue bug.** `warmWhite` and `warmBlack` pass `hue: 20` where the other constants use 0–1 fractions (`20/360` intended). The value is out of range, so the colour depends on clamping behaviour.
- **Hierarchy through opacity.** Caption, Secondary and Tertiary are the same ink at 100/70/50%. Over a translucent HUD blur, that makes contrast unpredictable; body text can fall under 4.5:1.
- **Hover-dependent discovery.** Controls that only appear on hover are invisible to new users, and hard on trackpad and accessibility users.
- **A 10k-line storyboard.** Most settings pages are AppKit in one `Main.storyboard`, so it's hard to review, diff or theme. SwiftUI islands are hosted inside it, so there are two layout systems and two theming paths.
- **UI and hardware coupled through property side effects.** Setting a `@Published` property writes DDC. That's why there's no rate limiting. The design system and the systems architecture fail the same way: there's no layer between intent and effect.

## 3.3 What to take into your app

Take the *feel*, not the implementation:

- One `Tokens.swift` generated from the JSON in DESIGN_TOKENS.md.
- A 4-step type scale in SF Pro + SF Pro Rounded for numerals, with no Menlo.
- Semantic colours with light/dark pairs from one source.
- The 22 pt pill slider.
- Two spring presets.
- No hover-only controls.
- Your warm/neutral state colours should *mean something*. The menu bar icon and the accent could literally show the current white point, and switch to pure neutral grey in colour-critical mode.

---

# 4. Recommended architecture (one page)

```
 ESP32 (SSE) ──► LuxKit ──► Engine.LuxFilter ──┐
                                                ▼
             User input (sliders, override) ─► Engine.Policy ──► Targets{bright, gains, bias%, biasK}
                                                │                     │
                   Persistence (JSON in App Support: curve, calibration LUT, counters, mode)
                                                                      ▼
                          ┌──────────── DDCKit.WriteScheduler (actor) ────────────┐
                          │ gate: awake? unlocked? Lunar-safe? under budget?       │
                          │ coalesce latest-wins • min-interval • dead-band • no-op│
                          └──► Arm64 transport (IOAVService) ──► AOC CU34G4Z       │
                                                                      ▼
                          GoveeKit (UDP 4003, rate-limited, periodic re-send) ──► light bars
 SystemEvents (sleep/wake/reconfigure/lock/Lunar running) ──► closes/opens both gates
```

**Invariants:**

1. Only the scheduler talks to hardware.
2. The Engine is pure and unit-tested.
3. The colour-critical override is a policy state that the Engine checks first.
4. The app's own state is the source of truth. Hardware reads are diagnostics.
5. Every write is logged and counted.

---

# 5. What you should NOT build

Be ruthless. Each of these is a week or more that doesn't serve the four goals:

1. **Don't fork Lunar or try to make it compile.** It can't be done without the encrypted files, and trying would drift toward recovering them.
2. **Don't build multi-monitor support, the Intel DDC path, the Apple-display path (DisplayServices), or the network DDC path.** You have one monitor, and the matching code can be trivial.
3. **Don't build Lunar's other modes** (Sync, Location, Clock). Your sensor is better than all of them.
4. **Don't smooth transitions over DDC.** Smooth the lux. Write rarely.
5. **Don't adapt contrast.** On a VA panel, DDC contrast lowers native contrast, which is the panel's main strength. Set it once in the OSD.
6. **Don't do software dimming, gamma tables, "sub-zero", XDR or overlays.** That's a different product.
7. **Don't build spline fitting or cliff detection for v1.** Piecewise-linear + monotonic insert + a decaying user offset is enough. Revisit after a month of use.
8. **Don't build a curve editor before you have a week of lux logs.** You'll design it around imagined data.
9. **Don't build Govee screen-colour sync (ambilight)** or use the Govee cloud API. ScreenCaptureKit colour extraction is its own project, and cloud adds rate limits and accounts.
10. **Don't recreate Lunar's design system.** Extract the tokens, collapse them to about a dozen semantic ones, and build in SwiftUI only.
11. **Don't add Sparkle auto-updates, licensing, onboarding carousels, an App Store build, hotkeys or Shortcuts** until you've used the app daily for a month. This is a personal tool.
12. **Don't scale gains above neutral** to preserve luminance (§2.4). Use the backlight.
13. **Don't call it True Tone** until the sensor can measure colour. If that matters, a TCS34725 (already supported by `Lunar/ALS/tcs34725.yaml`) or AS7341 on the ESP32 is a weekend hardware job, and it turns rule 2's "dim → warm" into real ambient-CCT matching.

---

# 6. Open questions to answer in step 0 (before any Swift)

1. Does the AOC take a **single** DDC write for 0x16/0x18/0x1A, or does it need two?
2. Do **reads** of 0x10 and 0x16–0x1A return sane values?
3. Are gains applied in the **linear or encoded** domain? (Colorimeter, or side by side with a D50 reference.)
4. What's the gain **range**: is 50 the midpoint of 0–100, and does > 50 clip?
5. Does the AOC **reset gains** after sleep, power-off or input change? (If it does, the reapply-on-wake path is critical.)
6. Can Lunar and a second SSE client stay connected to the ESP32 for 24 h at the same time?
7. Which Govee model(s) do you have, do they show "LAN Control" in the app, and what Kelvin range does `colorwc` accept?
