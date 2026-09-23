# Lighting prototype (plan step 0)

Shell-only version of the adaptive display and lighting app: adaptive white point, bias light, colour-critical override and EEPROM-safe DDC writes. It also includes a probe kit that answers the plan's open hardware questions by measurement.

The verdict (how much of the app this delivers, and whether to build the Swift app) is in [`../docs/lighting-app/VERDICT.md`](../docs/lighting-app/VERDICT.md).

```
bin/lightd      adaptive loop (lux → filter → targets → rate-limited DDC + Govee). Runs under launchd
bin/light       one-shot control: critical on|off|toggle · kelvin <K> · neutral · bias · status · writes
bin/govee       Govee LAN API from the shell: discover · on/off · brightness · kelvin · rgb · raw
lib/            engine.awk (pure maths) · ddc.sh (write scheduler) · govee.sh · apply.sh · common.sh
probe/          hardware measurements: run these first, on the Mac
swiftbar/       menu bar UI via SwiftBar (open source)
test/           simulators + test suite (runs anywhere: `test/run_tests.sh`)
```

Dependencies:

- macOS's own bash 3.2, awk, curl, nc and perl.
- m1ddc, built by `probe/00-setup.sh`, only for the `m1ddc` backend and the probes.
- The Lunar CLI, only for the `lunar` backend.
- SwiftBar, optional.

## 1. Probe your hardware first (about 1 hour of hands-on time plus a 24 h log)

Run these in Terminal, in order. Each writes `probe/results/NN-*.txt` ending in a `RESULT` line.

| Probe | Answers | Needs | Time |
|---|---|---|---|
| `probe/00-setup.sh` | Tools; builds m1ddc stock (2 writes) and `m1ddc-1x` (1 write); lists displays and sensor IDs | Command Line Tools | 3 min |
| `probe/01-cli-audit.sh` | **Audit 1–2:** does `lunar lux` read your ESP32? Does `lunar displays external blueGain` write VCP 0x1A? | Lunar running | 2 min |
| `probe/02-sensor-log.sh 24` | **Q6:** two SSE clients (this + Lunar) stable for 24 h? Also records your lux dataset (CSV) | Lunar running | 24 h, unattended |
| `probe/03-ddc-read.sh` | **Q2:** do reads work and match the OSD? **Q4a:** gain max | Lunar quit | 2 min |
| `probe/04-single-write.sh` | **Q1:** does the AOC need every write sent twice? | Lunar quit | 2–5 min |
| `probe/05-gain-domain.sh` | **Q3:** linear-light or gamma-encoded gain? **Q4b:** headroom above 50? Prints what your gain rows *really* produce and a corrected `GAIN_TABLE` | Lunar quit, dark room, sensor taped to the screen | 15 min |
| `probe/06-persistence.sh` | **Q5:** what resets gains (sleep, input, power)? **EEPROM:** how fast a write is committed (you pull the power cord 3×) | Lunar quit | 10 min |
| `probe/07-govee.sh` | **Q7:** discovery, port 4003 commands, Kelvin range | LAN Control on in the Govee app | 3 min |

How probe 05 works without a colorimeter:

1. It sets two of the three gains to 0 and shows a full-screen white page, so only one primary lights up.
2. Your TSL2591, taped to the screen, then sees a fixed spectrum. Its reading is proportional to that channel's output, whatever its spectral response.
3. Stepping that channel's gain from 50 to 20 gives the response curve.
4. The output ratio at gain 40 tells the two hypotheses apart: **0.80** means linear light, **0.61** means gamma-encoded.

## 2. Run it

```bash
./install.sh                     # copies config to ~/.lighting/config.sh, starts lightd under launchd
$EDITOR ~/.lighting/config.sh    # paste GAIN_TABLE/GAIN_GAMMA from probe 05; set GOVEE_IPS from probe 07
bin/light status
bin/light critical toggle        # the override
tail -f ~/.lighting/lightd.log ~/.lighting/writes.log
```

**Backends** (`BACKEND` in config):

- **`lunar` (default).** Lunar Pro keeps doing adaptive brightness, including its learning curve, and keeps owning the DDC bus. The prototype adds lux → Kelvin → gains, the override and the bias light. Gains are written as Lunar display properties, so with `reapplyColorGain` on (`lunar displays external reapplyColorGain true`), **Lunar's native wake handling re-applies your white point after sleep.** Only one app touches the monitor.
- **`m1ddc`.** No Lunar. The prototype also does brightness, from a fixed log-lux curve with no learning. Quit Lunar or unmanage the AOC first. Wake detection is a heuristic here: a gap of more than 90 s between lux samples.

**Safety limits** (in `lib/ddc.sh`):

| Limit | Default |
|---|---|
| No-op skip | Never re-sends the last value |
| Brightness dead-band | 2 units |
| Minimum interval: brightness | 20 s |
| Minimum interval: gain set | 10 min |
| Daily cap: brightness | 300 |
| Daily cap: gains | 50 per channel |
| Write log | every attempt |

The override bypasses the intervals, never the caps or the no-op check.

## 3. Menu bar and Shortcuts

**SwiftBar** (menu bar icon showing live Kelvin, the override toggle, and write counts):

```bash
brew install --cask swiftbar
ln -s "$PWD/swiftbar/lighting.10s.sh" ~/SwiftBarPlugins/      # or whichever folder SwiftBar uses
```

**Shortcuts** (an override on a hotkey, the Shortcuts menu, Siri or a Stream Deck):

1. Shortcuts → Settings → Advanced → **Allow Running Scripts**.
2. Create a new Shortcut with the action **Run Shell Script**: `/path/to/lighting-prototype/bin/light critical toggle`.
3. In Shortcut details, turn on **Pin in Menu Bar** and add a **keyboard shortcut**.
4. Optionally, a native-only chain with no scripts: Lunar's **Get Ambient Light (in lux)** → **If** / **Calculate** → Lunar's **Adjust Colors of a Screen (in hardware)** (R/G/B). This works as a one-shot. Shortcuts can't run it continuously; that's what `lightd` is for.

## 4. Known limits (all tested against simulators only)

- **Nothing here has touched the real AOC, ESP32 or Govee bars yet.** `test/run_tests.sh` proves the logic, packet formats, rate limits and probe analysis against simulators (44 checks). The probes are what prove the hardware.
- **Local Network privacy (macOS 15+) may block `curl`/`nc` when started by launchd.** Terminal-launched runs inherit Terminal's permission; background agents may not get a prompt. `LUX_SOURCE=lunar` sidesteps it for the sensor, because Lunar already has the permission. Govee UDP may still be blocked. If `lightd.log` shows Govee sends but the strips don't react under launchd while `bin/govee` works from Terminal, this is why.
- `lunar lux --listen` only emits when the value changes. In a perfectly steady room that looks like a stale sensor, and `lightd` reconnects every `STALE_SECS`. That's why the default `STALE_SECS` is 300; with `LUX_SOURCE=sse`, 60 is enough.
- White point has no learning. You edit the curve in config. Brightness learning comes from Lunar in `lunar` mode only.
