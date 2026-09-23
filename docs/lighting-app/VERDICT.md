# Shell prototype: capability audit and verdict

Follow-up to [PLAN.md](PLAN.md) §2.8 step 0. The prototype is in [`lighting-prototype/`](../../lighting-prototype/).

**What was and wasn't measured.** This work ran in a cloud container with no access to your Mac Studio, the AOC, the ESP32 or the Govee bars, so **there are no hardware measurements in this document.**

What *was* verified:

1. **Lunar's CLI and Shortcuts, from source.** Every command in the audit is quoted from `Lunar/Data/CLI.swift` and `LunarShortcuts/`.
2. **The prototype's logic, against simulators.** A fake ESPHome SSE sensor, a fake Govee strip on real UDP sockets (4001/4002/4003, including multicast), mock `m1ddc`/`lunar` binaries, and a simulated AOC + TSL2591 pair that responds to gain writes under either hypothesis. **44/44 checks pass** (`lighting-prototype/test/run_tests.sh`). Testing found and fixed one real bug that would have frozen the loop on your Mac.
3. **The probe kit's analysis.** Given synthetic monitors of each type, it correctly classifies them and recovers the right Kelvin for your rows.

The seven hardware answers come from running `lighting-prototype/probe/` on your Mac: about 1 hour hands-on, plus an unattended 24 h log. Each question below says which probe settles it.

---

## Capability audit

### 1. Can Lunar Pro's CLI read lux from your sensor? **Yes** (source-verified; probe 01 confirms on hardware)

```bash
~/.local/bin/lunar lux              # last reading from the external sensor
~/.local/bin/lunar lux --average    # mean of the last 15 readings
~/.local/bin/lunar lux --listen     # streams a value every time it changes
```

- **The Lunar app must be running.** The `lunar` script forwards commands over a local socket (127.0.0.1:23803) to the running app (`AppDelegate.swift:2181–2203`, `Shared.swift:63`). `lux` returns `SensorMode.specific.lastAmbientLight` when an external sensor is available (`CLI.swift:450`). That's the value Lunar already reads from `lunarsensor.local`, so your ESP32 only ever sees one client.
- The CLI installs to **`~/.local/bin/lunar`**, not `/usr/local/bin` (`CLI_BIN_DIR`, `AppDelegate.swift:2964`). Install it from Lunar's settings.
- The same socket also answers HTTP: the body is `cmd=lux`, with the API key from `lunar key` in an `Authorization:` header (`CLI.swift:2667–2700`). So even a Shortcuts **Get Contents of URL** action can read lux without a shell.
- I can't see whether the CLI is Pro-gated, because the gate lives in the encrypted `Pro.swift`. You own Pro, so it doesn't matter to you.

### 2. Can it write red/green/blue gain (VCP 0x16/0x18/0x1A)? **Yes** (source-verified; probe 01 confirms on hardware)

```bash
lunar displays external redGain 50       # VCP 0x16
lunar displays external greenGain 46     # VCP 0x18
lunar displays external blueGain 40      # VCP 0x1A
lunar ddc external 0x1A 40               # raw write, same VCP
lunar ddc external 0x1A read             # raw read
lunar displays external reapplyColorGain true   # have Lunar restore gains after wake
```

- `redGain`/`greenGain`/`blueGain` are in `Display.CodingKeys.settable` (`Display.swift:1080–1110`). Setting one runs `Display.redGain.didSet` → `control.setRedGain` → `DDC.write(0x16)` (`Display.swift:3782`, `DDC.swift:1614`).
- **Use the property form, not raw `ddc`.** The property updates Lunar's stored value. Its wake handler (`AppDelegate.swift:1719`, `:2493`) then re-applies *your* white point after sleep instead of fighting it. Raw `lunar ddc` bypasses the stored value, so Lunar would restore a stale one.
- Lunar's own Apple Silicon DDC transport is encrypted (`DDC2.c`), so I can't say how many times Lunar sends each packet. Probe 04 measures what the AOC needs, using m1ddc.

### 3. Does m1ddc do it on your AOC CU34G4Z? **Not tested** (no hardware); probes 00, 03 and 04 settle it

```bash
m1ddc set red 50 ; m1ddc set green 46 ; m1ddc set blue 40
m1ddc get blue ; m1ddc max blue
```

The commands are confirmed from m1ddc's source (`sources/m1ddc.m`, VCPs in `headers/i2c.h`). Probe 00 builds two copies: stock (every write sent twice, `DDC_ITERATIONS 2`) and a single-write build. Probe 04 then compares them on your monitor.

Your own evidence is the strongest prior: BetterDisplay and Lunar Pro both reach the AOC over DDC on this port, and both use the same `IOAVService` path m1ddc does. I'd expect it to work, but that's a prior, not a result.

### 4. Can the Govee bars be driven from the shell via UDP? **Yes** (port 4003 confirmed; verified against a simulated strip)

Control goes to **UDP 4003** (`govee_led_wez/govee.py`: `COMMAND_PORT = 4003`). Discovery is multicast to 239.255.255.250:**4001**, and replies come back on **4002**.

```bash
# nc (BSD nc ships with macOS)
printf '%s' '{"msg":{"cmd":"brightness","data":{"value":10}}}' | nc -u -w1 192.168.1.60 4003
printf '%s' '{"msg":{"cmd":"colorwc","data":{"color":{"r":0,"g":0,"b":0},"colorTemInKelvin":5000}}}' | nc -u -w1 192.168.1.60 4003
printf '%s' '{"msg":{"cmd":"turn","data":{"value":1}}}' | nc -u -w1 192.168.1.60 4003

# socat equivalent
printf '%s' '{"msg":{"cmd":"brightness","data":{"value":10}}}' | socat - UDP-DATAGRAM:192.168.1.60:4003
```

**Discovery isn't a safe `nc` one-liner.** `nc -u -l 4002` locks onto the *first* device that replies and ignores the rest. `bin/govee discover` uses python3 (it comes with the Command Line Tools) and hears every strip.

### 5. Can macOS Shortcuts chain all of this into one action? **Yes as a one-shot, no as the adaptive loop**

- **As one action: yes.** Lunar ships native Shortcuts actions, **Get Ambient Light (in lux)** and **Adjust Colors of a Screen (in hardware)** (R/G/B, with an optional delay between colours). Chain them through **If**/**Calculate**, then a **Run Shell Script** for Govee. It works when triggered.
- **Continuously: no.** Shortcuts has no "when lux changes" trigger, and isn't meant to run every few seconds. The loop has to be something that stays running: `lightd` under launchd.
- **Where Shortcuts is excellent: the override button.** A Shortcut that runs `light critical toggle` can be pinned in the menu bar, given a global keyboard shortcut, and triggered by Siri or a Stream Deck. That's your one-click colour-critical mode, with no app.

---

## The seven open questions

| # | Question | Status | Settled by | What to look for |
|---|---|---|---|---|
| 1 | Does the AOC need writes sent twice? | **Not measured** | `probe/04-single-write.sh` (2–5 min) | Single-send success rate vs double-send. 12/12 single → switch to one write cycle and halve DDC traffic |
| 2 | Do reads return sane values? | **Not measured** | `probe/03-ddc-read.sh` (2 min) | Ten reads per control: consistent, and matching the OSD? |
| 3 | **Linear-light or gamma-encoded gain?** | **Not measured** | `probe/05-gain-domain.sh` (15 min, dark room, sensor taped to the screen) | Output ratio at gain 40: **0.80 → linear, 0.61 → encoded**. The probe prints what your rows really produce (below) |
| 4 | Gain range; does > 50 clip? | **Not measured** | Probes 03 (max) and 05 (output at 55/60) | "HEADROOM exists" vs "50 is the ceiling" |
| 5 | Does the AOC reset gains on sleep, input change or power-off? | **Not measured** | `probe/06-persistence.sh` Part A | KEPT/RESET per event. If it resets on wake, `reapplyColorGain` (Lunar backend) is essential |
| 6 | Can Lunar + a second SSE client coexist for 24 h? | **Not measured** | `probe/02-sensor-log.sh 24` | Reconnects ≤ 2, no long gaps, `lunar lux` still fresh. It also writes the lux CSV you need for tuning. The recommended setup (`LUX_SOURCE=lunar`) **avoids the question entirely**: only Lunar talks to the ESP32 |
| 7 | Govee model, LAN Control, Kelvin range | **Not measured** | `probe/07-govee.sh` (3 min) | Discovery replies (`sku`), whether 4003 commands work, the visible Kelvin range |

### Q3 in detail: is your 4500K row 4500K or 5400K?

This is the question that matters most, and it's cheap to answer with hardware you already own:

1. Zero two of the three gains and show full-screen white. The TSL2591 then sees one primary with a fixed spectrum, so its reading is proportional to that channel's output.
2. Step that gain from 50 down to 20 and read the curve.

Here's what the probe's analysis prints for each hypothesis. These are simulated monitors, not your AOC:

| Your row | If the AOC is **linear-light** | If the AOC is **gamma-encoded** |
|---|---|---|
| "5500K" 50/47/44 | ≈ 6020K, 95% luminance | ≈ 5530K, 89% |
| "5000K" 50/46/40 | ≈ 5710K, 93% | ≈ 5000K, 85% |
| "4500K" 50/44/36 | **≈ 5400K**, 89% | **≈ 4510K**, 79% |
| Corrected table | `6500:50:50:50, 6000:50:48:44, 5500:50:45:37, 5000:50:41:31, 4500:50:38:24, 4000:50:34:18` | your table is already right |

I have no basis for guessing which one the AOC is. Don't treat either as likely; run the probe. It also prints a `GAIN_TABLE` built from *your* measured curve, which beats either model if the AOC turns out to be neither.

### EEPROM: does it commit every write, or buffer in RAM?

**No software can count EEPROM cycles,** mine or anyone's. What `probe/06-persistence.sh` Part B *can* do is bound the commit delay. It writes a value, and you pull the power cord (not the button) 1 s, 30 s and 60 s later.

- **Survives the 1 s cut:** each write is committed almost immediately. The worst-case wear model in PLAN.md §2.2 applies to everything, bursts included.
- **Survives only the 30 s or 60 s cut:** the monitor buffers and commits on a timer. A burst inside that window costs one cycle, so Lunar-style smooth transitions are cheaper than feared.

Either way, **writes spaced further apart than the commit delay each cost a cycle.** That's exactly what the prototype's rate limits produce. The daily caps and the 10-minute gain interval stay necessary whatever this probe says. It only tells you whether bursts are cheap.

---

## Verdict

### What percentage of the intended app do shell + Shortcuts deliver?

**About 85%, in the recommended configuration.** That's Lunar Pro doing brightness and DDC, plus the prototype, plus SwiftBar and a Shortcut. Without Lunar (the m1ddc backend) it's about 65–70%. All of this still has to survive probe 05 and a week of real use.

| Intended capability | Shell + Lunar Pro | Shell + m1ddc (no Lunar) |
|---|---|---|
| Adaptive brightness from the ESP32 | ✅ Lunar's, including its learning curve | ✅ Fixed log-lux curve, no learning |
| Adaptive white point (lux → Kelvin → R/G/B gains) | ✅ | ✅ |
| Rate limits, daily caps, write log (EEPROM safety) | ✅ | ✅ |
| One-click colour-critical override, immediate | ✅ Shortcut hotkey / menu bar / SwiftBar | ✅ |
| Bias light tracking the screen | ✅ (see the Local Network caveat below) | ✅ (same caveat) |
| Survives sleep/wake | ✅ Lunar's native handling re-applies gains | ⚠️ Heuristic (gap between samples) |
| Coexists with Lunar | ✅ by design: one app on the bus | n/a (Lunar must be out of the way) |
| Menu bar status (live Kelvin, lux, override) | ⚠️ SwiftBar: live text + actions, no sliders | ⚠️ Same |
| Launch at login, crash-restart | ✅ launchd | ✅ |
| Learns from manual corrections | ⚠️ Brightness yes (Lunar), white point no | ❌ |
| Settings UI, curve editor | ❌ A config file | ❌ |
| Independent of Lunar Pro | ❌ | ✅ |

### What specifically cannot be done without a native app

These are the only things that need native code:

1. **Real system events.** NSWorkspace sleep/wake/screen-lock notifications and `CGDisplayRegisterReconfigurationCallback`. Shell can only infer them by polling or from gaps. In the Lunar configuration, Lunar's native code covers this for you.
2. **A proper identity for macOS Local Network privacy (15+).** A signed app gets a prompt and a toggle in System Settings. `curl`/`nc` started by launchd may be denied silently. This is the one real risk to the shell version, and I couldn't test it. Reading lux through Lunar sidesteps it for the sensor; Govee UDP is the exposed part.
3. **A real menu bar UI:** live sliders, a white-point swatch, a curve you can drag. SwiftBar gets you text, icons and click actions, and nothing richer.
4. **Brightness-grade DDC robustness without Lunar.** Fault counters, persistent `IOAVService` handles, and serialised off-main-thread I2C. The shell version gets these only by borrowing Lunar.

Everything else in the brief can be done in shell, and is: lux → Kelvin → gains maths, rate limiting, override, bias light, launch at login.

### Is the remainder worth 6–8 weeks for someone learning Swift?

**For the function, no.** The shell + Lunar Pro version covers all four goals in your brief: adaptive brightness, adaptive white point, bias light, and a non-negotiable override. The 6–8 weeks mostly buy UI polish, independence from Lunar Pro, and native sleep/wake. None of those is a goal you listed.

**As a design-engineering education, maybe yes, but only after 2–4 weeks of living with the shell version.** By then you'll have:

- a measured gain table from probe 05
- a lux CSV from probe 02
- the answers to Q1–Q7
- real opinions about what the menu bar should show

Starting Swift before that means designing around guesses. If what you want is to ship Swift, build it as the learning project it is, not because the shell version falls short.

### If you build the app anyway: the smallest useful v1

**A native white-point controller that sits next to Lunar, not a Lunar replacement.** Target 3–4 weeks.

It does:

- `MenuBarExtra` showing the live Kelvin swatch, lux, and the override toggle
- lux read from `lunar lux --listen` (or SSE)
- DDC gains only, through a port of MonitorControl's `Arm64DDC` plus the write scheduler from `lighting-prototype/lib/ddc.sh`, re-expressed as an actor
- **real** sleep/wake/lock notifications
- the calibrated `GAIN_TABLE` from probe 05

It doesn't do: brightness (Lunar keeps it), Govee (the `govee` script keeps it; call it or port it later), settings screens (hard-code the config), or learning.

That v1 beats the shell in exactly the places the shell is weak: native events, a Local Network identity and a real UI. After that, each later step replaces one shell piece and stays testable against the same simulators.

---

## How to run it (short version)

```bash
cd lighting-prototype
probe/00-setup.sh && probe/01-cli-audit.sh      # 5 min: tools + Lunar CLI audit
probe/03-ddc-read.sh && probe/04-single-write.sh
probe/05-gain-domain.sh                         # dark room, sensor on screen: Q3
probe/06-persistence.sh && probe/07-govee.sh
probe/02-sensor-log.sh 24 &                     # leave running
./install.sh                                    # then edit ~/.lighting/config.sh with probe results
```

Paste the `probe/results/*.txt` files back into a session and I'll turn them into a final table, a corrected config, and a go/no-go on the app.
